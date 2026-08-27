#!/usr/bin/env bash
# Pick the waybar layout (SUPER+/).
#
# Every layout here is reachable, which was not true until hud left
#: hud was a mode that forced its own layout, so in hud mode
# this picker wrote a choice to state that waybar-restart.sh then overrode —
# accepted, recorded, and invisible.
. "$HOME/.config/mango/scripts/lib.sh"

# Refuse before the picker opens, and say so: in noctalia mode there is no
# waybar to lay out, and a menu that accepts a choice and then does nothing is
# worse than a key that reports why.
if ! mode_has_bar; then
	notify-send "Waybar" "No waybar in $(current_mode) mode"
	exit 0
fi

LAYOUTS=("full" "focus" "minimal")

menu_entries() {
	local current
	current=$(bar_layout)
	for name in "${LAYOUTS[@]}"; do
		[ "$name" = "$current" ] && echo "$name  •" || echo "$name"
	done
}

CHOICE=$(menu_entries | rofi_menu 20 -no-custom -p "Waybar layout") || exit 0
[[ "$CHOICE" == *"  •" ]] && exit 0
name="${CHOICE//  •/}"
name="${name// /}"
[ -z "$name" ] && exit 0

# Validate
valid=0
for n in "${LAYOUTS[@]}"; do [ "$n" = "$name" ] && valid=1; done
[ $valid -eq 0 ] && exit 0

state_write bar-layout "$name"
"$MANGO_DIR/scripts/waybar/waybar-restart.sh"
