#!/usr/bin/env bash
MANGO="$HOME/.config/mango"

# Runtime state lives OUTSIDE the config tree, at ~/.local/state/mango
# (2026-07-30). It used to be $MANGO/state, which forced ~/.config/mango to
# stay writable and therefore out of the Nix store — a program writing into its
# own config directory is the thing that blocks a store-based, reproducible
# config. It also left `pia-auth` (mode 600 PIA credentials) sitting inside the
# git repo, relying on .gitignore to stay out of history.
#
# Every reader resolves it the same way, so change it here and there only.
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/mango"

mkdir -p "$STATE"
echo "tiling" > "$STATE/current-mode"
cp "$MANGO/tiling/tiling.conf" "$MANGO/config.conf"

# The two `ln -sf … active-theme.*` lines that were here are gone (2026-07-30).
# Both mode scripts pointed them at the same gruvbox files, so the indirection
# selected nothing — kitty.conf and foot.ini now name the theme directly. It
# was only ever load-bearing when the removed `dms` mode had its own palette.
# Equibop has no settings.json until it is launched once, which is the normal
# state on a fresh machine — skip rather than erroring on every mode switch.
if [ -f ~/.config/equibop/settings/settings.json ]; then
  jq '.enabledThemes = ["gruvbox.theme.css"]' ~/.config/equibop/settings/settings.json > /tmp/equibop-settings.json && mv /tmp/equibop-settings.json ~/.config/equibop/settings/settings.json
fi
