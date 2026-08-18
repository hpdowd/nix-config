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
  # The 20 keys below are gruvbox.nvim's own palette names. They currently hold
  # exactly upstream's values, so this is a no-op today and a working lever the
  # moment palette.nix changes — checks/static.sh asserts the first half of that.
  nvimPalette = pkgs.writeText "palette.lua" ''
    -- GENERATED from modules/home/palette.nix — edit that, then rebuild.
    -- Consumed by lua/plugins/colorscheme.lua as gruvbox.nvim's
    -- `palette_overrides`. Not present in dotfiles/nvim/.
    return {
      dark0 = "#${p.bg0}",
      dark1 = "#${p.bg1}",
      dark2 = "#${p.bg2}",
      dark3 = "#${p.bg3}",
      light0 = "#${p.fg0}",
      light1 = "#${p.fg1}",
      light4 = "#${p.fg4}",
      gray = "#${p.brBlack}",
      neutral_red = "#${p.red}",
      neutral_green = "#${p.green}",
      neutral_yellow = "#${p.yellow}",
      neutral_blue = "#${p.blue}",
      neutral_purple = "#${p.magenta}",
      neutral_aqua = "#${p.cyan}",
      bright_red = "#${p.brRed}",
      bright_green = "#${p.brGreen}",
      bright_yellow = "#${p.brYellow}",
      bright_blue = "#${p.brBlue}",
      bright_purple = "#${p.brMagenta}",
      bright_aqua = "#${p.brCyan}",
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

    # --- Managed as FILES, not directories -----------------------------------
    # Pins the config read-only while leaving the directory writable for sibling
    # runtime files. Cost: no longer changeable from inside the app.
    "Kvantum/kvantum.kvconfig".source = ../../dotfiles/Kvantum/kvantum.kvconfig;
    # Concatenated, not a bare path: `#` opens a Nix comment and would swallow
    # the semicolon, erroring on the next line.
    "Kvantum/Gruvbox#".source = ../../dotfiles/Kvantum + "/Gruvbox#";

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
