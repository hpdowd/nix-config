#!/usr/bin/env bash
# Usage: idle-inhibit.sh <toggle|on|off|status|is-on>
#
# "Do not sleep" — the escape hatch for a long unattended build. It holds a
# `zwp_idle_inhibit_manager_v1` inhibitor, which is the only thing swayidle's
# ladder honours here: swayidle takes its idle signal from the compositor, and
# `systemd-inhibit --what=idle` never reaches it (docs/SYSTEM.md §9).
#
# Why a unit and not waybar's built-in idle_inhibitor module. That module holds
# the inhibitor on the bar's own layer surface, as a static bool in the waybar
# process, toggled only by a click on the widget. waybar exposes no IPC and no
# signal for it — SIGUSR1/2 drive bar visibility, and `signal` refreshes
# `custom/*` modules only — so there was no way to reach it from a key. Worse,
# the state died with the bar: `waybar-reload`, a mode switch, a layout switch
# and SUPER+/ all handed the machine back to the idle ladder, glyph included,
# with nothing logged. A unit outlives every one of those. docs/adr/0031.
#
# The inhibitor is wlinhibit, whose whole job is to hold one open until killed;
# the unit is declared in modules/home/default.nix. Process lifetime is the
# state, so there is no state file to drift out of step with it — and so this
# is the one mango script with no reason to source lib.sh.

set -u

UNIT=wlinhibit.service

# Escapes, not literal glyphs, for the reason power-profile.sh gives: written
# literally on 2026-07-31 its icons were lost in transit and every branch
# assigned the empty string, so the module emitted {"text":""} and waybar drew
# nothing. Both are past U+ffff, so `\U` with eight digits — bash's `\u` takes
# four, and `3` silently means U+F04B followed by "3".
ICON_ON=$'\U000F04B3'  # nf-md-sleep_off
ICON_OFF=$'\U000F04B2' # nf-md-sleep

is_on() {
	systemctl --user is-active --quiet "$UNIT"
}

refresh_waybar() {
	pkill -RTMIN+12 waybar
}

do_on() {
	systemctl --user start "$UNIT"

	# `start` returns once the process is forked, not once it holds anything.
	# wlinhibit prints "unable to aquire idle inhibit manager" and exits 1 when
	# the compositor advertises none, and that lands after the return — so
	# without this the key would report success and inhibit nothing.
	sleep 0.3
	if ! is_on; then
		notify-send -u critical "Keep awake" \
			"wlinhibit did not stay up: $(systemctl --user is-active "$UNIT")"
		refresh_waybar
		return 1
	fi
	refresh_waybar
}

do_off() {
	systemctl --user stop "$UNIT"
	refresh_waybar
}

do_toggle() {
	if is_on; then do_off; else do_on; fi
}

# Always prints a non-empty `text`: an empty custom module is indistinguishable
# from an absent one. `failed` gets its own branch rather than folding into
# "off" — a restart-limited unit and a deliberately released one look the same
# on the bar otherwise, and only one of them is a problem.
do_status() {
	case "$(systemctl --user is-active "$UNIT" 2>/dev/null)" in
	active)
		printf '{"text":"%s","class":"activated","tooltip":"Idle inhibited — nothing dims, locks or sleeps"}\n' "$ICON_ON"
		;;
	failed)
		printf '{"text":"%s","class":"failed","tooltip":"Keep awake FAILED — the idle ladder is live. systemctl --user status %s"}\n' "$ICON_ON" "$UNIT"
		;;
	*)
		printf '{"text":"%s","class":"deactivated","tooltip":"Idle ladder live — dim 4m, lock 5m, sleep 30m on battery"}\n' "$ICON_OFF"
		;;
	esac
}

case "${1:-}" in
toggle) do_toggle ;;
on) do_on ;;
off) do_off ;;
status) do_status ;;
# For lib.sh's mode handover. A verb rather than letting the caller run
# `systemctl --user is-active wlinhibit.service` itself: the unit name is
# written once, here, and a caller cannot drift from it.
is-on) is_on ;;
*)
	echo "Usage: ${0##*/} <toggle|on|off|status|is-on>"
	exit 1
	;;
esac
