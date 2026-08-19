#!/usr/bin/env bash
# Noctalia mode — noctalia-shell replaces waybar and swaync. docs/adr/0020.
# The body is apply_mode() in ../lib.sh, as for tiling.
. "$HOME/.config/mango/scripts/lib.sh"

# noctalia rewrites settings.json itself (Commons/Settings.qml writes through a
# JsonAdapter), so no xdg.configFile may claim the path — two owners is an
# activation failure. Instead the file is written from here, in two halves that
# differ in when they apply (docs/adr/0022):
#
#   settings.json         preferences. Written ONCE, when there is no file at
#                         all. Editing it does nothing to a machine that has
#                         already run the mode — by design; they are yours to
#                         change from noctalia's own UI afterwards.
#   settings-pinned.json  the keys that would otherwise fight this machine —
#                         wallpaper, night light, idle, lock-on-suspend,
#                         gsettings sync, app theming, plugin updates, and the
#                         colour scheme. Merged over the live file on EVERY
#                         entry into the mode, so noctalia's UI will visibly
#                         revert a change to one of these on the next switch.
#                         Change them here, not there.
#
# Both are partial and neither carries `settingsVersion`: upstream's migrations
# all guard on the old key being present, so they no-op rather than corrupting
# a partial file. checks/static.sh asserts every key in both still exists in the
# package's Assets/settings-default.json — noctalia ignores unknown keys in
# silence, so a rename upstream would otherwise just stop applying.
#
# `install -Dm644`, not `cp`: the source is a 0444 store file and cp would carry
# that mode across, the same trap apply_mode documents.
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/settings.json"
[ -f "$DEST" ] || install -Dm644 "$MANGO_DIR/noctalia/settings.json" "$DEST"

# The live shell holds settings in memory and writes the whole file back, so
# merging underneath a running one would be undone without a word. Entering the
# mode from tiling always has it stopped (its autostart stops the unit), so
# this only trips on a direct re-run of this script — and it says so
# rather than reporting a pin it did not apply.
if systemctl --user is-active --quiet noctalia; then
	notify-send "Noctalia" "Already running — pinned settings not re-applied"
else
	pin_tmp=$(mktemp)
	# `.[0] * .[1]` is jq's RECURSIVE merge, right-hand wins, so the pin
	# replaces only the leaves it names and leaves the rest of the object
	# alone. Guarded: a settings.json noctalia left half-written must not be
	# replaced by jq's empty output.
	if jq -s '.[0] * .[1]' "$DEST" "$MANGO_DIR/noctalia/settings-pinned.json" >"$pin_tmp"; then
		install -m 644 "$pin_tmp" "$DEST"
	else
		notify-send -u critical "Noctalia" "settings.json is not valid JSON — pinned settings not applied"
	fi
	rm -f "$pin_tmp"
fi

apply_mode noctalia
