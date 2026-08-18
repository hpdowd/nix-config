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
  # THREE generated files, and the split matters:
  #
  #   lua/config/scheme.lua       names only — read by the hand-written lazy.lua
  #                               and ui.lua, so those two hold no scheme name
  #   lua/plugins/colorscheme.lua the plugin spec, because a new scheme means a
  #                               new PLUGIN, not overrides on a foreign one
  #   lua/config/palette.lua      colours, and only when the theme declares an
  #                               override map — see below
  #
  # WHY THE PLUGIN IS GENERATED. THEME-MIGRATION §3: overriding 16 keys of a
  # Mocha theme with gruvbox values leaves 10 Catppuccin ones in place, and the
  # result is a visible hybrid rather than gruvbox. So the theme file names the
  # plugin whose scheme it IS, and only a theme that DEVIATES from its plugin
  # (mocha-high-contrast, which lifts Mocha's greys) also supplies a palette.
  nvimTheme = p.apps.nvim;

  # COMMENTS GO HERE, NOT IN THE STRINGS BELOW. `#` starts no comment inside a
  # Nix `` literal and none in Lua either, so a `#` line in a block below is
  # emitted verbatim and breaks the file at load. That shipped once, past a green
  # `nix flake check`, because the check only grepped for the accent — hence the
  # parse check on the derivation.
  nvimScheme = pkgs.writeText "scheme.lua" ''
    -- GENERATED from modules/home/themes/${import ./scheme.nix}.nix — edit that,
    -- then rebuild. Names only, no colours: lazy.lua needs the colourscheme to
    -- fall back to and ui.lua needs lualine's theme, and neither should carry a
    -- scheme name of its own.
    return {
      name = "${nvimTheme.name}",
      lualine = "${nvimTheme.lualine}",
    }
  '';

  # The plugin's own vocabulary on the left, the palette's roles on the right —
  # the map lives in the theme file because the key names belong to the plugin,
  # not to this machine. Emitted only when that map is non-empty; a scheme that
  # matches its plugin takes upstream's values and this file does not exist.
  nvimPalette = pkgs.writeText "palette.lua" ''
    -- GENERATED from modules/home/palette.nix — edit that, then rebuild.
    -- Consumed by lua/plugins/colorscheme.lua as the plugin's own override hook.
    return {
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (key: role: "  ${key} = \"#${p.${role}}\",") nvimTheme.palette
    )}
    }
  '';

  nvimColorscheme = pkgs.writeText "colorscheme.lua" ''
    -- GENERATED from modules/home/themes/${import ./scheme.nix}.nix — edit that,
    -- then rebuild. Not present in dotfiles/nvim/.
    --
    -- High priority and `lazy = false` so it loads before anything that reads
    -- highlight groups at startup.
    return {
      {
        "${nvimTheme.spec}",
        name = "${nvimTheme.name}",
        priority = 1000,
        lazy = false,
        config = function()
    ${nvimTheme.setup}
          vim.cmd.colorscheme("${nvimTheme.name}")
        end,
      },
    }
  '';

  # The parse check is the point of this being a derivation rather than a copy.
  # A malformed generated file is invisible to every other gate here: `nix flake
  # check` builds it happily, the palette scan greps it for the accent and finds
  # one, and nvim reports a failed plugin config at startup and falls back to no
  # colourscheme — which looks like a theme that did not apply, not a syntax
  # error. `luajit -b … /dev/null` compiles without running, so this is a syntax
  # gate and nothing more.
  nvimConfig = pkgs.runCommand "nvim-config" { nativeBuildInputs = [ pkgs.luajit ]; } ''
    cp -r ${../../dotfiles/nvim} $out
    chmod -R u+w $out
    cp ${nvimScheme} $out/lua/config/scheme.lua
    cp ${nvimColorscheme} $out/lua/plugins/colorscheme.lua
    ${lib.optionalString (nvimTheme.palette != { }) "cp ${nvimPalette} $out/lua/config/palette.lua"}
    for f in lua/config/scheme.lua lua/plugins/colorscheme.lua \
             ${lib.optionalString (nvimTheme.palette != { }) "lua/config/palette.lua"}; do
      luajit -b "$out/$f" /dev/null \
        || { echo "generated $f is not valid Lua" >&2; exit 1; }
    done
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

    # noctalia's pinned settings — merged over its own settings.json by
    # `scripts/modes/noctalia.sh` on every entry into that mode.
    #
    # GENERATED, and it is here rather than under dotfiles/mango/noctalia/
    # because of ONE key: `predefinedScheme`. noctalia owns roughly half the
    # screen in its mode and resolves its palette from that name internally, so
    # a scheme change that misses it leaves the machine half this palette and
    # half noctalia purple — which looks like a theme, not a fault. The rest of
    # the file is settings rather than colours and moved with it, because the
    # alternative is two owners for one path.
    "mango/noctalia/settings-pinned.json".text = builtins.toJSON {
      wallpaper.enabled = false;
      nightLight.enabled = false;
      idle.enabled = false;
      general.lockOnSuspend = false;
      colorSchemes = {
        syncGsettings = false;
        useWallpaperColors = false;
        predefinedScheme = p.apps.noctalia;
        darkMode = true;
      };
      templates = {
        enableUserTheming = false;
        activeTemplates = [ ];
      };
      plugins.autoUpdate = false;
      appLauncher.enableClipboardHistory = true;
      # `keybind` is a STRING in noctalia's schema, not a number — it is the key
      # the session menu listens for, and a JSON integer here is silently ignored.
      sessionMenu.powerOptions = [
        {
          action = "lock";
          enabled = true;
          keybind = "1";
        }
        {
          action = "suspend";
          enabled = true;
          keybind = "2";
        }
        {
          action = "hibernate";
          enabled = true;
          keybind = "3";
        }
        {
          action = "reboot";
          enabled = true;
          keybind = "4";
        }
        {
          action = "logout";
          enabled = false;
          keybind = "5";
        }
        {
          action = "shutdown";
          enabled = true;
          keybind = "6";
        }
        {
          action = "rebootToUefi";
          enabled = true;
          keybind = "7";
        }
      ];
    };

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
    # `scheme.theme.css`, NOT the scheme's name. The file is generated from
    # whatever palette is selected, so a name like `catppuccin.theme.css` is
    # wrong four schemes out of five — and it was already wrong once: the theme
    # stayed `gruvbox.theme.css` through the 2026-08-18 migration because a
    # filename is a *name*, not a colour, and the migration was grepping for hex.
    # A scheme-neutral name cannot go stale, which is the only way to win here.
    #
    # The lifecycle is the other half of this. `mango/scripts/lib.sh` sets
    # `enabledThemes` on every mode switch, and Equibop ignores a name that
    # matches no file **without logging** — so this key and that script have to
    # move together. `checks/static.sh` asserts they agree.
    "equibop/themes/scheme.theme.css".text =
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
    #
    # GENERATED, because the theme name is the scheme's. It was a hand-written
    # two-line file naming `catppuccin-mocha-mauve`, which made it one of the
    # places a scheme change had to be remembered — and Kvantum falls back to
    # its default style for a theme it cannot find, without a word.
    "Kvantum/kvantum.kvconfig".text = ''
      # GENERATED from modules/home/palette.nix — edit that, then rebuild.
      [General]
      theme=${p.packages.kvantum.name}
    '';

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
  }
  # The Kvantum theme itself, from the store — but only when the scheme HAS one.
  # All four shipped schemes do; a scheme that instead names a Kvantum built-in
  # (`KvArcDark` and friends, which the style plugin already ships) has nothing
  # to link, and an entry here would point at a path that does not exist. Kept
  # because `packages.kvantum.attr = null` is a supported shape — Dracula and Ayu
  # used it before they were dropped for needing too many stand-ins.
  #
  # Not vendored under dotfiles/: the gruvbox theme this arrangement replaced was
  # a lone .kvconfig this repo carried because nixpkgs had no package for it, and
  # a Kvantum theme is mostly rendered SVG widget art that does not belong in git.
  // lib.optionalAttrs (p.packages.kvantum.attr != null) {
    "Kvantum/${p.packages.kvantum.name}".source =
      "${pkgs.themeKvantum}/share/Kvantum/${p.packages.kvantum.name}";
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
