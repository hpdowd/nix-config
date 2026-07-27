#!/usr/bin/env bash

STATE_FILE="$HOME/.config/mango/state/waybar-layout"
MANGO_DIR="$HOME/.config/mango"

LAYOUTS=("full" "focus" "minimal")

current_name() {
    [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo "full"
}

menu_entries() {
    local current
    current=$(current_name)
    for name in "${LAYOUTS[@]}"; do
        [ "$name" = "$current" ] && echo "$name  •" || echo "$name"
    done
}

CHOICE=$(menu_entries | "$MANGO_DIR/scripts/walker/walker.sh" -d -p "Waybar layout" --maxheight 160) || exit 0
[[ "$CHOICE" == *"  •" ]] && exit 0
name="${CHOICE//  •/}"
name="${name// /}"
[ -z "$name" ] && exit 0

# Validate
valid=0
for n in "${LAYOUTS[@]}"; do [ "$n" = "$name" ] && valid=1; done
[ $valid -eq 0 ] && exit 0

echo "$name" > "$STATE_FILE"
"$MANGO_DIR/scripts/waybar/waybar-restart.sh"
