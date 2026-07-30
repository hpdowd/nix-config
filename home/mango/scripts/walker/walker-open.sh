#!/usr/bin/env bash
# Opens the main walker launcher with height appropriate for the current mode.
MODE=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/mango/current-mode" 2>/dev/null || echo "tiling")
if [ "$MODE" = "hud" ]; then
  exec ~/.config/mango/scripts/walker/walker.sh --maxheight 220 --minheight 220 --width 200
else
  exec ~/.config/mango/scripts/walker/walker.sh
fi
