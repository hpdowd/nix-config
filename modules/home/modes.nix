# The scheme each desktop mode wears — the colour-only half. docs/adr/0034.
#
# ./scheme.nix names the artefact scheme (widget art, icons, cursor, yazi,
# nvim, Zed). Those are built, so they cannot follow a mode switch; there is
# one set for the machine. This file is the half that can follow one, where
# colour is the whole of a consumer's theme.
#
# Follows this file   mango's chrome and noctalia's predefinedScheme, both at
#                     build time; kitty, foot, rofi and ncspot through a
#                     runtime symlink, and Equibop through a filename, both
#                     re-pointed by apply_theme() — see ./mode-theme.nix.
# Does not            waybar and swaync, which noctalia does not run and which
#                     are generated once from ./scheme.nix. checks/static.sh
#                     asserts every mode that does run them wears that scheme.
#
# A file, not an option, for ./scheme.nix's reason: each value is interpolated
# into `import ./themes/<name>.nix`, so a typo is a file-not-found at eval.
#
# Every key must be a mode in modes in dotfiles/mango/scripts/desktop-mode.sh,
# and every mode there a key here — asserted both ways.
{
  tiling = "heartbox";
  noctalia = "heartbox";
}
