# Gruvbox Dark baseline (CLAUDE.md).
#
# Caveat worth reading before you enable this: your Mangowm mode scripts
# actively rewrite theme files at runtime (symlinking active-theme.conf,
# jq-patching Equibop's settings.json). Anything home-manager manages
# declaratively becomes a read-only store symlink and those scripts will fail
# with EACCES.
#
# So: GTK/Qt *global* theming is declared here, while per-app theme files stay
# out-of-store symlinks in dotfiles.nix.
#
# KNOWN INTERACTION — read before your first mode switch:
# `mango/scripts/system/gtk-apply.sh` sets org.gnome.desktop.interface
# gtk-theme/icon-theme/cursor-theme/font-name/color-scheme via `gsettings` at
# runtime. home-manager's `gtk` module writes those same dconf keys. Both
# writes succeed (dconf stays writable), but home-manager reasserts its values
# on every `nixos-rebuild switch` and at login, so a mode switch's theme change
# will silently revert.
#
# Pick one owner:
#   (a) let the script own it  — delete the `gtk` block below, keep only
#       fonts/cursor here. Simplest, and preserves your mode-switching.
#   (b) let Nix own it         — keep this block, strip the gsettings lines
#       out of gtk-apply.sh, and switch themes by rebuilding.
# (a) is recommended: your modes are the whole point of the setup.
{ config, pkgs, lib, ... }:

{
  gtk = {
    enable = true;

    theme = {
      name = "Gruvbox-Dark";
      package = pkgs.gruvbox-gtk-theme;
    };

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };

    font = {
      name = "IBM Plex Sans";
      size = 11;
    };

    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };

    # The gtk4 default changed to `null` in home-manager; this keeps the old
    # behaviour of applying the same theme to GTK4 apps.
    gtk4.theme = config.gtk.theme;
  };

  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";
  };

  # Cursor — set at the home level so it propagates to both GTK and Wayland
  # clients (XCURSOR_THEME / XCURSOR_SIZE).
  home.pointerCursor = {
    enable = true; # now required explicitly
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # Kvantum's own config (~/.config/Kvantum) is symlinked live in dotfiles.nix
  # rather than declared here — declaring it too would be a collision, since
  # two modules can't both own the same path. The gruvbox Kvantum theme comes
  # from the AUR (kvantum-theme-gruvbox-git); if nixpkgs doesn't carry it,
  # copy the theme directory into ~/.config/Kvantum by hand — it's just
  # .kvconfig + .svg files and needs no packaging.
}
