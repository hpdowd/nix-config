#!/usr/bin/env bash
# Tiling mode — solid full-width bar.
#
# The body is apply_mode() in ../lib.sh: this file and the since-removed
# hud.sh (docs/adr/0035) were byte-identical apart from two names, which is
# why the body was extracted. Autostart and the keybinds invoke the mode
# scripts by path, so they stay as files rather than becoming `mode.sh tiling`.
. "$HOME/.config/mango/scripts/lib.sh"

apply_mode tiling
