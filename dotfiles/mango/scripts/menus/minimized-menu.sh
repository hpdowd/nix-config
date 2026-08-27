#!/usr/bin/env bash
# Usage: minimized-menu.sh '<appid-to-icon JSON>'
#
# Picks among the windows SUPER+I has put away and restores the one chosen.
# Opened by clicking custom/minimized on the bar, which shows only the count —
# a waybar module's label is text and GTK gives it one background image, so this
# is the surface where a window can carry its own icon. docs/adr/0052.
#
# `mmsg dispatch focusid client,<id>` RESTORES A SPECIFIC WINDOW, onto the tag
# you are viewing, focused. That is what makes this menu allowed to exist:
# docs/adr/0033 refuses an action that appears to do nothing, and while
# `restore_minimized` was the only verb the choice could not be honoured — it
# takes no client and pops the last minimized window on the current tag,
# answering `{"success":true}` either way. Verified 2026-08-28 on throwaway
# windows, both directions and across tags. docs/gotchas.md -> Waybar.
#
# The icon names come from waybar.nix as $1, so the appid table has one owner
# and the picker's art matches the title bar's.

# NOT `lib.sh`'s `rofi_menu`, and not because of the sizing. rofi's dmenu icon
# syntax puts a NUL between the row text and its metadata, and BASH STRINGS
# CANNOT CARRY NUL: `rofi_menu` reads its entries with `entries=$(cat)`, and a
# command substitution drops the byte silently. So does building the menu up in
# a variable. The first version of this did both and rendered rows reading
# `Spotify Premiumicon<U+241F>spotify` — every row's metadata as visible text,
# with nothing erroring. The bytes have to go straight down the pipe.
# docs/gotchas.md -> rofi.

ICONS=${1:-}
# An absent argument must not be fatal: the menu then lists titles without
# icons rather than not opening at all.
[ -n "$ICONS" ] || ICONS='{}'

# id, title and icon name per minimized window, one jq, tab-separated. `@tsv`
# keeps an empty title from collapsing the field count, which a plain
# interpolation would do.
mapfile -t rows < <(
	mmsg get all-clients 2>/dev/null |
		jq -r --argjson icons "$ICONS" '
			.clients[]? | select(.is_minimized == true)
			| [ (.id | tostring),
			    (.title // .appid // "?"),
			    ($icons[.appid] // $icons.default // "") ] | @tsv
		' 2>/dev/null
)

# Nothing hidden: the module collapses to nothing in that state, so there is
# nothing to have clicked. Exit quietly rather than draw an empty menu.
[ "${#rows[@]}" -gt 0 ] || exit 0

ids=()
for row in "${rows[@]}"; do
	ids+=("${row%%$'\t'*}")
done

# `-theme-str`, not `-l`: on rofi 2.0 the theme overrides the command line, so
# `-l` is accepted and ignored and every menu renders at config.rasi's height.
# Same reasoning as lib.sh's, which this cannot call. 12 is the ceiling other
# machine-generated lists here use.
lines=${#rows[@]}
[ "$lines" -gt 12 ] && lines=12

# `-show-icons` DOES beat config.rasi, unlike `-l` — config.rasi turns icons off
# for every other menu, where the glyphs are already in the text. Verified with
# `rofi -dump-config`, which reports `show-icons: true` with the flag and
# `false` without. docs/gotchas.md -> rofi.
#
# `-format i` returns the row INDEX. Titles are not unique — two foot windows
# are two rows reading `foot` — so matching the returned string back to an id
# would restore whichever collided first.
idx=$(
	for row in "${rows[@]}"; do
		IFS=$'\t' read -r _ title icon <<<"$row"
		if [ -n "$icon" ]; then
			printf '%s\0icon\x1f%s\n' "$title" "$icon"
		else
			printf '%s\n' "$title"
		fi
	done | rofi -dmenu -theme-str "listview { lines: $lines; }" \
		-i -no-custom -format i -show-icons -p "minimized"
) || exit 0
[ -n "$idx" ] || exit 0

id=${ids[$idx]:-}
[ -n "$id" ] || exit 0

# The dispatch answers `{"success":true}` whether or not it restored anything,
# so the reply is not evidence. Read the client back instead.
mmsg dispatch focusid "client,$id" >/dev/null 2>&1
if [ "$(mmsg get all-clients 2>/dev/null |
	jq -r --argjson i "$id" '.clients[]? | select(.id == $i) | .is_minimized')" = "true" ]; then
	notify-send -a mango "Minimized" "Window $id did not come back" 2>/dev/null
fi
