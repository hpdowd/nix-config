#!/usr/bin/env bash
MANGO="$HOME/.config/mango"
echo "tiling" > "$MANGO/state/current-mode"
cp "$MANGO/tiling/tiling.conf" "$MANGO/config.conf"
ln -sf ~/.config/kitty/gruvbox-orange.conf ~/.config/kitty/active-theme.conf
ln -sf ~/.config/foot/gruvbox-colors.ini ~/.config/foot/active-theme.ini
jq '.enabledThemes = ["gruvbox.theme.css"]' ~/.config/equibop/settings/settings.json > /tmp/equibop-settings.json && mv /tmp/equibop-settings.json ~/.config/equibop/settings/settings.json
