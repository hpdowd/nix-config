#!/usr/bin/env bash
# Streams the focused window title as waybar JSON.
#
# Replaces waybar's built-in "dwl/window" module. Mango 0.15.5 dropped the dwl
# IPC protocol (zdwl_ipc_manager_v2) that module binds to, which made waybar
# segfault on startup. Mango exposes the same information over its own IPC.

emit() {
    jq -cn --arg t "$1" '{text: $t, tooltip: $t, class: "window"}'
}

title_of() {
    jq -r 'if type == "object" then (.title // "") else "" end' 2>/dev/null
}

# Seed with the current focus so the bar is populated immediately.
emit "$(mmsg get focusing-client 2>/dev/null | title_of)"

while true; do
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        title=$(printf '%s' "$line" | title_of)
        emit "$title"
    done < <(mmsg watch focusing-client 2>/dev/null)

    # Stream ended (compositor reload/restart) — clear, back off, reconnect.
    emit ""
    sleep 1
done
