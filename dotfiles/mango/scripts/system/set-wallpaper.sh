#!/usr/bin/env bash
# Usage: set-wallpaper.sh <path-to-image>
# Sets the wallpaper live via swww and saves it as the persistent wallpaper.

if [ -z "$1" ]; then
	echo "Usage: set-wallpaper.sh <path-to-image>"
	exit 1
fi

if [ ! -f "$1" ]; then
	echo "File not found: $1"
	exit 1
fi

# ~/.local/share, not ~/.config/mango — that directory is a read-only store
# path as of 2026-07-30, and a wallpaper is user data, not configuration.
WALLPAPER_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/mango/wallpaper.png"

mkdir -p "$(dirname "$WALLPAPER_PATH")"
cp "$1" "$WALLPAPER_PATH"
awww img "$WALLPAPER_PATH" --transition-type wipe --transition-duration 1
