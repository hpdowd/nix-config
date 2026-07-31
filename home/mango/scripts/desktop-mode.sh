#!/usr/bin/env bash

MANGO_DIR="$HOME/.config/mango"

# Runtime state moved out of the config tree to ~/.local/state/mango on
# 2026-07-30, but this script kept reading the old $MANGO_DIR/state path until
# 2026-07-31. The failure was silent and asymmetric: current_mode() never found
# the file, so it always returned its "tiling" fallback, the menu always marked
# tiling as the active mode, and the `•` guard below then treated picking
# tiling as "already there" and exited 0. Switching TO hud worked; switching
# BACK was impossible, with nothing logged.
#
# Resolve it exactly as scripts/modes/*.sh do — one expression, one location.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mango"
STATE="$STATE_DIR/current-mode"
WALKER_CONFIGS="$MANGO_DIR/walker/configs"

MODES=("tiling" "hud")

current_mode() {
    [ -f "$STATE" ] && cat "$STATE" || echo "tiling"
}

menu_entries() {
    local current
    current=$(current_mode)
    for mode in "${MODES[@]}"; do
        [ "$mode" = "$current" ] && echo "$mode  •" || echo "$mode"
    done
}

CHOICE=$(menu_entries | "$MANGO_DIR/scripts/walker/walker.sh" -d -p "Desktop mode" --maxheight 220) || exit 0
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
