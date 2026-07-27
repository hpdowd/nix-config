#!/usr/bin/env bash
MODE="${1:-$(cat "$HOME/.config/mango/state/current-mode" 2>/dev/null || echo "tiling")}"
exec "$HOME/.config/mango/scripts/modes/$MODE.sh"
