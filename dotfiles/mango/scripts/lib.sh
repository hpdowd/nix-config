#!/usr/bin/env bash
# Shared definitions for the mango scripts. Source it, don't run it:
#
#   . "$HOME/.config/mango/scripts/lib.sh"
#
# This exists because the state directory used to be re-derived in every script
# that touched it, each with its own copy of the `${XDG_STATE_HOME:-…}` fallback
# and its own default value. That is how the mode switch broke one-way on
# 2026-07-31: `desktop-mode.sh` still resolved `current-mode` under the old
# `$MANGO_DIR/state`, found nothing, fell back to "tiling", and so reported
# tiling as active in every mode — which made switching back look like a no-op.
# Nothing was logged. One definition, in one file, forecloses that whole class.

# shellcheck shell=bash
# SC2034: these are consumed by the scripts that source this file, not here.
# shellcheck disable=SC2034
MANGO_DIR="$HOME/.config/mango"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mango"
# shellcheck disable=SC2034
WAYBAR_DIR="$MANGO_DIR/waybar"

# Read a state file, or echo the default if it is missing or empty. Every
# reader wants exactly this, and the defaults must agree across scripts.
state() {
    local file="$STATE_DIR/$1" fallback="$2" value
    value=$(cat "$file" 2>/dev/null) || true
    [ -n "$value" ] && printf '%s\n' "$value" || printf '%s\n' "$fallback"
}

state_write() {
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$2" > "$STATE_DIR/$1"
}

# The three switches, with their defaults in ONE place.
current_mode() { state current-mode tiling; }      # tiling | hud | noctalia
waybar_layout() { state waybar-layout full; }      # full | focus | minimal
waybar_position() { state waybar-position top; }   # top | bottom

# noctalia mode runs its own bar, so the three waybar scripts must refuse
# rather than start one over it. Here, not in each of them, for the reason the
# header gives: a reader and a writer that disagree fail silently.
mode_has_waybar() { [ "$(current_mode)" != noctalia ]; }

# Apply a desktop mode. modes/tiling.sh and modes/hud.sh differed only in two
# names and were otherwise a byte-identical copy of the body below, including
# the equibop block — so a fix to one silently missed the other.
apply_mode() {
    local mode="$1"
    state_write current-mode "$mode"

    # `install -m 644`, NOT `cp`. ~/.config/mango is a store path, so
    # <mode>.conf is a read-only 0444 file and `cp` gives a new destination the
    # source's mode — the first switch wrote a 0444 config.conf and every
    # switch after it died with `Permission denied`. `install -m` sets the mode
    # explicitly rather than inheriting it.
    install -m 644 "$MANGO_DIR/$mode/$mode.conf" "$MANGO_DIR/config.conf"

    # Equibop has no settings.json until it has been launched once, which is
    # the normal state on a fresh machine — skip rather than erroring on every
    # mode switch.
    local eq="$HOME/.config/equibop/settings/settings.json"
    if [ -f "$eq" ]; then
        jq '.enabledThemes = ["gruvbox.theme.css"]' "$eq" > "$eq.tmp" && mv "$eq.tmp" "$eq"
    fi
}
