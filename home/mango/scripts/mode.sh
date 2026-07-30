#!/usr/bin/env bash
MODE="${1:-$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/mango/current-mode" 2>/dev/null || echo "tiling")}"
exec "$HOME/.config/mango/scripts/modes/$MODE.sh"
