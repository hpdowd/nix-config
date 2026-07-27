#!/bin/bash
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

WALLPAPER_PATH="$HOME/.config/mango/wallpaper/wallpaper.png"

cp "$1" "$WALLPAPER_PATH"
awww img "$WALLPAPER_PATH" --transition-type wipe --transition-duration 1
