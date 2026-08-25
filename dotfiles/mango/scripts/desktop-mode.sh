#!/usr/bin/env bash
# Pick the desktop mode (SUPER+CTRL+/).
#
# This script read the old `$MANGO_DIR/state/current-mode` path until
# 2026-07-31, months after the state moved. The failure was silent and
# asymmetric: current_mode() never found the file, so it always returned its
# "tiling" fallback, the menu always marked tiling as active, and the `•` guard
# below then read picking tiling as "already there" and exited 0. Switching
# Away worked; switching back was impossible, with nothing logged.
#
# That is why the path and the fallback now come from lib.sh — one definition,
# so a reader cannot disagree with a writer about either.
. "$HOME/.config/mango/scripts/lib.sh"

# One line, and it must stay one line: checks/static.sh reads it with `sed` to
# cross-check that every mode has its conf and its mode script.
MODES=("tiling" "noctalia")

menu_entries() {
	local current
	current=$(current_mode)
	for mode in "${MODES[@]}"; do
		[ "$mode" = "$current" ] && echo "$mode  •" || echo "$mode"
	done
}

CHOICE=$(menu_entries | rofi_menu 20 -no-custom -p "Desktop mode") || exit 0
[[ "$CHOICE" == *"  •" ]] && exit 0
MODE="${CHOICE//  •/}"
MODE="${MODE// /}"
[ -z "$MODE" ] && exit 0

# Validate
valid=0
for m in "${MODES[@]}"; do [ "$m" = "$MODE" ] && valid=1; done
[ $valid -eq 0 ] && exit 0

"$MANGO_DIR/scripts/mode.sh" "$MODE"
mmsg dispatch reload_config
