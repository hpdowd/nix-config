# Gruvbox Dark, medium contrast — the one palette.
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
# `rec` so the semantic names below are defined in terms of the canonical ones
# rather than repeating the hex. Missing a key is an eval error.
rec {
  # --- Canonical gruvbox names ----------------------------------------------
  bg0 = "282828";
  bg1 = "3c3836";
  bg2 = "504945";
  bg3 = "665c54";
  fg0 = "fbf1c7";
  fg1 = "ebdbb2";
  fg4 = "a89984";

  black = "282828";
  red = "cc241d";
  green = "98971a";
  yellow = "d79921";
  blue = "458588";
  magenta = "b16286";
  cyan = "689d6a";
  white = "a89984";

  brBlack = "928374";
  brRed = "fb4934";
  brGreen = "b8bb26";
  brYellow = "fabd2f";
  brBlue = "83a598";
  brMagenta = "d3869b";
  brCyan = "8ec07c";
  brWhite = "ebdbb2";

  # --- Semantic roles -------------------------------------------------------
  # What a UI surface asks for. The bar, the menus and the compositor borders
  # all speak in these; only the terminals want the 16-colour set above.
  #
  # Note which yellow is which: `accent` is the NORMAL yellow (d79921, also
  # mango's focuscolor), while the status colour `yellow` below is the BRIGHT
  # one. The bar has always used them that way; naming them apart is what stops
  # the next edit from collapsing the two.
  base = bg0; # window background
  surface = bg1; # raised background, mango's unfocused border
  overlay = bg2; # hairlines, selection background, mango's focused-window fill
  text = fg1;
  subtext = fg4; # dimmed / inactive text
  accent = yellow; # the single accent — selection, active workspace, prompt

  # Status colours are the BRIGHT variants; they sit on `base` and need the
  # contrast.
  okColor = brGreen;
  warnColor = brYellow;
  errColor = brRed;
  infoColor = brBlue;

  # --- Terminal aliases -----------------------------------------------------
  # kitty and foot named these before the semantic set existed.
  bg = bg0;
  fg = fg1;
  selBg = bg2;
}
