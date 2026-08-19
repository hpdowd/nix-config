# The colour scheme each desktop mode wears — the COLOUR-ONLY half of theming.
#
# `./scheme.nix` names the ARTEFACT scheme: GTK and Kvantum widget art, the icon
# set, cursor bitmaps, the yazi flavor, the nvim plugin and the Zed theme. Those
# are rendered SVG, compiled SCSS and plugin code — built, not coloured — so
# they cannot follow a mode switch, and there is one of them for the machine.
#
# This file names the other half, per mode: colour, where colour is the WHOLE of
# a consumer's theme. docs/adr/0034 is the decision and the scope line.
#
# WHAT FOLLOWS THIS FILE TODAY
#   mango chrome   universal/colors-<mode>.conf, generated per mode
#   noctalia       colorSchemes.predefinedScheme in settings-pinned.json.
#                  noctalia runs in exactly ONE mode, so it needs no runtime
#                  swap — only the right name at build time. Left on scheme.nix
#                  it would contradict the mango chrome drawn around it, which
#                  is the one arrangement worse than either scheme alone.
#   kitty, foot,   ./mode-theme.nix generates one sidecar per mode for each,
#   rofi, ncspot   reached through a runtime symlink `apply_theme()` in
#                  dotfiles/mango/scripts/lib.sh re-points on every switch.
#                  These four run in EVERY mode and read one fixed path, which
#                  is why they need the indirection and mango does not.
#   Equibop        ./dotfiles.nix generates <mode>.theme.css, and apply_theme
#                  writes the NAME into Equibop's own settings.json. Per mode
#                  like the four above, but with no link: the indirection it
#                  needed already existed.
#
# WHAT DOES NOT
#   waybar and swaync do not run in noctalia mode, so they follow whatever
#   `tiling` and `hud` agree on. checks/static.sh asserts those two DO agree:
#   if they ever need to differ, they join the swap first.
#
# A FILE rather than a home-manager option, for ./scheme.nix's reason applied
# one layer along: each value is interpolated into `import ./themes/<name>.nix`,
# so a typo is a file-not-found at EVAL. An option typed `str` would accept
# "gruvbxo" and leave the failure to whichever consumer read it first.
#
# Every key here must be a mode in `MODES` in
# dotfiles/mango/scripts/desktop-mode.sh, and every mode there must be a key
# here — asserted both ways by checks/static.sh. A mode with no entry is an eval
# error; a key naming no mode is a scheme nothing can select.
{
  tiling = "gruvbox";
  hud = "gruvbox";
  noctalia = "nord";
}
