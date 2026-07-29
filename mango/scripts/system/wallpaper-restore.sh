#!/usr/bin/env bash
# Starts the awww daemon and re-applies the saved wallpaper.
#
# Called from mango/universal/autostart.conf. Without this the desktop comes up
# with no wallpaper at all: awww-daemon does not survive a session, and nothing
# else started it — set-wallpaper.sh was the only caller of awww, and it is only
# ever run by hand. That was equally true on Arch; the wallpaper simply had to
# be re-set manually after every boot.
#
# Note the binary is `awww`, not `swww`: nixpkgs renamed the package to the fork
# already in use here. See nixos/modules/system/desktop.nix.

WALLPAPER="$HOME/.config/mango/wallpaper/wallpaper.png"

# The file is gitignored (.gitignore excludes /mango/wallpaper/), so a fresh
# clone has no wallpaper to restore. Nothing to do, and not an error.
[ -f "$WALLPAPER" ] || exit 0

pgrep -x awww-daemon >/dev/null || awww-daemon &

# `awww img` fails until the daemon has bound its socket, so poll rather than
# guessing at a sleep. ~4s of headroom; it normally binds well inside 1s.
for _ in $(seq 1 20); do
    awww query >/dev/null 2>&1 && break
    sleep 0.2
done

exec awww img "$WALLPAPER" --transition-type wipe --transition-duration 1
