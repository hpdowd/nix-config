#!/usr/bin/env bash
# Streams the focused window title as waybar JSON.
#
# Replaces waybar's built-in "dwl/window" module. Mango 0.15.5 dropped the dwl
# IPC protocol (zdwl_ipc_manager_v2) that module binds to, which made waybar
# segfault on startup. Mango exposes the same information over its own IPC.

# waybar kills this module by closing its pipe, and the `mmsg watch` inside the
# process substitution below does NOT go with it: four orphans were alive at
# once on 2026-08-16, up to fourteen hours old, each holding 5 MB and an open
# IPC socket to mango. One leaks per `pkill waybar` — so every mode switch and
# every waybar-reload. `-P $$` targets this script's own children by parent
# rather than by name, which is both exact and safe: matching `mmsg` would take
# out every other module's watcher too. PIPE is in the list because that is how
# this script usually dies, and its default action skips the EXIT trap.
cleanup() { pkill -P $$ 2>/dev/null; }
trap cleanup EXIT PIPE HUP INT TERM

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
