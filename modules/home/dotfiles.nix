# Hand-written dotfiles, linked into ~/.config. Tier 2 (store-based) and tier 3
# (out-of-store) only; tier 1 is programs.nix / waybar.nix. Rules in
# docs/adr/0009, history in docs/adr/0002, layout in docs/SYSTEM.md §6.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Not ~/.config — xdg.configFile writes there, so every entry would link to
  # itself. Declared in options.nix; shell.nix needs it too.
  dots = config.local.checkout;
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/dotfiles/${path}";

  p = import ./palette.nix;

  # Bare "rrggbb" → { r; g; b; } as integers. fsel and swaync both want decimal
  # channels, which is the spelling that let two copies of the palette hide:
  # grepping this repo for `d79921` found neither `rgb(215, 153, 33)`.
  rgbOf = c: {
    r = lib.fromHexString (builtins.substring 0 2 c);
    g = lib.fromHexString (builtins.substring 2 2 c);
    b = lib.fromHexString (builtins.substring 4 2 c);
  };

  # `r, g, b` with no wrapper — swaync composes some of these into rgba() with a
  # separate alpha var, so the channels have to stand alone.
  channels =
    c:
    let
      v = rgbOf c;
    in
    "${toString v.r}, ${toString v.g}, ${toString v.b}";

  # mango wants 0xrrggbbaa and has no opacity of its own, so alpha is part of
  # every colour it takes.
  mangoColor = c: "0x${c}ff";

  # One of midnight-discord's five-step colour scales, mixed from a single
  # palette colour. Steps 2 and 3 are the colour itself — that is the framework's
  # own shape, not a mistake, and the status vars read step 2.
  #
  # `color-mix` rather than five hex literals: the gruvbox original hand-tuned
  # twenty-five hsl() values across five scales, where a typo and a considered
  # value look identical. Mixing keeps one source colour per scale, so a palette
  # change moves all five.
  scale =
    name: c:
    lib.concatStringsSep "\n" [
      "  --${name}-1: color-mix(in srgb, #${c} 85%, white);"
      "  --${name}-2: #${c};"
      "  --${name}-3: #${c};"
      "  --${name}-4: color-mix(in srgb, #${c} 88%, black);"
      "  --${name}-5: color-mix(in srgb, #${c} 76%, black);"
    ];

  # The colours mango takes, per mode. Emitted as files the mode configs
  # `source=`, which is mango's own include directive (see the source= block at
  # the top of any mode config) — so the hand-written configs keep the layout
  # and rules and hold no hex at all.
  #
  # `border` differs by mode deliberately: noctalia mode draws its own heavier
  # chrome and takes `overlay`, the other two take `surface` (docs/adr/0022).
  # Everything below `border` is identical across modes and comes from
  # universal/settings.conf, which is why it was the file that drifted.
  mangoColors = border: ''
    # GENERATED from modules/home/palette.nix — edit that, then rebuild.
    # `source=`d by the mode config. Reloading mango alone re-reads the LAST
    # rebuild's copy, which looks exactly like the change having had no effect.
    bordercolor=${mangoColor border}
    focuscolor=${mangoColor p.accent}
    rootcolor=${mangoColor p.base}
    maximizescreencolor=${mangoColor p.okColor}
    urgentcolor=${mangoColor p.errColor}
    scratchpadcolor=${mangoColor p.brMagenta}
    globalcolor=${mangoColor p.brMagenta}
    overlaycolor=${mangoColor p.brCyan}
  '';

  # nvim is linked as ONE directory symlink, so unlike mango there is no way to
  # drop a generated file inside it — home-manager would be claiming a path that
  # already has an owner. Merging in the store instead keeps the single-symlink
  # shape and avoids `recursive = true`, whose failure mode here is destroying
  # the checkout (see unlinkStaleConfigDirs below and docs/adr/0002).
  #
  # The 17 keys below are catppuccin/nvim's own palette names, which are
  # Catppuccin's colour vocabulary rather than a plugin invention — so unlike
  # the gruvbox arrangement this replaced, they line up with what palette.nix
  # names instead of needing a translation table. checks/static.sh asserts the
  # generated file carries the accent.
  #
  # Deliberately absent: crust, flamingo, maroon, peach, sky, sapphire,
  # lavender, overlay0 and overlay2. palette.nix does not name them, and the
  # plugin's own Mocha values for them are correct — this machine IS Mocha.
  # Adding them here to "finish the job" would put nine more colours in the
  # palette that no other consumer reads. `mantle` earned its place by
  # acquiring one — Equibop's recessed background.
  nvimPalette = pkgs.writeText "palette.lua" ''
    -- GENERATED from modules/home/palette.nix — edit that, then rebuild.
    -- Consumed by lua/plugins/colorscheme.lua as catppuccin/nvim's
    -- `color_overrides.mocha`. Not present in dotfiles/nvim/.
    return {
      base = "#${p.bg0}",
      mantle = "#${p.mantle}",
      surface0 = "#${p.bg1}",
      surface1 = "#${p.bg2}",
      surface2 = "#${p.bg3}",
      rosewater = "#${p.fg0}",
      text = "#${p.fg1}",
      subtext0 = "#${p.fg4}",
      subtext1 = "#${p.brWhite}",
      overlay1 = "#${p.brBlack}",
      mauve = "#${p.accent}",
      red = "#${p.red}",
      green = "#${p.green}",
      yellow = "#${p.yellow}",
      blue = "#${p.blue}",
      pink = "#${p.magenta}",
      teal = "#${p.cyan}",
    }
  '';

  nvimConfig = pkgs.runCommand "nvim-config" { } ''
    cp -r ${../../dotfiles/nvim} $out
    chmod -R u+w $out
    cp ${nvimPalette} $out/lua/config/palette.lua
  '';
in
{
  xdg.configFile = {
    # --- Desktop environment ------------------------------------------------
    # `recursive` so the mode scripts can create config.conf here. Converting an
    # already-linked directory this way destroys the checkout — see
    # unlinkStaleConfigDirs below and docs/adr/0002.
    "mango" = {
      source = ../../dotfiles/mango;
      recursive = true;
    };

    # The colours, generated. These paths do not exist under dotfiles/mango, so
    # they are new siblings inside the recursive tree rather than a second owner
    # for a linked path — the same arrangement waybar/colors.css already uses.
    "mango/universal/colors-tiling.conf".text = mangoColors p.surface;
    "mango/universal/colors-hud.conf".text = mangoColors p.surface;
    "mango/universal/colors-noctalia.conf".text = mangoColors p.overlay;

    # --- Editors ------------------------------------------------------------
    # lazy-lock.json lives in stdpath("state"). Not the bare directory: the
    # generated palette is merged in first, see nvimConfig above.
    "nvim".source = nvimConfig;

    # --- Shell --------------------------------------------------------------
    # Not `zsh` — home-manager owns ~/.config/zsh/.zshrc, and one path cannot
    # have two owners.
    "zsh/conf.d".source = ../../dotfiles/zsh/conf.d;

    # --- Store-based ---------------------------------------------------------
    "glow".source = ../../dotfiles/glow; # no home-manager module at this pin

    # fsel has no module, but the whole file is nine settings and two colours —
    # small enough that generating all of it beats splitting it, so there is no
    # dotfiles/fsel/ any more. Terminal bg/fg come from foot.
    #
    # fsel wants decimal `rgb(r, g, b)`, which is the spelling that hid this
    # copy of the accent: grepping the repo for `d79921` never found it.
    "fsel/config.toml".text =
      let
        rgb = c: "rgb(${toString (rgbOf c).r}, ${toString (rgbOf c).g}, ${toString (rgbOf c).b})";
      in
      ''
        # GENERATED from modules/home/palette.nix — edit that, then rebuild.
        highlight_color = "${rgb p.accent}"
        cursor = "█"

        pin_color = "${rgb p.accent}"
        pin_icon = "*"

        terminal_launcher = "foot -e"

        [app_launcher]
        filter_desktop = true
        filter_actions = false
        list_executables_in_path = false
        match_mode = "fuzzy"
        ranking_mode = "frecency"
        pinned_order = "ranking"
      '';

    # rofi reads ~/.config/rofi/config.rasi and nothing in the mango tree points
    # at it, so this declaration is the only thing that connects the two
    # (docs/adr/0014). Files, not a directory: rofi writes a cache and
    # rofi.png next to them.
    #
    # Split the same way the bar is: the layout rules are hand-tuned
    # presentation and stay written by hand, the palette is data and is derived
    # from modules/home/palette.nix. config.rasi `@import`s this one.
    "rofi/config.rasi".source = ../../dotfiles/rofi/config.rasi;
    "rofi/colors.rasi".text =
      let
        p = import ./palette.nix;
      in
      ''
        /* GENERATED from modules/home/palette.nix — edit that, then rebuild.
           Imported by config.rasi. The names match waybar/colors.css so the
           bar and the menus can be reasoned about in one vocabulary. */
        * {
            base:    #${p.base};
            overlay: #${p.overlay};
            text:    #${p.text};
            subtext: #${p.subtext};
            accent:  #${p.accent};
            urgent:  #${p.errColor};
        }
      '';

    # Not `services.swaync` — autostart.conf owns the lifecycle so a restyle
    # applies on mode switch. docs/adr/0005.
    #
    # ONE generated file, not a hand-written `:root` plus an `@import` of a
    # generated palette the way waybar and rofi are split. swaync's CSS engine
    # is not GTK's, `@import` is not confirmed to work in it, and a stylesheet
    # whose colours silently fail to load renders as "swaync ignored my theme" —
    # so the palette is concatenated at build time instead, where nothing can
    # fail to resolve at runtime. The body stays a hand-written FRAGMENT.
    #
    # The non-colour vars are carried through as literal text. They are settings
    # rather than data and would be better off in the fragment, but they share
    # the one `:root` block, and splitting it into two would reintroduce exactly
    # the runtime-resolution question this avoids.
    "swaync/style.css".text = ''
      /* The `:root` block below is GENERATED from modules/home/palette.nix —
         edit that, then rebuild. The rules after it are hand-written and live
         in dotfiles/swaync/style-body.css. */
      :root {
        --cc-bg: rgba(${channels p.base}, 0.92);
        --noti-border-color: rgba(255, 255, 255, 0.15);
        --noti-bg: ${channels p.base};
        --noti-bg-alpha: 0.92;
        --noti-bg-darker: rgb(30, 30, 30);
        --noti-bg-hover: rgb(50, 50, 50);
        --noti-bg-focus: rgba(60, 60, 60, 0.6);
        --noti-close-bg: rgba(255, 255, 255, 0.1);
        --noti-close-bg-hover: rgba(255, 255, 255, 0.15);
        --text-color: rgb(${channels p.text});
        --text-color-disabled: rgb(150, 150, 150);
        --bg-selected: rgb(${channels p.accent});
        --notification-icon-size: 64px;
        --notification-app-icon-size: calc(var(--notification-icon-size) / 3);
        --notification-group-icon-size: 32px;
        --border: 1px solid var(--noti-border-color);
        --border-radius: 0px;
        --notification-shadow: 0 0 0 1px rgba(0, 0, 0, 0.3),
          0 1px 3px 1px rgba(0, 0, 0, 0.7), 0 2px 6px 2px rgba(0, 0, 0, 0.3);
        --font-size-body: 13px;
        --font-size-summary: 13px;
        --hover-transition: background 0.15s ease-in-out;
        --group-collapse-transition: opacity 400ms ease-in-out;
      }

    ''
    + builtins.readFile ../../dotfiles/swaync/style-body.css;

    # Equibop (Discord). Same split as swaync above and for the same reason —
    # a hand-written FRAGMENT carrying layout, with the colours generated onto
    # the end. Reversed order, though: the fragment leads, because CSS requires
    # `@import` to precede every other rule and the midnight framework is
    # imported by URL at the top of it.
    #
    # Managed as a FILE inside `themes/`, not as the directory: Equibop's own
    # theme installer writes siblings there, and two owners for one path is an
    # activation failure rather than a merge.
    #
    # The lifecycle is the other half of this. `mango/scripts/lib.sh` sets
    # `enabledThemes` on every mode switch, and Equibop ignores a name that
    # matches no file **without logging** — so the filename below and the one in
    # that script have to move together. They did not, once: the theme stayed
    # gruvbox through the 2026-08-18 migration because it is a *name*, not a
    # colour, and the migration was grepping for hex.
    "equibop/themes/catppuccin.theme.css".text =
      builtins.readFile ../../dotfiles/equibop/theme-body.css
      + ''
        /* ---------------------------------------------------------------
           GENERATED from modules/home/palette.nix — edit that, then rebuild.
           The rules above are hand-written and live in
           dotfiles/equibop/theme-body.css.
           --------------------------------------------------------------- */
        :root {
          --colors: on;

          /* Text */
          --text-0: #${p.base}; /* on accent elements */
          --text-1: #${p.text}; /* important */
          --text-2: #${p.text}; /* headings */
          --text-3: #${p.brWhite}; /* normal */
          --text-4: #${p.subtext}; /* icons, channels */
          --text-5: #${p.brBlack}; /* muted, timestamps */

          /* Backgrounds. `mantle` is the one tone darker than `base`, for
             pressed controls; the main surface is `base` itself. */
          --bg-1: #${p.mantle}; /* darkest — clicked buttons */
          --bg-2: #${p.surface}; /* dark buttons */
          --bg-3: #${p.overlay}; /* secondary elements, spacing */
          --bg-4: #${p.base}; /* main background */

          --hover:         rgba(${channels p.text}, 0.04);
          --active:        rgba(${channels p.text}, 0.08);
          --active-2:      rgba(${channels p.text}, 0.05);
          --message-hover: rgba(${channels p.text}, 0.03);

          /* Accents. Only `--accent-3` is a palette colour; hover and pressed
             are mixed from it, so the button scale cannot drift from it. */
          --accent-1: #${p.infoColor}; /* links, accent text */
          --accent-2: #${p.cyan}; /* small accent elements */
          --accent-3: #${p.accent}; /* accent buttons */
          --accent-4: color-mix(in srgb, var(--accent-3) 65%, white);
          --accent-5: color-mix(in srgb, var(--accent-3) 80%, black);
          --accent-new: #${p.errColor}; /* mute/deafen/danger */

          --mention:       linear-gradient(to right, color-mix(in hsl, #${p.accent}, transparent 90%) 40%, transparent);
          --mention-hover: linear-gradient(to right, color-mix(in hsl, #${p.accent}, transparent 95%) 40%, transparent);
          --reply:         linear-gradient(to right, color-mix(in hsl, #${p.overlay}, transparent 90%) 40%, transparent);
          --reply-hover:   linear-gradient(to right, color-mix(in hsl, #${p.overlay}, transparent 95%) 40%, transparent);

          /* Status */
          --online:    var(--green-2);
          --dnd:       var(--red-2);
          --idle:      var(--yellow-2);
          --streaming: var(--purple-2);
          --offline:   var(--text-4);

          /* Borders */
          --border-light:  var(--hover);
          --border:        var(--active);
          --border-hover:  var(--active);
          --button-border: hsla(0, 0%, 100%, 0.1);

          /* Colour scales, mixed from one palette colour each rather than
             hand-tuned hsl() — the gruvbox original had five literals per
             scale and no way to tell a considered value from a typo. */
        ${scale "red" p.errColor}
        ${scale "green" p.okColor}
        ${scale "blue" p.infoColor}
        ${scale "yellow" p.warnColor}
        ${scale "purple" p.accent}
        }

        /* Code blocks */
        .hljs { background: #${p.surface} !important; color: #${p.text} !important; }
        .hljs-keyword, .hljs-selector-tag, .hljs-deletion   { color: #${p.red}; }
        .hljs-string,  .hljs-addition, .hljs-selector-class { color: #${p.green}; }
        .hljs-number,  .hljs-literal                        { color: #${p.magenta}; }
        .hljs-attr,    .hljs-type, .hljs-params             { color: #${p.yellow}; }
        .hljs-built_in, .hljs-title, .hljs-name             { color: #${p.blue}; }
        .hljs-function, .hljs-class, .hljs-tag              { color: #${p.cyan}; }
        .hljs-meta,    .hljs-regexp                         { color: #${p.accent}; }
        .hljs-comment                                       { color: #${p.brBlack}; font-style: italic; }
      '';

    # --- Managed as FILES, not directories -----------------------------------
    # Pins the config read-only while leaving the directory writable for sibling
    # runtime files. Cost: no longer changeable from inside the app.
    "Kvantum/kvantum.kvconfig".source = ../../dotfiles/Kvantum/kvantum.kvconfig;
    # From the store, not vendored under dotfiles/. The gruvbox theme it
    # replaces was a lone .kvconfig this repo carried because nixpkgs had no
    # package for it; catppuccin-kvantum ships the widget SVG as well, which is
    # most of what a Kvantum theme is and none of which belongs in git.
    "Kvantum/catppuccin-mocha-mauve".source =
      "${pkgs.catppuccin-kvantum}/share/Kvantum/catppuccin-mocha-mauve";

    # theme.nix owns GTK settings, so nwg-look's own state is pinned read-only
    # to stop the GUI fighting it.
    "nwg-look/config".source = ../../dotfiles/nwg-look/config;

    # settings.ini, gtk.css and bookmarks are generated in theme.nix; assets only
    # here.
    "gtk-3.0/assets".source = ../../dotfiles/gtk-3.0/assets;
    "gtk-3.0/colors.css".source = ../../dotfiles/gtk-3.0/colors.css;
    "gtk-4.0/colors.css".source = ../../dotfiles/gtk-4.0/colors.css;

    # --- The one genuine holdout ---------------------------------------------
    # corectrl writes its config from the GUI, which is the point of it.
    "corectrl".source = link "corectrl";
  };

  # gh, glab-cli, gpu-screen-recorder and opencode hold credentials and are
  # gitignored, so linking them would rename the real directory aside — see
  # docs/SYSTEM.md §11. ~/.zshenv is written by programs.zsh.dotDir.

  # Store-based, not `link`: nothing writes here, Nix keeps the executable bit,
  # and audio.nix has a unit pointing in.
  home.file.".scripts".source = ../../dotfiles/scripts;

  # Removes a stale out-of-store symlink before anything is linked into it —
  # without this, `recursive = true` writes through it into the checkout
  # (docs/adr/0002). Derived from xdg.configFile, never hardcoded: a
  # hand-maintained list missed a batch and clobbered ten tracked files.
  home.activation.unlinkStaleConfigDirs =
    let
      # First path segment only: "gtk-3.0/assets" guards "~/.config/gtk-3.0".
      topLevel = lib.unique (
        map (n: lib.head (lib.splitString "/" n)) (lib.attrNames config.xdg.configFile)
      );
    in
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] (
      lib.concatMapStrings (d: ''
        if [ -L "${config.xdg.configHome}/${d}" ]; then
          run rm $VERBOSE_ARG "${config.xdg.configHome}/${d}"
        fi
      '') topLevel
    );

  # Top-level dirs GTK file managers omit from the ~ view (Ctrl+H to show).
  home.file.".hidden".text = ''
    Android
    Applications
    blender
    colors
    go
    log
    R
    share
    temp
    vaults
    winboat
    Zomboid
  '';
}
