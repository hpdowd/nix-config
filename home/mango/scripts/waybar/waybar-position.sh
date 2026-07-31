#!/usr/bin/env bash
# Move the waybar between the top and bottom screen edge.
#
# Bound to SUPER+SHIFT+/ , alongside SUPER+/ (waybar layout) and SUPER+CTRL+/
# (desktop mode). Those two open a walker picker because they have three and
# two-plus options respectively; this one is a straight toggle, because with
# exactly two positions a menu is more keystrokes than the thing it selects.
#
# An explicit argument is still accepted (`waybar-position.sh bottom`) so the
# position can be forced from a script without knowing the current value.
#
# This script owns nothing but the state file. The actual work — rewriting
# `position` into the chosen layout config, since waybar has no --position
# flag — is in waybar-restart.sh, so that every other caller of it (login
# autostart, mode switch, layout switch, config reload) lands on the same
# position without having to know this feature exists.

set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mango"
STATE="$STATE_DIR/waybar-position"

current=$(cat "$STATE" 2>/dev/null || echo "top")

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

mkdir -p "$STATE_DIR"
echo "$next" > "$STATE"

exec "$HOME/.config/mango/scripts/waybar/waybar-restart.sh"
