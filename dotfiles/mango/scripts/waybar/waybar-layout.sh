#!/usr/bin/env bash
# Pick the waybar layout (SUPER+/). `hud` is deliberately not offered: it is
# selected by the desktop MODE, not here — see waybar-restart.sh.
. "$HOME/.config/mango/scripts/lib.sh"

# Refuse before the picker opens, and SAY SO: in noctalia mode there is no
# waybar to lay out, and a menu that accepts a choice and then does nothing is
# worse than a key that reports why.
if ! mode_has_waybar; then
    notify-send "Waybar" "No waybar in $(current_mode) mode"
    exit 0
fi

LAYOUTS=("full" "focus" "minimal")

menu_entries() {
    local current
    current=$(waybar_layout)
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

state_write waybar-layout "$name"
"$MANGO_DIR/scripts/waybar/waybar-restart.sh"
