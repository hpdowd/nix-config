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

# THE ICON IS THE STYLESHEET'S. This emits the appid as a CSS `class`, and
# modules/home/waybar.nix generates `#custom-window.<class>` rules that give it
# a `-gtk-icontheme()` background — real Papirus art, where a label could only
# ever hold a font glyph. docs/adr/0052.
#
# waybar's own way of doing icons — `format = "{icon} {}"` with `format-icons`
# keyed on `alt` — renders the WHOLE label empty on 0.15.0 and logs nothing, so
# `alt` is emitted for readers and nothing reads it to draw.

# Mirrors `cssClass` in modules/home/waybar.nix, which writes the matching
# selector. The two must sanitise alike: a class that stops matching its rule
# draws the default icon and says nothing. checks/static.sh compares them.
css_class() {
	printf '%s' "${1//[. ]/-}"
}

# `empty` collapses the module, icon included. Without it a bar with nothing
# focused still draws the default icon over `padding-left` — an app icon for no
# app. `unknown` is a window that set no appid: it keeps the default icon,
# because something IS focused and the title is real.
emit() {
	local text=$1 appid=$2 class
	if [ -z "$text" ]; then
		class=empty
	else
		class=$(css_class "$appid")
		[ -n "$class" ] || class=unknown
	fi
	jq -cn --arg t "$text" --arg a "$appid" --arg c "$class" \
		'{text: $t, alt: $a, tooltip: $t, class: $c}'
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
