#!/usr/bin/env bash
# Runtime GTK glue. Usage: gtk-apply.sh  (the old <mode> argument is gone)
#
# Nix owns the GTK theme as of 2026-07-30 — see modules/home/theme.nix and
# docs/adr/0004. home-manager writes gtk-3.0/settings.ini, gtk-4.0/settings.ini,
# both gtk.css files, the bookmarks, and the matching
# org.gnome.desktop.interface dconf keys.
#
# What was removed from this script, and why:
#
#   cp "$GTK3/gtk-tiling.css"      "$GTK3/gtk.css"
#   cp "$GTK3/settings-tiling.ini" "$GTK3/settings.ini"    (and the GTK4 pair)
#       Dead. The `-tiling` files were byte-identical to their targets, this
#       script took a $MODE argument and then ignored it, and BOTH modes called
#       it as `gtk-apply.sh tiling` anyway. The same empty indirection as the
#       `active-theme.*` symlinks. Those source files are deleted.
#
#   gsettings set org.gnome.desktop.interface …
#       home-manager writes these dconf keys itself, and reasserts them on
#       every rebuild and at login. Leaving both in place is the conflict
#       theme.nix warned about — whichever ran last would win.
#
# What is left is the part home-manager does NOT do:
#
#   - GTK_THEME in the systemd user environment, so user services started
#     outside the login shell still get the theme.
#   - Restarting the GTK portal, which caches the theme at startup and will
#     otherwise keep serving the old one to Flatpak/portal clients.

# READ from what home-manager actually wrote, not spelled out here. This was
# `catppuccin-mocha-mauve-standard` as a literal, which made it one more place a
# scheme change had to be remembered — and it exports GTK_THEME, so a stale name
# here would override the correct settings.ini for every user service started
# afterwards. The settings.ini is generated from the theme file, so reading it
# back is the same value by construction.
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"
GTK_THEME_NAME=$(sed -n 's/^gtk-theme-name=//p' "$SETTINGS" | head -1)

# The floor. An empty name would export GTK_THEME= and drop every portal client
# to Adwaita, which looks like a theme someone chose.
if [ -z "$GTK_THEME_NAME" ]; then
	echo "gtk-apply: no gtk-theme-name in $SETTINGS — refusing to export an empty theme" >&2
	exit 1
fi

systemctl --user set-environment GTK_THEME="$GTK_THEME_NAME"
systemctl --user restart xdg-desktop-portal-gtk
