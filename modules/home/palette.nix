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

  # --- Muted set (ncspot) ----------------------------------------------------
  # ncspot's theme is a deliberately desaturated gruvbox: a TUI that fills whole
  # rows with its background colours, where the full-strength palette above is
  # loud enough to read as an error state. These are NOT derived from the values
  # above and no formula reproduces them — ebdbb2 → c9b890 is not a uniform
  # scale — so they are named here as their own values rather than computed.
  #
  # They live in this file anyway, because the point of it is that **every
  # colour on this machine has one home**. A muted variant kept next to its one
  # consumer is exactly how the palette came to exist in three places before
  # 2026-08-14: it looks local right up until someone changes the scheme and
  # finds this set still gruvbox.
  muted = {
    bg = bg0; # ncspot's `background` — the one value shared with the main set
    fg = "c9b890"; # dimmed fg1, used for every foreground role
    dim = "7a6a50"; # secondary text
    accent = "d4a039"; # dimmed accent — titles, progress, search matches
    ok = "89aa61"; # dimmed brGreen — the playing track
    err = "ad401f"; # dimmed red — error background
    surface = "2e2720"; # raised background: status bar, cmdline, playing row
    overlay = "3d352c"; # borders, highlight, progress trough
  };
}
