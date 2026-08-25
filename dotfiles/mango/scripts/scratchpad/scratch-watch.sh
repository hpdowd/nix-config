#!/usr/bin/env bash
# Daemon: syncs /tmp/scratch-* state files with mango focus events.
# Signals waybar (sigrtmin+8) only when state actually changes.
# Start from autostart.sh; restarts automatically if mmsg -w exits.

SCRATCHPADS=(spotify equibop)

# Reap the `mmsg watch` below on the way out. Nothing kills this script today —
# it is `exec-once`, so a mode switch leaves it alone — but window-title.sh had
# exactly this shape and leaked one watcher per waybar kill, each holding an IPC
# socket to mango for as long as the session lasted. `-P $$` is by parent, not
# by name, so it cannot reach another script's watcher.
#
# The signal traps must `exit`. A handler that only cleans up replaces sigterm's
# default action, so logind's sigterm stopped killing this script: it reaped the
# watcher, fell back into the loop below, and spun on `sleep 1` until the scope
# hit DefaultTimeoutStopUSec and SIGKILLed it — 90 s added to every shutdown and
# reboot, logged only as `session-N.scope: Stopping timed out`.
# docs/gotchas.md → Scripts.
cleanup() { pkill -P $$ 2>/dev/null; }
trap cleanup EXIT
trap 'exit 0' PIPE HUP INT TERM

# Clean slate on start — compositor restart means all scratchpads are gone
for pad in "${SCRATCHPADS[@]}"; do rm -f "/tmp/scratch-${pad}"; done
pkill -RTMIN+8 waybar 2>/dev/null || true

update() {
	local appid="$1"
	local changed=0

	for pad in "${SCRATCHPADS[@]}"; do
		local f="/tmp/scratch-${pad}"
		if [ "$appid" = "$pad" ]; then
			[ -f "$f" ] || {
				touch "$f"
				changed=1
			}
		else
			[ -f "$f" ] && {
				rm -f "$f"
				changed=1
			}
		fi
	done

	[ "$changed" -eq 1 ] && pkill -RTMIN+8 waybar
}

while true; do
	mmsg watch all-clients 2>/dev/null | while IFS= read -r line; do
		if [[ "$line" =~ appid[[:space:]]+([^[:space:]]+) ]]; then
			update "${BASH_REMATCH[1],,}"
		fi
	done
	# `mangowm` was never the process name — mango is unwrapped, so comm is
	# plain `mango` and this loop exited on its first reconnect.
	pgrep -x mango >/dev/null || exit 0
	sleep 1
done
