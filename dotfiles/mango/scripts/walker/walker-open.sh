#!/usr/bin/env bash
# Opens the main walker launcher with height appropriate for the current mode.
. "$HOME/.config/mango/scripts/lib.sh"

if [ "$(current_mode)" = "hud" ]; then
  exec "$MANGO_DIR/scripts/walker/walker.sh" --maxheight 220 --minheight 220 --width 200
else
  exec "$MANGO_DIR/scripts/walker/walker.sh"
fi
