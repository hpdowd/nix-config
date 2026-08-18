#!/usr/bin/env bash
# Tiling mode — solid full-width bar.
#
# The body is apply_mode() in ../lib.sh: this file and hud.sh were byte-
# identical apart from two names. Autostart and the keybinds invoke the mode
# scripts by path, so they stay as files rather than becoming `mode.sh tiling`.
. "$HOME/.config/mango/scripts/lib.sh"

apply_mode tiling
