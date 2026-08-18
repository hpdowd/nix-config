# Catppuccin Mocha, grey ramp lifted to WCAG AAA.
#
# Selected by `modules/home/scheme.nix`. Mocha's hues, on Mocha's own `crust`
# as the background, with every text-bearing colour at 7:1 or better against
# what it sits on.
#
# WHY THIS EXISTS. Mocha's accents were never the problem — all twelve clear
# AAA on `base` unaided. Its *greys* are. Measured against the running editor
# rather than guessed at: nvim paints Comment with `overlay2` (5.81:1 on Mocha's
# base) and `brBlack`/`overlay1` carries timestamps and inactive labels at
# 4.44:1. Those are the least saturated, most-read colours on the machine, so
# "the text is hard to read" is a precise complaint about them rather than a
# vague one about the scheme.
#
# One thing this theme does NOT fix: nvim's LineNr takes `surface1`, a
# *background* tone used as foreground, and lands near 2:1 here as it does
# upstream. That is Catppuccin's deliberate subtlety, not a palette bug — the
# ramp below is chosen so it is no worse than Mocha's, and making it legible is
# a highlight override rather than a colour.
#
# WHAT CHANGED, and nothing else did:
#   - `bg0` drops from Mocha's `base` to its `crust` (#1e1e2e → #11111b), which
#     buys ~1.14x on everything at once. The old `base` becomes `bg1`, so the
#     background ramp is Mocha's own, shifted one step down.
#   - the greys are lifted until they clear 7:1, by raising HSV value and easing
#     saturation: `brBlack` #7f849c → #999eb7, ncspot's `dim` likewise.
#   - the twelve accents are **byte-identical to Mocha's**. They already passed;
#     changing them would have made this a different scheme rather than a more
#     legible one, and the six theme packages (GTK, Kvantum, cursor, icons,
#     noctalia, yazi) are shared with `mocha` precisely because the hues are.
#
# The numbers are asserted, not asserted-once-and-trusted: `checks/static.sh`
# recomputes every ratio in this file on each `nix flake check`, so a future
# edit that dims a grey fails the build rather than the eye.
rec {
  # WCAG AAA, asserted by checks/static.sh over every text role in this file.
  # This is the number the whole theme exists to hold.
  contrastFloor = 7.0;

  # --- Canonical names ------------------------------------------------------
  bg0 = "11111b"; # crust — the background, one step below Mocha's
  bg1 = "1e1e2e"; # base
  # Mocha's surface1/surface2, NOT its surface0/1. Shifting the whole ramp down
  # with `bg0` was the first attempt and it dropped nvim's LineNr to 1.65:1 —
  # darkening the background while also darkening what is drawn on it. Only
  # `bg0` moves; everything above it stays where Mocha put it.
  bg2 = "45475a"; # surface1
  bg3 = "585b70"; # surface2
  fg0 = "f5e0dc"; # rosewater
  fg1 = "cdd6f4"; # text
  fg4 = "a6adc8"; # subtext0 — 8.42:1 here, where it was 7.37 on Mocha's base

  # Below `bg0`, for Equibop's pressed controls. Mocha's own crust is `bg0`
  # now, so this is darker than anything Catppuccin names.
  mantle = "09090f";

  mauve = "cba6f7";

  black = "313244"; # surface0 — lifted with the rest of the ramp
  red = "f38ba8";
  green = "a6e3a1";
  yellow = "f9e2af";
  blue = "89b4fa";
  magenta = "f5c2e7"; # pink
  cyan = "94e2d5"; # teal
  white = "a6adc8"; # subtext0

  # `brBlack` carries nvim's NonText, Conceal and FoldColumn, swaync's
  # timestamps and every inactive label. Mocha puts it at 4.44:1; here it is
  # 7.08:1, and `comment` below shares the value.
  brBlack = "999eb7";
  brRed = red;
  brGreen = green;
  brYellow = yellow;
  brBlue = blue;
  brMagenta = magenta;
  brCyan = cyan;
  brWhite = "bac2de"; # subtext1

  # --- Semantic roles -------------------------------------------------------
  base = bg0;
  surface = bg1;
  overlay = bg2;
  text = fg1;
  subtext = fg4;
  # The dimmest colour that is still TEXT. 7.08:1 — this is the value the
  # complaint was actually about.
  # Spelled out rather than aliased to `brBlack`: checks/static.sh reads these
  # by regex from this file, and an alias reads as "role absent".
  comment = "999eb7";
  accent = mauve;

  okColor = green;
  warnColor = yellow;
  errColor = red;
  infoColor = blue;

  # --- Terminal aliases -----------------------------------------------------
  bg = bg0;
  fg = fg1;
  selBg = bg2;

  # --- Muted set (ncspot) ----------------------------------------------------
  # Measured against `surface` below, NOT against `bg0`: ncspot fills whole rows
  # with its raised background, so that is the colour its text actually sits on.
  # Checking these against `bg0` would have passed three values that fail where
  # they are used — `err` reads 7.05:1 on `surface` and would have looked fine
  # at 8.6 against the wrong reference.
  muted = {
    bg = bg0;
    fg = "b1b8d3"; # 9.01:1 on surface
    dim = "9ea2ba"; # 7.03:1
    accent = "b595dc"; # 7.01:1
    ok = "90c48d"; # 8.84:1
    err = "e488a3"; # 7.05:1
    surface = "171724"; # raised background: status bar, cmdline, playing row
    overlay = "1b1b2a"; # borders, highlight, progress trough
  };
}
