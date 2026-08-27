#!/usr/bin/env bash
# Usage: set-wallpaper.sh <path-to-image>
# Sets the wallpaper live and saves it as the persistent one.
set -u

if [ -z "${1:-}" ]; then
	echo "Usage: set-wallpaper.sh <path-to-image>"
	exit 1
fi

if [ ! -f "$1" ]; then
	echo "File not found: $1"
	exit 1
fi

# ~/.local/share, not ~/.config/mango — that directory is a read-only store
# path, and a wallpaper is user data rather than configuration. docs/adr/0003.
WALLPAPER_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/mango/wallpaper.png"

mkdir -p "$(dirname "$WALLPAPER_PATH")"
cp "$1" "$WALLPAPER_PATH"

# Through the mode's own shell, not `awww img` directly: wayle owns the engine
# in tiling and noctalia owns its own. docs/adr/0045.
case "$(. "$HOME/.config/mango/scripts/lib.sh" && current_mode)" in
noctalia)
	noctalia-shell ipc call wallpaper set "$WALLPAPER_PATH" 2>/dev/null ||
		echo "set-wallpaper: noctalia did not accept the wallpaper" >&2
	;;
*)
	# awww directly, as before wayle. wayle spawned awww-daemon as its own child
	# and held the transition/cycling state with it, so driving awww underneath a
	# running wayle was the two-owners failure docs/adr/0005 records. With wayle
	# unstarted there is one owner again. docs/adr/0051.
	pgrep '^\.?awww-daemon' >/dev/null || awww-daemon &
	awww img "$WALLPAPER_PATH" --transition-type wipe --transition-duration 1
	;;
esac
