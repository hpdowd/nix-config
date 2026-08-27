# 0045 — Each mode owns its wallpaper

**Status:** Accepted (2026-08-24). Supersedes the wallpaper clause of
[0020](0020-noctalia-is-a-desktop-mode.md) — *"`wallpaper` off (`awww` owns
it)"*. The rest of 0020 stands.

**Trimmed 2026-08-28.** This record also made wayle the tiling mode's shell.
[0051](0051-waybar-is-the-tiling-bar-again.md) reversed that after three days
and holds the reasons; only the wallpaper decision is still in force, and it is
all that is left here. Comments citing 0045 for a wayle-era fact were repointed
in the same change.

## Context

`0020` turned wallpaper off in noctalia mode because `awww` owned it globally,
so one engine drew the background in every mode. That made the wallpaper the
only part of a mode's look that could not follow the mode: a mode switch
repainted the bar, the menus, the terminal and the lock screen, and left the
desktop behind them unchanged.

## Decision

Each mode drives its own wallpaper. In tiling that is `awww`, started by
`tiling/autostart.conf`; in noctalia it is noctalia's own engine, with
`wallpaper.enabled = true`.

## Consequences

- The wallpaper follows a mode switch, like every other surface.
- Two engines exist, and exactly one runs at a time. Each mode script starts
  its own and stops the other's, the same handover `noctalia-start.sh` already
  used for the notification daemon.
- `scripts/system/set-wallpaper.sh` and `wallpaper-restore.sh` are the tiling
  half and know only `awww`. A wallpaper set in noctalia mode does not survive
  into tiling and is not meant to.
