# The runtime colour swap — docs/adr/0034 phase 2.
#
# `colors-<mode>.conf` proved the shape for mango: one generated file per mode,
# in the scheme `./modes.nix` gives that mode. mango can use it directly because
# `apply_mode` rewrites `config.conf` on every switch anyway. kitty, foot and
# rofi cannot: they run in EVERY mode and read one fixed path, so they need an
# indirection between the path they read and the file they get.
#
# This file generates the per-mode halves. The links are made at runtime by
# `apply_theme()` in dotfiles/mango/scripts/lib.sh:
#
#   ~/.config/kitty/current-theme.conf  ->  kitty/colors-<mode>.conf
#   ~/.config/foot/themes/noctalia      ->  foot/colors-<mode>
#   ~/.config/rofi/colors.rasi          ->  rofi/colors-<mode>.rasi
#   ~/.config/ncspot/config.toml        ->  ncspot/colors-<mode>.toml
#
# NONE of those four link paths may be an `xdg.configFile` — two owners for one
# path is an activation failure, not a merge. `rofi/colors.rasi` was one until
# this file existed and had to be given up in the same change.
#
# WHY THE GENERATED FILES ARE KEYED BY MODE AND NOT BY SCHEME. The obvious
# spelling is one sidecar per distinct scheme, `kitty/colors-gruvbox.conf`, and
# `apply_theme <scheme>`. That makes the shell learn a scheme name, which means
# the Nix→shell boundary carries a *value* that both sides have to agree on —
# the class of drift `lib.sh` was extracted to stop, and the one that broke the
# mode switch one-way on 2026-07-31. Keyed by mode, the shell already knows the
# only argument there is, and tiling and hud sharing a scheme costs one
# duplicate generated file that nothing reads by hand.
#
# THE ODD NAMES ARE DELIBERATE, and they are the two that let noctalia's own
# auto-theming templates be a later toggle rather than a redesign
# (docs/adr/0034 phase 3):
#
#   current-theme.conf   exactly what noctalia's kitty post-hook `ln -sf`s. That
#                        hook refuses to edit an unwritable kitty.conf, so it
#                        touches only this link — and a mode switch takes it
#                        back.
#   themes/noctalia      even in tiling mode, and even holding gruvbox. Their
#                        foot hook `sed -i`s foot.ini UNLESS it greps
#                        `include.*noctalia` — and foot.ini is a read-only store
#                        symlink, so that sed is the difference between a
#                        no-op and the repo silently ceasing to own the file.
{ lib, ... }:
let
  modes = import ./modes.nix;
  paletteOf = mode: import ./themes/${modes.${mode}}.nix;

  # One entry per mode, for each of the three consumers. `mapAttrs'` over
  # `modes` rather than a hand-written list: a mode added to modes.nix gets its
  # three sidecars with nothing to remember, and a mode removed takes them away
  # — which makes the link dangle, which `apply_theme` refuses to do and the
  # activation script below repairs.
  perMode =
    path: render:
    lib.mapAttrs' (
      mode: _: lib.nameValuePair (path mode) { text = render mode (paletteOf mode); }
    ) modes;

  # The provenance line every generated file opens with. A generated file whose
  # origin is a sentence rather than a name is the one that gets edited by hand.
  from =
    mode: c:
    "${c} GENERATED from modules/home/themes/${modes.${mode}}.nix, for the '${mode}' mode (modules/home/modes.nix). Edit those, then rebuild.";

  # kitty wants a leading `#`, foot and rofi want bare hex. One palette, three
  # spellings — which is exactly why checks/static.sh asserts the accent in each
  # consumer's OWN spelling rather than grepping for one form everywhere.
  hash = c: "#${c}";

  kittyTheme = mode: p: ''
    ${from mode "#"}
    # Included by kitty.conf as `include current-theme.conf`, which is a runtime
    # symlink. kitty re-reads this on SIGUSR1; apply_theme sends it.
    color0  ${hash p.black}
    color1  ${hash p.red}
    color2  ${hash p.green}
    color3  ${hash p.yellow}
    color4  ${hash p.blue}
    color5  ${hash p.magenta}
    color6  ${hash p.cyan}
    color7  ${hash p.white}
    color8  ${hash p.brBlack}
    color9  ${hash p.brRed}
    color10 ${hash p.brGreen}
    color11 ${hash p.brYellow}
    color12 ${hash p.brBlue}
    color13 ${hash p.brMagenta}
    color14 ${hash p.brCyan}
    color15 ${hash p.brWhite}
    background ${hash p.bg}
    foreground ${hash p.fg}
    cursor ${hash p.fg}
    cursor_text_color ${hash p.bg}
    selection_foreground ${hash p.bg}
    selection_background ${hash p.selBg}
    tab_bar_margin_color ${hash p.bg}
    tab_bar_background ${hash p.bg}
    active_tab_foreground ${hash p.bg}
    active_tab_background ${hash p.brMagenta}
    inactive_tab_foreground ${hash p.subtext}
    inactive_tab_background ${hash p.bg}
  '';

  # `[colors-dark]`, carried over from the config this replaces rather than
  # flattened to `[colors]` — that is what the machine runs today and this is a
  # change of ownership, not of appearance.
  #
  # foot's `include` gives the imported file its OWN section scope, so this
  # starting with a section header is correct and does not leak into foot.ini.
  footTheme = mode: p: ''
    ${from mode "#"}
    # Included by foot.ini as `include=~/.config/foot/themes/noctalia`, which is
    # a runtime symlink. foot CANNOT re-read its config — 1.27's SIGUSR1/2 only
    # switch between the sections already loaded — so a swap reaches NEW WINDOWS
    # ONLY. apply_theme says so rather than leaving it looking broken.
    [colors-dark]
    foreground=${p.fg}
    background=${p.bg}
    selection-foreground=${p.fg}
    selection-background=${p.selBg}

    regular0=${p.black}
    regular1=${p.red}
    regular2=${p.green}
    regular3=${p.yellow}
    regular4=${p.blue}
    regular5=${p.magenta}
    regular6=${p.cyan}
    regular7=${p.white}

    bright0=${p.brBlack}
    bright1=${p.brRed}
    bright2=${p.brGreen}
    bright3=${p.brYellow}
    bright4=${p.brBlue}
    bright5=${p.brMagenta}
    bright6=${p.brCyan}
    bright7=${p.brWhite}
  '';

  # The names match waybar/colors.css so the bar and the menus can be reasoned
  # about in one vocabulary — unchanged from the colors.rasi this replaces.
  rofiTheme = mode: p: ''
    /* ${from mode "*"} */
    /* Imported by config.rasi as `@import "colors"`, which resolves
       colors.rasi — a runtime symlink. rofi re-reads on every launch, so this
       one needs no reload at all. */
    * {
        base:    ${hash p.base};
        overlay: ${hash p.overlay};
        text:    ${hash p.text};
        subtext: ${hash p.subtext};
        accent:  ${hash p.accent};
        urgent:  ${hash p.errColor};
    }
  '';
  # ncspot's whole config is its theme — the only thing ever set here — so the
  # per-mode file IS the config and the link is `config.toml` itself. That is
  # only affordable because `programs.ncspot.settings = { }` makes the module
  # write no file at all (it is wrapped in `mkIf (cfg.settings != { })`), so the
  # path stays unclaimed while the module still installs the package. Tier 1
  # keeps the half that matters and gives up only the typing on twenty strings.
  #
  # ANY future non-theme ncspot setting goes in HERE, not in
  # `programs.ncspot.settings` — one value there re-claims `config.toml` and
  # turns every mode switch into an activation conflict.
  #
  # The `muted` set, not the canonical ramp: ncspot fills whole rows with these
  # and the audit in checks/static.sh measures them against each other. See
  # modules/home/palette.nix.
  ncspotTheme =
    mode: p:
    let
      m = p.muted;
    in
    ''
      ${from mode "#"}
      # ncspot reads this ONCE, at startup — there is no reload and no signal,
      # so a mode switch reaches the NEXT ncspot. apply_theme says so rather
      # than leaving it looking broken, exactly as it does for foot.
      [theme]
      background = "${hash m.bg}"
      primary = "${hash m.fg}"
      secondary = "${hash m.dim}"
      title = "${hash m.accent}"
      playing = "${hash m.ok}"
      playing_selected = "${hash m.ok}"
      playing_bg = "${hash m.surface}"
      highlight = "${hash m.overlay}"
      # `highlight_fg` / `error_fg`, not `highlight_bg` / `error`. ncspot ignores
      # keys it does not recognise without complaining, so a renamed key here is
      # a colour that silently reverts to the default.
      highlight_fg = "${hash m.fg}"
      error_bg = "${hash m.err}"
      error_fg = "${hash m.fg}"
      statusbar_progress = "${hash m.accent}"
      statusbar_progress_bg = "${hash m.overlay}"
      statusbar = "${hash m.fg}"
      statusbar_bg = "${hash m.surface}"
      cmdline = "${hash m.fg}"
      cmdline_bg = "${hash m.surface}"
      search_match = "${hash m.accent}"
      border = "${hash m.overlay}"
    '';
in
{
  xdg.configFile =
    (perMode (m: "kitty/colors-${m}.conf") kittyTheme)
    // (perMode (m: "foot/colors-${m}") footTheme)
    // (perMode (m: "rofi/colors-${m}.rasi") rofiTheme)
    // (perMode (m: "ncspot/colors-${m}.toml") ncspotTheme);

  # THE BOOTSTRAP, and it is the one thing standing between this design and a
  # silent failure. All three links are made by `apply_theme`, which runs on a
  # mode SWITCH — so before the first switch on a fresh machine there is no link
  # at all, and rofi's `@import`, kitty's `include` and foot's `include` every
  # one of them fail UNLOGGED. ncspot is the same shape one layer up: no
  # config.toml at all is a valid ncspot, in its own default colours.
  #
  # `[ -e ]` follows symlinks, so this repairs a DANGLING link too, which is the
  # other way to arrive here: dropping a mode from modes.nix deletes the sidecar
  # its link still points at.
  #
  # `mkdir -p` for foot's themes/ only: home-manager creates a config
  # subdirectory when it owns a file inside it, and it owns the per-mode files
  # directly under `kitty/`, `rofi/` and `ncspot/` — but nothing under
  # `foot/themes/`, whose only occupant is the link itself.
  #
  # Seeded to `tiling`, deliberately not to a scheme name: `current_mode()` in
  # lib.sh falls back to tiling for exactly the same reason, and checks/static.sh
  # asserts tiling wears the artefact scheme. One fallback, two readers, agreed
  # by construction. This does NOT read `current-mode` — a second reader of the
  # state directory in a language that cannot share lib.sh is the drift lib.sh
  # exists to prevent. Being one mode switch stale is the accepted cost.
  home.activation.seedModeTheme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    seed() { [ -e "$HOME/.config/$1" ] || run ln -sfn "$HOME/.config/$2" "$HOME/.config/$1"; }
    run mkdir -p "$HOME/.config/foot/themes"
    seed kitty/current-theme.conf kitty/colors-tiling.conf
    seed foot/themes/noctalia     foot/colors-tiling
    seed rofi/colors.rasi         rofi/colors-tiling.rasi
    seed ncspot/config.toml       ncspot/colors-tiling.toml
  '';
}
