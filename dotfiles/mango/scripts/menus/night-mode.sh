#!/usr/bin/env bash
# Usage: night-mode.sh <toggle|menu|status>
#
# Drives the wlsunset *user service* rather than the wlsunset process. Only one
# Wayland client can hold a gamma control, so the old pkill-and-respawn fought
# the service and lost ("gamma control of output eDP-1 failed"). The unit is
# declared in nixos/modules/home/default.nix; its ExecStart
# (../system/night-light-run.sh) reads the temperature written here.

. "$HOME/.config/mango/scripts/lib.sh"

UNIT=wlsunset.service
TEMP_FILE="$STATE_DIR/night-temp"
DEFAULT_TEMP=4000

is_on() {
	systemctl --user is-active --quiet "$UNIT"
}

refresh_waybar() {
	pkill -RTMIN+9 waybar
}

do_toggle() {
	if is_on; then
		systemctl --user stop "$UNIT"
	else
		systemctl --user start "$UNIT"
	fi
	refresh_waybar
}

do_menu() {
	CHOICE=$(printf \
		"  2700K   Candlelight\n  3000K   Warm\n  3500K   Evening\n  4000K   Soft white\n  4500K   Neutral\n  6500K   (off)" |
		rofi_menu 20 -no-custom -p "Night mode")

	[ -z "$CHOICE" ] && exit 0

	TEMP=$(echo "$CHOICE" | grep -oE '[0-9]+K' | tr -d 'K')
	[ -z "$TEMP" ] && exit 0

	# 6500K is the day temperature, so picking it means "no shift" — stop the
	# service rather than run it as a no-op.
	if [ "$TEMP" = "6500" ]; then
		systemctl --user stop "$UNIT"
		refresh_waybar
		exit 0
	fi

	mkdir -p "$(dirname "$TEMP_FILE")"
	echo "$TEMP" >"$TEMP_FILE"

	# restart, not reload: wlsunset only reads its temperature from argv.
	systemctl --user restart "$UNIT"
	refresh_waybar
}

do_status() {
	MOON=$(printf '\xef\x86\x86')
	if is_on; then
		TEMP=$(cat "$TEMP_FILE" 2>/dev/null || echo "$DEFAULT_TEMP")
		printf '{"text":"%s ","class":"on","tooltip":"Night light on · %sK at night"}\n' "$MOON" "$TEMP"
	else
		printf '{"text":"%s ","class":"off","tooltip":"Night light off"}\n' "$MOON"
	fi
}

case "$1" in
toggle) do_toggle ;;
menu) do_menu ;;
status) do_status ;;
*)
	echo "Usage: $0 <toggle|menu|status>"
	exit 1
	;;
esac
