#!/usr/bin/env bash
# Apply GTK theme for a given mode. Usage: gtk-apply.sh <mode>
MODE="${1:-tiling}"
GTK3="$HOME/.config/gtk-3.0"
GTK4="$HOME/.config/gtk-4.0"

if [ "$MODE" = "dms" ]; then
    GTK_THEME_NAME="adw-gtk3-dark"
    GTK_ICON_THEME="Papirus-Dark"
    GTK_CURSOR_THEME="Capitaine Cursors (Gruvbox)"
    GTK_FONT="Hack Nerd Font Regular 10"
    COLOR_SCHEME="prefer-dark"
    cp "$GTK3/gtk-dms.css"       "$GTK3/gtk.css"
    rm -f "$GTK4/gtk.css"
    cp "$GTK4/gtk-dms.css"       "$GTK4/gtk.css"
    cp "$GTK3/settings-dms.ini"  "$GTK3/settings.ini"
    cp "$GTK4/settings-dms.ini"  "$GTK4/settings.ini"
else
    GTK_THEME_NAME="Gruvbox-Yellow-Dark"
    GTK_ICON_THEME="Papirus-Dark"
    GTK_CURSOR_THEME="Capitaine Cursors (Gruvbox)"
    GTK_FONT="Hack Nerd Font Regular 10"
    COLOR_SCHEME="prefer-dark"
    cp "$GTK3/gtk-tiling.css"       "$GTK3/gtk.css"
    rm -f "$GTK4/gtk.css"
    cp "$GTK4/gtk-tiling.css"       "$GTK4/gtk.css"
    cp "$GTK3/settings-tiling.ini"  "$GTK3/settings.ini"
    cp "$GTK4/settings-tiling.ini"  "$GTK4/settings.ini"
fi

systemctl --user set-environment GTK_THEME="$GTK_THEME_NAME"
gsettings set org.gnome.desktop.interface gtk-theme      "$GTK_THEME_NAME"
gsettings set org.gnome.desktop.interface icon-theme     "$GTK_ICON_THEME"
gsettings set org.gnome.desktop.interface cursor-theme   "$GTK_CURSOR_THEME"
gsettings set org.gnome.desktop.interface font-name      "$GTK_FONT"
gsettings set org.gnome.desktop.interface color-scheme   "$COLOR_SCHEME"
systemctl --user restart xdg-desktop-portal-gtk
