#!/usr/bin/env bash
MANGO="$HOME/.config/mango"
sed -i 's/ \+#.*$//' "$MANGO/dms/binds.conf"
echo "dms" > "$MANGO/state/current-mode"
cp "$MANGO/dms/dms.conf" "$MANGO/config.conf"
ln -sf ~/.config/kitty/dank-theme.conf ~/.config/kitty/active-theme.conf
ln -sf ~/.config/foot/dank-colors.ini ~/.config/foot/active-theme.ini
jq '.enabledThemes = ["dank-discord.css"]' ~/.config/equibop/settings/settings.json > /tmp/equibop-settings.json && mv /tmp/equibop-settings.json ~/.config/equibop/settings/settings.json
