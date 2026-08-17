# 0023 — in noctalia mode, noctalia's keys do noctalia's actions

**Status:** Accepted (2026-08-16)

The "later decision" [0020](0020-noctalia-is-a-desktop-mode.md) deferred: it
recorded that noctalia's launcher, lock screen and panels went unused and that
handing any of them over "would need its own record". Follows
[0014](0014-declare-the-namer-not-just-the-file.md) (assert reachability both
ways, per selector) and extends
[0022](0022-noctalia-mode-looks-like-noctalia.md).

## Context

A desktop shell is not a bar. noctalia ships a launcher, a lock screen, a
control centre, a calendar, a session menu, a settings panel and a dock, and in
`noctalia` mode every one of them sat behind no key at all while the keys that
were bound reached past it to rofi, swaync and swaylock. The mode looked like
noctalia and behaved like tiling.

Two mechanisms could carry the change, and the difference between them is not a
matter of taste — it was measured.

**Per-mode `bind=` overrides do work, and they are the wrong tool.** mango's
binds *append* (`parse_config.h`: `realloc(… count + 1 …)`) and the dispatcher
stops at the first match — `src/mango.c`, comment `only match the first
keybind`. So a mode conf sourced ahead of `universal/bind.conf` genuinely
overrides it. But mango also runs `check_key_binding_conflicts()` and prints
`[WARNING] Key binding conflict` naming both files and both line numbers for
every duplicate, unless *both* carry the `c` flag. Verified against a nested
instance: it fires. Thirteen overrides means thirteen warnings on every start
and reload, on the same stderr where a real conflict would appear. A warning you are
trained to scroll past is worse than no warning.

**`noctalia-shell ipc call` reports failure and exits 0.** `Target not found.`
and `Function not found.` go to stdout with status 0; a successful void call
prints nothing at all. That is the `mmsg -s -d` shape verbatim — the flag form
that broke five scripts and all four waybar layouts here without a word — so
output is the only signal and the exit status is worthless.

One more thing turned up while reading the shell's own code: **noctalia's logout
is inert on this machine.** `MangoService.logout()` runs `mmsg -s -q`, the
dwl-era flag form, which returns `{"error":"unknown command"}` and exits 0.
Confirmed by running the same shape by hand.

## Decision

**One bind, one script, one table.** `scripts/menus/shell.sh` generalises the
`notify.sh` that [0020](0020-noctalia-is-a-desktop-mode.md) introduced for the
notification panel alone: a `case` mapping each action to a noctalia target and
function on one side, and a shell function holding the rofi/swaync/swaylock
equivalent on the other. Thirteen keys route through it — launcher, lock,
clipboard, emoji, network, bluetooth, power, DND, the two bar keys and the two
notification keys. `notify.sh` is deleted; it is now one
row.

**Two keys that refused now do something.** `SUPER+/` and `SUPER+SHIFT+/` were
guarded by `mode_has_waybar()` and answered a `notify-send` in noctalia mode —
correct, and still two dead keys out of a set that small. They are the
"configure the bar" keys, and each mode's bar is a different program: waybar's
layout picker and position toggle in tiling and hud, noctalia's settings panel
and `bar toggle` in noctalia. That is what the table is for, so they join it
rather than becoming a per-mode override. `SUPER+CTRL+C` was the settings key
for one afternoon and is gone; one action, one key.

**Four gaps that were not asked about but were missing.** Measured against the
shipped IPC surface rather than guessed: a window switcher (`SUPER+W` —
`rofi -show window` in every mode — see above for why not noctalia's own), do-not-disturb (`SUPER+SHIFT+N` —
`notifications toggleDND`, or `swaync-client -d`), and keep-awake
(`SUPER+SHIFT+A`). The last is noctalia-only: its inhibitor is quickshell's
native `IdleInhibitor` over `zwp_idle_inhibit_manager_v1`, which mango
advertises, so it holds off **swayidle's** ladder and not merely noctalia's own
idle service — which is pinned off. tiling and hud have no CLI for that at all;
they hold one only through waybar's module, in 4 of their 8 layouts.

The keys that stay put are as deliberate as the ones that moved: **the
calculator, the password store, the window switcher and the VPN menu are rofi in
every mode.** The reasons differ and were checked one at a time. noctalia's
launcher *does* have a calculator — `CalculatorProvider.qml`, `handleSearch:
true`, so typing `1+1` into the plain launcher works — but there is no
`launcher calculator` IPC function, so no key can open it directly. It has no
`rbw` front end at all, and its network panel does not know about the PIA
profiles this repo declares. The window switcher is the interesting one: it has
`launcher windows`, and that lists **nothing** here, because `WindowsProvider`
reads `CompositorService.windows`, which `MangoService` only ever fills inside
the `DwlIpc`-guarded `updateWindows()` — see the correction on
[0020](0020-noctalia-is-a-desktop-mode.md). rofi's window mode reads
wlr-foreign-toplevel, which mango does advertise, so `SUPER+W` is rofi's in all
three modes.
**Volume, brightness and playback keys stay on `wpctl`, `brightnessctl` and
`playerctl`** in every mode — hardware keys must keep working when the shell is
down, and noctalia already draws its OSD for a change it did not make.

**Keys with no counterpart elsewhere are bound per-mode.** Control centre,
calendar, dock and keep-awake live in `noctalia/bind.conf`, sourced only by
`noctalia.conf`. Putting them in `universal/` would make four dead keys in
tiling and hud — the failure [0020](0020-noctalia-is-a-desktop-mode.md) exists to
avoid — and putting the *shared* thirteen there would trip the conflict warning.
They still call `shell.sh`, so "the shell is not running" and "Target not found"
are reported from one place.

**The lock screen authenticates through the PAM service this repo already
owns.** Left alone, noctalia probes and takes `/etc/pam.d/login` because it
exists. The unit now sets `NOCTALIA_PAM_SERVICE=swaylock`, which
`desktop.nix` declares with `fprintAuth = false` for the reason a Wayland locker
always needs it: it cannot render `pam_fprintd`'s prompt, so with the sensor
ahead of `pam_unix` the first seconds of every unlock swallow your typing.
One stack, one place, and testing swaylock now tests both.

**The automatic lock does not move.** swayidle's `before-sleep`, `lock` and the
300 s timeout stay on `lockscreen -f`. That path must be synchronous — `-f`
forks only once the lock is actually up, which is what stops a suspend racing
ahead of it — and it must work when noctalia is not running at all, which is two
modes out of three and any time the unit has wedged. So the manual key uses
noctalia's lock and the unattended path uses swaylock's. If noctalia's lock is
already up, swaylock fails to acquire the session lock and exits non-zero, which
the existing `;` in that timeout already tolerates.

> **Amended the same day by [0024](0024-the-unattended-lock-follows-the-mode.md):
> it moves.** The consequence above was the giveaway — the last sentence
> describes swaylock reporting, from inside the unattended path, whether
> something else already holds the lock. That makes the synchronous promise
> keepable without any new mechanism: ask noctalia, then run swaylock anyway,
> and its failure *is* the proof the lock is up. Both halves of the reasoning
> here still stand; only the conclusion drawn from them was too cautious.

Two settings follow the binds into `settings-pinned.json`, because a key that
opens an empty panel is the same failure as a key that does nothing:
`appLauncher.enableClipboardHistory` (off by default; noctalia's clipboard view
reads the same `cliphist` this repo has been filling all along) and
`sessionMenu.powerOptions` with **logout disabled**, since the action is inert
here. A missing button beats a button that silently does nothing.

### The checks

- **Every `target function` pair in the table exists in the shipped QML.** The
  function must be inside *that* target's `IpcHandler` block — two independent
  greps would pass `dock clear`, because some other target does declare `clear`.
  16 pairs, floor at zero.
- **Every action a bind names is in the table, and every action in the table is
  reached by a bind.** Both directions, per
  [0014](0014-declare-the-namer-not-just-the-file.md). The first version of this
  check read the prose in the comments too and reported an action called
  `rather`; it now looks only at `^bind=` lines.
- **No key is bound twice in any mode.** Built per mode from the `source=` lines
  of its own conf, which is exactly the set mango parses, and lowercased first
  because the dispatcher compares with `xkb_keysym_to_lower()`. This is the
  runtime warning above, moved somewhere it will be read — adding a per-mode
  bind file is precisely the change that can introduce a collision.
- **The script-reference check learned to read scripts, not just configs.**
  `network-menu.sh` and `bluetooth-menu.sh` are now called from `shell.sh`
  rather than from a `.conf`, so they fell straight out of the old scan with no
  count reaching zero to say so. It covers `$MANGO_DIR/scripts/…` too now: 14
  references became 19.

## Consequences

- **The lock screen is the one thing here not verified end to end.** Everything
  else was tested by running it; a lock cannot be, without the password. The
  PAM stack is the one swaylock already uses on this machine, so the risk is
  quickshell's PAM module rather than the configuration — but confirm it before
  relying on it, and know the way out: `CTRL+ALT+F2` to a TTY. Killing the shell
  does **not** unlock; `ext-session-lock-v1` keeps the session locked when the
  locker dies, by design.
- **`shell.sh` is shared, so removing noctalia touches it.** `docs/SYSTEM.md` §6
  names it: the four `fb=none` rows go — control centre, calendar, dock,
  keep-awake — and `noctalia/bind.conf` leaves with the
  directory.
- **Thirteen keys now depend on a running shell in one mode.** When it is down they
  say so with `notify-send` — which works, because
  `noctalia-start.sh` restores swaync on a failed start
  ([0022](0022-noctalia-mode-looks-like-noctalia.md)).
- **`SUPER+Escape` is new in every mode.** `power-menu.sh` existed and was
  reachable from nothing: the waybar module that called it was defined in
  `config-hud.jsonc` and never listed in `modules-right`. tiling and hud gain a
  power menu they always had and could not open.
