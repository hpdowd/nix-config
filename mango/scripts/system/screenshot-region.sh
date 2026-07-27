#!/usr/bin/env bash
# Region screenshot with frozen screen.
# wayfreeze overlays the current frame so moving content stays still during selection.

wayfreeze &
FREEZE_PID=$!

# Give the overlay a moment to appear
sleep 0.1

REGION=$(slurp 2>/dev/null)

[ -z "$REGION" ] && { kill "$FREEZE_PID" 2>/dev/null; wait "$FREEZE_PID" 2>/dev/null; exit 0; }

grim -g "$REGION" - | tee ~/Pictures/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png | wl-copy

kill "$FREEZE_PID" 2>/dev/null
wait "$FREEZE_PID" 2>/dev/null
