#!/usr/bin/env bash
# Apply a mode: `mode.sh [tiling|hud]`, defaulting to whatever is current.
. "$HOME/.config/mango/scripts/lib.sh"

MODE="${1:-$(current_mode)}"
exec "$MANGO_DIR/scripts/modes/$MODE.sh"
