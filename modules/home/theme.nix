# Gruvbox Dark baseline (CLAUDE.md).
#
# Caveat worth reading before you enable this: the Mangowm mode scripts rewrite
# some files at runtime, and anything home-manager manages declaratively becomes
# a read-only store symlink, so those writes fail with EACCES.
#
# As of 2026-07-30 that list is shorter than it was. `active-theme.conf` /
# `active-theme.ini` are gone (dead indirection — both modes chose the same
# theme), and runtime state moved to ~/.local/state/mango. What still writes
# into a config directory: `mango/config.conf` (the mode dispatch file) and the
# jq patch of Equibop's settings.json — and Equibop is not linked here anyway.
#
# So: GTK/Qt *global* theming is declared here, while per-app theme files stay
# out-of-store symlinks in dotfiles.nix.
#
# OWNERSHIP — switched to option (b) on 2026-07-30: Nix owns the GTK theme.
#
# The old decision (option (a), 2026-07-28) gave it to `gtk-apply.sh`, on the
# grounds that home-manager reasserts its dconf values on every rebuild and at
# login, so a Nix-declared theme would silently revert whatever a mode switch
# had set. That reasoning was sound but rested on a premise that turned out to
# be false: **GTK theming is not mode-dependent here, and never was.**
#
# Three things were checked before flipping it:
#   - `gtk-apply.sh` takes a $MODE argument and then ignores it — it copies the
#     `-tiling` variants unconditionally.
#   - Both `tiling/autostart.conf` and `hud/autostart.conf` call it as
#     `gtk-apply.sh tiling`. Even hud asks for tiling.
#   - `settings-tiling.ini` and `gtk-tiling.css` were byte-identical to the
#     `settings.ini` / `gtk.css` they were copied over.
#
# So the per-mode GTK machinery selected nothing, exactly like the
# `active-theme.*` indirection removed the same day (docs/adr/0004). There is
# no mode switch for Nix to fight.
#
# Per the rule this file already stated, the gsettings and cp lines were
# stripped from `gtk-apply.sh` in the same change — never one without the
# other. What is left of that script is the GTK_THEME environment variable for
# systemd user services and the portal restart, which home-manager does not do.
{ config, pkgs, lib, ... }:

{
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";
  };

  # GTK. Replaces the hand-maintained settings.ini files and the `gsettings`
  # block in gtk-apply.sh — home-manager writes both the ini files and the
  # matching org.gnome.desktop.interface dconf keys, which is strictly more
  # than the script did by hand.
  #
  # Values transcribed from the old home/gtk-3.0/settings.ini so nothing
  # changes visually. The cursor stays on `home.pointerCursor` below: this
  # home-manager version has no `gtk.cursorTheme`, and pointerCursor already
  # propagates to GTK.
  gtk = {
    enable = true;

    theme = {
      name = "Gruvbox-Yellow-Dark";
      package = pkgs.gruvbox-gtk-theme;
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
      # home-manager changed this default from `config.gtk.theme` to `null`,
      # gated on home.stateVersion >= "26.05". Ours is 25.11, so we get the
      # legacy behaviour plus a warning on every rebuild. Set explicitly to the
      # legacy value: it is what the machine is running today and what was
      # eyeballed as correct, so silencing the warning must not change how
      # anything looks. `gruvbox-gtk-theme` does ship gtk-4.0 assets, so this
      # is meaningful rather than inert.
      #
      # To adopt the new default later, set this to `null` — GTK4/libadwaita
      # apps then fall back to Adwaita instead of following the GTK3 theme.
      # That is a visual change; make it deliberately, not to quieten a log.
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

  # Cursor — set at the home level so it propagates to Wayland clients via
  # XCURSOR_THEME / XCURSOR_SIZE and ~/.icons/default/index.theme.
  #
  # This used to say Adwaita, which contradicted the repo's own config:
  # gtk-3.0/settings.ini asks for `Capitaine Cursors (Gruvbox)` at size 24.
  # With the `gtk` block gone (see the header), settings.ini is the source of
  # truth for GTK apps, so declaring Adwaita here would have produced a split —
  # Capitaine in GTK apps, Adwaita everywhere else. Matched to settings.ini.
  #
  # `capitaine-cursors-themed` provides the theme under exactly that name,
  # confirmed by building it and listing share/icons.
  #
  # gtk.enable is off because the `gtk` module is disabled; leaving it on would
  # be inert at best and, if the module were ever re-enabled, would collide
  # with the out-of-store gtk-3.0 symlink from dotfiles.nix.
  home.pointerCursor = {
    enable = true; # now required explicitly
    name = "Capitaine Cursors (Gruvbox)";
    package = pkgs.capitaine-cursors-themed;
    size = 24;
    gtk.enable = false;
    x11.enable = true;
  };

  # Kvantum's own config (~/.config/Kvantum) is symlinked live in dotfiles.nix
  # rather than declared here — declaring it too would be a collision, since
  # two modules can't both own the same path. The gruvbox Kvantum theme comes
  # from the AUR (kvantum-theme-gruvbox-git); if nixpkgs doesn't carry it,
  # copy the theme directory into ~/.config/Kvantum by hand — it's just
  # .kvconfig + .svg files and needs no packaging.
}
