# 0022 — Noctalia mode looks like noctalia

**Status:** Accepted (2026-08-15)

Extends [0020](0020-noctalia-is-a-desktop-mode.md) (noctalia is a desktop mode),
and amends the seeding half of it. Uses the mode machinery from
[0004](0004-mode-scripts-own-theming.md) and the palette from
[0009](0009-generated-config-over-linked-files.md).

## Context

[0020](0020-noctalia-is-a-desktop-mode.md) installed noctalia as a third desktop
mode and stopped there deliberately: it answered *how to run it without
breaking the other two*, not *what it should look like*. Two things were left
behind, and both look like the mode being finished when it is not.

**`noctalia/noctalia.conf` was a byte-for-byte copy of `tiling.conf`.** Same
flat look every mode had: `animations=0`, `border_radius=0`, every gap `0`,
`borderpx=1`. That is the right look under waybar, which is a flush bar with
square modules. noctalia is the opposite — a floating bar with a 12px frame
radius, rounded panels, its own shadows and its own open/close animations. The
result read as two desktops stacked: a rounded, gapped shell sitting on hard
square windows that snapped between positions with no motion at all.

**The settings seed was inert on any machine that had already run the mode.**
`modes/noctalia.sh` installed `settings.json` only when the destination was
absent, which [0020](0020-noctalia-is-a-desktop-mode.md) recorded as the cost of
not owning a file the program rewrites. The bill came due immediately: noctalia
ships `colorSchemes.predefinedScheme = "Noctalia (default)"`, a purple, and this
machine is Gruvbox everywhere else by construction — `modules/home/palette.nix`
is one definition feeding the terminals, the bar and rofi, with
`checks/static.sh` asserting it has not drifted. Adding the scheme to the seed
would have changed nothing here, because the file already existed. A setting
that is declared in the repo and not in force on the machine is the same failure
as a config that was never declared, and it is harder to see.

## Decision

**A mode owns its look, and noctalia's is rounded, gapped and animated.**
`noctalia.conf` now diverges from the shared flat look after the `source=` lines
rather than repeating them: `border_radius=12` to match noctalia's own
`bar.frameRadius`, 8px inner and 12px outer gaps, `borderpx=2` in palette
`overlay`, `animations=1` with zoom open and close, and shadows on floating
windows.

This works because **mango's parser is last-wins and processes `source=` inline
at its position** — verified against a nested instance, not assumed; the probe
and the trap are in `docs/gotchas.md` → Desktop → mango. Every mode conf can
therefore keep sourcing `universal/settings.conf` and then disagree with it,
which is what keeps the divergence to one block instead of a forked tree.

Three things are deliberately *not* turned on:

- **Compositor `blur` stays 0.** This machine hard-hangs on an amdgpu TTM fault
  (`docs/gotchas.md` → Power); a permanent full-screen shader pass is not what
  to spend that risk on. noctalia's *own* blur-behind is separately inert here —
  mango implements no `ext-background-effect-v1` — so nothing regressed.
- **`layer_shadows` stays 0**, because noctalia draws shadows on its own panels
  (`general.enableShadows`). Turning them on would double every one.
- **`layerrule=noanim:1,layer_name:^noctalia-`.** Same reasoning one step
  further: noctalia animates its panels, notifications and OSD as it shows them,
  and mango animating the surface underneath plays two animations over one
  another. Anchored, because matching is PCRE2 and unanchored.

**The settings file is written in two halves that differ in when they apply.**

| File | Applied | Holds |
|---|---|---|
| `noctalia/settings.json` | once, when there is no file at all | preferences — terminal command, changelog popup, telemetry |
| `noctalia/settings-pinned.json` | on **every** entry into the mode | the keys that would otherwise fight this machine |

The pin is `jq -s '.[0] * .[1]'` — a recursive merge, right-hand wins — so it
replaces the leaves it names and leaves every other key noctalia has written
alone. Verified against the live file before shipping: 25 key paths in, one
value changed, nothing added and nothing lost.

Pinned are the six conflicts [0020](0020-noctalia-is-a-desktop-mode.md) already
identified (wallpaper, night light, idle, lock-on-suspend, gsettings sync, app
theming) plus `plugins.autoUpdate` and, new here, **the colour scheme**:
`predefinedScheme = "Gruvbox"` with `useWallpaperColors = false`. The palette is
a machine-wide invariant with a check behind it, so noctalia's copy of it is
not a per-app preference to be clicked away.

Three failures this opens, each closed by `checks/static.sh` (all gated on
`dotfiles/mango/noctalia/` existing, so removal takes the checks with it):

- **noctalia ignores a settings key it does not know, in silence.** So every key
  path in both files is asserted to exist in the package's own
  `Assets/settings-default.json` — 25 today, with a floor at zero.
- **A scheme name that resolves to no file leaves the shell on whatever it last
  loaded**, which looks like a theme rather than a fault. The pinned name is
  resolved the way `ColorSchemeService.resolveSchemePath()` resolves it and the
  file asserted present.
- **A `layer_name:` matching no namespace is a rule that never fires.** The
  prefix is checked against the `namespace:` declarations in the shipped QML —
  the same shape as the rofi layer rules that matched nothing for months.

**The handover is one script, not three `exec=` lines.** Found the same day, by
switching tiling → noctalia → tiling → noctalia and getting no bar the second
time. The handover has an order and a failure path, and separate `exec=` lines
have neither:

- **Order.** swaync must release `org.freedesktop.Notifications` before noctalia
  claims it ([0005](0005-one-owner-per-daemon.md)), so the kill cannot race the
  start.
- **Failure.** Five crashes inside `StartLimitIntervalSec` leave the unit
  `failed` with `start-limit-hit`, and every later `start` then refuses.
  `systemctl` says so and exits 1 — but an `exec=` line has no reader for either,
  so the mode switch reports success and produces nothing. Fixing whatever
  caused the crashes does not clear it; only `reset-failed` does.

`scripts/modes/noctalia-start.sh` therefore `reset-failed`s before starting,
waits for the unit to be active **and still active 1.5 s later** (a crash-looping
unit is briefly active on every restart, so one check catches it in exactly that
window), and on failure restarts swaync and says so with `notify-send`. Losing
the bar and the notification daemon in the same instant is otherwise entirely
silent — there is nothing left to report with.

## Consequences

- **noctalia's Settings UI will visibly revert a pinned key on the next mode
  switch.** That is the trade, and it is why the split exists rather than
  pinning the whole file: everything outside the pin is genuinely free to
  change from the UI and survives. Change a pinned key in
  `settings-pinned.json`, then re-enter the mode.
- **The pin does not apply while noctalia is running.** The live shell holds
  settings in memory and writes the whole file back, so a merge underneath it
  would be undone without a word. Entering from tiling or hud always has the
  unit stopped, so this only trips on a direct re-run of `modes/noctalia.sh`,
  which now says so with `notify-send` instead of reporting a pin it did not
  apply.
- **The animation block in `universal/settings.conf` is upstream's default and
  has never been rendered.** Every mode had `animations=0`, so it was carried
  through the migration unexamined. noctalia mode is the first thing to display
  it, and the durations and curves there are a first tuning, not a settled one.
- **The two flat modes are unchanged.** tiling and hud keep the shared look;
  this is a divergence in one file, not a new theme layer.
- **Removal grows by exactly one path.** `settings-pinned.json` lives inside
  `dotfiles/mango/noctalia/` and the check block is gated on that directory, so
  both leave with the `git rm -r`; `scripts/modes/noctalia-start.sh` sits in the
  shared scripts tree, deliberately — the mango script-reference check only
  scans `~/.config/mango/scripts/…`, so a script parked in the mode's own
  directory would be the one thing nothing verifies. `docs/SYSTEM.md` §6's
  uninstall names it.
