#!/usr/bin/env bash
# Restarts waybar using both the current desktop mode and layout state.
# Called by desktop-mode.sh, waybar-layout.sh, waybar-position.sh, and reload.sh.

WAYBAR_DIR="$HOME/.config/mango/waybar"
MODE=$(cat "$HOME/.config/mango/state/current-mode" 2>/dev/null || echo "tiling")
LAYOUT=$(cat "$HOME/.config/mango/state/waybar-layout" 2>/dev/null || echo "full")

if [ "$MODE" = "hud" ]; then
    CONFIG="$WAYBAR_DIR/config-hud.jsonc"
    STYLE="$WAYBAR_DIR/style-hud.css"
else
    case "$LAYOUT" in
        focus)   CONFIG="$WAYBAR_DIR/config-focus.jsonc" ;;
        minimal) CONFIG="$WAYBAR_DIR/config-minimal.jsonc" ;;
        *)       CONFIG="$WAYBAR_DIR/config.jsonc" ;;
    esac

    case "$MODE" in
        tiling) STYLE="$WAYBAR_DIR/style-solid.css" ;;
        *)      STYLE="$WAYBAR_DIR/style.css" ;;
    esac

    # Tiling: strip floating margins via temp file so originals are preserved
    if [ "$MODE" = "tiling" ]; then
        tmp=$(mktemp /tmp/waybar-XXXXXX.jsonc)
        sed -E \
            -e 's/"margin-top": [0-9]+/"margin-top": 0/' \
            -e 's/"margin-left": [0-9]+/"margin-left": 0/' \
            -e 's/"margin-right": [0-9]+/"margin-right": 0/' \
            "$CONFIG" > "$tmp"
        CONFIG="$tmp"
    fi
fi

pkill waybar
sleep 0.1
nohup waybar -c "$CONFIG" -s "$STYLE" >/dev/null 2>&1 &
