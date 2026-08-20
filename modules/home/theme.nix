# Global GTK and Qt theming, following the selected scheme.
#
# EVERY NAME AND PACKAGE HERE COMES FROM THE THEME FILE. This module used to
# spell out `catppuccin-mocha-mauve-standard` and friends, which made it the one
# place a scheme change had to be remembered rather than declared — and a GTK
# theme name matching nothing falls back to Adwaita silently, so forgetting
# looked like a theme someone chose. `modules/home/themes/*.nix` names them now
# and `pkgs/default.nix` resolves them; docs/adr/0032.
#
# `themeGtk` and friends are `null` when the scheme's name is a toolkit built-in
# (Adwaita-dark, KvArcDark) — home-manager takes `package = null` to mean "the
# theme is already installed", which is exactly true for those.
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

let
  p = import ./palette.nix;
in
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
      # The name is the package's own directory name, not a label — read off the
      # built package, never constructed from the arguments. A name matching
      # nothing drops to Adwaita.
      name = p.packages.gtk.name;
      package = pkgs.themeGtk;
    };
    iconTheme = {
      name = p.packages.icons.name;
      package = pkgs.themeIcons;
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

      # `dark`, not the `2` home-manager derives from `colorScheme` above:
      # GTK reads this enum from settings.ini by NICK, and the integer makes
      # GTK 4.22 log `has a value that cannot be interpreted` and skip the key.
      # `extraConfig` merges last in home-manager's gtk4 module, so this wins.
      # The effective scheme is dark either way — the xdg-desktop-portal
      # `org.freedesktop.appearance` value overrides settings.ini — so this is
      # noise removal, not a visual change. Upstream writes 2 deliberately
      # (modules/misc/gtk/lib.nix); drop this when that is fixed.
      extraConfig = {
        gtk-application-prefer-dark-theme = 1;
        gtk-decoration-layout = ":";
        gtk-interface-color-scheme = "dark";
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
    # rather than by taking the palette. The attribute and the theme directory
    # it installs are spelled differently — `mochaMauve` against
    # `catppuccin-mocha-mauve-cursors`, and `capitaine-cursors-themed` against
    # `Capitaine Cursors (Gruvbox)`, spaces and parentheses included.
    name = p.packages.cursor.name;
    package = pkgs.themeCursor;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # home-manager's own `onChange` for this file guards on `[[ -v DISPLAY ]]` and
  # then runs `xrdb -merge`. SET is not the same as REACHABLE: on a Wayland
  # session DISPLAY can name a socket that is not there, the guard passes, xrdb
  # exits 1, and — because the activation script runs under `set -e` — the whole
  # generation fails. `nixos-rebuild` then reports exit 4 with the switch
  # already applied, which reads as a broken system rather than a failed
  # cosmetic reload.
  #
  # This file carries `Xcursor.theme`, so every scheme change rewrites it and
  # fires the hook (docs/adr/0041 made that routine). Nothing in this session
  # loads .Xresources anyway — `xsession.profileExtra` does not run here — so
  # the merge is best-effort by definition and must not be able to abort
  # anything. docs/gotchas.md → Theming.
  # Keyed by `config.xresources.path`, which is an ABSOLUTE path and not
  # `.Xresources` — home-manager's own module writes `home.file.${cfg.path}`,
  # and a relative key here defines a second, sourceless file entry instead of
  # overriding that one. The failure is an eval error naming `.source`.
  home.file.${config.xresources.path}.onChange = lib.mkForce ''
    if [[ -v DISPLAY ]]; then
      ${lib.getExe pkgs.xrdb} -merge ${config.xresources.path} || true
    fi
  '';

  # Kvantum's config is owned by dotfiles.nix — two modules cannot both own the
  # path.
}
