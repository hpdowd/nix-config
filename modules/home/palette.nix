# Catppuccin Mocha — the one palette.
#
# Bare hex, no leading `#`: every consumer spells it differently (kitty wants
# `#rrggbb`, foot wants bare, GTK CSS wants `#`, mango wants `0xrrggbbaa`), so
# the shared form is the one they all build from rather than one of them.
#
# This existed three times before 2026-08-14 — a `let` binding in programs.nix
# for the terminals, `dotfiles/mango/waybar/colors.css` for the bar, and a
# fourth copy was about to go into rofi's theme. Nothing kept them in step, and
# a palette that has drifted looks deliberate: you cannot tell a considered
# accent from a typo by looking at it.
#
# The KEY NAMES are gruvbox's and are deliberately unchanged — twelve consumers
# and `checks/static.sh` address colours by these names, so renaming them is a
# separate change from recolouring them. Where a name no longer describes its
# value (`yellow` is Mocha's yellow, but `magenta` is Mocha's *pink* and `cyan`
# is its *teal*), the Catppuccin name is given in the comment.
#
# `rec` so the semantic names below are defined in terms of the canonical ones
# rather than repeating the hex. Missing a key is an eval error.
rec {
  # --- Canonical names ------------------------------------------------------
  # Mocha's monochromatic ramp: base → surface0/1/2 for backgrounds, subtext0 →
  # text → rosewater for foregrounds.
  bg0 = "1e1e2e"; # base
  bg1 = "313244"; # surface0
  bg2 = "45475a"; # surface1
  bg3 = "585b70"; # surface2
  fg0 = "f5e0dc"; # rosewater — the brightest foreground
  fg1 = "cdd6f4"; # text
  fg4 = "a6adc8"; # subtext0 — dimmed / inactive

  # One step DARKER than `bg0`, which the ramp above has no name for: `bg0` is
  # the darkest of it. Discord's theme needs a recessed tone for pressed
  # controls, and inventing one would put a colour on screen that Mocha does
  # not contain. Mocha's own name for it, so it is a lookup and not a choice.
  mantle = "181825";

  # Mocha's primary. Not one of the sixteen, so it is named here: it is the
  # accent, and it is what noctalia resolves as `mPrimary` for the same scheme,
  # which is what keeps the bar and the shell agreeing.
  mauve = "cba6f7";

  black = "45475a"; # surface1
  red = "f38ba8";
  green = "a6e3a1";
  yellow = "f9e2af";
  blue = "89b4fa";
  magenta = "f5c2e7"; # pink
  cyan = "94e2d5"; # teal
  white = "a6adc8"; # subtext0

  # Catppuccin has no bright axis: it is a pastel scheme whose accents are
  # already at full strength, and every upstream Catppuccin terminal theme ships
  # `bright` equal to `normal` for the six chromatic slots. Reproduced here
  # rather than inventing six lighter values, which would be this repo's hex and
  # not Catppuccin's. Only the two achromatic slots differ, where Mocha does
  # have somewhere brighter to go.
  brBlack = "7f849c"; # overlay1 — lighter than bg3, so it reads as a colour
  brRed = red;
  brGreen = green;
  brYellow = yellow;
  brBlue = blue;
  brMagenta = magenta;
  brCyan = cyan;
  brWhite = "bac2de"; # subtext1

  # --- Semantic roles -------------------------------------------------------
  # What a UI surface asks for. The bar, the menus and the compositor borders
  # all speak in these; only the terminals want the 16-colour set above.
  base = bg0; # window background
  surface = bg1; # raised background, mango's unfocused border
  overlay = bg2; # hairlines, selection background, mango's focused-window fill
  text = fg1;
  subtext = fg4; # dimmed / inactive text
  accent = mauve; # the single accent — selection, active workspace, prompt

  # Under gruvbox these were the BRIGHT variants, because the normal ones were
  # too dark to sit on `base`. Mocha's accents clear 7:1 against `base` on their
  # own (text 11.3, green 11.0, red 7.1), so they are the normal ones and the
  # `br*` aliases above would be the same values anyway.
  okColor = green;
  warnColor = yellow;
  errColor = red;
  infoColor = blue;

  # --- Terminal aliases -----------------------------------------------------
  # kitty and foot named these before the semantic set existed.
  bg = bg0;
  fg = fg1;
  selBg = bg2;

  # --- Muted set (ncspot) ----------------------------------------------------
  # ncspot's theme is a deliberately desaturated variant: a TUI that fills whole
  # rows with its background colours, where the full-strength palette above is
  # loud enough to read as an error state.
  #
  # Under gruvbox these were picked by eye and no formula reproduced them. Mocha
  # is uniform enough that one does: each is blended 18% toward `bg0`, which is
  # what "dimmed but still itself" means on a pastel scheme. Stated so the next
  # scheme change knows whether it can repeat the trick — it can only if the new
  # scheme is likewise even, and should go back to picking by eye if it is not.
  #
  # They live in this file anyway, because the point of it is that **every
  # colour on this machine has one home**. A muted variant kept next to its one
  # consumer is exactly how the palette came to exist in three places before
  # 2026-08-14: it looks local right up until someone changes the scheme and
  # finds this set still wearing the old one.
  muted = {
    bg = bg0; # ncspot's `background` — the one value shared with the main set
    fg = "aeb5d0"; # dimmed text, used for every foreground role
    dim = "6e7288"; # secondary text
    accent = "ac8ed3"; # dimmed mauve — titles, progress, search matches
    ok = "8ec08c"; # dimmed green — the playing track
    err = "cd7792"; # dimmed red — error background
    surface = "262637"; # raised background: status bar, cmdline, playing row
    overlay = "2d2e40"; # borders, highlight, progress trough
  };
}
