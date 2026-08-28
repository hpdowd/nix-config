# 0020 — Noctalia is a desktop mode, not a second desktop

**Status:** Accepted (2026-08-14), **corrected 2026-08-16 — the mango
integration does not work**; extended by
[0022](0022-noctalia-mode-looks-like-noctalia.md) and
[0023](0023-noctalia-owns-its-own-actions.md)

Follows [0005](0005-one-owner-per-daemon.md) (one owner per daemon) and
[0014](0014-declare-the-namer-not-just-the-file.md) (assert reachability both
ways, per selector). Uses the mode machinery from
[0004](0004-mode-scripts-own-theming.md).

## Context

`noctalia-shell` is a Wayland desktop shell — bar, notifications, launcher,
dock, OSD, lock screen — built on quickshell. Trying it here meant answering one
question first: **how do you install a thing that wants to own the whole desktop,
next to a desktop that already has owners for every one of those jobs, and still
be able to delete it cleanly?**

Two shapes were available and both are wrong:

- **Install it and start it.** waybar and noctalia both draw a bar; swaync and
  noctalia both claim `org.freedesktop.Notifications`. The second claimant of a
  DBus name does not error — it simply never receives a notification. That is
  [0005](0005-one-owner-per-daemon.md)'s failure verbatim, and it is invisible
  until the day you miss something.
- **Fork the config into a parallel tree.** Every fix then has to be made twice,
  which is exactly what `apply_mode()` was extracted in `scripts/lib.sh` to stop.

The repo already had the right abstraction. A **desktop mode** is a named set of
(mango config, autostart, walker config); `SUPER+CTRL+/` picks one;
`checks/static.sh` asserts that the set of names and the set of files agree in
both directions. Nothing about it was specific to having two modes.

Two packages carry the name in nixpkgs. `noctalia-shell` 4.7.7 is the stable QML
shell on `noctalia-qs`; `noctalia` 5.0.0-beta.8 is a native rewrite that **clones
plugin repositories over git at runtime** (`Services/Noctalia/PluginService.qml`).
The second is not something to point at a machine you rely on.

It also has first-class mango support — `Services/Compositor/MangoService.qml`,
selected when `XDG_CURRENT_DESKTOP` contains `mango`, driving the bar off the DWL
IPC. Without that the workspace and window widgets would render empty, which on
this desktop is indistinguishable from the bar being broken.

> ⚠️ **Corrected 2026-08-16: that last paragraph is wrong, and its own predicted
> failure is what actually happens.** `MangoService.qml` is selected, but every
> path in it is guarded on `DwlIpc.available`, which is false on this machine and
> always will be: quickshell probes for the Wayland global `zdwl_ipc_manager_v2`
> and mango 0.16.0 advertises no dwl IPC at all — `mmsg`'s JSON socket is a
> different interface. So `rebuildWorkspaces()` and `updateWindows()` return
> early, and the **Workspace widget (the centre of the bar) and ActiveWindow
> widget render nothing**. The claim was read off the file's existence rather
> than off a running shell, which is the mistake this repo names in its own
> first paragraph. See `docs/SYSTEM.md` §13 for the tell and the options.

## Decision

**noctalia is a third desktop mode.** `MODES=("tiling" "hud" "noctalia")`, and
the existing check makes the rest mandatory: `noctalia/noctalia.conf`,
`scripts/modes/noctalia.sh`, `walker/configs/noctalia.toml`.

Four things follow from "one owner per daemon", and each is what makes the mode
removable:

**The mode owns the handover, in the autostart.** `noctalia/autostart.conf` kills
waybar and swaync and does not restart them; `tiling/` and `hud/` restart both
and `systemctl --user stop noctalia`. `stop` on an absent unit errors harmlessly,
so deleting noctalia does not require touching those two files.

**Noctalia runs as a systemd user unit, alone among the mode daemons.**
`mmsg dispatch reload_config` re-runs every `exec=` line, so a `pgrep` guard has
to be exactly right or a reload leaves two shells fighting over one layer
surface. `start` and `stop` are idempotent by construction. It also puts a
failure in `systemctl --user status` rather than nowhere — and there is one to
catch: at login straight into noctalia mode the unit can start before
`dbus-update-activation-environment` has published `WAYLAND_DISPLAY`, so it
carries `Restart=on-failure` with a start limit per
[0006](0006-start-limits-on-remote-units.md).

**Its settings are seeded, never owned.** noctalia rewrites `settings.json`
itself, so no `xdg.configFile` may claim the path — two owners is an activation
failure, not a merge ([0002](0002-out-of-store-dotfiles.md)). `modes/noctalia.sh`
installs `noctalia/settings.json` only when the destination is absent. The seed
is partial and carries no `settingsVersion`: upstream's migrations all guard on
the old key being present, so they no-op rather than corrupting it.

Only the keys that would otherwise fight this machine are set — `wallpaper` off
(`awww` owns it) — **superseded 2026-08-24 by
[0045](0045-each-mode-owns-its-wallpaper.md): each mode owns its wallpaper, and
this one is now `true`** — `nightLight` off (`wlsunset` does), `idle` off and
`lockOnSuspend` off (swayidle and `lockscreen -f` do), `syncGsettings` off (
[0004](0004-mode-scripts-own-theming.md) put GTK in Nix's hands). App theming is
already off upstream and is pinned off anyway: it writes matugen output into
`~/.config/gtk-3.0`, `kitty`, `foot` — paths this repo owns read-only.

**A bind that names one mode's daemon becomes a dead key in another.**
`CTRL+ALT+\` called `swaync-client` directly, which does nothing at all in
noctalia mode and exits 0. It now calls `scripts/menus/notify.sh`, which branches
on `current_mode`. Same for `waybar-layout.sh` and `waybar-position.sh`: they
refuse via `mode_has_waybar()` in `lib.sh` and say so with `notify-send`, rather
than opening a picker that accepts a choice and discards it.

### The check that was missing

Adding the mode surfaced a gap. `checks/static.sh` verified that every script
named by a **waybar config** exists and is executable, but nothing checked the
same for the `bind=` and `exec=` lines in the mango tree — the far larger set.
`notify.sh` was committed `644`; Nix preserves the mode bit, so it arrived in the
store `444` and the key was dead on arrival. The check now covers both trees, and
fails on a reference count of zero rather than passing by matching nothing
([0011](0011-shell-is-gated-too.md)).

`universal/bind-tiling-hud.conf` is now `bind-shared.conf`, since three modes
source it. The name was going to be wrong either way round; this one stays right
if noctalia is removed.

## Consequences

- **`walker/configs/noctalia.toml` is a verbatim copy of `tiling.toml`.** The
  check demands one config per mode and rejects surplus ones, and a tracked
  symlink in this tree resolved into its own parent once already. Third copy of
  a file that differs from the first in nothing. Accepted over relaxing the check,
  which would widen the blast radius of "try a shell" into the gate itself.
- **Removal is one pass, and the gate enforces it.** Drop `"noctalia"` from
  `MODES` and `nix flake check` fails until the conf and mode script are gone
  too. The uninstall is written out in `docs/SYSTEM.md` §6, which is the count
  to trust — it grew with [0022](0022-noctalia-mode-looks-like-noctalia.md) and
  [0023](0023-noctalia-owns-its-own-actions.md), and the walker config named
  here left with walker.
- **swayosd keeps running in noctalia mode, and its OSD overlaps noctalia's.**
  Deliberate: `swayosd-server` is `exec-once`, so a mode that killed it would not
  get it back on the way out — one-way breakage, silently. Cosmetic overlap is
  the cheaper failure. Nothing in the binds calls `swayosd-client`, so in
  practice only the caps-lock indicator doubles up.
- **7.2 MiB, fully cached.** `noctalia-qs` is a quickshell fork, so nothing
  collides with the `quickshell` and `dgop` packages dropped with DMS in
  [0008](0008-arch-removed.md)'s migration.
- **Three of its features are inert here** — the power-profile widget (TLP, not
  power-profiles-daemon), blur-behind (mango has no `ext-background-effect-v1`),
  and a GitHub version fetch that no setting gates. Measured, not predicted;
  listed in `docs/SYSTEM.md` §13 so they are not re-reported as new.
- **noctalia's own launcher, lock screen and idle handling go unused.** walker,
  `lockscreen -f` and swayidle stay in charge in every mode. Turning any of them
  over to noctalia is a later decision, and would need its own record — it means
  the mode is no longer removable without also restoring a lock path.
