#!/usr/bin/env bash
# Streams the focused window title as waybar JSON.
#
# Replaces waybar's built-in "dwl/window" module. Mango 0.15.5 dropped the dwl
# IPC protocol (zdwl_ipc_manager_v2) that module binds to, which made waybar
# segfault on startup. Mango exposes the same information over its own IPC.

# waybar kills this module by closing its pipe, and the `mmsg watch` inside the
# process substitution below does not go with it: four orphans were alive at
# once on 2026-08-16, up to fourteen hours old, each holding 5 MB and an open
# IPC socket to mango. One leaks per `pkill waybar` — so every mode switch and
# every waybar-reload. `-P $$` targets this script's own children by parent
# rather than by name, which is both exact and safe: matching `mmsg` would take
# out every other module's watcher too. Pipe is in the list because that is how
# this script usually dies, and its default action skips the exit trap.
#
# The signal traps `exit` and leave the reaping to exit. Handling a signal with
# a handler that does not exit replaces the default action, so the first version
# of this fix traded the watcher leak for a worse one — the script itself became
# immune to sigterm and sigpipe, reaped its child, and looped forever. At logout
# that cost 90 s of `session-N.scope: Stopping timed out` on every shutdown and
# reboot; per `pkill waybar` it leaked this script instead of its watcher.
# docs/gotchas.md → Scripts.
cleanup() { pkill -P $$ 2>/dev/null; }
trap cleanup EXIT
trap 'exit 0' PIPE HUP INT TERM

# THE APP GLYPH GOES IN THE TEXT, and the table comes from waybar.nix as $1.
#
# waybar's own way — `format = "{icon} {}"` with a `format-icons` map keyed by
# the JSON `alt` — renders the WHOLE label empty on 0.15.0 and logs nothing.
# So the table stays declared in Nix, where a name and its glyph sit together,
# and the lookup happens here where it actually draws. `alt` is still emitted:
# it costs nothing and it is what a `#custom-window.<app>` CSS rule would key
# on. docs/adr/0051.
#
# Bar label only. The tooltip is the plain title — a glyph in a tooltip is
# decoration on text nobody is glancing at.
ICONS=${1:-}

icon_for_app() {
	local appid=$1 out=""
	[ -n "$ICONS" ] || return 0
	out=$(jq -r --arg a "$appid" '.[$a] // .default // ""' <<<"$ICONS" 2>/dev/null) || out=""
	printf '%s' "$out"
}

emit() {
	local text=$1 appid=$2 icon
	icon=$(icon_for_app "$appid")
	[ -n "$text" ] && [ -n "$icon" ] && text="$icon $text"
	jq -cn --arg t "$text" --arg p "$1" --arg a "$appid" \
		'{text: $t, alt: $a, tooltip: $p, class: "window"}'
}

# Both fields in ONE jq, joined on U+001F: two invocations per focus change is
# two processes on a path that fires on every window switch, and `read` with a
# tab cannot see an empty leading field — the appid is empty for a client that
# has not set one. gotchas.md -> Scripts.
fields_of() {
	jq -r 'if type == "object" then ((.title // "") + "\u001f" + (.appid // "")) else "\u001f" end' 2>/dev/null
}

emit_fields() {
	local blob=$1
	emit "${blob%%$'\037'*}" "${blob#*$'\037'}"
}

# Seed with the current focus so the bar is populated immediately.
emit_fields "$(mmsg get focusing-client 2>/dev/null | fields_of)"

while true; do
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		emit_fields "$(printf '%s' "$line" | fields_of)"
	done < <(mmsg watch focusing-client 2>/dev/null)

	# Stream ended (compositor reload/restart) — clear, back off, reconnect.
	emit "" ""
	sleep 1
done
