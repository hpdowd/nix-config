# Gotchas — the failure catalogue

Everything here has actually broken this machine. Read the section for the area
you are about to change. `CLAUDE.md` carries the rules that apply to every task;
this file carries the ones that apply to one area.

Almost all of these share a shape: **the failure is silent**. A missing thing and
a broken thing look identical, so "it ran and exited 0" is not evidence.

- [Arch carryover](#arch-carryover) — state that survived via `@home`
- [nixpkgs and NixOS](#nixpkgs-and-nixos) — packaging traps
- [Desktop](#desktop) — mango, rofi, swaync, wlogout
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

**`pgrep -x` fails the same way, and `pgrep -f` cannot replace it in a guard.**
All four `pgrep -x` targets in the repo were dead: `elephant`, `kdeconnectd` and
`awww-daemon` are wrapped, and the compositor's `comm` is `mango` — `mangowm`
was never a process name. The read-only form fails in *both* directions: a guard
that never matches respawns a running daemon, and a liveness test that never
matches exits a healthy loop (`scratch-watch.sh` could only ever `exit 0` on
reconnect). `phone-status.sh` reported "KDE Connect not running" against a
kdeconnectd that had been up since boot.

Swapping in `-f` is a trap here, because a guard's own shell is a match:
`pgrep -f 'kdeconnectd$' || kdeconnectd` matches the shell running that very
line — the cmdline ends in `kdeconnectd` — so the guard is now permanently
*true* and the daemon never starts. Anchoring on `bin/` does not help either;
`kdeconnectd` and `mango` are invoked bare, so their cmdline carries no path.

**Match `comm` with a regex that tolerates the wrapper's dot:**

```bash
pgrep '^\.?kdeconnectd' >/dev/null || kdeconnectd   # matches .kdeconnectd-wr
```

`comm` never contains the guard's own command line, so it cannot self-match, and
the `\.?` prefix plus prefix-matching absorbs both the wrapper dot and the
15-char truncation. Keep `-x` only for a binary that is genuinely unwrapped, and
anchor it (`pgrep -x mango`) — a bare prefix would also match `mangohud`.
`checks/static.sh` resolves every `-x` target through both profiles and fails on
a wrapped one.

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

**The node named `nixpkgs` in `flake.lock` is not our nixpkgs.** Node names are
allocated in traversal order, so `claude-desktop`'s un-`follows`ed nixpkgs took
the bare name and ours is **`nixpkgs_3`**. Reading
`.nodes.nixpkgs.locked.rev` therefore reports the wrong flake's pin — and
convincingly, since it is a real nixpkgs rev that moves on its own schedule. It
made a `nix flake update` that had bumped our nixpkgs by 18 months of aliases
look like it had changed nothing. Resolve the name first:

```bash
jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' flake.lock
```

---

## Desktop

### A script committed 644 is a dead key

**Nix preserves the mode bit, so a `bind=` pointing at a non-executable script
does nothing and exits 0.** Found on 2026-08-14 while adding `notify.sh` for the
noctalia mode: the file was written without `chmod +x`, arrived in the store as
`-r--r--r--`, and `CTRL+ALT+\` silently stopped toggling notifications. Nothing
logged, and the file is present and correctly linked in `~/.config` — the same
tell as the section below.

`checks/static.sh` had asserted exactly this for scripts named by a **waybar
config** since the empty-module bugs, but not for the far larger set named by
`bind=` and `exec=` lines in the mango tree. It now covers both, and fails on a
reference count of zero rather than passing by matching nothing.

The tell: `ls -lL ~/.config/mango/scripts/<name>` — the target's mode, not the
symlink's. Git tracks the bit, so `chmod +x` needs a `git add` to take effect in
the build.

### noctalia and swaync cannot both run

**The second claimant of `org.freedesktop.Notifications` does not error — it
just never receives a notification.** noctalia-shell is a notification daemon as
well as a bar, so `noctalia/autostart.conf` kills swaync and does not restart it,
and `tiling/`+`hud/` restart swaync and stop the noctalia unit. ADR 0005 is the
general rule; ADR 0020 is this instance.

Verify by ownership, never by "it started": `busctl --user status
org.freedesktop.Notifications` names the owning PID. `notify-send test` then
tells you which one drew it.

### The noctalia bar does not appear, and nothing says why

**Two failures stack, and the second one hides the first.** Seen 2026-08-15
after switching tiling → noctalia → tiling → noctalia: the second entry produced
no bar at all.

The crash is `Failed to create wl_display (No such file or directory)` followed
by Qt's `no Qt platform plugin could be initialized` and `SIGABRT`, ~700 ms in.
It means the **systemd user manager's** `WAYLAND_DISPLAY` names a socket that is
not there — the manager has its own copy of the environment, published once by
`dbus-update-activation-environment --systemd --all` in
`universal/autostart.conf`, and it does not track the session afterwards.
Compare the two directly; they are supposed to agree:

```sh
systemctl --user show-environment | grep -E 'WAYLAND_DISPLAY|^DISPLAY|MANGO'
printf '%s %s %s\n' "$WAYLAND_DISPLAY" "$DISPLAY" "$MANGO_INSTANCE_SIGNATURE"
# repair, from inside the session:
dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY MANGO_INSTANCE_SIGNATURE
```

⚠️ **Running a nested mango is how the environment goes stale.** The nested
instance runs the live `universal/autostart.conf`, whose first line republishes
*its* `WAYLAND_DISPLAY` into the user manager; killing it then leaves the
manager pointing at a socket that no longer exists, and every user unit started
afterwards connects to nothing. This is the same trap as the config paths above,
one layer further out — strip the `autostart.conf` sources from any test config.

**Then the unit wedges, and that is what makes it look intermittent.** Five
crashes inside `StartLimitIntervalSec` leave it `failed` with
`start-limit-hit`; after that `systemctl --user start` refuses with "attempted
too often" and exits 1 — but an `exec=` line in an autostart has no reader for
that, so the mode switch reports success and produces nothing. So **fixing the
environment is not enough**: the unit stays wedged until a `reset-failed`.
`scripts/modes/noctalia-start.sh` now does that on every entry into the mode,
waits for the unit to be up *and stay* up, and restores swaync with a
`notify-send` if it does not — losing the bar and the notification daemon at
once is otherwise completely silent.

### noctalia's workspace widget is empty, and the shell says so once

**mango advertises no dwl IPC, so noctalia's Workspace and ActiveWindow widgets
render nothing** — and the Workspace widget is the centre of its bar. The shell
picks the right backend and reports it (`MangoService Initializing MangoWC/DWL
compositor integration (DWL protocol)`), which reads like success; every path in
that backend is then guarded on `DwlIpc.available`, which is false forever.
quickshell probes for the Wayland global `zdwl_ipc_manager_v2`; mango 0.16.0
creates only `wlr_*` globals, and `mmsg`'s JSON socket is a different interface
that noctalia uses for two unrelated calls. One line at startup is the whole
tell:

```sh
journalctl --user -u noctalia | grep 'DWL is not available'
```

**Read this as a method, not a fact about one widget.** `docs/adr/0020` recorded
the integration as working because `MangoService.qml` exists and is selected —
a file's existence stood in for a running system, in the one repo whose first
rule is that those look identical. A compositor integration is only confirmed by
watching the widget change when you switch tags.

### `noctalia-shell ipc call` exits 0 when the name is wrong

**`Target not found.` and `Function not found.` are printed, and the status is
0.** A successful void call prints nothing. So **output is the signal** and the
exit status tells you nothing — the same shape as the dwl-era `mmsg -s -d` that
broke five scripts here. Test a call by capturing it, never by `&&`:

```sh
out=$(noctalia-shell ipc call launcher toggle 2>&1); [ -z "$out" ] || echo "FAILED: $out"
noctalia-shell ipc show   # the authoritative list of targets and functions
```

`checks/static.sh` pairs every call in `scripts/menus/shell.sh` against the
`IpcHandler` blocks in the shipped QML, matching the function *inside* its own
target — `dock clear` would otherwise pass, because `notifications` declares
`clear`.

**Its logout is inert on this machine.** `MangoService.logout()` runs
`mmsg -s -q`, the flag form mango answers with `{"error":"unknown command"}` and
exit 0. The session menu's logout button is disabled in `settings-pinned.json`
for that reason — a missing button beats one that silently does nothing.

### noctalia's whole mango backend spoke dwl, so the launcher did nothing

`logout()` above was not the only one. **Five calls in `MangoService.qml` used
the `mmsg -s -d <func>` flag form**, including `spawn()` — which is what
`ApplicationsProvider` reaches through `CompositorService.spawn()`, so **picking
an app in noctalia's launcher launched nothing**. Not every time, which is why it
went unnoticed: entries whose `Exec` has quoted or spaced arguments take an
earlier branch (`app.execute()`) and do work.

The overlay rewrites them to `mmsg dispatch` (`docs/adr/0025`), with a check
pairing each verb against mango's own function table — `mmsg` answers an unknown
*function* exactly as it answers an unknown *command*: `{"error":…}`, exit 0.

Two calls are deliberately left in the flag form. `mmsg -g -A` (display scales)
and `mmsg -s -t` (tag switch) need a different call **shape**, not a different
spelling; they are the `DwlIpc` half above, behind the empty workspace widget.

⚠️ **Once a package is overridden in the overlay, `prev.<pkg>` is the wrong
one.** Every consumer must take `final.`, or the system carries two closures and
they are not interchangeable: **quickshell resolves an ipc target by the
`shell.qml` PATH the instance was started from**, so a caller built against the
unpatched derivation gets `No running instances` while the shell is up. The
`lockscreen` wrapper is the one that matters — it would hand every unattended
lock back to swaylock, indistinguishably from noctalia simply being down.
`checks/static.sh` pins the wrapper's copy to the system's.

⚠️ **This also decides where your applications live.** `mmsg dispatch
spawn_shell` makes them children of **mango**, in the session scope. The
alternative fix — noctalia's `appLauncher.customLaunchPrefix`, which routes
through `Quickshell.execDetached` — makes them children of the *shell*, inside
`noctalia.service`, whose `KillMode=control-group` means **a mode switch kills
everything you launched from noctalia**. Same for anything started from the dock.

### Leaving noctalia mode leaves 1 MB of tmpfs behind, every time

The shell itself exits cleanly — the unit's cgroup takes the whole tree,
`setsid` and all — but **quickshell never removes its instance directory**. Each
start leaves `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/` holding a socket, a lock
and a `log.qslog` that reaches 1.5 MB. It *knows* they are dead: every failed
`ipc call` prints a "Dead instances:" list naming them. 18 of them were holding
11 MB of RAM on 2026-08-16.

`noctalia-start.sh` prunes them before each start, using quickshell's own
`by-pid/` index for liveness rather than parsing the binary lock file.

```sh
du -sh "$XDG_RUNTIME_DIR/quickshell"   # what it has accumulated
```

### Entering noctalia mode used to end night light for the session

`NightLightService.qml` runs **`pkill -x wlsunset` in `Component.onCompleted`,
unconditionally** — on every start, whether or not `nightLight.enabled` is
pinned off. It matches: this repo's wlsunset is unwrapped, so `comm` is plain
`wlsunset` and `-x` hits (the usual `-x`-misses-the-wrapper trap does not save
you here — see Scripts).

The reason it stayed dead is systemd's, not noctalia's. **`Restart=on-failure`
does not restart a process killed by SIGTERM**: systemd counts SIGTERM, SIGINT,
SIGHUP and SIGPIPE as *clean* exits. Confirmed with a transient unit —
`Result=success`, `NRestarts=0`. `night-light-run.sh` ends in `exec wlsunset`,
so wlsunset **is** the unit's main process and takes the signal directly.

The unit is now `Restart=always`, with a check on it. noctalia's own journal is
where this was found, and it says so plainly:

```sh
journalctl --user -u noctalia | grep 'Killed stale wlsunset'
systemctl --user show wlsunset -p NRestarts -p ActiveState
```

### Editing noctalia's settings seed changes nothing

**`noctalia/settings.json` is written once, when there is no file at all**, so
on any machine that has entered the mode even once, adding a key there is a
change that lands in the repo and never on the machine — which looks exactly
like a key that does not work. The half that *does* apply is
`noctalia/settings-pinned.json`, merged over the live file on every entry into
the mode (ADR 0022). Put a setting that must hold there; put a preference the
UI may keep in the seed.

**noctalia ignores a settings key it does not know, in silence** — no log, no
fallback, and the UI shows its own default. So a key renamed upstream stops
applying and reads as never having been set. `checks/static.sh` asserts every
key path in both files still exists in the package's
`Assets/settings-default.json`.

The pin is skipped while the shell is running, because noctalia holds settings
in memory and writes the whole file back. It says so with `notify-send` rather
than reporting a merge that was about to be overwritten.

### A tracked, linked file can still be inert

**The program has to be told where it is, and that pointer is config too.**
Three cases found on 2026-08-09, all of which looked fully converted:
`elephant` read `~/.config/elephant/menus.toml` for its menu path, not the
mango tree the menus lived in; `fsel` reads `~/.config/fsel`, reached only by a
hand-made symlink; the bitwarden provider read
`~/.config/elephant/bitwarden.toml`. Every bridge was in `@home` and in no
repo, so all three worked here and on no other machine. All were declared
(ADR 0014); the elephant pair left with walker.

**`rofi` is the live instance of the same shape.** It reads
`~/.config/rofi/config.rasi` and nothing in the mango tree points at it, so
`modules/home/dotfiles.nix` naming that path is the only thing connecting the
two — and rofi with no config falls back to its built-in theme rather than
erroring. `checks/static.sh` asserts the declaration exists.

The tell is never the filesystem — the file is present and linked either way.
Ask the program: `rofi -no-config -h` must list the modes you expect.

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

**`mango/walker/config.toml` was the same shape and once broke `rebuild`
outright.** Each `autostart.conf` `ln -sf`'d it into place, but it was *also*
tracked, so home-manager wanted to own it: activation died with `Existing file …
would be clobbered`, and `backupFileExtension` does not rescue you. The timing was
the nasty part — the symlink only exists once a mode script has run, so the
failure surfaced after an unrelated mode switch. It is gone with walker (rofi
has one config for every mode), but **when adding anything under
`dotfiles/mango/`, check nothing writes to that path at runtime.**

**Don't `sudo` the mango scripts.** Under sudo `~` is `/root`, so `reload.sh`
fails with `No such file or directory` and `MANGO_INSTANCE_SIGNATURE is not set`
— which reads like a broken install rather than a wrong user — and used to
leave a **root-owned elephant** your own `pkill` cannot kill. `reload.sh`
refuses to run as root; it no longer restarts any daemon, because rofi has
none.

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

**The parser is last-wins, and `source=` is processed inline at its position.**
So a key set *after* a `source=` overrides what that file set — which is how
`noctalia/noctalia.conf` sources the shared settings and then disagrees with
them (ADR 0022) — and the same key set *before* it is silently discarded.
Measured on 2026-08-15, not assumed. The probe is cheap, because one option has
a value you can read back:

```sh
# in a scratch HOME: sub.conf sets `xkb_rules_layout=de`, config.conf sources it
# and then sets `us`. `mmsg get keyboardlayout` names the winner.
printf 'source=./sub.conf\nxkb_rules_layout=us\n' > "$H/.config/mango/config.conf"
```

**mango ignores `XDG_CONFIG_HOME` — it reads `$HOME/.config/mango/config.conf`.**
This bites exactly when testing: a nested instance started with a scratch
`XDG_CONFIG_HOME` reads the **live** config and runs the live `autostart.conf`
against the running session, killing waybar and starting daemons. Override
`HOME`, not `XDG_CONFIG_HOME`, and strip the `autostart.conf` sources from the
test config.

**Settings are last-wins but BINDS ARE FIRST-WINS, and a duplicate warns.**
Binds append (`parse_config.h`: `realloc(… count + 1 …)`) and the dispatcher
stops at the first match (`src/mango.c`, `only match the first keybind`), so a
mode conf sourced *ahead* of `universal/bind.conf` does override it — the exact
opposite of the rule for scalar settings two paragraphs up. Do not use it
without a reason: mango also prints `[WARNING] Key binding conflict` naming both
files and both lines for every duplicate, unless both binds carry the `c` flag,
and a handful of those trains you to ignore the one that matters. Mode-dependent
keys go through `scripts/menus/shell.sh` instead (ADR 0023); only keys that
exist in *one* mode are bound per-mode.

**A misspelled option IS reported** — a rarity in this repo, so use it. mango
prints `[ERROR]: Unknown keyword: <key>` with the file and line number to
stderr, at parse time. Nothing else validates a conf file, so a nested instance
started against a candidate config is the only pre-flight there is; one that
logs a single error you put there yourself has accepted every other line.

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

**Chain the idle lock with `;`, never `&&`.** Only one client may hold an
`ext-session-lock-v1` lock, so the `swaylock -f` on the 5-minute timeout exits
non-zero whenever you had already locked by hand — and with `&&` the
`wlopm --off` after it never runs, leaving the panel lit for the rest of the
idle period. It costs battery and logs nothing. `;` blanks either way, which is
correct in both cases: already locked, or newly locked.

**That same failure is the only way to ask "is the session locked?".** Nothing
here answers the question directly: noctalia's `lockScreen` IPC declares one
function, `lock()`, and returns before its lock surface exists; `mmsg get` has
no session-lock subcommand; `loginctl`'s `LockedHint` tracks the logind *signal*
and not the Wayland protocol, so it is unchanged by either locker. What does
answer it is running swaylock and reading the exit status — it prints
`Failed to lock session -- is another lockscreen running?` and exits non-zero
only once the compositor has confirmed the session locked. `lockscreen` uses
exactly that as the proof behind the noctalia lock (`docs/adr/0024`), which is
also why it is safe: the probe's *success* case is a lock too.

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

**Its colours come from `palette.nix`, and did not until 2026-08-16.** The ring
and the keypress highlight were gruvbox *orange* (`d65d0e`, `fe8019`) while the
machine's accent has always been yellow (`d79921`) — hex typed by hand into the
one surface nothing compared against the palette, in the one place you cannot
see it next to anything else. Add a colour here as `opaque gruvbox.<role>` or
`wash gruvbox.<role>`, never as a literal.

⚠️ **The `--effect-*` options do nothing without a background image, and
pixelating a solid colour does nothing even then.** Two independent no-ops that
compose into one silent failure:

- `apply_effects` runs on a *loaded image*. With no `-i` and no `-S` there is no
  image, so the effects list is never reached — the flag parses, and is ignored.
- `effect_pixelate` averages each block, and the average of a uniform field is
  that same value. `--effect-pixelate 40` over `color=282828ff` returns
  `#282828`.

So `swaylock --effect-blur 7x5 -f` on a colour-only config exits 0, renders
identically, and looks exactly like a broken build. **Effects need `-i` or
`-S`.** The background is now a pre-generated pool instead (`docs/adr/0018`).

**Backgrounds are resampled with `CAIRO_FILTER_BILINEAR`.** Any image that is
not 1:1 with the output gets its edges softened, which destroys a deliberately
blocky image without erroring. The pool is generated at the panel's native
1920×1200 so the scale factor is exactly 1.

⚠️ **`#282828` is neutral, so a background "shade" of it must have R=G=B.**
A ramp built from stops like `#322e2b` (R50/G46/B43) is a warm brown: it reads
as a *different colour* rather than a lighter or darker version of the
background, however carefully its mean is matched. This survived four rounds of
brightness adjustment because brightness was never what was wrong. The
derivation asserts neutrality per tone rather than trusting the ramp.

**A weighted ramp clumps.** Sampling five tones with one of them at 68% put
**236 of 360 blocks into a single connected region** — two thirds of the screen
as one flat mass, which defeats the point of a texture. The generator bans a
block from matching any of its eight neighbours; below about nine tones there
are too few colours left for that constraint to be satisfiable.

⚠️ **`services.fprintd.enable` switches the sensor on for EVERY pam service, not
just the ones you name.** `security.pam.services.<x>.fprintAuth` defaults to
`config.services.fprintd.enable`, so one `enable = true` put `pam_fprintd` into
all 23 stacks — `swaylock` and `login` included. Setting it explicitly on `sudo`
looks like scoping and is pure no-op; only an explicit `fprintAuth = false`
removes it. This was written into this file as "sudo only, deliberately" while
the opposite was live. **Verify with
`grep -l pam_fprintd /etc/pam.d/*`, never from the Nix.**

That matters because `pam_fprintd` is `sufficient` at order 11400, *ahead* of
`pam_unix` at 11700, and a password-first UI cannot survive that ordering.
swaylock has no way to render the sensor's prompt, so the first `timeout`
seconds of every unlock swallow your typing with no indication why — 30 s at the
default. Inverting the order is not a fix either: it only polls the sensor after
you submit an *empty* password, making the gesture "press Enter, then touch"
([swaylock#61](https://github.com/swaywm/swaylock/issues/61)). `greetd` inherits
the problem by substacking `login`, so it needs `login.fprintAuth = false` rather
than a rule of its own.

`fprintAuth` is therefore off on `swaylock` and `login`, and left on everywhere
else — `sudo`, `su` and the rest are terminal prompts, where the order reads
correctly and Ctrl-C falls through. Doing it properly on the lock screen means a
different locker (hyprlock has native fprintd support) or the third-party
`swaylock-fprintd` wrapper, which is not in nixpkgs — both judged more churn than
the feature is worth.

**Ctrl-C at the fingerprint prompt drops to the password prompt** rather than
killing `sudo` — the module catches SIGINT and returns `PAM_AUTHINFO_UNAVAIL`,
which a `sufficient` control passes through to `pam_unix`. Confirmed by hand on
2026-08-11. It is not guaranteed by the code: `signalfd` only receives *blocked*
signals and the module never calls `sigprocmask`, so this works because `sudo`
happens to block SIGINT across the PAM call. Re-test it if the fall-through ever
stops working; don't assume the module owns the behaviour.

**`pam_fprintd`'s `timeout` fires once; `max-tries` is a different counter.** A
timeout returns `PAM_AUTHINFO_UNAVAIL` immediately rather than consuming a try,
so an *untouched* sensor costs `timeout` seconds and no more — upstream's default
30 s is the whole of the stall people mistake for a hang. `max-tries` (default 3)
only counts real `verify-no-match` results, i.e. a finger that was read and
rejected, each getting a fresh `timeout` window. Set via
`rules.auth.fprintd.settings`, **not** `args` — `args` is computed from
`settings` by the NixOS module, so defining it directly collides. Confirm the
result with `grep ^auth /etc/pam.d/sudo`; the tokens are `timeout=` and
`max-tries=` (hyphen, not underscore, despite the log text saying `max_tries`).

### rofi

`rofi` replaced walker and elephant on 2026-08-14 (ADR 0021). The walker
findings are kept below the rule, because the *shape* of each recurs.

**A rofi plugin listed as its own package is a plugin rofi never loads.**
nixpkgs `rofi` is a `symlinkJoin` over `rofi-unwrapped` that adds
`-plugin-path` pointing into its own `lib/rofi`, so a `rofi-calc` sitting
beside it in `systemPackages` puts the `.so` somewhere nothing looks. `-show
calc` then prints `Mode calc is not found` to a stderr nobody reads and **exits
1** — a dead key. Plugins go through `rofi.override { plugins = [ … ]; }`.
`rofi-rbw` is the exception and not a plugin at all: a standalone front-end
over `rbw`, so it is an ordinary package.

**Ask the binary, not the Nix:** `rofi -no-config -h | sed -n '/Detected
modes/,/^$/p'` lists what actually `dlopen`ed, which is what `checks/static.sh`
now reads. Under the build sandbox it needs `HOME` set to something writable —
with `/homeless-shelter` rofi fails to create its runtime dir, warns, and
prints **no help at all**, which reads as "the scan is broken" rather than
"rofi is broken".

**`-no-custom` cannot be un-set.** Setting it in `config.rasi` applies to every
`-dmenu` call, and `-no-no-custom` on the command line is accepted, ignored,
and exits 0. So it goes at the call site: every fixed-choice menu passes it,
and the password prompt in `menus/network-menu.sh` must not — with it, Enter
returns nothing and `nmcli` runs with an empty password.

**Pinning `mainbox { children: [ ... ] }` silently deletes every widget you
left out.** rofi's default is `[ inputbar, message, listview, mode-switcher ]`.
Writing `[ inputbar, listview ]` to "keep it simple" removed the message bar —
and **rofi-calc renders its live result through the mode `_get_message` hook**,
which `rofi_view_reload_message_bar` (view.c:208) returns from immediately when
`mesg_box` is NULL. So `SUPER+=` stopped previewing as you typed while Enter
went on working, because `calc-command` fires off the entry, not the message.
Nothing logged. Do not pin the list unless you are reordering something: the
default order is already the wanted one, and an empty message bar is
`widget_disable`d, so it costs the dmenu menus no space.

**rofi's built-in defaults are Solarized light, and they show through.** A rasi
that styles only the widgets it names leaves every other one resolving through
rofi's default *role* variables — `urgent-background` is `#fdf6e3`, cream on a
gruvbox window, and you find out the first time a menu marks a row urgent.
Override the roles (`normal-*`, `selected-*`, `active-*`, `urgent-*`,
`alternate-*`) rather than the widgets. The check is
`rofi -dump-theme | grep 'var(lightbg)\|var(blue)\|var(red)'` — anything left
is a widget still wearing the default theme.

**rofi's shipped `gruvbox-dark` is a different gruvbox from this system's.**
2px borders against `borderpx=1`, an `#a89984` border matching nothing here,
`#665c54` selection where the terminals use `#504945`, and alternate rows
striped `#32302f`. Importing it looked like the cheap way to match and was
the reason the menus read as foreign. The palette is
`modules/home/palette.nix`; see ADR 0009.

**Sizing comes from the theme, not the caller.** rofi has no `--maxheight`;
`listview { dynamic: true; lines: N; }` makes `lines` a ceiling and shrinks to
fit. Porting a walker call by dropping `--maxheight` is correct, not lossy.

**walker 2.x could not draw a window without elephant, and exited 0 about it.**
This is why the migration happened, and it is the sharpest example in this file
of the repo's signature bug. With the walker daemon up and only elephant
killed, `walker -d` **exits 0, prints nothing, opens no window** — from the
keyboard indistinguishable from pressing Escape, and from a script
indistinguishable from a cancel, because every caller reads a cancel as
`|| exit 0`. The control run with elephant up exits 124, the window still being
open when the timeout fires. **Two exit codes that differ only by a timeout is
the whole diagnostic.**

**An elephant provider whose backing CLI was missing did not load, and said
nothing.** `SUPER+P` opened an empty window for weeks because `bitwarden.so`
shelled out to **`rbw`**, which was never declared — while `~/.config/rbw/` had
come across via `@home`, so the config surviving made it look verified. The
same trap is live for `rofi-rbw`, which is a front-end over the same `rbw`:
`rbw`, `wtype` and `pinentry-qt` stay declared in `modules/home/packages.nix`
for it, and the failure looks identical (an empty list, exit 0).

**Every elephant provider was ~26 MB and all were loaded at startup** — Go
plugins each statically linking their own runtime, `symbols.so` alone 144 MB,
all `dlopen`ed by the daemon. Trimming 25 providers to 15 cut the store path
807 → 546 MB and moved RSS **not at all**: 295 MB before, 305 MB after. Recorded
because the prediction that it would fall was written down as though measured;
see ADR 0019's status line.

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

**Killing waybar leaks the `mmsg watch` behind `window-title.sh`.** The module
script dies with the bar; the stream inside its process substitution does not.
Four orphans were alive at once on 2026-08-16 — PPID 1, up to fourteen hours
old, ~5 MB each, every one holding an open IPC socket to mango with nothing
reading from it. One leaks per `pkill waybar`, so **every mode switch and every
`waybar-reload`**. The tell is that they carry `WAYBAR_OUTPUT_NAME` in their
environment long after the bar that set it is gone:

```sh
pgrep -a 'mmsg watch'                       # more than one per module = leaked
tr '\0' '\n' < /proc/<pid>/environ | grep WAYBAR_OUTPUT_NAME
```

The fix is `trap 'pkill -P $$' EXIT PIPE HUP INT TERM` — by **parent**, not by
name, since matching `mmsg` would take out every other module's watcher too.
`PIPE` is in the list because a closed bar pipe is how the script usually dies,
and SIGPIPE's default action skips the `EXIT` trap. `checks/static.sh` requires
it of every script that streams `mmsg watch`.

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

> **A module that also emits text must name `3270 Nerd Font` after the symbols
> font**, not fall through to generic `monospace`. `Symbols Nerd Font Mono` is
> symbols-only — it carries no digits and no `%` — so `custom/phone`, which
> renders `󰂂 85%`, would take its percentage from whatever fontconfig resolves
> `monospace` to, sitting beside a `battery` module rendering its own in 3270.
> Pango falls back per character, so listing both gets the glyph from the first
> and the digits from the second.

**Measure the advance, don't infer it from how the glyph looks.** Two comments in
`style-solid.css` claimed the opposite of what the fonts do and were corrected
only after measuring. `fc-list ':charset=<hex>'` answers whether a glyph exists,
not whether it fits; for that, read `hmtx` against the glyph's ink bounds:

```sh
ft=$(nix eval --raw nixpkgs#python3Packages.fonttools.outPath)
PYTHONPATH=$(echo "$ft"/lib/python3.*/site-packages) nix shell nixpkgs#python3 \
  --command python -c '…TTFont(path); hmtx[g] vs glyf[g].xMax…'
```

`nix shell nixpkgs#python3Packages.fonttools -c python` does **not** work — that
puts the `ttx` CLI on `PATH` without putting the module on `PYTHONPATH`, and the
import fails in a way that reads like the package being wrong.

Measured on 3270 (upem 2000) vs Symbols Nerd Font Mono (upem 2048):

| glyph | 3270 advance / ink | Symbols advance / ink |
|---|---|---|
| `U+F10B` fa-mobile | 874 / 0–1269 — **overflows 395** | 2048 / 320–1728 |
| `U+F0084` md-battery | 874 / 0–1000 — **overflows 126** | 2048 / 409–1639 |

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

**`idle_inhibitor` is process state — a waybar restart releases it.** The
toggle is a static bool on a surface that dies with the bar, so `waybar-reload`,
a mode switch and `SUPER+/` all hand the machine back to the idle ladder, glyph
included. `minimal` and `hud` do not carry the module, so switching to either
releases it with nothing to re-arm. Use `systemctl --user stop swayidle` for
anything that must not be interrupted. `checks/static.sh` asserts at least one
layout still carries it — dropping it from all eight just shortens the bar.

**When a `custom/*` module is missing from the bar, run its exec by hand and
check the `text` field is non-empty** — not just that the script succeeds. An
empty custom module is indistinguishable from an absent one. `custom/power-profile`
emitted `{"text":""}` for a while because its icons were written as literal
glyphs and lost in transit; they are `$'\uXXXX'` escapes now, deliberately.

**And the inverse: a module invisible for long enough loses its stylesheet.**
`custom/phone` was listed in the `full` and `hud` layouts but had **no CSS rule
in either sheet** — not even a place in the shared reset list — for as long as it
existed. Nothing caught it, because for that whole time `phone-status.sh`'s
liveness guard could not match a wrapped `kdeconnectd` and the script always took
its "KDE Connect not running" branch, which emits empty text. Fixing that guard
(`866b57b`) made the module render for the first time, unstyled: no padding, no
`border-left`, so the phone glyph sat flush against `custom/power-profile` and
read as **a second icon inside the power module** rather than a module of its
own. It was reported that way, and blamed on the noctalia work landing the same
week.

Two things follow. **A dead guard hides a presentation bug behind a functional
one**, and fixing the functional one exposes it with no warning — when a guard
fix makes something appear, check it has a rule. And **`custom/phone` deliberately
emits empty text when the phone is unreachable**, so the module is absent rather
than a permanently grey glyph; only `connected` / `warning` / `critical` are
styled, and `disconnected` / `offline` are unstyled on purpose.

---

## Power

`docs/SYSTEM.md` §9 is the reference for battery thresholds, suspend, hibernation
and the WiFi resume fix. The traps worth carrying in your head:

- ⚠️ **`/sys/firmware/acpi/platform_profile` changes nothing the scheduler
  sees.** It is a `thinkpad_acpi` DYTC hint to the firmware's power budget.
  Diffed across `low-power`/`balanced`/`performance`, the governor, EPP,
  `scaling_min_freq`, `scaling_max_freq` and `boost` are byte-identical. The
  waybar toggle cycled it for a year and moved a glyph and nothing else — and
  TLP rewrote it on every charger transition anyway. **Power modes are TLP
  profiles** (`docs/adr/0017`). If you are about to reach for this attribute to
  change CPU behaviour, you are about to ship a placebo.
- **`EPP=power` is not a cap.** It biases how eagerly the governor ramps; it
  sets no ceiling. With `boost=1` and no `scaling_max_freq`, a keystroke-sized
  task still hits 4.63 GHz and spikes the package to ~30 W. **The fan on this
  chassis tracks bursts, not averages**, which is why "low-power" idled at
  ~2340 RPM and 45–52 °C. Only `CPU_SCALING_MAX_FREQ_*` and `CPU_BOOST_*` stop
  it.
- ⚠️ **An unset TLP bound does not mean "no limit" — it means "don't write".**
  `set_cpu_scaling_min_max_freq` skips the write when
  `CPU_SCALING_MAX_FREQ_ON_<profile>` is empty, so the **previous** profile's cap
  survives the switch. Leaving fanless left every core pinned at its ceiling
  while waybar reported `performance`; caught only by reading `scaling_max_freq`
  directly. Every profile in `power.nix` now states both ends, including the two
  that want the full range. Check with
  `tlp-stat -p | grep scaling_m`, not with the bar.
- **A TLP setting the version does not read is accepted silently.** TLP 1.9.1's
  amdgpu branch folds `PP_BAL` and `PP_SAV` into one arm reading only
  `RADEON_DPM_PERF_LEVEL_ON_BAT` — there is **no** `_ON_SAV`. Written into
  `tlp.conf` it is inert and unlogged, which is why the iGPU pin lives in the
  `power-mode` wrapper instead. **Grep the installed TLP's `func.d/` for a
  setting before trusting it**, rather than the manpage: 1.9.1 also ships a
  `tlpctl(1)` page for a binary it does not install.
- ⚠️ **A sudoers rule naming a package's store path does not match the same
  binary reached through `$PATH`.** sudo-rs resolves the *directory* symlinks of
  the command it is handed and stops, so `sudo -n power-mode` canonicalises to
  `$system-path/bin/power-mode` — not to the `power-mode` package that
  `/run/current-system/sw/bin/power-mode` links to. The rule silently does not
  apply and the only symptom is `sudo: interactive authentication is required`,
  which reads like a missing rule rather than a mismatched one. `power.nix`
  lists **both** `${powerMode}/bin/power-mode` and
  `"${config.system.path}/bin/power-mode"`.
  **`sudo -l <cmd>` cannot detect this** — it exits 0 for anything wheel may run
  *with* a password, so it says "permitted" for a rule that will still prompt.
  Test with `sudo -n <cmd>` and read the exit code, and do not put a pipe
  between the two: `sudo -n … | tail` reports `tail`'s status, which is how this
  was first mis-verified as working.
- **`tlp` needs root and `sudo -n` fails loudly — let it.** The old cycle script
  redirected its own errors to `/dev/null`; the same habit hid 24 shellcheck
  findings once, and hid every failed sysfs write during the fan investigation.
  A write to `scaling_max_freq` as a non-root user fails and the shell carries
  on, so the sweep "ran" and measured the unmodified machine.

- ⚠️ **A `services.logind` change is not live after `switch` — logind is never
  reloaded, so the lid keeps the previous action until you reboot.** nixpkgs sets
  `systemd.services.systemd-logind.reloadIfChanged` but leaves the matching
  `restartTriggers` line **commented out** (`nixos/modules/system/boot/systemd/
  logind.nix`), so a `logind.conf`-only change marks no unit as changed and
  `switch-to-configuration` reloads nothing. `/etc/systemd/logind.conf` reads
  correctly the whole time; only the daemon disagrees. Cost a whole overnight
  lid-close that suspended under the *old* handler. `power.nix` now declares the
  trigger. **Check the daemon, not the file:**
  `busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitch`.
  To apply by hand: `systemctl reload systemd-logind` — `Type=notify-reload`, so
  it re-reads config without dropping sessions. A *restart* would kill them.
- **Idle behaviour is not a power-management default — nothing supplies it.**
  There is no desktop environment here, so until swayidle got `timeouts` the
  machine had no dim, no idle lock and no idle sleep at all, and the only visible
  symptom was a battery that "seemed to go quickly". Check
  `services.swayidle.timeouts`, not TLP, when idle drain is the complaint.
- **The idle suspend's media check sees MPRIS only.** `playerctl` reports what
  publishes an MPRIS interface — ncspot, Spotify, browsers, mpv. A game, or a
  call in an app that publishes none, plays audio into a machine that sleeps
  under it. Video is unaffected either way: mpv and Firefox hold a
  `zwp_idle_inhibit` surface, which stops the ladder before any rung runs.
- **`poweralertd` alerts on every UPower device, headphones included.** `-S`
  restricts it to power supplies and `-s` drops the burst of current-state
  notifications at login. Without both, it reads as broken rather than noisy.
- **A lit panel during suspend is a battery bug, not a cosmetic one** — the
  DISPLAY block tracks the CRTC, so it holds s0i3 off and the machine idles at
  ~4 W through what looks like sleep. **The backlight cannot fix it**;
  `brightnessctl` and `bl_power` only drive PWM, and hooks written that way
  succeed, exit 0, and change nothing. `wlopm --off '*'` is the mechanism.
- **s0i3 *is* reached now** — measured at ~0.15 W over a 9h37m lid-closed
  suspend (58% → 54%), against the ~3–4 W this file recorded when the panel
  stayed lit. The earlier "s0i3 is never reached even so, cause unknown" was
  written before the `wlopm` hooks landed and is retracted. Measure it the same
  way — battery percentage either side of a long sleep — rather than by eye; if
  the figure regresses, read `/sys/kernel/debug/amd_pmc/smu_fw_info` **first**,
  it names the offending IP block in one command.
- **Nothing locked the screen on sleep until swayidle** — logind's
  `HandleLidSwitch` suspends, it does not lock, so a closed lid resumed straight
  to the desktop. See the swaylock section for why the lock handler cannot be a
  `powerManagement` hook.
- **A lid action of `ignore` also means "do not lock".** The lock hangs off
  swayidle's `before-sleep`, so it fires only when something actually *sleeps*.
  `HandleLidSwitchDocked = "ignore"` therefore leaves a docked closed lid awake
  and unlocked — accepted here, since locking would lock you out of the external
  display you are using. It is easy to miss precisely because it looks like the
  lid doing nothing, which is what `ignore` is supposed to look like.
- **`lock` as a lid action is edge-only, and would silently not re-fire.**
  `manager_handle_action` bails on `HANDLE_LOCK` when `!is_edge`
  (`logind-action.c`), while sleep actions have no such guard. Since logind
  re-runs the lid decision at *level* for as long as the lid is shut, a `lock`
  branch fires once on close and never again — so it cannot pick up a later
  change like an undock. Sleep actions can, which is what makes undock-then-
  hibernate work with `ignore`. Read the source before assuming a lid value
  behaves like its neighbours.
- Verify the live values with `busctl get-property org.freedesktop.login1
  /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitchDocked`,
  not the Nix — see the reload trap above.
- **upower's critical-battery percentages fail silently as a set**: give
  `percentageLow`/`Critical`/`Action` values that aren't strictly descending and
  it discards all three for its own defaults, unlogged — the action fires at a
  charge nobody chose. Check `/etc/UPower/UPower.conf`, not the Nix.
- **`HybridSleep` on a critical battery is not hibernation here** — it writes the
  image and then *stays in s2idle*, which at 3% charge is the one moment the
  machine must draw nothing. That is the NixOS default; this host sets
  `Hibernate`. (The ~3 W once recorded for that s2idle is from the same batch of
  short measurements as the retracted s0i3 figure above, and is not to be
  trusted. The decision does not rest on it: any suspend at 3% is wrong.)
- **`suspend-then-hibernate` on the lid was abandoned — logind's re-check
  degrades it to a plain `suspend`.** A spurious wake ends the s-t-h cycle
  outright; ~30 s later (`HoldoffTimeoutSec`) logind re-handles the still-closed
  lid and logs a bare `Suspending...`, *not* `Suspending, then hibernating...`.
  That is an unbounded s2idle with no hibernate timer behind it, which is where
  the resume hang below lives. Setting **both** lid handlers to s-t-h does not
  help — it was tried, and the re-check still degraded. Observed identically on
  three consecutive boots; every lid close ended in a power cycle. The lid now
  hibernates outright — the *lid* does. The 30-minute idle rung suspends
  (`docs/adr/0016`): every failure in this bullet is logind re-handling a lid
  that is still shut, and there is no lid switch to re-handle when the rung fires
  with the lid open. Do not generalise one to the other in either direction.
  - **Read the operation name, not the fact that it suspended.** logind logs a
    D-Bus request as `suspend requested from client PID … ('systemctl')`; the
    bare `Suspending...` with no such line is logind's *own* handler. That one
    distinction is what separates "a script did this" from "logind chose this".
  - Each wake coincides with the Synaptics reader (`06cb:00f9`) dropping off
    USB bus 1; the counters reset per boot, so it is unconfirmed. **The path is
    the parent, not the device** — `1-3` reads `power/wakeup` = `disabled`, but
    its XHCI controller `0000:74:00.3` is `enabled`, which is how a device
    leaving the bus raises a PME. Checking the device alone says "wakeup is off"
    and is not the answer. The reader is the only device on bus 1, so
    `echo disabled > /sys/bus/pci/devices/0000:74:00.3/power/wakeup` costs
    nothing. Untried on purpose: it would remove the confirming symptom. The
    idle rung's suspend (`docs/adr/0016`) is what produces samples.
  - **It also fails the other way: no spurious wake, and no hibernate either.**
    A 2026-08-11 lid-close logged `Suspending, then hibernating...` cleanly and
    then sat in s2idle for **9h37m** with `HibernateDelaySec=30m` set — the timed
    wake simply never fired, and nothing logged its absence. Suspect the alarm
    RTC: `rtc0` is `acpi-tad` with **no `wakealarm` attribute at all**, and only
    `rtc1` (`rtc_cmos`) reports "RTC can wake from S4". Unproven; two independent
    ways for s-t-h to end in an unbounded s2idle is the argument for not
    returning to it, whatever the wake source turns out to be.
- **Long s2idle sometimes never resumes, and it looks like a dead machine.** The
  panel is off (`wlopm --off` in `sleep-actions.service`'s `ExecStart`) and is
  only restored by `resumeCommands` in that unit's `ExecStop` — so a resume that
  hangs before then leaves a black screen and dead input, indistinguishable from
  a machine that is merely asleep. The tell is in the journal, not on the screen:
  a good wake logs `amdgpu … PCIE GART … enabled` and `SMU is resuming…`; the
  failing one logs neither and the boot's journal simply **stops**. Compare two
  wakes before blaming the display hooks.
- **Hibernation's `resume_offset` fails silently**: the machine boots fresh and
  discards the session, presenting as "hibernate didn't work". It is valid only
  for the exact swapfile that exists now.
- **The kernel log cannot tell you whether a hibernate succeeded** — the image is
  snapshotted *before* the write, so success and refusal leave byte-identical
  traces. The primary signal is the machine physically powering off. Do not set
  `HibernateMode=shutdown` on that misreading; it was tried and reverted.
- ⚠️ **Hibernation entry is a multi-second window, and reopening the lid inside
  it hung the machine outright.** 2026-08-13 04:11:51 `Lid closed.` →
  `Hibernating...` → 04:11:52.78 `PM: hibernation: hibernation entry`, and that
  is the **last line of the boot**. The lid was reopened <5 s later; the machine
  was dead — no panel, no input — and had to be power-cycled. The next boot at
  04:12:38 logged `PM: Image not found (code -22)`, so **no image was ever
  written**: the hang is in the entry phase, before the snapshot, not in resume.
  This is distinct from the s2idle resume hang below — that one ends a boot at
  `PM: suspend entry (s2idle)`.
  - **The window is not instantaneous.** Preallocation alone measured **7.10 s**
    and **22.17 s** on the two hibernates either side of this one
    (`PM: hibernation: Allocated … kbytes in N seconds`), on top of process
    freeze and device suspend. Any lid-open within ~20 s of a lid-close lands
    inside it. Treat a short lid close as the hazard case, not the cheap one.
  - **How to tell a hang from a success, since both look like silence.** A
    hibernate that *worked* replays its entry-phase kernel lines at **resume**
    time — the kmsg buffer is inside the image — so `Marking nosave` …
    `hibernation exit` all arrive with the resume's timestamp, hours after the
    entry line. Aug 12 18:08:06 entry → Aug 13 00:58:35 replay is the good
    shape. A journal that **stops** at `hibernation entry` and is followed by a
    fresh boot logging `Image not found` is the hang. There is no third signal:
    journald is frozen for the whole entry phase, so nothing written after the
    freeze survives unless a resume flushes it.
  - **Correlate, unconfirmed:** `power-mode power-saver` ran **2.5 s** before the
    lid close, so the entry ran with the CPU capped at 1115770 kHz, boost off,
    and the iGPU pinned to DPM `low` — i.e. the slowest possible version of the
    window it then had to survive. Worth checking against the mode at the time
    before blaming the lid alone.
  - **Mitigated, not fixed.** `powerDownCommands` now un-throttles before
    `sleep.target` (`docs/SYSTEM.md` §9, `docs/adr/0017`), which removes that
    correlate and shortens the window. It does not make the window safe, and the
    hang has **one** observation behind it — do not read a quiet month as proof.
    ⚠️ **Order the writes: boost first.** With boost off the driver clamps
    `cpuinfo_max_freq` to the 2901000 nominal, so reading the ceiling before
    lifting boost uncaps the CPU to *nominal* and looks like it worked. Verified
    both ways live: `boost=0` → `cpuinfo_max_freq` 2901000, `boost=1` → 4630443.
- **Re-test "this protocol isn't available" claims.** This file long asserted
  mango advertised no `wl_output`, so DPMS was impossible — which is what sent
  sleep blanking down the backlight path that could never have worked, and cost a
  flat battery to discover. `wlopm --json` is one command.
- ⚠️ **Turning off power-profiles-daemon removed the *answer*, not just the
  second tuner.** PPD is also the interface desktops use to *ask* what the power
  profile is, so `services.power-profiles-daemon.enable = false` left every such
  client — noctalia's control-centre button, GNOME's power page,
  `powerprofilesctl` — finding no service and rendering a greyed control, in
  silence, for months. `power-profiles-tlp` now owns that bus name and answers it
  from TLP (`docs/adr/0026`). **When you disable a daemon because it conflicts,
  check what else was reading its interface.**
- ⚠️ **A running unit is not an activatable bus name, and `systemctl status`
  cannot tell you which you have.** `power-profiles-tlp` came up, owned the name,
  and answered `busctl` correctly — and noctalia still did nothing, because
  quickshell probes the name at *its* startup, tries to **activate** it when
  unowned, and gives up for the life of the process. The tell was an hour-old
  journal line, `Could not launch service …: The name is not activatable`,
  followed by `The PowerProfiles service will not work`. Meanwhile
  `noctalia-shell ipc call powerProfile set balanced` printed nothing, which by
  `docs/adr/0023`'s rule reads as success. **Any daemon here that owns a bus name
  a desktop client consumes needs `share/dbus-1/system-services/<name>.service`
  with `SystemdService=`**, not just a `wantedBy` unit. `checks/static.sh`
  asserts it.
- **An XML comment may not contain `--`, and dbus rejects the whole file if one
  does.** The first draft of `pkgs/power-profiles-tlp/dbus-policy.conf` had a
  prose double hyphen in its header comment. Since that file is loaded by the
  *system* bus, the blast radius is every service on it, not the one being
  added. `checks/static.sh` runs `xmllint --noout` over it; keep prose dashes
  single.
- **`services.tuned.ppdSupport` is the off-the-shelf version of this and is the
  wrong tool here.** It does claim both PPD bus names, but it translates into
  *tuned* profiles, which set governor and EPP themselves — a second owner on the
  cpufreq path alongside TLP (`docs/adr/0005`), and every number in
  `docs/adr/0017` was measured with TLP applying them alone.
- **Reading a Qt/QML client's D-Bus contract needs `strings -e l`.** The profile
  names quickshell parses (`power-saver`, `balanced`, `performance`) are UTF-16
  literals in the binary and do **not** appear in a default ASCII `strings` dump
  — which reads as "the names are unconstrained" rather than "the scan missed
  them".

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

**`gruvbox-gtk-theme` is vendored in `pkgs/`, because nixpkgs deleted it.**
GTK2 went, taking `gtk-engine-murrine` with it, and murrine's reverse
dependencies were removed rather than fixed — `gruvbox-gtk-theme` and
`gruvbox-material-gtk-theme` both, on 2026-07-22. The failure is an **eval**
error naming a package nothing appeared to have touched, on the next
`nix flake update`; it aborts the whole config before any build starts, so it
looks far worse than it is. The dependency was only a `propagatedUserEnvPkgs`
entry serving the theme's `gtk-2.0/` files, so dropping it costs nothing here —
the vendored derivation is the removed one minus murrine and minus the variant
plumbing, building `Gruvbox-Yellow-Dark` directly. Upstream
(Fausto-Korpsvart/Gruvbox-GTK-Theme) is alive and unchanged.

> Any theme still carrying a `gtk-2.0/` directory is a candidate to go the same
> way. The tell is a removal notice in nixpkgs' `pkgs/top-level/aliases.nix`
> quoting a *transitive* GTK2 dependency, not a problem with the package itself.

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

**A Nerd Font package and its unpatched twin have different family names.**
`_0xproto` is family `0xProto`; only `nerd-fonts._0xproto` is
`0xProto Nerd Font Mono`. kitty's `bold_font`/`italic_font` asked for the latter
while `fonts.nix` installed the former, so both lines fell back to Hack and bold
text simply looked normal — nothing logged, for months. Same class as the 3270
miss above it. **`fc-match` will not catch this**: it matches on *family* alone,
so `fc-match "0xProto Nerd Font Mono Bold"` reports a fallback even when the font
is installed correctly. Verify with the application's own resolver —
`kitty --debug-font-fallback` prints the file it actually opened for each of
Normal/Bold/Italic/Bold-Italic. 0xProto ships no bold-italic, so that one variant
is Hack by design.

Baseline: **Gruvbox Dark**, Hack Nerd Font Mono 11 in the terminals, with kitty
bold/italic in 0xProto Nerd Font Mono. Modes are **tiling** (Gruvbox Orange) and
**hud**; the active one is in `~/.local/state/mango/current-mode`.

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
