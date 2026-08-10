# Gotchas — the failure catalogue

Everything here has actually broken this machine. Read the section for the area
you are about to change. `CLAUDE.md` carries the rules that apply to every task;
this file carries the ones that apply to one area.

Almost all of these share a shape: **the failure is silent**. A missing thing and
a broken thing look identical, so "it ran and exited 0" is not evidence.

- [Arch carryover](#arch-carryover) — state that survived via `@home`
- [nixpkgs and NixOS](#nixpkgs-and-nixos) — packaging traps
- [Desktop](#desktop) — mango, walker, elephant, swaync, wlogout
- [Waybar](#waybar)
- [Power](#power) — battery, suspend, hibernation, the GPU freeze
- [Editors](#editors)
- [Theming](#theming)
- [Networking](#networking)
- [Secrets](#secrets)
- [Scripts](#scripts)

---

## Arch carryover

`@home` is shared, so imperative state crossed the migration untouched. **Nothing
in this repo is wrong in these cases and no rebuild can fix them** — the bad
value lives in a profile directory. Suspect this shape for anything that worked
on Arch and now fails instantly and silently.

**Chromium/Electron apps that die instantly** — `~/.cache/<app>/SingletonLock` is
a symlink naming `<hostname>-<pid>`. The hostname is now `thinkpad`, not `arch`;
Chromium cannot check a PID on another machine, so it assumes the profile is open
elsewhere and exits 1 with **nothing on stdout or stderr**. Spotify failed this
way. Fix: rename `Singleton{Lock,Cookie,Socket}` aside. Presents as "my shortcut
isn't working", not as the app failing.

**Zen — everything is called `zen-beta`.** The flake installs the beta channel,
so the binary, the desktop file and the Wayland `app_id` are all `zen-beta`;
Arch's package used `zen`. Every reference had to change and each failed
silently — `xdg.mimeApps` pointed at a nonexistent `zen.desktop` (so https fell
back to chromium), and two `mango/universal/rule.conf` rules matched `appid:zen`
and never fired. Confirm an appid with `mmsg watch focusing-client`.

> `nvim/scripts/zen-wrapper` is unrelated — a knap preview wrapper that launches
> chromium in app mode. Don't "fix" it to use Zen.

**Zen's profile selection.** `profiles.ini` picks the default per-installation
via an `[Install<hash>]` section keyed on the **executable path**, which became a
store path. With no match, Zen fell back to the legacy `Default=1` flag, which
sat on a near-empty profile — so the first NixOS launch had no extensions, logins
or history. Fixed by moving `Default=1` onto `[Profile0]` (the real 839 MB
profile). **Do not add an `[Install<hash>]` entry for the current store path** —
it changes on every Zen update and would orphan the setting again.

**LibreOffice's "defective JRE" dialog** came from
`libreoffice/4/user/config/javasettings_Linux_X86_64.xml` recording an Arch JVM
path. Delete that file *and* its `user/pack/` copy (`SecureUserConfig=true` keeps
packed backups, so leaving the pack invites a restore); it regenerates as
`javaInfo xsi:nil="true"`, which raises no dialog. What made it want Java at all
was an orphaned Zotero extension — `unopkg list`, then `unopkg remove`. No JDK is
needed for ordinary use, and `javaldx` exiting 255 is the normal "no JRE" signal.

**`~/.config/systemd/user/` overrides `/etc/systemd/user/`**, so Arch-era units
silently shadowed generated ones. `micmute-led.service` was shadowed by a copy
with no `PATH=`, so `pactl` was not found and it restart-looped 6,464 times. That
directory now holds only home-manager symlinks, so the hazard is closed rather
than merely audited — keep it that way. A unit's `path` is its **entire** PATH,
including `bash` itself.

**NetworkManager profiles and Bluetooth pairings** were restored by hand into
root-owned directories and are **not declarative** — a decision, not a TODO.
Re-restoring reintroduces `autoconnect=yes`; see [Networking](#networking).

---

## nixpkgs and NixOS

**There is no `/bin/bash`.** `/bin` holds one entry, `sh`. A `#!/bin/bash`
shebang fails with exit 127 and *silence* — a waybar `custom/*` module whose exec
exits 127 renders as an empty module, which reads as the module being absent.
This bit 13 scripts after the migration. `checks/static.sh` now fails the build
on it.

**Wrapped binaries break `pkill -x`.** nixpkgs ships wrappers, so `comm` becomes
`.foo-wrapped`, truncated by the kernel to 15 chars (`.elephant-wrapp`). `-x`
matches `comm` exactly, so it silently matches nothing — every mango reload
leaked another elephant, and every swaync restyle hit an instance that never
died. Match the command line: `pkill -f 'bin/elephant$'`, `pkill -f '^swaync( |$)'`.

> **The `$` anchor only holds for a process invoked with no arguments.**
> `pkill -f 'bin/wlogout$'` matches nothing against
> `…/bin/wlogout -b 6 -c 12 …`, because `-f` matches the *whole* command line
> and the arguments come after the path. It exits 1 and leaves the process
> running — which, for a fullscreen layer-shell overlay, means it stays on
> screen. Drop the anchor when the process takes arguments.

**`buildEnv` collisions abort the whole generation.** Two packages owning one
file path is the failure to expect when adding packages. If one supersedes the
other, drop it; if they merely contend, use `lib.hiPrio` on the **winner** —
`lib.lowPrio` on the loser does nothing when the priorities are already equal.

**`cc` and `c++` are clang**, the reverse of Arch. `packages.nix` carries
`(lib.hiPrio clang)` to break a collision with `gfortran`, which ships its own
`cc`. `gcc`, `g++` and `gfortran` are all still on PATH.

**The nixpkgs attribute is not the binary name.** `clangd` ships in
`clang-tools`; the Nix LSP is `nil`; there is **no bare `pinentry`** attribute
(removed in favour of the variants, so `pkgs.pinentry` is an eval error).
Searching for the binary's name finds nothing and reads as "not packaged".

**`share/<pkgname>` is not in `environment.pathsToLink`**, so a package's data
files exist *only* at its versioned store path —
`/run/current-system/sw/share/wlogout/` does not exist even with wlogout
installed. Never hardcode `/usr/share/...`. The one safe absolute path is one
**computed at build time**: `programs.wlogout` interpolates each vendored PNG as
its own store path. GTK draws its missing-image box for a failed CSS `url()`
**without logging a warning**, so this class of bug is invisible in logs — it was
reported as "the icons are just square boxes".

**nixpkgs packages ship user units that Arch's did not, and they auto-start.**
nixpkgs' swaync ships `swaync.service` with `WantedBy=graphical-session.target`,
which raced the `exec=` line in `autostart.conf`; autostart won the bus name and
the unit died five times into `start-limit-hit`. Notifications worked throughout,
which is why it went unnoticed. It is masked via
`xdg.configFile."systemd/user/swaync.service".text = ""` — an empty unit file
loads as `masked`, and `source = "/dev/null"` is rejected by pure evaluation.
**Before trusting autostart to be the only owner**, check
`ls $(nix eval --raw nixpkgs#foo)/share/systemd/user/`. See `docs/adr/0005`.

**`Restart=` without `StartLimitBurst=` is a loaded gun.** A `rclone` unit
reproduced an Arch path that only worked by accident, could not create its mount
point, and retried every 5 s — 230 restarts, escalating past HTTP 429 into an
**account-level abuse restriction on Proton's side**. The damage landed on
someone else's service, not on this machine. Any unit that talks to a remote API
needs a start limit. See `docs/adr/0006`. (Proton Drive was removed outright;
don't re-add it — Proton blocks rclone's access method.)

---

## Desktop

### A tracked, linked file can still be inert

**The program has to be told where it is, and that pointer is config too.**
Three cases found on 2026-08-09, all of which looked fully converted:
`elephant` reads `~/.config/elephant/menus.toml` for its menu path, not the
mango tree the menus live in; `fsel` reads `~/.config/fsel`, reached only by a
hand-made symlink; the bitwarden provider reads
`~/.config/elephant/bitwarden.toml`. Every bridge was in `@home` and in no
repo, so all three worked here and on no other machine. All three are declared
now (ADR 0014), and `checks/static.sh` asserts the menu path.

The tell is never the filesystem — the file is present and linked either way.
Ask the program: `elephant listproviders` must name `menus:connectivity`.

### mango

**`mmsg` takes verbs, not flags:** `get`, `dispatch`, `watch`. Anything else
returns `{"error":"unknown command"}` **and exits 0**, so a script on the old
dwl-era `-s -d` form reports success while doing nothing. Five scripts and all
four waybar layouts were silently broken this way. Translations: `mmsg -s -d <f>`
→ `mmsg dispatch <f>`; `mmsg -w -c` → `mmsg watch all-clients`. There is **no
`get layout`** — the symbol lives on the monitor object:

```sh
mmsg get all-monitors | jq -r '.monitors[] | select(.active) | .layout_symbol'
```

Check the return value; it is the only signal you get. `checks/static.sh` fails
on a dash-flag `mmsg`.

**`mango/config.conf` is generated and gitignored, and the config it contains
*is* tracked.** The mode script does a verbatim `cp tiling/tiling.conf
config.conf`, so `config.conf` is a *copy of whichever mode is active* — tracking
it would commit a duplicate that changes on every mode switch. The real files are
`tiling/tiling.conf` and `hud/hud.conf`. Consequence for a fresh clone: mango
starts on built-in defaults — no waybar, no keybinds — until a mode script has
run once.

**`mango/walker/config.toml` is the same shape and once broke `rebuild`
outright.** Both `autostart.conf` files `ln -sf` it into place, but it was *also*
tracked, so home-manager wanted to own it: activation died with `Existing file …
would be clobbered`, and `backupFileExtension` does not rescue you. The timing is
the nasty part — the symlink only exists once a mode script has run, so the
failure surfaces after an unrelated mode switch. **When adding anything under
`dotfiles/mango/`, check nothing writes to that path at runtime.**

**Don't `sudo` the mango scripts.** Under sudo `~` is `/root`, so `reload.sh`
fails with `No such file or directory` and `MANGO_INSTANCE_SIGNATURE is not set`
— which reads like a broken install rather than a wrong user — and leaves a
**root-owned elephant** your own `pkill` cannot kill. `reload.sh` refuses to run
as root.

**Runtime state is `${XDG_STATE_HOME:-$HOME/.local/state}/mango`** (`current-mode`,
`waybar-layout`, `waybar-position`, `night-temp`, `last-vpn`). One script
disagreeing about that path made mode switching **one-way with nothing logged**:
`current_mode()` never found the file, fell back to `"tiling"`, and the
"already in that mode" guard exited 0. Running the mode script by hand always
worked, which hid it. If a mode switch goes one-way again, check that every
reader *and* writer agrees. `checks/static.sh` scans for the old path.
See `docs/adr/0003`.

**`bind=` matches on keycode; `bindsym=` matches on keysym.** So
`SUPER+SHIFT,slash` is correct and not dead: shift turns `/` into `question`, but
`bind=` entries resolve to keycodes at parse time and compare without consulting
the shift level. Same for `SUPER+SHIFT,1..9`. **If you switch a shifted bind to
`bindsym=`, spell out the shifted keysym** — otherwise it never fires, with
nothing in any log.

**`exec-once` fires only on initial compositor startup, not on reload** — log out
and back in after changing autostart. The `lxpolkit` line there is an Arch
leftover guarded by `command -v`, so it is a permanent no-op; the real agent is
the `polkit-gnome-authentication-agent-1` user service in `desktop.nix`.

**Editing `dotfiles/mango/` needs a rebuild** — `~/.config/mango` is a store path
with `recursive = true` (so the mode scripts can still `cp`), and the files there
are read-only copies. Rebuild, *then* reload.

### swaylock

**swaylock needs a PAM service declared by hand, or it can never unlock.** It is
not setuid and authenticates as the PAM service name `swaylock`; with no
`/etc/pam.d/swaylock`, PAM falls back to `other` = `pam_warn` + `pam_deny`, so
**every password is rejected, correct or not**. sway and river get this free from
`wayland-session.nix`, which `programs.mango.enable` does not import. Declared in
`modules/system/desktop.nix`. The only diagnostic is `pam_warn(swaylock:auth)` in
the journal — the lock screen just says the password is wrong.

**Do not `pkill swaylock` to escape it.** `ext-session-lock-v1` requires the
compositor to **stay locked** if the lock client dies without sending
`unlock_and_destroy` — that is the protocol's guarantee, not a bug. You get a
permanently blank surface with the session still locked, and `mmsg` has no unlock
command. The ways out are relaunching swaylock on the same `WAYLAND_DISPLAY` to
take over the abandoned lock, or restarting the session.

**That is why lock-on-sleep is swayidle and not a `powerManagement` hook.** A
root sleep hook runs inside `sleep-actions.service`, which is
`RemainAfterExit` and **stopped on resume** — systemd then kills its cgroup,
including the `swaylock -f` the hook forked into it. The result is the
permanently blank locked surface above, arriving every single resume. swayidle
runs in the user session instead, and its `-w` sleep inhibitor also guarantees
the lock is up *before* the suspend rather than racing it.

**`programs.swaylock.package` must be `null` here.** `desktop.nix` installs
**swaylock-effects** system-wide and declares PAM for it, but the home-manager
module defaults to installing plain `pkgs.swaylock`, which lands *earlier* in
PATH and would shadow it. Measured against swaylock 1.8.6: it **lacks
`clock`, `timestr` and `datestr`** (though it does have `indicator` and
`indicator-idle-visible`), so the clock — the entire reason the lock screen is
configured this way — just stops appearing.

⚠️ **swaylock exits 0 on an unrecognised config key.** It prints
`unrecognized option '--clock'` and a full usage dump, and the exit status is
`0` for a good config and a bad one alike. Only the output tells them apart.

> **Validating the config without locking yourself in**: swaylock parses its
> config *before* it connects to the compositor, so
> ```
> env -u WAYLAND_DISPLAY swaylock --config ~/.config/swaylock/config -f
> ```
> exercises the parse and then fails to find a display, locking nothing.
> **Silence means it parsed.** Any usage dump means a key was rejected.

That config is also the *only* one now: `~/.config/swaylock/config` used to be
an **untracked** hand-written file that quietly supplied the theme to every bare
`swaylock -f`, alongside two more copies at `mango/{tiling,hud}/swaylock.conf`
for the `--config` binds. All three are gone.

### walker / elephant

**An elephant provider whose backing CLI is missing does not load, and says
nothing.** `SUPER+P` opened an empty window for weeks because `bitwarden.so`
shells out to **`rbw`**, which was never declared — while `~/.config/rbw/` had
come across via `@home`, so the config surviving made it look verified. **The
diagnostic is `elephant listproviders`**: the provider is simply absent, while
its `.so` sits in the store next to the ones that loaded. `rbw`, `wtype` and
`pinentry-qt` are declared now.

---

## Waybar

The eight `config-<layout>-<position>.jsonc` files are **generated** by
`modules/home/waybar.nix` — there are no `config*.jsonc` in this repo. Each
module is defined once and a layout is a list of names, so **a module name with
no definition is an eval error rather than an empty module**. Two asserts back
it: one for undefined names, one for a `tweaks` entry targeting a module the
layout does not carry (which waybar ignores in silence). The stylesheets stay
hand-written — hand-tuned presentation is data, not settings.

`xdg.configFile` writes them into `~/.config/mango/waybar/`, which coexists with
the recursive mango link **only** because the hand-written `.jsonc` files were
deleted. Two owners for one path is an activation failure.

**`on-scroll-up` on the volume and backlight modules DECREASES, and that is
correct.** `trackpad_natural_scrolling=1` makes libinput invert the axis before
any client sees it, so fingers-up arrives as `on-scroll-down`. Reading the
generated JSON alone makes this look like an inversion bug; it was "fixed" on
that basis once and reverted. Note `mouse_natural_scrolling=0`, so an external
wheel gets the opposite behaviour and no single config serves both. `-l 1.5` is a
volume ceiling and belongs on whichever direction increases.

> `mpris` and `ext/workspaces` disagree about scroll direction in either frame.
> Known, deliberately left alone — flag it rather than changing it unasked.

**Glyphs in `waybar.nix` must be literal UTF-8** — Nix has no `\uXXXX` escape.
Transcribing them by hand is exactly how this repo loses icons; four `network`
glyphs were silently changed during the conversion and had to be recovered from
git by codepoint. Verify with `jq -r` piped through a codepoint dump, not by eye.
A glyph the font lacks renders as an empty box with nothing in any log — check
with `fc-list ':charset=<hex>' family` before swapping one in.

**Icon-only modules need a font with a full 1em advance.** `custom/power-profile`
renders in `Symbols Nerd Font Mono`, not the bar's `3270 Nerd Font`: 3270 patches
Font Awesome icons in at natural width but keeps a narrow 0.54em advance, so the
ink overflows its cell to the right with all the slack on the left. **Padding
cannot fix it** — symmetric padding centres the advance box, not the ink. The
module gets *wider* when fixed, since the real advance was understated.

**`#taskbar button` must keep `min-width` ≤ `icon-size`.** waybar `pack_start`s
the icon, so any width beyond the icon becomes empty space on the **right only**.
The two numbers are coupled — change both together.

**`custom/power`'s `wlogout -b N` must equal the wlogout entry count**, which is
declared in a different file (`programs.nix`). `-b` is a column count, not a
maximum: leave it at 5 after adding a sixth entry and the extra button wraps
onto a second row that `-T 320 -B 320` has left no height for.

**Do not reintroduce `dwl/window`.** mango 0.15.5 dropped the `zdwl_ipc_manager_v2`
protocol that module binds, and its absence makes waybar **SIGSEGV on startup**.
The title comes from `custom/window` (`scripts/waybar/window-title.sh`); the CSS
selector is `#custom-window`.

**The bar shows the RAW battery percentage — `full-at` was removed, do not put it
back.** It rescaled the reading as `shown = real / full-at × 100` so TLP's 85%
stop would read 100%, which made the bar disagree with fastfetch, `upower` and
sysfs by a constant factor forever. That is not a bug you notice, it is one you
*explain* — it absorbed two separate reports of the module freezing before anyone
checked whether the number was stale rather than merely rescaled.
`checks/static.sh` asserts no generated config carries it. Consequence: the bar
parks at 85% on AC and never reads 100%, and `states.warning = 30` now fires at a
real 30%.

**The battery module freezes — an open waybar bug.** The tell is an
**asymmetry**: the CSS class tracks reality while the label text does not (the
module renders `#battery.warning`, which needs a reading ≤30, while displaying
81%). `Battery::update()` applies the CSS class as a *side effect* of
`getState()`, and `label_.set_markup()` is the last statement; `bar.cpp` wraps
the whole call in a `try`/`catch` that logs and continues. **Anything that throws
between those two lines leaves the class current and the text frozen forever,
with the module still repainting.** What throws is still unknown, because
`waybar-restart.sh` used to discard stderr — **stderr now goes to
`~/.local/state/mango/waybar.log`, with the previous run kept as `waybar.log.1`.
When the number sticks again, read that file *before* restarting.** Workaround:
`waybar-reload`. Do not reach for `full-at` or the charge thresholds — a frozen
module and a rescaled one look identical in a screenshot, which is how this
survived two rounds.

> Diagnostics: `/var/lib/upower/history-charge-*.dat` logs one line per change,
> so it dates a freeze precisely — a click-corrected reading that predates the
> last gap means the module was stuck, not the battery. waybar 0.15.0 has a stray
> `puts()` in `Battery::update()`, so a throwaway single-module instance gives an
> exact one-line-per-update counter (use `stdbuf -o0`; the live bar discards
> stdout).

> `bat`/`adapter` are named explicitly. Auto-detection keeps the **last**
> `/sys/class/power_supply` entry carrying `online` or `status`, decided by
> readdir order — this machine has four supplies and it resolved to `AC` only by
> luck.

**When a `custom/*` module is missing from the bar, run its exec by hand and
check the `text` field is non-empty** — not just that the script succeeds. An
empty custom module is indistinguishable from an absent one. `custom/power-profile`
emitted `{"text":""}` for a while because its icons were written as literal
glyphs and lost in transit; they are `$'\uXXXX'` escapes now, deliberately.

---

## Power

`docs/SYSTEM.md` §9 is the reference for battery thresholds, suspend, hibernation
and the WiFi resume fix. The traps worth carrying in your head:

- **A lit panel during suspend is a battery bug, not a cosmetic one** — the
  DISPLAY block tracks the CRTC, so it holds s0i3 off and the machine idles at
  ~4 W through what looks like sleep. **The backlight cannot fix it**;
  `brightnessctl` and `bl_power` only drive PWM, and hooks written that way
  succeed, exit 0, and change nothing. `wlopm --off '*'` is the mechanism.
- **s0i3 is never reached even so** (~3 W, every IP block idle). Cause unknown,
  search space unbounded, hunt abandoned in favour of hibernation. If suspend
  drain is suspected again, read `/sys/kernel/debug/amd_pmc/smu_fw_info` **first**
  — it names the offending IP block in one command.
- **Nothing locked the screen on sleep until swayidle** — logind's
  `HandleLidSwitch` suspends, it does not lock, so a closed lid resumed straight
  to the desktop. See the swaylock section for why the lock handler cannot be a
  `powerManagement` hook.
- **Hibernation's `resume_offset` fails silently**: the machine boots fresh and
  discards the session, presenting as "hibernate didn't work". It is valid only
  for the exact swapfile that exists now.
- **The kernel log cannot tell you whether a hibernate succeeded** — the image is
  snapshotted *before* the write, so success and refusal leave byte-identical
  traces. The primary signal is the machine physically powering off. Do not set
  `HibernateMode=shutdown` on that misreading; it was tried and reverted.
- **Re-test "this protocol isn't available" claims.** This file long asserted
  mango advertised no `wl_output`, so DPMS was impossible — which is what sent
  sleep blanking down the backlight path that could never have worked, and cost a
  flat battery to discover. `wlopm --json` is one command.

### The amdgpu/TTM freeze

A GPF in `ttm_lru_bulk_move_tail` kills the faulting task **while it still holds
the TTM `lru_lock`**, so every later GPU touch deadlocks and one oops becomes a
total hang. Power-cycling mid-freeze then **latches the i8042**, so the next boot
has a greeter that accepts no keystrokes — which looks like a PAM/greetd fault
and is not; a full power cycle clears it.

Mitigated, not fixed: Overdrive removed (the prime suspect and the differentiating
variable vs Arch), `kernel.panic_on_oops = 1` + `kernel.panic = 10` (which is what
breaks the double-hard-reset chain), `kernel.sysrq = 1`. **No kernel version
change will fix this** — the code has been unchanged since 2021, so there is
nothing to bisect. Don't drop to `pkgs.linuxPackages` hoping otherwise.

**Reading an old journal as `henry` greps to zero exactly like a clean history.**
`system@*.journal` is ACL'd to a GID this user is not in, so an unprivileged
`journalctl -D <dir>` silently reads only the `user-1000@` session files, which
carry no kernel messages. This produced a confident "zero crashes on Arch" that
was an artefact of the read. Confirm the `Linux version` lines are non-empty
before believing any zero.

---

## Editors

**No mason, and helix ships no servers either — language servers come from
`$PATH`**, so they must be declared in `modules/home/packages.nix`. A missing
server is **skipped in silence**: after the migration only `rust-analyzer`
worked, and nobody noticed for a day. All 12 resolve now.

```sh
for s in nil lua-language-server bash-language-server marksman taplo \
         yaml-language-server pyright ruff clangd typescript-language-server \
         texlab tinymist stylua shfmt gopls; do
  command -v $s >/dev/null || echo "$s MISSING"
done
```

**`typescript-language-server` does not bundle `tsserver`** — nixpkgs ships it
with an empty `node_modules`, so it resolves typescript from the workspace or
`$PATH`. Without a separate `typescript` entry the server starts and then fails
on any file outside a project with its own `node_modules`, which looks like the
server being broken rather than absent.

**The two editors disagree about Python.** nvim asks for `pyright`; helix's
defaults are `ty`, `ruff`, `jedi-language-server` and `pylsp`, none of which is
pyright. So helix gets lint and format from `ruff` but **no type checking**.
Deliberately not closed. **Always confirm with `hx --health <lang>`** rather than
assuming a server declared for nvim serves helix — it is the fastest audit,
one line per language with `✘` against anything it cannot find.

**The binary is `hx`, not `helix`.** The desktop entry ships `Exec=hx %F`, so the
launcher works while typing `helix` does not. Nothing is broken.

`$EDITOR`/`$VISUAL` are `nvim` — that is what git, `sudoedit`, `systemctl edit`,
lazygit and yazi invoke, so changing editors means changing those, not adding an
alias. `mimeapps.list` separately points markdown and shell scripts at
`nvim.desktop`, which governs GUI double-clicks only.

`nvim` and `helix/themes/gruvbox.toml` stay hand-written on purpose — see
`docs/SYSTEM.md` §6. See also `docs/adr/0007`.

---

## Theming

**Terminal colours are generated from a single Nix palette.** kitty and foot are
built by `modules/home/programs.nix` from one `gruvbox` `let` binding (kitty
takes `#rrggbb`, foot bare hex). Change the palette there, once — the two files
used to carry the same sixteen values with nothing keeping them in step.

**GTK theming is owned by Nix** (`modules/home/theme.nix`), not by the mode
scripts: both `settings.ini` files, both `gtk.css` files, the Thunar bookmarks
and the dconf keys. `gtk-apply.sh` now only exports `GTK_THEME` to the systemd
user environment and restarts `xdg-desktop-portal-gtk` (which caches the theme at
startup). **Never have both setting the theme** — one owner, in either direction.
See `docs/adr/0004`.

**Papirus folder icons are recoloured at build time.** Stock folders are blue,
which reads as badly broken against Gruvbox — the symptom is Thunar looking
correctly themed *except* every folder. The usual fix, the `papirus-folders` CLI,
recolours the theme **in place** and so cannot work: the icon theme is a
read-only store path, and the tool silently achieves nothing. `pkgs/default.nix`
overrides the package with `color = "yellow"` instead. It is done in the
**overlay** rather than at the call sites because both `gtk.iconTheme.package`
and `systemPackages` reference the theme — overriding one would put two Papirus
derivations on `XDG_DATA_DIRS` and let lookup order pick the folder colour.

**Indirection that selects nothing is this repo's recurring dead weight.**
`kitty/active-theme.conf`, the `gtk-*-tiling` variants and `waybar/style.css`
were each a switch whose arms were identical or unreachable, left behind when the
`dms` mode was removed. Before adding a per-mode variant, check the modes
actually differ.

Baseline: **Gruvbox Dark**, Hack Nerd Font Mono 11 in the terminals. Modes are
**tiling** (Gruvbox Orange) and **hud**; the active one is in
`~/.local/state/mango/current-mode`.

---

## Networking

Full detail in `docs/SYSTEM.md` §9. The two things that mislead:

**WiFi does not survive resume** — `ath11k_pci` does not cleanly reinitialise and
DHCP times out. **Two layers, both needed and not mergeable**: TLP disables radio
power saving for normal runtime (applied by its service), and
`systemd.services.wifi-resume` cycles the radio 3 s after wake (executed by
systemd) — the latter is what actually fixes resume. Both are declarative; `/etc`
is generated and read-only, so don't edit it.

**VPN autoconnect is off on all nine profiles, deliberately.** They came off the
backup with `autoconnect=yes`; `homelab` auto-activated, claimed the default
route, and pushed DNS `192.168.1.5` onto every link — so away from the home LAN
**all** name resolution failed. Nothing identifies itself as a VPN problem at
that point; it presents as total DNS death. Check `resolvectl status` for a
tunnel holding `Default Route: yes` before suspecting anything else. Since
2026-08-09 the nine are declared in `networking.nix` and `checks/static.sh`
fails the build on a missing `autoconnect=false`, so this is enforced rather
than remembered (`docs/adr/0013`).

**Editing one of the nine from a GUI silently un-declares it.** All three
keyfile directories are read — `/etc`, `/run`, `/usr/lib` — and `ensureProfiles`
writes to `/run`. An `nmcli con modify` writes a *new* file into `/etc` with the
same UUID, and one of the two is then ignored, so the profile you edit and the
profile Nix generates stop being the same thing with no error either way. The
tell is `nmcli -f NAME,FILENAME con show`: the nine must report a `/run/...`
path. This is why the hand-restored `/etc` copies had to be moved aside when
they were declared — leaving them made the declaration a no-op.

**The other 29 profiles are deliberately not declared.** `ensureProfiles`
deletes nothing, so a subset is the supported shape. Don't "finish the job" by
adding the ordinary access points: it moves 29 hotel WiFi passwords into sops to
buy nothing.

> `git.henrydowd.dev` is `192.168.1.200`, a LAN address — on `192.168.1.0/24` it
> is reachable directly and the tunnel is not involved. Bring it up by hand only
> when away: `nmcli connection up homelab`.

---

## Secrets

`secrets/secrets.yaml` is sops-encrypted and tracked in git. The age key is
`/var/lib/sops-nix/key.txt`, in no repo and no backup — **back it up separately**,
or that file is unreadable and a fresh install cannot reach the VPN.

**Edit with `nix develop -c sops secrets/secrets.yaml` from the repo root.** sops
resolves recipients from the `.sops.yaml` in the *working directory*, so running
it from inside `secrets/` makes the relative path resolve to a file that does not
exist — at which point sops silently opens its `hello: Welcome to SOPS!` template
for a *new* file instead of erroring. **That template is the tell.** `sops` and
`age` are devShell-only for exactly this reason.

**A secret is DECLARED only where something reads it.** `sops.secrets.<name>`
decrypts to `/run/secrets/<name>` on every boot, so declaring one nothing
consumes just puts plaintext on a running system. Declared: `pia/username`,
`pia/password`. Stored-only (recover with `sops -d --extract`): the `homelab`
WireGuard key and the `gh`/`glab`/`tea` tokens — those three CLIs rewrite their
own config, which is the `corectrl` fight.

`checks/static.sh` asserts every `secrets/*.yaml` carries the `sops:` metadata
block, because **an unencrypted secrets file looks exactly like an encrypted
one** unless you open it, and the mistake is unrecoverable once pushed. It does
**not** check the values are real — a file of placeholders encrypts and passes.

Changing the PIA credentials is `sops` then `rebuild`; `vpn-menu.sh` has no "set
credentials" entry, because a sops secret is root-installed mode 0400. A fallback
to a writable file was rejected on purpose — it would leave "no plaintext secret
outside sops" unenforceable. See `docs/adr/0012`.

---

## Scripts

`dotfiles/scripts/` → `~/.scripts`, a **store path**. Before they moved into the
repo they existed on this disk only, while `audio.nix` declared a unit whose
`ExecStart` pointed at one — so a fresh install produced a unit that could not
start.

**None of them have a file extension.** Don't add `.sh`; fish's aliases did, and
were therefore always broken.

| Script | Note |
|---|---|
| `micmute-led` | syncs the ThinkPad mic-mute LED with PipeWire. Runs as the user service in `audio.nix`, which is the **only** place `pactl` exists (from `pkgs.pulseaudio`, deliberately not in `systemPackages`) — so running it from a shell fails with `pactl: command not found` |
| `toggle_lid_action` | **inert on NixOS**, and fails in a way that reads like permissions: it edits `/etc/systemd/logind.conf` in place, which is a symlink into a read-only store path, so it exits 1 with `Permission denied` and `sudo` does not help. Reading still works. The setting is declarative in `power.nix`. Kept only to answer "what is it set to" |
| `clean_tmp` | `cleantmp` alias |
| `keyd-application-mapper` | per-application keyd layers |
| `pdf_to_a4` | Ghostscript A4 conversion, aspect preserved |
| `texpdf` | pdflatex + aux cleanup |
