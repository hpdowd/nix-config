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
# OWNERSHIP — decided 2026-07-28, option (a): the mode scripts own the GTK
# theme, Nix does not.
#
# `mango/scripts/system/gtk-apply.sh` sets org.gnome.desktop.interface
# gtk-theme/icon-theme/cursor-theme/font-name/color-scheme via `gsettings` at
# runtime. home-manager's `gtk` module writes those same dconf keys. Both
# writes succeed (dconf stays writable), but home-manager reasserts its values
# on every `nixos-rebuild switch` and at login — so with a `gtk` block declared
# here, a mode switch's theme change silently reverts.
#
# The `gtk` block is therefore deliberately absent. Mode switching is the point
# of this setup, so the script wins. What stays declared in Nix is the part the
# scripts never touch: the theme *packages* (in modules/system/desktop.nix, so
# the names gtk-apply.sh sets actually resolve), the Qt platform theme, and the
# cursor.
#
# If you ever want Nix to own it instead — option (b) — add a `gtk` block back
# here AND strip the gsettings lines out of gtk-apply.sh. Do not do one without
# the other; that is the state this file used to be in.
{ config, pkgs, lib, ... }:

{
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";
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
