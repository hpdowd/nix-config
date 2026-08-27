#!/usr/bin/env bash
# Starts the awww daemon and re-applies the saved wallpaper.
#
# Called from mango/tiling/autostart.conf. Without this the desktop comes up
# with no wallpaper at all: awww-daemon does not survive a session, and nothing
# else started it — set-wallpaper.sh was the only caller of awww, and it is only
# ever run by hand. That was equally true on Arch; the wallpaper simply had to
# be re-set manually after every boot.
#
# THIS RAN THROUGH WAYLE from 2026-08-24 to 2026-08-26 (`wayle wallpaper set`,
# called by wayle-restart.sh rather than from an autostart line), because wayle
# spawned awww-daemon as its OWN CHILD and held the state that went with it.
# With wayle unstarted that child is never spawned, so this is the only thing
# starting the daemon again. docs/adr/0051.
#
# TILING'S autostart, not universal's, which is where it sat before wayle. That
# was right when noctalia had `wallpaper.enabled = false` (docs/adr/0020, "off,
# awww owns it"); docs/adr/0045 turned noctalia's own engine ON and it is still
# on, so a shared restore would now fight noctalia for the layer surface. One
# line, in the mode that wants it.
#
# Note the binary is `awww`, not `swww`: nixpkgs renamed the package to the fork
# already in use here. See nixos/modules/system/desktop.nix.

# Moved out of the config tree on 2026-07-30, same reasoning as runtime state:
# ~/.config/mango is now a read-only store path, so a 4.6 MB PNG cannot live
# there — and it never should have, being user data rather than configuration.
WALLPAPER="${XDG_DATA_HOME:-$HOME/.local/share}/mango/wallpaper.png"

# Not in any repo, so a fresh clone has no wallpaper to restore. Nothing to do,
# and not an error.
[ -f "$WALLPAPER" ] || exit 0

# Match comm with the wrapper's leading dot, not the command line: `-x` misses
# `.awww-daemon-wr`, and `-f` would match this script's own guard line.
pgrep '^\.?awww-daemon' >/dev/null || awww-daemon &

# `awww img` fails until the daemon has bound its socket, so poll rather than
# guessing at a sleep. ~4s of headroom; it normally binds well inside 1s.
for _ in $(seq 1 20); do
	awww query >/dev/null 2>&1 && break
	sleep 0.2
done

exec awww img "$WALLPAPER" --transition-type wipe --transition-duration 1
