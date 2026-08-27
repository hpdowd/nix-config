#!/usr/bin/env bash
# Usage: minimized.sh '<appid-to-glyph JSON>'
#
# The windows SUPER+I has put away, as waybar JSON. Replaced `wlr/taskbar`,
# which listed every open window — the list you already have on the workspace
# tags — where the only windows you cannot see from the bar are the minimized
# ones. docs/adr/0051.
#
# One glyph per minimized window, from the same table `custom/window` uses, so a
# minimized zen reads as the same browser glyph it wore in the title. The table
# is passed in from waybar.nix rather than written here; see the note on
# `custom/window` for why the lookup is the script's and the table is not.
#
# WHAT THE CLICK CAN AND CANNOT DO. `mmsg dispatch restore_minimized` is mango's
# only restore verb and it takes no client: it pops the last minimized window on
# the CURRENT TAG. There is no way to target one, and no way to tell from here
# which tag a minimized window belongs to — mango clears `tags` to `[]` on
# minimize, which is also what makes `is_minimized` worth reading rather than
# inferring. So the tooltip lists what is hidden and the click restores the most
# recent; a rofi picker was considered and rejected, because a menu that accepts
# a choice it cannot honour is worse than no menu (docs/adr/0033).
#
# `{"success":true}` FROM A RESTORE THAT RESTORED NOTHING is the shape to expect
# when the stack is empty or the window was minimized on another tag. Verified
# on 2026-08-27: a window minimized and restored on one tag round-trips exactly;
# a window minimized on tag 1 does not come back while tag 2 is active, and the
# dispatch says `success` either way. docs/gotchas.md -> Waybar.

# waybar kills this module by closing its pipe, and the `mmsg watch` inside the
# process substitution below does not go with it — four orphans were alive at
# once on 2026-08-16 from the sibling script, each holding 5 MB and an open IPC
# socket. `-P $$` targets this script's own children by parent rather than by
# name, which is both exact and safe. The signal traps `exit` and leave the
# reaping to the EXIT trap: a handler that does not exit REPLACES the default
# action, which is how the first version of the sibling's fix made the script
# immune to sigterm and leaked itself instead. docs/gotchas.md -> Scripts.
cleanup() { pkill -P $$ 2>/dev/null; }
trap cleanup EXIT
trap 'exit 0' PIPE HUP INT TERM

ICONS=${1:-}
# jq needs valid JSON for --argjson, and an absent argument must not be fatal:
# the module then renders glyph-less rather than not at all.
[ -n "$ICONS" ] || ICONS='{}'

# `class` is what CSS collapses on. An empty text still draws `.module`'s
# padding, which is 10px of dead bar in the resting state — the same 10px that
# was reported as bluetooth's padding on the wayle bar (docs/gotchas.md).
emit() {
	local out
	out=$(jq -c --argjson icons "$ICONS" '
		[.clients[]? | select(.is_minimized == true)] as $m
		| { text:    ($m | map($icons[.appid] // $icons.default // "") | join(" ")),
		    tooltip: ($m | map(.title // .appid // "?") | join("\n")),
		    class:   (if ($m | length) == 0 then "empty" else "some" end) }
	' 2>/dev/null) || out=""
	# A jq that failed prints nothing, and waybar holds a module's last value
	# when its update yields nothing — so the bar would keep showing a count
	# that has stopped tracking anything. Say so instead.
	[ -n "$out" ] || out='{"text":"?","tooltip":"minimized.sh: the client list did not parse","class":"error"}'
	printf '%s\n' "$out"
}

# Seed from a one-shot so the module is populated before the first change.
mmsg get all-clients 2>/dev/null | emit

while true; do
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		printf '%s' "$line" | emit
	done < <(mmsg watch all-clients 2>/dev/null)

	# Stream ended (compositor reload/restart) — back off and reconnect. No
	# empty emit first, unlike window-title.sh: a title that is stale is wrong,
	# but the minimized set does not change because the bar lost its stream.
	sleep 1
done
