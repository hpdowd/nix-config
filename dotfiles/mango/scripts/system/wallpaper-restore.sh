#!/usr/bin/env bash
# Re-applies the saved wallpaper through wayle, in tiling mode.
#
# Called by wayle-restart.sh after the unit is up — not from an autostart line.
# It ran from universal/autostart.conf until 2026-08-24, for both modes,
# because awww was the machine's single wallpaper owner. It is not any more:
# wayle drives the engine in tiling and noctalia manages its own, so a shared
# restore would fight noctalia for the layer surface. docs/adr/0045.
#
# `wayle wallpaper set`, not `awww img`: awww is wayle's engine here and wayle
# holds the state that goes with it (transition, cycling, per-monitor). Driving
# awww underneath it is the two-owners failure docs/adr/0005 records, and the
# loser is silent.
set -u

# ~/.local/share, not ~/.config/mango — that directory is a read-only store
# path, and a wallpaper is user data rather than configuration. docs/adr/0003.
WALLPAPER="${XDG_DATA_HOME:-$HOME/.local/share}/mango/wallpaper.png"

# Not in any repo, so a fresh clone has no wallpaper to restore. Nothing to do,
# and not an error.
[ -f "$WALLPAPER" ] || exit 0

# `wayle wallpaper set` fails until the shell has bound its socket, so poll
# rather than guessing at a sleep. ~5s of headroom.
for _ in $(seq 1 25); do
	if wayle wallpaper info >/dev/null 2>&1; then
		exec wayle wallpaper set "$WALLPAPER"
	fi
	sleep 0.2
done

echo "wallpaper-restore: wayle did not answer in 5s — wallpaper not restored" >&2
exit 1
