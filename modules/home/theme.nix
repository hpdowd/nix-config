# Catppuccin Mocha baseline — global GTK and Qt theming.
#
# NIX OWNS THE GTK THEME, not the mode scripts. The per-mode GTK machinery
# selected nothing (both modes called `gtk-apply.sh tiling`, and the `-tiling`
# variants were byte-identical to their targets), so there is no mode switch for
# Nix to fight. gtk-apply.sh keeps only the GTK_THEME export and the portal
# restart, which home-manager does not do. Never have both set the theme —
# docs/adr/0004.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";
  };

  # Writes both settings.ini files and the matching
  # org.gnome.desktop.interface dconf keys. The cursor is set via
  # `home.pointerCursor` below — this home-manager version has no
  # `gtk.cursorTheme`.
  gtk = {
    enable = true;

    theme = {
      # The name is the package's own directory name, not a label — see the
      # note in pkgs/default.nix. A name matching nothing drops to Adwaita.
      name = "catppuccin-mocha-mauve-standard";
      package = pkgs.catppuccin-gtk;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    font = {
      name = "Hack Nerd Font";
      size = 10;
    };
    colorScheme = "dark";

    gtk3 = {
      # `gtk-decoration-layout=:` means no titlebar buttons — mango draws its
      # own decorations, so client-side ones would be duplicates.
      extraConfig = {
        gtk-application-prefer-dark-theme = 1;
        gtk-decoration-layout = ":";
        gtk-toolbar-style = "GTK_TOOLBAR_ICONS";
        gtk-toolbar-icon-size = "GTK_ICON_SIZE_LARGE_TOOLBAR";
        gtk-button-images = 0;
        gtk-menu-images = 0;
        gtk-enable-event-sounds = 1;
        gtk-enable-input-feedback-sounds = 0;
        gtk-xft-antialias = 1;
        gtk-xft-hinting = 1;
        gtk-xft-hintstyle = "hintslight";
        gtk-xft-rgba = "rgb";
      };
      extraCss = ''
        * {
          border-radius: 0;
        }
      '';
      # Thunar's sidebar. Previously a hand-edited gtk-3.0/bookmarks file.
      bookmarks = [
        "file:///home/henry/Projects/homelab"
        "file:///home/henry/Projects"
        "file:///home/henry/Downloads"
        "file:///home/henry/Pictures"
        "file:///home/henry/temp"
      ];
    };

    gtk4 = {
      # Pinned to the legacy default, which home-manager warns about below
      # stateVersion 26.05. Setting it to `null` adopts the new behaviour and
      # drops GTK4/libadwaita apps back to Adwaita — a visual change, so do it
      # deliberately rather than to quieten the warning.
      theme = config.gtk.theme;

      extraConfig = {
        gtk-application-prefer-dark-theme = 1;
        gtk-decoration-layout = ":";
      };
      extraCss = ''
        * {
          border-radius: 0;
        }
      '';
    };
  };

  # Set at the home level so it reaches Wayland clients via XCURSOR_THEME and
  # ~/.icons/default/index.theme.
  #
  # `gtk.enable` was false while the gtk block above was disabled, which left
  # gtk-cursor-theme-name out of settings.ini once GTK moved into Nix. On now,
  # so GTK apps get the cursor declared here rather than inheriting it.
  home.pointerCursor = {
    enable = true;
    # Rendered bitmaps, so this follows the scheme by being a different package
    # rather than by taking the palette. `mochaMauve` is the attribute; the
    # theme directory it installs is what this name must match, and the two are
    # spelled differently.
    name = "catppuccin-mocha-mauve-cursors";
    package = pkgs.catppuccin-cursors.mochaMauve;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # Kvantum's config is owned by dotfiles.nix — two modules cannot both own the
  # path.
}
