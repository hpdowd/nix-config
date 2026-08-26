#!/usr/bin/env bash
# The notification history, as a menu. Reached by CTRL+ALT+backslash and by the
# control centre's Notifications row — in TILING mode only: noctalia draws its
# own panel and menus/shell.sh routes there before either caller gets here.
#
# WHY A MENU AND NOT THE PANEL. wayle's history IS a dropdown, and a dropdown
# opens from a bar click and from nothing else — com.wayle.Shell1 exposes
# BarShow/BarHide/BarToggle and no more, and a click action is a shell command
# or a `dropdown:`, never both. The bar's power button keeps the real panel on
# right-click; a KEY needs this. docs/adr/0047.
#
# A reader that delegates, the shape docs/adr/0033 gives the control centre:
# every action here is a `wayle notify` verb, so the bar's own count and this
# list cannot disagree about what a dismissal did.

set -u

. "$HOME/.config/mango/scripts/lib.sh"

# Escapes, not literal glyphs, for the reason control-center.sh gives: written
# literally on 2026-07-31 a set of these was lost in transit and every branch
# assigned the empty string, which renders as a row with no icon rather than as
# an error. Both are covered by the fonts rofi resolves — checked with
# `fc-list ':charset=f0f3' family`.
ICON_BELL=$'\uF0F3'  # nf-fa-bell, as control-center.sh spells it
ICON_CLEAR=$'\uF1F8' # nf-fa-trash
SEP=$'────────────────────────'
CLEAR_LABEL='Clear all'

# `busctl`, not `wayle notify list`. The CLI prints each body inline, newlines
# and all, so a two-line notification is three rows and two of them carry no id.
# The D-Bus method is typed: a(usss) of id, app, summary, body.
BUS=(--user -j call com.wayle.Notifications1 /com/wayle/Notifications com.wayle.Notifications1)

# Fails loudly rather than rendering an empty list: "nothing waiting" and "the
# daemon did not answer" are the two this repo keeps confusing, and only one of
# them is a working notification stack.
read_list() {
	local raw
	raw=$(busctl "${BUS[@]}" List 2>/dev/null) || return 1
	printf '%s' "$raw" | jq -r '.data[0][] | [(.[0] | tostring), .[1], .[2]] | @tsv' 2>/dev/null
}

while :; do
	# Command substitution, NOT `mapfile < <(read_list)`: a process substitution
	# does not propagate its exit status, so that spelling reported success with
	# zero rows whatever happened — "nothing waiting" for a daemon that is not
	# there, which is the one confusion this script exists to avoid.
	if ! rows_tsv=$(read_list); then
		notify-send -u critical "Notifications" \
			"wayle is not answering on com.wayle.Notifications1 — is the bar running?"
		echo "notifications.sh: com.wayle.Notifications1 did not answer" >&2
		exit 1
	fi
	mapfile -t rows <<<"$rows_tsv"

	ids=()
	entries=()
	for row in "${rows[@]}"; do
		[ -n "$row" ] || continue
		IFS=$'\t' read -r id app summary <<<"$row"
		ids+=("$id")
		# An app with no summary still gets a row: an entry rendering as blank
		# reads as a list that failed to load.
		entries+=("$ICON_BELL  ${app:-?}  ·  ${summary:-(no summary)}")
	done

	if [ "${#ids[@]}" -eq 0 ]; then
		printf '%s  Nothing waiting\n' "$ICON_BELL" | rofi_menu 1 -no-custom -p "Notifications" >/dev/null
		exit 0
	fi

	choice=$(
		{
			printf '%s\n' "${entries[@]}"
			printf '%s\n' "$SEP"
			printf '%s  %s  ·  %s waiting\n' "$ICON_CLEAR" "$CLEAR_LABEL" "${#ids[@]}"
		} | rofi_menu 15 -no-custom -p "Notifications"
	) || exit 0
	[ -n "$choice" ] || exit 0
	[ "$choice" = "$SEP" ] && continue

	case "$choice" in
	*"  $CLEAR_LABEL  ·  "*)
		wayle notify dismiss-all
		exit 0
		;;
	esac

	# Matched on the rendered line rather than on a row index, because the list
	# can gain an entry between the render and the choice — an index would then
	# dismiss the wrong notification, and a label cannot. Two identical
	# summaries from one app dismiss the first of the two, which is the same
	# outcome either way.
	for i in "${!entries[@]}"; do
		if [ "${entries[$i]}" = "$choice" ]; then
			wayle notify dismiss "${ids[$i]}"
			break
		fi
	done
done
