# Native home-manager program modules.
#
# This file is the counterpart to dotfiles.nix, and the direction of travel is
# from that file to this one. dotfiles.nix carries configs as *files* — either
# copied verbatim into the store or symlinked out of it — which is what the
# Arch migration needed on day one and what CLAUDE.md's "store-based vs
# out-of-store" rule is about. That rule answers "may this file be read-only?".
# It is the wrong question to stop at.
#
# The better question is "should this file exist as a file at all?". A native
# module *generates* the config from Nix, which buys three things a store copy
# does not:
#
#   - the option set is typed, so a typo is an evaluation error rather than a
#     setting the program silently ignores at runtime. This repo's recurring
#     failure mode is config that is wrong in a way nothing reports (the dead
#     `mmsg -s -d` flags, the empty `custom/*` modules, the `appid:zen` rules
#     that matched nothing) — types are the only mechanism here that turns any
#     of that into a build failure.
#   - the package and its config have ONE owner. Previously `kitty` was in
#     packages.nix and `kitty/` was in dotfiles.nix, so nothing tied them
#     together; now `programs.kitty.enable` installs the binary and writes the
#     config, and removing it removes both.
#   - values can be shared. The Gruvbox palette below is a `let` binding used
#     by kitty and foot, rather than the same sixteen hex codes transcribed
#     into two files that drift.
#
# WHAT IS DELIBERATELY NOT HERE:
#
#   mango    no home-manager module exists. It also has a genuine writability
#            requirement (the mode scripts `cp` into config.conf), so it stays
#            store-based with `recursive = true`.
#   nvim     ~22 files of lazy.nvim config. `programs.neovim` with Nix-managed
#            plugins is a rewrite, not a conversion — it would trade `:Lazy
#            sync` for a rebuild on every plugin bump, and the store path
#            already makes it reproducible. The store copy is the right answer.
#   swaync   `services.swaync` declares `systemd.user.services.swaync`, which
#            is precisely the unit masked in default.nix, because
#            mango/{tiling,hud}/autostart.conf owns swaync's lifecycle so a
#            restyle takes effect on mode switch. Converting it flips that
#            ownership decision; that is an ADR, not a line in a bulk pass.
#   glow,    no module in nixpkgs' home-manager at this pin.
#   nwg-look
#   corectrl the honest holdout — see dotfiles.nix.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # The palette lived here as a `let` binding until 2026-08-14, which was
  # already the second copy (kitty/gruvbox-orange.conf and
  # foot/gruvbox-colors.ini before it) — and the bar carried a third in
  # waybar/colors.css. One file now, shared with the bar and the menus.
  p = import ./palette.nix;

  # kitty wants a leading `#`, foot wants bare hex. One palette, two spellings.
  hash = c: "#${c}";

  # swaylock wants `rrggbbaa` and has no separate opacity setting, so the alpha
  # is part of every colour it takes. Two are used: solid, and the wash behind
  # the indicator that lets the background pool through.
  opaque = c: "${c}ff";
  wash = c: "${c}55";
in
{
  # ==========================================================================
  # Terminals
  # ==========================================================================

  # kitty. Was home/kitty/{kitty.conf,gruvbox-orange.conf,tabs.conf}; the three
  # files were split only because kitty.conf `include`d the other two, which is
  # not a distinction worth preserving once Nix generates the whole thing.
  programs.kitty = {
    enable = true;

    font = {
      name = "Hack Nerd Font Mono";
      size = 11;
    };

    settings = {
      # Font. `font_family`/`size` come from `font` above; these are the
      # variants, which that option does not cover.
      # Needs `nerd-fonts._0xproto` in fonts.nix, not `_0xproto` — the family
      # name differs. 0xProto ships no bold-italic, so that variant stays Hack.
      bold_font = "0xProto Nerd Font Mono Bold";
      italic_font = "0xProto Nerd Font Mono Italic";
      symbol_map = "U+E000-U+F8FF,U+100000-U+10FFFF Symbols Nerd Font Mono";
      force_ltr = "no";
      modify_font = "underline_position 2";

      # Cursor
      cursor_shape = "beam";
      cursor_beam_thickness = "1.5";
      cursor_blink_interval = 0;

      # Window
      window_padding_width = "15 20";
      wayland_titlebar_color = "background";

      scrollback_lines = 10000;
      enable_audio_bell = "no";

      # Colours
      color0 = hash p.black;
      color1 = hash p.red;
      color2 = hash p.green;
      color3 = hash p.yellow;
      color4 = hash p.blue;
      color5 = hash p.magenta;
      color6 = hash p.cyan;
      color7 = hash p.white;
      color8 = hash p.brBlack;
      color9 = hash p.brRed;
      color10 = hash p.brGreen;
      color11 = hash p.brYellow;
      color12 = hash p.brBlue;
      color13 = hash p.brMagenta;
      color14 = hash p.brCyan;
      color15 = hash p.brWhite;
      background = hash p.bg;
      foreground = hash p.fg;
      cursor = hash p.fg;
      cursor_text_color = hash p.bg;
      selection_foreground = hash p.bg;
      selection_background = hash p.selBg;

      # Tab bar (was tabs.conf, renamed from dank-tabs.conf when DMS was
      # dropped — the name was kept deliberately, the file need not be).
      tab_bar_edge = "top";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";
      tab_bar_align = "left";
      tab_bar_min_tabs = 2;
      tab_bar_margin_width = "0.0";
      tab_bar_margin_height = "2.5 1.5";
      tab_bar_margin_color = hash p.bg;
      tab_bar_background = hash p.bg;
      active_tab_foreground = hash p.bg;
      active_tab_background = hash p.brMagenta;
      active_tab_font_style = "bold";
      inactive_tab_foreground = "#d5c4a1";
      inactive_tab_background = hash p.bg;
      inactive_tab_font_style = "normal";
      tab_activity_symbol = ''" ● "'';
      # The quotes are part of the VALUE, not Nix syntax — kitty needs them to
      # keep the template as one token.
      tab_title_template = ''"{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{title[:30]}{title[30:] and '…'} [{index}]"'';
      active_tab_title_template = ''"{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{title[:30]}{title[30:] and '…'} [{index}]"'';
    };
  };

  # foot. The `[colors-dark]` section name is carried over verbatim from
  # home/foot/gruvbox-colors.ini rather than flattened to `[colors]` — that is
  # what the machine runs today, and this pass is meant to change ownership,
  # not appearance.
  programs.foot = {
    enable = true;
    settings = {
      main = {
        shell = "zsh";
        title = "foot";
        font = "Hack Nerd Font Mono:size=11";
        letter-spacing = 0;
        dpi-aware = "no";
        pad = "20x15";
        bold-text-in-bright = "no";
        gamma-correct-blending = "no";
      };

      scrollback.lines = 10000;

      cursor = {
        style = "beam";
        beam-thickness = "1.5";
      };

      colors-dark = {
        foreground = p.fg;
        background = p.bg;
        selection-foreground = p.fg;
        selection-background = p.selBg;

        regular0 = p.black;
        regular1 = p.red;
        regular2 = p.green;
        regular3 = p.yellow;
        regular4 = p.blue;
        regular5 = p.magenta;
        regular6 = p.cyan;
        regular7 = p.white;

        bright0 = p.brBlack;
        bright1 = p.brRed;
        bright2 = p.brGreen;
        bright3 = p.brYellow;
        bright4 = p.brBlue;
        bright5 = p.brMagenta;
        bright6 = p.brCyan;
        bright7 = p.brWhite;
      };

      key-bindings = {
        scrollback-up-page = "Page_Up";
        scrollback-down-page = "Page_Down";
        search-start = "Control+Shift+f";
      };

      search-bindings = {
        cancel = "Escape";
        find-prev = "Shift+F3";
        find-next = "F3 Control+G";
      };
    };
  };

  # ==========================================================================
  # Editors
  # ==========================================================================

  # nvim is the editor; helix was removed 2026-08-17 (docs/adr/0027). Nothing
  # here generates nvim config — it is a store-linked tree, see dotfiles.nix.

  # zed. This one is a straight WIN over the file it replaces, and the reason is
  # worth knowing because it is the technique to reach for elsewhere.
  #
  # dotfiles.nix pinned zed/settings.json as a read-only store file, so Zed's
  # own settings UI could not write to it at all. This module does not link a
  # file: it runs an activation script (`entryAfter [ "linkGeneration" ]`, so
  # after the old symlink is cleaned up) that merges the Nix-declared settings
  # INTO the real, writable ~/.config/zed/settings.json with
  # `jq -n '$dynamic * $static'`. Static wins on conflict.
  #
  # So Zed stays free to persist its own state, while everything declared here
  # is reasserted on every rebuild. Declarative config and a writable file are
  # not actually in tension — that framing was an artefact of only having
  # symlinks to work with.
  programs.zed-editor = {
    enable = true;

    # Zed ships some schemes and not others, so the list comes from the theme
    # file: Gruvbox is built in and declares `[ ]`; Catppuccin and Nord are
    # extensions. Declared here so the theme named in `userSettings.theme` below
    # can actually resolve.
    extensions = p.apps.zed.extensions;

    userSettings = {
      project_panel.dock = "left";
      outline_panel.dock = "left";
      collaboration_panel.dock = "left";
      git_panel.dock = "left";

      agent = {
        dock = "right";
        favorite_models = [ ];
        model_parameters = [ ];
      };

      # MCP agent servers. `type = "registry"` means Zed resolves the command
      # itself; the binaries still have to be on PATH (packages.nix).
      agent_servers = {
        opencode.type = "registry";
        claude-acp.type = "registry";
        github-copilot-cli.type = "registry";
      };

      telemetry = {
        diagnostics = false;
        metrics = false;
      };

      icon_theme = {
        mode = "system";
        light = "Zed (Default)";
        dark = "JetBrains New UI Icons (Dark)";
      };

      # A theme name Zed cannot resolve leaves it on One Dark and logs nothing —
      # the usual shape. Zed installs extensions on first launch, so the very
      # first start after a scheme change may show the fallback until it
      # finishes.
      #
      # THE ONE PAIR NO CHECK HERE CAN GATE. Both halves live in Zed's own
      # registry: `checks/static.sh` can assert the theme file names an
      # extension and a theme, but not that Zed resolves either. Verify by
      # output after a scheme change — open Zed and look.
      theme = {
        mode = "system";
        light = p.apps.zed.light;
        dark = p.apps.zed.dark;
      };

      buffer_font_family = "Hack Nerd Font Mono";
      buffer_font_size = 16.0;
      ui_font_size = 16;
      vim_mode = true;
      base_keymap = "VSCode";
    };
  };

  # ==========================================================================
  # TUI tools
  # ==========================================================================

  # htop.
  #
  # Two things dropped from the old htoprc on purpose:
  #
  #   `htop_version=3.5.1-1.1-arch` — a stale Arch build string, and htop only
  #   ever writes it, never reads it as configuration.
  #
  #   the `screen:Main=` / `screen:I/O=` blocks — these restate htop's own
  #   defaults (screen:Main's column list is byte-identical to the `fields=`
  #   line below), and they are ORDER-SENSITIVE: each `.sort_key`-style line
  #   binds to the `screen:` above it, while the module emits settings sorted
  #   by attribute name. Expressing them here would reorder them and break the
  #   association. Omitted, htop falls back to exactly these defaults.
  #
  # htop rewrites htoprc when you change settings in its UI, and the generated
  # file is read-only, so those changes will not persist. That is unchanged
  # from today — dotfiles.nix already pinned htoprc as a store file.
  programs.htop = {
    enable = true;
    settings = {
      fields = with config.lib.htop.fields; [
        PID
        USER
        PRIORITY
        NICE
        M_VIRT
        M_RESIDENT
        M_PRIV
        STATE
        PERCENT_CPU
        PERCENT_MEM
        TIME
        COMM
      ];

      hide_kernel_threads = true;
      hide_userland_threads = false;
      hide_running_in_container = false;
      shadow_other_users = false;
      show_thread_names = false;
      show_program_path = true;
      highlight_base_name = false;
      highlight_deleted_exe = true;
      shadow_distribution_path_prefix = false;
      highlight_megabytes = true;
      highlight_threads = true;
      highlight_changes = false;
      highlight_changes_delay_secs = 5;
      find_comm_in_cmdline = true;
      strip_exe_from_cmdline = true;
      show_merged_command = false;
      header_margin = true;
      screen_tabs = true;
      detailed_cpu_time = false;
      cpu_count_from_one = false;
      show_cpu_smt_labels = false;
      show_cpu_usage = true;
      show_cpu_frequency = false;
      show_cpu_temperature = false;
      degree_fahrenheit = false;
      show_cached_memory = true;
      update_process_names = false;
      account_guest_in_cpu_meter = false;
      color_scheme = 0;
      enable_mouse = true;
      delay = 15;
      hide_function_bar = 0;
      header_layout = "two_50_50";

      tree_view = false;
      sort_key = config.lib.htop.fields.PERCENT_CPU;
      tree_sort_key = config.lib.htop.fields.PID;
      sort_direction = -1;
      tree_sort_direction = 1;
      tree_view_always_by_pid = false;
      all_branches_collapsed = false;
    }
    # Meter modes: `bar` is htop mode 1, `text` is mode 2 — the old file's
    # `column_meter_modes_0=1 1 1` / `..._1=1 2 2 2`.
    // (
      with config.lib.htop;
      leftMeters [
        (bar "LeftCPUs2")
        (bar "Memory")
        (bar "Swap")
      ]
    )
    // (
      with config.lib.htop;
      rightMeters [
        (bar "RightCPUs2")
        (text "Tasks")
        (text "LoadAverage")
        (text "Uptime")
      ]
    );
  };

  # yazi. The flavor is a `.yazi` package directory, which is what the `flavors`
  # option takes — so it is assembled in the overlay from upstream's own file
  # rather than transcribed. 916 lines of third-party hex, and not ours to edit.
  programs.yazi = {
    enable = true;

    # The `y` wrapper — run yazi, then cd to wherever it exited. This used to be
    # a hand-written `y()` in zsh/conf.d/10-aliases.zsh while home-manager
    # separately emitted its own `yy()` into ~/.zshrc: two near-identical
    # definitions of one function, coexisting only because their names happened
    # to differ. home-manager is changing this default from `yy` to `y`, which
    # would have made them collide, with the winner decided by source order
    # (conf.d is sourced last, so the hand-written one would have won silently).
    # Set explicitly, and deleted from 10-aliases.zsh — one owner.
    shellWrapperName = "y";

    # `scheme`, not the scheme's name: the flavor package follows
    # modules/home/scheme.nix, so a name here would be wrong four schemes out of
    # five — the same reason Equibop's generated theme file is `scheme.theme.css`.
    flavors.scheme = pkgs.themeYazi;
    theme.flavor = {
      dark = "scheme";
      light = "scheme";
    };
  };

  # ncspot. Only the theme was ever configured.
  #
  # Worth noting what this conversion fixes: ncspot writes `userstate.cbor`
  # next to its config, which is why dotfiles.nix had to pin config.toml as a
  # single FILE to keep the directory writable (docs/adr/0003). The module does
  # the same thing for the same reason, so the workaround is now upstream's
  # problem rather than a local special case.
  #
  # The colours are the `muted` set from palette.nix, not hex typed here — see
  # that file for why a desaturated variant is still palette data.
  programs.ncspot = {
    enable = true;
    settings.theme =
      let
        m = p.muted;
      in
      {
        background = hash m.bg;
        primary = hash m.fg;
        secondary = hash m.dim;
        title = hash m.accent;
        playing = hash m.ok;
        playing_selected = hash m.ok;
        playing_bg = hash m.surface;
        highlight = hash m.overlay;
        # `highlight_fg` / `error_fg`, not `highlight_bg` / `error`. ncspot
        # ignores keys it does not recognise without complaining, so a renamed
        # key here is a colour that silently reverts to the default.
        highlight_fg = hash m.fg;
        error_bg = hash m.err;
        error_fg = hash m.fg;
        statusbar_progress = hash m.accent;
        statusbar_progress_bg = hash m.overlay;
        statusbar = hash m.fg;
        statusbar_bg = hash m.surface;
        cmdline = hash m.fg;
        cmdline_bg = hash m.surface;
        search_match = hash m.accent;
        border = hash m.overlay;
      };
  };

  # imv. The palette's lightest foreground as the background, so black SVGs and
  # icons stay visible.
  programs.imv = {
    enable = true;
    settings.options.background = p.fg;
  };

  # ==========================================================================
  # Lock screen
  # ==========================================================================

  # The ONE swaylock config. Every hands-off lock path goes through
  # `lockscreen -f` — swayidle on sleep, wlogout, the binds — and that wrapper
  # execs swaylock, so they all still read this file. It replaces the per-mode
  # mango/{tiling,hud}/swaylock.conf pair, and an untracked hand-written
  # ~/.config/swaylock/config that had been quietly supplying the theme.
  #
  # In `noctalia` mode the wrapper hands the lock to noctalia first and this is
  # the fallback (docs/adr/0024); in tiling and hud it is still the lock screen.
  #
  # `image` is deliberately NOT set here: the wrapper passes `-i` per lock so
  # the pattern varies (docs/adr/0018). `color` stays as the fallback for when
  # the pool is empty.
  #
  # `package = null` is load-bearing: desktop.nix installs swaylock-EFFECTS
  # system-wide and PAM is declared for it. Plain `swaylock` from home-manager
  # would shadow it in PATH and does not have `clock` — which it reports by
  # dumping usage and exiting 0. See docs/gotchas.md for the parse check.
  programs.swaylock = {
    enable = true;
    package = null;

    settings = {
      # A swaylock screen with nothing drawn on it is indistinguishable from a
      # machine that is off or hung. The clock ticks, which is the proof of
      # life; the ring is where typing shows up. Both are swaylock-effects
      # extensions — plain swaylock has neither.
      clock = true;
      indicator = true;
      indicator-idle-visible = true;
      timestr = "%H:%M";
      datestr = "%a %e %b";

      indicator-caps-lock = true;
      show-failed-attempts = true;

      # Colours come from palette.nix, not from hex typed here. Two of them did
      # not: the ring and the keypress highlight were gruvbox ORANGE (d65d0e,
      # fe8019), a shade this machine uses nowhere else, so the lock screen was
      # the one surface whose accent disagreed with the bar, the menus and the
      # window borders — and a drifted palette looks deliberate. `opaque` and
      # `wash` spell the two alpha values the indicator needs.
      color = opaque p.bg0;
      # The pool is generated at the panel's native 1920x1200, so `fill` scales
      # by exactly 1 and the block edges stay hard. swaylock resamples with
      # CAIRO_FILTER_BILINEAR, so an external output at another resolution gets
      # a softened copy — cosmetic, and only on that output.
      scaling = "fill";
      font = "Hack Nerd Font Mono";
      # Sized to the indicator, not to the screen: this is also the "Verifying"
      # and "Wrong" text, which has to fit inside the ring.
      font-size = 20;
      indicator-radius = 100;
      indicator-thickness = 7;

      inside-color = wash p.bg0;
      inside-clear-color = wash p.bg0;
      inside-ver-color = wash p.blue;
      inside-wrong-color = wash p.errColor;

      ring-color = opaque p.accent;
      ring-clear-color = opaque p.okColor;
      ring-ver-color = opaque p.blue;
      ring-wrong-color = opaque p.errColor;

      key-hl-color = opaque p.warnColor;
      bs-hl-color = opaque p.errColor;

      text-color = opaque p.text;
      text-clear-color = opaque p.text;
      text-ver-color = opaque p.infoColor;
      text-wrong-color = opaque p.errColor;
      text-caps-lock-color = opaque p.warnColor;

      # Fully transparent — the ring carries the state, the lines only add
      # edges to it.
      line-color = "00000000";
      line-clear-color = "00000000";
      line-ver-color = "00000000";
      line-wrong-color = "00000000";
      separator-color = "00000000";
    };
  };

  # ==========================================================================
  # Session menu
  # ==========================================================================

  # wlogout.
  #
  # THE ICON PATHS ARE THE WHOLE DIFFICULTY HERE, and getting them wrong
  # reproduces a bug this repo has already had once.
  #
  # home/wlogout/style.css referenced its five PNGs RELATIVELY
  # (`url("icons/lock.png")`), which worked because GTK resolves CSS url()
  # against the stylesheet's own path and dotfiles.nix linked the whole
  # directory, icons included. This module does not link a directory: it
  # renders `style` into a standalone file in the store, so a relative url()
  # would resolve next to that lone .css and find nothing.
  #
  # GTK draws its missing-image box for a failed url() WITHOUT logging
  # anything, so the failure is invisible in the journal — it was originally
  # reported as "the icons are just square boxes".
  #
  # Fixed by interpolating each PNG's own store path into the CSS. Nix copies
  # each file into the store individually and substitutes an absolute path, so
  # there is no directory for the reference to be relative to. This is the one
  # kind of absolute path that is safe here: it is computed at build time and
  # cannot go stale, unlike the `/usr/share/wlogout/icons/` paths these
  # replaced.
  programs.wlogout = {
    enable = true;

    layout = [
      {
        label = "lock";
        action = "${pkgs.lockscreen}/bin/lockscreen -f";
        text = "Lock";
        keybind = "l";
      }
      {
        label = "logout";
        action = "loginctl terminate-user $USER";
        text = "Logout";
        keybind = "e";
      }
      {
        label = "suspend";
        action = "systemctl suspend";
        text = "Suspend";
        keybind = "u";
      }
      # Same S4 the lid and the power key reach; here for discoverability.
      {
        label = "hibernate";
        action = "systemctl hibernate";
        text = "Hibernate";
        keybind = "h";
      }
      {
        label = "reboot";
        action = "systemctl reboot";
        text = "Reboot";
        keybind = "r";
      }
      {
        label = "shutdown";
        action = "systemctl poweroff";
        text = "Shutdown";
        keybind = "s";
      }
    ];

    style = ''
      * {
          background-image: none;
          box-shadow: none;
          font-family: "3270 Nerd Font", monospace;
          font-weight: bold;
      }

      window {
          background-color: rgba(32, 27, 20, 0.88);
      }

      /* padding/margin are deliberately small — the button is sized by the
         wlogout margins in waybar.nix, and these only add dead space to it. */
      button {
          font-size: 20px;
          color: #7a6a50;
          background-color: rgba(46, 39, 32, 0.8);
          border: 2px solid rgba(61, 53, 44, 1.0);
          border-radius: 10px;
          margin: 8px;
          padding: 8px;
          background-repeat: no-repeat;
          background-position: center 30%;
          background-size: 52px 52px;
          transition: background-color 0.15s ease, color 0.15s ease, border-color 0.15s ease;
      }

      button:hover {
          background-color: rgba(61, 53, 44, 0.9);
          border-color: #c9b890;
          color: #c9b890;
      }

      button:active {
          background-color: #c9b890;
          color: #201b14;
      }

      #lock {
          background-image: image(url("${../../dotfiles/wlogout/icons/lock.png}"));
      }

      #logout {
          background-image: image(url("${../../dotfiles/wlogout/icons/logout.png}"));
      }

      #suspend {
          background-image: image(url("${../../dotfiles/wlogout/icons/suspend.png}"));
      }

      #hibernate {
          background-image: image(url("${../../dotfiles/wlogout/icons/hibernate.png}"));
      }

      #reboot {
          background-image: image(url("${../../dotfiles/wlogout/icons/reboot.png}"));
      }

      #shutdown {
          background-image: image(url("${../../dotfiles/wlogout/icons/shutdown.png}"));
      }
    '';
  };
}
