#!/usr/bin/env bash
# Focus the window the bar's media module is reporting. Left-click on `mpris`.
#
# It used to be `scratch-toggle.sh Spotify spotify` — one player, hardcoded, on
# a module that shows whichever player is active. With a video playing in the
# browser the label said one thing and the click did another, and Spotify
# appeared over the window you were actually listening to. docs/adr/0058.
#
# MATCHED BY PID, not by name. MPRIS bus names and mango appids do not agree:
# zen-beta publishes `org.mpris.MediaPlayer2.firefox`, so any name table would
# need a row per browser and would go stale silently. D-Bus can say which
# process owns the bus name, and mango reports a pid per client, so the two
# sides can be joined on a fact neither of them invented.
set -u

# The player the module is showing. waybar's mpris picks the playing one when
# there is one, so prefer that and fall back to the first that answers — a
# paused player is still the one whose title is on the bar.
pick_player() {
	local p players=()
	mapfile -t players < <(playerctl -l 2>/dev/null)
	[ ${#players[@]} -gt 0 ] || return 1
	for p in "${players[@]}"; do
		[ "$(playerctl -p "$p" status 2>/dev/null)" = "Playing" ] && {
			printf '%s' "$p"
			return 0
		}
	done
	printf '%s' "${players[0]}"
}

# Who owns org.mpris.MediaPlayer2.<player>. `busctl --user` rather than qdbus:
# it is in the session already and needs no Qt.
owner_pid() {
	busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
		org.freedesktop.DBus GetConnectionUnixProcessID s "org.mpris.MediaPlayer2.$1" 2>/dev/null |
		awk '{print $2}'
}

# The window pid and the MPRIS pid are the same process for every player here,
# checked against zen-beta and spotify. Walking up is for the ones where they
# are not: a player that publishes MPRIS from a helper process would otherwise
# match nothing and the click would do nothing, silently.
client_for_pid() {
	local pid=$1 clients=$2 hit
	while [ -n "$pid" ] && [ "$pid" != 1 ]; do
		hit=$(jq -r --argjson p "$pid" \
			'first(.clients[]? | select(.pid == $p) | "\(.id)\t\(.appid)\t\(.is_namedscratchpad)")' \
			<<<"$clients" 2>/dev/null)
		[ -n "$hit" ] && [ "$hit" != null ] && {
			printf '%s' "$hit"
			return 0
		}
		pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
	done
	return 1
}

player=$(pick_player) || {
	notify-send -t 2000 "Media" "Nothing is playing"
	exit 0
}

pid=$(owner_pid "$player")
[ -n "$pid" ] || {
	notify-send -t 2000 "Media" "$player publishes no process id"
	exit 0
}

clients=$(mmsg get all-clients 2>/dev/null)
[ -n "$clients" ] || {
	notify-send -u critical "Media" "The compositor did not answer"
	exit 1
}

# Assigned first and tested second, not `read ... || fail`: `read` returns 1 at
# EOF without a trailing newline even when it has filled every variable, so that
# form reports failure on success.
hit=$(client_for_pid "$pid" "$clients") || hit=""
[ -n "$hit" ] || {
	# A player with no window of its own — playerctld, or a daemon. Say so
	# rather than exiting 0 on a click that appears to do nothing.
	notify-send -t 2000 "Media" "$player has no window"
	exit 0
}
IFS=$'\t' read -r id appid named <<<"$hit"

# A named scratchpad is not on a tag and `focusid` cannot reveal it — that is
# the whole point of the pad. Spotify is one, which is why the old hardcoded
# call worked for it and only it.
if [ "$named" = true ]; then
	mmsg dispatch "toggle_named_scratchpad,$appid,none,${appid,,}"
else
	mmsg dispatch "focusid client,$id"
fi
