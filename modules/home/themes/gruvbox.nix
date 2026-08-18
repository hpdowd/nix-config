# Gruvbox Dark, medium contrast — upstream's values, unmodified.
#
# Selected by `modules/home/scheme.nix`. See modules/home/palette.nix for how
# these files are chosen and what the shared key names mean.
#
# This is the scheme this machine wore until 2026-08-18, recovered from commit
# c0407a9 rather than retyped. Three things had to be added to it, because the
# interface grew after it was retired: `mantle` (Equibop's recessed background),
# the two floors, and the `packages`/`apps` blocks. Two values in the muted set
# also changed — see there; they predate the contrast check and would not pass
# it.
#
# GRUVBOX IS THE REASON THE ANSI FLOOR IS SEPARATE. Its normal red is 2.69:1 on
# `bg0` — dimmer than any other colour on this machine, and that is upstream's
# deliberate design, not a mistake to correct. Under one combined floor the
# whole theme would have had to declare 2.6, which would have let `comment`
# quietly rot to the same place. docs/adr/0032.
rec {
  # --- Legibility, asserted by checks/static.sh -----------------------------
  # What this machine's own UI draws text with. 4.02 is `brBlack`/`comment`,
  # gruvbox's grey — below WCAG AA, and authentic. There is no
  # `gruvbox-high-contrast` sibling; `mocha-high-contrast` is the worked example
  # if one is ever wanted.
  contrastFloor = 4.0;
  # The sixteen terminal slots — what OTHER programs print with. 2.69 is the
  # normal red (#cc241d), which gruvbox has shipped since 2012.
  ansiFloor = 2.6;

  # --- Canonical gruvbox names ----------------------------------------------
  bg0 = "282828";
  bg1 = "3c3836";
  bg2 = "504945";
  bg3 = "665c54";
  fg0 = "fbf1c7";
  fg1 = "ebdbb2";
  fg4 = "a89984";

  # One step darker than `bg0`, for Equibop's pressed controls. Gruvbox's own
  # `dark0_hard`, so it is a lookup and not an invention — the same standard
  # `mantle` is held to in the Catppuccin themes.
  mantle = "1d2021";

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
  base = bg0; # window background
  surface = bg1; # raised background, mango's unfocused border
  overlay = bg2; # hairlines, selection background, mango's focused-window fill
  text = fg1;
  subtext = fg4; # dimmed / inactive text
  # The dimmest colour that is still TEXT. Gruvbox's grey, 4.02:1 — the value
  # this theme's floor is set by. Spelled out rather than aliased to `brBlack`
  # so the two can move apart without one silently following the other.
  comment = "928374";
  # NOTE WHICH YELLOW. The accent is the NORMAL yellow, which is also mango's
  # focuscolor; the status colour `warnColor` below is the BRIGHT one. The bar
  # has always used them that way, and naming them apart is what stops the next
  # edit from collapsing the two.
  accent = "d79921";

  # The BRIGHT variants, because gruvbox's normal ones are too dark to sit on
  # `base` — this is the split the ANSI floor above exists to keep honest.
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
  # A deliberately desaturated gruvbox: a TUI that fills whole rows with its
  # background colours, where the full-strength palette above is loud enough to
  # read as an error state. NO FORMULA REPRODUCES THESE — `ebdbb2` → `c9b890` is
  # not a uniform scale — so unlike Mocha's they are named values. That was true
  # in 2026-08 and it is still true; the migration runbook's "check which case
  # you are in" step lands on "by eye" for this scheme.
  #
  # Six of the eight are the 2026-08 values verbatim. Two are not, and both were
  # below 3:1 where they are actually drawn:
  muted = {
    bg = bg0; # ncspot's `background` — the one value shared with the main set
    fg = "c9b890"; # 7.53:1 on surface
    # Was #7a6a50 — 2.81:1 on `surface`, under any floor this theme could
    # declare. Re-derived from `fg4` rather than lifted by eye: 5.09:1.
    dim = "a49681"; # secondary text
    accent = "d4a039"; # dimmed accent — titles, progress, search matches — 6.23:1
    ok = "89aa61"; # dimmed brGreen — the playing track — 5.60:1
    # A BACKGROUND, not text: ncspot draws `error_fg` (= `fg` above) on it. Was
    # #ad401f, which put `fg` at 3.04:1. Darkened until `fg` clears this theme's
    # floor: 4.24:1. Every scheme here made the same mistake and it is the same
    # fix — docs/adr/0032.
    err = "83362d";
    surface = "2e2720"; # raised background: status bar, cmdline, playing row
    overlay = "3d352c"; # borders, highlight, progress trough
  };

  # --- Artefacts the palette cannot colour ----------------------------------
  # All five native — the bar every shipped scheme has to clear. `name` is read
  # off the built package; note that none of the five is guessable from the
  # attribute that builds it.
  #
  # NOT what this scheme used before 2026-08-18, which is worth knowing if you
  # are comparing against git history: the GTK theme was VENDORED in the overlay
  # (nixpkgs had dropped `gruvbox-gtk-theme`), Kvantum was a lone hand-carried
  # `.kvconfig`, the yazi flavor was 916 vendored lines under `dotfiles/`, and
  # the icons were Papirus recoloured yellow rather than a Gruvbox icon set.
  # Only the cursor is the same package it always was. Nothing here is vendored.
  packages = {
    gtk = {
      attr = "gruvbox-dark-gtk";
      name = "gruvbox-dark";
      native = true;
    };
    kvantum = {
      attr = "gruvbox-kvantum";
      name = "Gruvbox-Dark-Brown";
      native = true;
    };
    icons = {
      attr = "gruvbox-plus-icons";
      name = "Gruvbox-Plus-Dark";
      native = true;
    };
    cursor = {
      attr = "capitaine-cursors-themed";
      # Spaces and parentheses in a theme directory name. Read off the package;
      # constructing it from the attribute would produce none of these.
      name = "Capitaine Cursors (Gruvbox)";
      native = true;
    };
    yazi = {
      owner = "bennyyip";
      repo = "gruvbox-dark.yazi";
      rev = "619fdc5844db0c04f6115a62cf218e707de2821e";
      hash = "sha256-Y/i+eS04T2+Sg/Z7/CGbuQHo5jxewXIgORTQm25uQb4=";
      # This repo IS a `.yazi` package, so its flavor.toml is at the root —
      # unlike catppuccin/yazi, which ships bare per-accent TOMLs in a tree.
      file = "flavor.toml";
      native = true;
    };
  };

  # --- Applications that hold a theme NAME ----------------------------------
  apps = {
    noctalia = "Gruvbox";

    # The plugin IS the scheme, so `palette` is empty and nvim takes upstream's
    # values. Overriding 20 keys of gruvbox.nvim with values from this file
    # would leave 34 of its own behind — that is the hybrid THEME-MIGRATION §3
    # was written about, and it is the reason the plugin is swapped rather than
    # recoloured.
    nvim = {
      spec = "ellisonleao/gruvbox.nvim";
      name = "gruvbox";
      # lualine's own built-in, not the plugin's. `auto` would also work; this
      # is named because lualine genuinely ships it.
      lualine = "gruvbox";
      setup = ''
        require("gruvbox").setup({
          terminal_colors = true,
          transparent_mode = true,
          contrast = "",
          italic = { strings = false, comments = true },
        })
      '';
      palette = { };
    };

    # Gruvbox ships INSIDE Zed, so no extension is needed — the inverse of
    # Catppuccin. An empty list here is a statement, not an oversight.
    zed = {
      extensions = [ ];
      dark = "Gruvbox Dark";
      light = "Gruvbox Light";
    };
  };
}
