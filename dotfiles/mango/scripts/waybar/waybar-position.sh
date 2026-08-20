#!/usr/bin/env bash
# Move the waybar between the top and bottom screen edge.
#
# Bound to SUPER+SHIFT+/ , alongside SUPER+/ (waybar layout) and SUPER+CTRL+/
# (desktop mode). Those two open a rofi picker because they have three and
# two-plus options respectively; this one is a straight toggle, because with
# exactly two positions a menu is more keystrokes than the thing it selects.
#
# An explicit argument is still accepted (`waybar-position.sh bottom`) so the
# position can be forced from a script without knowing the current value.
#
# This script owns nothing but the state file. Selecting the matching config —
# waybar has no --position flag, so each position is a separate generated file
# — is waybar-restart.sh's job, so that every other caller of it (login
# autostart, mode switch, layout switch, config reload) lands on the same
# position without having to know this feature exists.

set -u

. "$HOME/.config/mango/scripts/lib.sh"

# Same reason as waybar-layout.sh: nothing to move in noctalia mode, and this
# one would otherwise flip the state file silently.
if ! mode_has_waybar; then
	notify-send "Waybar" "No waybar in $(current_mode) mode"
	exit 0
fi

current=$(waybar_position)

case "${1:-}" in
top | bottom)
	next="$1"
	;;
"")
	if [ "$current" = "bottom" ]; then next="top"; else next="bottom"; fi
	;;
*)
	echo "usage: ${0##*/} [top|bottom]" >&2
	exit 1
	;;
esac

state_write waybar-position "$next"

exec "$MANGO_DIR/scripts/waybar/waybar-restart.sh"
