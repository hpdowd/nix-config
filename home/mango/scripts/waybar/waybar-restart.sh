#!/usr/bin/env bash
# Restarts waybar from the current desktop mode, layout and position state.
#
# Called by desktop-mode.sh, waybar-layout.sh, waybar-position.sh, and by the
# `exec=` line in each mode's autostart.conf — which fires both at login and on
# every `mmsg dispatch reload_config`, so a reload also re-reads all three
# state files. This is the single place that knows how the three combine.

WAYBAR_DIR="$HOME/.config/mango/waybar"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mango"
MODE=$(cat "$STATE_DIR/current-mode" 2>/dev/null || echo "tiling")
LAYOUT=$(cat "$STATE_DIR/waybar-layout" 2>/dev/null || echo "full")
POSITION=$(cat "$STATE_DIR/waybar-position" 2>/dev/null || echo "top")

# sed expressions to apply to the chosen config, if any. Collected rather than
# applied inline so mode and position can each contribute without either one
# needing to know about the other.
EDITS=()

if [ "$MODE" = "hud" ]; then
    CONFIG="$WAYBAR_DIR/config-hud.jsonc"
    STYLE="$WAYBAR_DIR/style-hud.css"
else
    case "$LAYOUT" in
        focus)   CONFIG="$WAYBAR_DIR/config-focus.jsonc" ;;
        minimal) CONFIG="$WAYBAR_DIR/config-minimal.jsonc" ;;
        *)       CONFIG="$WAYBAR_DIR/config.jsonc" ;;
    esac

    case "$MODE" in
        tiling) STYLE="$WAYBAR_DIR/style-solid.css" ;;
        *)      STYLE="$WAYBAR_DIR/style.css" ;;
    esac

    # Tiling: the bar sits flush against the edge, so drop the floating margins.
    if [ "$MODE" = "tiling" ]; then
        EDITS+=(
            -e 's/"margin-top": *-?[0-9]+/"margin-top": 0/'
            -e 's/"margin-left": *-?[0-9]+/"margin-left": 0/'
            -e 's/"margin-right": *-?[0-9]+/"margin-right": 0/'
        )
    fi
fi

# Bottom: flip `position` and mirror the vertical margins.
#
# Rewriting the config is the only option — waybar takes just -c, -s and -b on
# the command line (`waybar --help`); `position` is a config key with no flag.
#
# The margin swap goes through a placeholder deliberately. sed applies every -e
# to the same line in sequence, so a plain top->bottom + bottom->top pair would
# rename margin-top to margin-bottom and then immediately back again, leaving
# both untouched. Mirroring matters for more than tidiness: the hud layout
# carries `"margin-bottom": -28` against a 28px bar to cancel its exclusive
# zone, and that has to move to the top edge with it.
if [ "$POSITION" = "bottom" ]; then
    EDITS+=(
        -e 's/"position": *"top"/"position": "bottom"/'
        -e 's/"margin-top": *(-?[0-9]+)/"margin-swap": \1/'
        -e 's/"margin-bottom": *(-?[0-9]+)/"margin-top": \1/'
        -e 's/"margin-swap": *(-?[0-9]+)/"margin-bottom": \1/'
    )
fi

if [ ${#EDITS[@]} -gt 0 ]; then
    # A fixed path under the state dir, not mktemp: the generated config is
    # regenerated on every mode/layout/position change, and mktemp left a new
    # /tmp/waybar-XXXXXX.jsonc behind each time. It belongs with the rest of
    # the runtime state anyway (ADR 0003) — the source configs are read-only
    # store paths and cannot be edited in place.
    mkdir -p "$STATE_DIR"
    GENERATED="$STATE_DIR/waybar-config.jsonc"
    sed -E "${EDITS[@]}" "$CONFIG" > "$GENERATED"
    CONFIG="$GENERATED"
fi

pkill waybar
sleep 0.1
nohup waybar -c "$CONFIG" -s "$STYLE" >/dev/null 2>&1 &
