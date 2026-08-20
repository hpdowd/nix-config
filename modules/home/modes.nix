# The scheme each desktop mode wears — the COLOUR-ONLY half. docs/adr/0034.
#
# ./scheme.nix names the ARTEFACT scheme (widget art, icons, cursor, yazi,
# nvim, Zed). Those are built, so they cannot follow a mode switch; there is
# one set for the machine. This file is the half that can follow one, where
# colour is the WHOLE of a consumer's theme.
#
# FOLLOWS THIS FILE   mango's chrome and noctalia's predefinedScheme, both at
#                     build time; kitty, foot, rofi and ncspot through a
#                     runtime symlink, and Equibop through a filename, both
#                     re-pointed by apply_theme() — see ./mode-theme.nix.
# DOES NOT            waybar and swaync, which noctalia does not run and which
#                     are generated once from ./scheme.nix. checks/static.sh
#                     asserts every mode that DOES run them wears that scheme.
#
# A FILE, not an option, for ./scheme.nix's reason: each value is interpolated
# into `import ./themes/<name>.nix`, so a typo is a file-not-found at EVAL.
#
# Every key must be a mode in MODES in dotfiles/mango/scripts/desktop-mode.sh,
# and every mode there a key here — asserted both ways.
{
  tiling = "gruvbox";
  noctalia = "nord";
}
