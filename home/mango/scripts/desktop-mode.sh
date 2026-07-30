#!/usr/bin/env bash

MANGO_DIR="$HOME/.config/mango"
STATE_DIR="$MANGO_DIR/state"
STATE="$STATE_DIR/current-mode"
WALKER_CONFIGS="$MANGO_DIR/walker/configs"

MODES=("tiling" "hud")

current_mode() {
    [ -f "$STATE" ] && cat "$STATE" || echo "tiling"
}

menu_entries() {
    local current
    current=$(current_mode)
    for mode in "${MODES[@]}"; do
        [ "$mode" = "$current" ] && echo "$mode  •" || echo "$mode"
    done
}

CHOICE=$(menu_entries | "$MANGO_DIR/scripts/walker/walker.sh" -d -p "Desktop mode" --maxheight 220) || exit 0
[[ "$CHOICE" == *"  •" ]] && exit 0
MODE="${CHOICE//  •/}"
MODE="${MODE// /}"
[ -z "$MODE" ] && exit 0

# Validate
valid=0
for m in "${MODES[@]}"; do [ "$m" = "$MODE" ] && valid=1; done
[ $valid -eq 0 ] && exit 0

"$MANGO_DIR/scripts/mode.sh" "$MODE"
mmsg -s -d reload_config
