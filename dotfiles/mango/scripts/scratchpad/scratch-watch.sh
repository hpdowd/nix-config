#!/usr/bin/env bash
# Daemon: syncs /tmp/scratch-* state files with mango focus events.
# Signals waybar (SIGRTMIN+8) only when state actually changes.
# Start from autostart.sh; restarts automatically if mmsg -w exits.

SCRATCHPADS=(spotify equibop)

# Clean slate on start — compositor restart means all scratchpads are gone
for pad in "${SCRATCHPADS[@]}"; do rm -f "/tmp/scratch-${pad}"; done
pkill -RTMIN+8 waybar 2>/dev/null || true

update() {
    local appid="$1"
    local changed=0

    for pad in "${SCRATCHPADS[@]}"; do
        local f="/tmp/scratch-${pad}"
        if [ "$appid" = "$pad" ]; then
            [ -f "$f" ] || { touch "$f"; changed=1; }
        else
            [ -f "$f" ] && { rm -f "$f"; changed=1; }
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
