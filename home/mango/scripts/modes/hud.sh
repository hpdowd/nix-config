#!/usr/bin/env bash
MANGO="$HOME/.config/mango"

# Runtime state lives OUTSIDE the config tree — see tiling.sh for why.
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/mango"

mkdir -p "$STATE"
echo "hud" > "$STATE/current-mode"
cp "$MANGO/hud/hud.conf" "$MANGO/config.conf"

# `ln -sf … active-theme.*` removed 2026-07-30 — dead indirection, see tiling.sh.
# Equibop has no settings.json until it is launched once, which is the normal
# state on a fresh machine — skip rather than erroring on every mode switch.
if [ -f ~/.config/equibop/settings/settings.json ]; then
  jq '.enabledThemes = ["gruvbox.theme.css"]' ~/.config/equibop/settings/settings.json > /tmp/equibop-settings.json && mv /tmp/equibop-settings.json ~/.config/equibop/settings/settings.json
fi
