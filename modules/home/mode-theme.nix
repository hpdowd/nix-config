# The per-mode colour halves — docs/adr/0034.
#
# kitty, foot, rofi and ncspot run in EVERY mode and read one fixed path, so
# each reads through a runtime symlink `apply_theme()` in
# dotfiles/mango/scripts/lib.sh re-points:
#
#   kitty/current-theme.conf  ->  kitty/colors-<mode>.conf
#   foot/themes/noctalia      ->  foot/colors-<mode>
#   rofi/colors.rasi          ->  rofi/colors-<mode>.rasi
#   ncspot/config.toml        ->  ncspot/colors-<mode>.toml
#
# None of those four link paths may be an `xdg.configFile` — two owners for one
# path is an activation failure. Keyed by MODE, never by scheme: a scheme name
# on the Nix->shell boundary is the drift lib.sh exists to stop.
#
# The odd link names are noctalia's, so its templates stay a later toggle
# rather than a redesign (adr/0034 phase 3b). docs/gotchas.md -> Theming.
{ lib, ... }:
let
  modes = import ./modes.nix;
  paletteOf = mode: import ./themes/${modes.${mode}}.nix;

  # Over `modes`, not a hand-written list: a mode added gets its sidecars with
  # nothing to remember, and one removed takes them away.
  perMode =
    path: render:
    lib.mapAttrs' (
      mode: _: lib.nameValuePair (path mode) { text = render mode (paletteOf mode); }
    ) modes;

  # Provenance, on every generated file — the one without it gets hand-edited.
  from =
    mode: c:
    "${c} GENERATED from modules/home/themes/${modes.${mode}}.nix, for the '${mode}' mode (modules/home/modes.nix). Edit those, then rebuild.";

  # kitty, rofi and ncspot want a leading `#`; foot wants bare hex. One palette,
  # two spellings, which is why the check greps for each consumer's own.
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

  # `[colors-dark]` as before — this changed ownership, not appearance. foot's
  # `include` scopes the section, so the header does not leak into foot.ini.
  footTheme = mode: p: ''
    ${from mode "#"}
    # foot 1.27 cannot re-read its config, so a swap reaches NEW WINDOWS ONLY.
    # apply_theme says so; docs/gotchas.md -> Theming.
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

  # Names match waybar/colors.css, so bar and menus share one vocabulary.
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
  # ncspot's whole config is its theme, so the per-mode file IS the config.
  # Affordable only because `programs.ncspot.settings = { }` leaves the path
  # unclaimed — ANY future non-theme setting goes here, not there.
  # docs/gotchas.md -> Theming. Drawn entirely from `muted`, and asserted so.
  ncspotTheme =
    mode: p:
    let
      m = p.muted;
    in
    ''
      ${from mode "#"}
      # Read ONCE at startup: a swap reaches the next ncspot, not this one.
      [theme]
      background = "${hash m.bg}"
      primary = "${hash m.fg}"
      secondary = "${hash m.dim}"
      title = "${hash m.accent}"
      playing = "${hash m.ok}"
      playing_selected = "${hash m.ok}"
      playing_bg = "${hash m.surface}"
      highlight = "${hash m.overlay}"
      # `highlight_fg` / `error_fg`, not `highlight_bg` / `error` — ncspot drops
      # keys it does not know, silently.
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

  # THE BOOTSTRAP. `apply_theme` runs on a mode SWITCH, so a fresh machine has
  # no link until the first one — silent in kitty, rofi and ncspot, and FATAL in
  # foot (exit 230, no terminal). `[ -e ]` follows symlinks, so a dangling link
  # is repaired too. `mkdir -p` for foot's themes/ alone: home-manager owns no
  # file under it. Seeded to `tiling`, matching `current_mode()`'s fallback —
  # one default, two readers. Deliberately does NOT read `current-mode`; being
  # one switch stale is cheaper than a second reader of that state.
  home.activation.seedModeTheme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    seed() { [ -e "$HOME/.config/$1" ] || run ln -sfn "$HOME/.config/$2" "$HOME/.config/$1"; }
    run mkdir -p "$HOME/.config/foot/themes"
    seed kitty/current-theme.conf kitty/colors-tiling.conf
    seed foot/themes/noctalia     foot/colors-tiling
    seed rofi/colors.rasi         rofi/colors-tiling.rasi
    seed ncspot/config.toml       ncspot/colors-tiling.toml
  '';
}
