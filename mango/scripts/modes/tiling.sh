#!/usr/bin/env bash
MANGO="$HOME/.config/mango"

# state/ and config.conf are gitignored (generated, not configuration), so a
# fresh clone has neither. Without this the first mode switch on a new machine
# fails to record the mode.
mkdir -p "$MANGO/state"
echo "tiling" > "$MANGO/state/current-mode"
cp "$MANGO/tiling/tiling.conf" "$MANGO/config.conf"
ln -sf ~/.config/kitty/gruvbox-orange.conf ~/.config/kitty/active-theme.conf
ln -sf ~/.config/foot/gruvbox-colors.ini ~/.config/foot/active-theme.ini
# Equibop has no settings.json until it is launched once, which is the normal
# state on a fresh machine — skip rather than erroring on every mode switch.
if [ -f ~/.config/equibop/settings/settings.json ]; then
  jq '.enabledThemes = ["gruvbox.theme.css"]' ~/.config/equibop/settings/settings.json > /tmp/equibop-settings.json && mv /tmp/equibop-settings.json ~/.config/equibop/settings/settings.json
fi
