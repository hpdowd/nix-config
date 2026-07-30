# 0005 — Exactly one owner per daemon

**Status:** Accepted (2026-07-30)

## Context

Every background process here can be started two ways: a `exec=` line in a
mango `autostart.conf`, or a systemd user unit. Several ended up with both, and
each failure looked like something else.

- **swaync** — nixpkgs ships `swaync.service` with
  `WantedBy=graphical-session.target`, which Arch's package did not. It raced
  the `exec=` line, which is the copy that matters because it passes
  `-s ~/.config/mango/swaync/style.css`. Autostart won the D-Bus name; the unit
  died with *"An instance of SwayNotificationCenter is already running!"* five
  times and hit `start-limit-hit`. **Notifications worked the whole time**,
  which is why nobody noticed.
- **wlsunset** — only one Wayland client can hold a gamma control. A
  `pgrep`/`pkill`-plus-spawn script racing a unit means the loser prints
  `gamma control of output eDP-1 failed` and silently does nothing.
- **rclone** — two enabled units for one mount; see
  [0006](0006-start-limits-on-remote-units.md).

## Decision

One owner per daemon, chosen by whichever needs to react to runtime state:

- **swaync → autostart**, because a restyle must take effect on mode switch.
  The nixpkgs unit is masked in `modules/home/default.nix` via
  `xdg.configFile."systemd/user/swaync.service".text = ""` — an empty unit file
  loads as `masked`; `source = "/dev/null"` is rejected by pure evaluation.
- **wlsunset → systemd**. The menu script only drives the unit
  (`systemctl --user start/stop/restart`), never spawns its own.
- **polkit, micmute-led → systemd.**

## Consequences

- When adding a package with a daemon, check
  `ls $(nix eval --raw nixpkgs#foo)/share/systemd/user/` before assuming
  autostart is the only owner. nixpkgs ships units Arch packages did not.
- Never "fix" a daemon by adding a `pkill`+spawn alongside a unit. That is the
  wlsunset bug, and it fails silently.
- Related trap: `pkill -x` matches `comm`, which the kernel truncates to 15
  characters — nixpkgs' wrapped `elephant` appears as `.elephant-wrapp`, so
  `pkill -x elephant` matched nothing and every reload leaked a process. Match
  the command line: `pkill -f 'bin/elephant$'`.
