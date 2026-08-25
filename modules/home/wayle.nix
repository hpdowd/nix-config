# Wayle — the tiling mode's bar, generated from one shared set of module
# definitions. It replaced waybar there; noctalia mode still runs its own shell
# and neither bar. docs/adr/0045.
#
# SIX FILES, and `config.toml` is not one of them. `services.wayle.settings`
# stays `{ }` deliberately: the home-manager module claims
# `xdg.configFile."wayle/config.toml"` the moment it holds one value, and that
# path is re-pointed at runtime by scripts/wayle/wayle-restart.sh. Two owners
# for one path is an activation failure, not a merge — the same reason
# `programs.ncspot.settings` is empty (docs/adr/0034). `checks/static.sh`
# asserts the path is absent from the generation.
#
# A layout is a list of names; a name with no definition is an EVAL ERROR
# rather than a module that renders as nothing. That is the whole reason these
# are generated — docs/adr/0009.
{
  lib,
  pkgs,
  ...
}:

let
  s = "~/.config/mango/scripts";

  # The shared palette. wayle resolves its own colour names internally, so this
  # is the one place this machine's palette meets wayle's vocabulary — the same
  # mapping waybar/colors.css makes, spelled out rather than iterated so a
  # renamed role breaks the build here.
  p = import ./palette.nix;

  palette = {
    bg = "#${p.base}";
    surface = "#${p.surface}";
    elevated = "#${p.overlay}";
    fg = "#${p.text}";
    fg-muted = "#${p.subtext}";
    primary = "#${p.accent}";
    red = "#${p.errColor}";
    yellow = "#${p.warnColor}";
    green = "#${p.okColor}";
    blue = "#${p.infoColor}";
  };

  # ── Custom modules — one copy each ────────────────────────────────────────
  #
  # WAYLE HAS NO SIGNAL IPC. waybar took a push (`pkill -RTMIN+N waybar`) from
  # the script that changed the state; wayle offers `poll`, `watch` and
  # `on-action` and nothing else. So each of these carries BOTH:
  #
  #   on-action    the click path — immediate, no wait for the next tick
  #   interval-ms  the everything-else path, because these states also change
  #                from a keybind and from the control centre, and a module
  #                that only updated on its own click would sit there lying
  #
  # The `pkill -RTMIN+N waybar` lines came out of the five scripts in the same
  # change: a pkill that matches nothing is this repo's signature failure.
  #
  # Output parsing: wayle reads stdout, and treats it as JSON when it starts
  # with `{`. These scripts already emit waybar's `{text,tooltip,class}`, so
  # they are reused UNCHANGED and the templates below name those fields.
  customModules = [
    {
      id = "weather";
      # Not wayle's native `weather`: this script owns a cache the control
      # centre reads, and one request carries the tooltip. docs/adr/0038, 0044.
      command = "${s}/system/weather.sh status";
      interval-ms = 300000;
      format = "{{ text }}";
      tooltip-format = "{{ tooltip }}";
      class-format = "{{ class }}";
      left-click = "${s}/system/weather.sh refresh";
      # The tooltip is a reading, not a forecast site. Right-click is the way
      # out to one, and the verb is the script's so the bar holds no URL.
      right-click = "${s}/system/weather.sh open";
      on-action = "${s}/system/weather.sh status";
    }
    {
      id = "vpn";
      command = "${s}/menus/vpn.sh";
      interval-ms = 5000;
      format = "{{ text }}";
      tooltip-format = "{{ tooltip }}";
      class-format = "{{ class }}";
      left-click = "${s}/menus/vpn.sh toggle";
      right-click = "${s}/menus/vpn-menu.sh";
      on-action = "${s}/menus/vpn.sh";
    }
    {
      id = "phone";
      # `bar`, NOT the bare call the control centre makes: `hide-if-empty` tests
      # this command's OUTPUT, and `status` answers with a JSON object carrying
      # an empty `.text`, which is not empty. The pair is the only reason the
      # verb exists. Resting state is an unreachable phone, which is most of the
      # time — and was 10px of dead bar between bluetooth and the divider,
      # reported as bluetooth's padding. docs/gotchas.md -> Wayle.
      command = "${s}/kdeconnect/phone-status.sh bar";
      interval-ms = 30000;
      hide-if-empty = true;
      format = "{{ text }}";
      tooltip-format = "{{ tooltip }}";
      class-format = "{{ class }}";
      # A verb, not `kdeconnect-cli -d <id> --ring`: the device ID belongs in
      # the script that already holds it.
      left-click = "${s}/kdeconnect/phone-status.sh ring";
      right-click = "kdeconnect-cli --refresh";
      on-action = "${s}/kdeconnect/phone-status.sh bar";
    }
    {
      id = "night-mode";
      # `interval = "once"` under waybar — it updated by signal ALONE. Without
      # a signal path that spelling would freeze the widget at whatever it read
      # at startup, which is why this one has a real interval now.
      command = "${s}/menus/night-mode.sh status";
      interval-ms = 5000;
      format = "{{ text }}";
      tooltip-format = "{{ tooltip }}";
      class-format = "{{ class }}";
      left-click = "${s}/menus/night-mode.sh toggle";
      right-click = "${s}/menus/night-mode.sh menu";
      on-action = "${s}/menus/night-mode.sh status";
    }
    {
      id = "power-profile";
      command = "${s}/system/power-profile.sh";
      interval-ms = 30000;
      format = "{{ text }}";
      tooltip-format = "{{ tooltip }}";
      class-format = "{{ class }}";
      left-click = "${s}/system/power-profile-cycle.sh";
      right-click = "${s}/system/power-profile-cycle.sh toggle-fanless";
      on-action = "${s}/system/power-profile.sh";
    }
    {
      id = "idle-inhibitor";
      # Reads the wlinhibit UNIT, which is the owner — not a bool the bar
      # holds. That is the whole of docs/adr/0031: waybar's built-in module
      # kept the state in the bar process and released it on every reload.
      command = "${s}/system/idle-inhibit.sh status";
      interval-ms = 30000;
      format = "{{ text }}";
      tooltip-format = "{{ tooltip }}";
      class-format = "{{ class }}";
      left-click = "${s}/system/idle-inhibit.sh toggle";
      on-action = "${s}/system/idle-inhibit.sh status";
    }
    {
      id = "power";
      # A custom module, not wayle's native `power`: a native module's click
      # takes an ACTION string (`dropdown:…`), not a shell command, and the
      # session verbs live on `dashboard` rather than `power`. wlogout is what
      # this machine already uses, with the same geometry waybar passed.
      #
      # `-b` is a column count: keep it equal to the wlogout entry count in
      # programs.nix, or the overflow wraps into a row the margins leave no
      # room for.
      icon-name = "ld-power-symbolic";
      label-show = false;
      left-click = "wlogout -b 6 -c 12 -r 12 -T 505 -B 505 -L 290 -R 290 --protocol layer-shell";
      right-click = "dropdown:notification";
    }
    {
      id = "control-center";
      # One entry point to everything the minimal layout drops. No command: it
      # is a button, so it renders its icon and nothing polls.
      icon-name = "ld-layout-dashboard-symbolic";
      label-show = false;
      left-click = "${s}/menus/shell.sh control-center";
    }
  ];

  customIds = map (m: "custom-${m.id}") customModules;

  # ── One colour ────────────────────────────────────────────────────────────
  # wayle gives every module its OWN semantic colour: clock `accent`, battery
  # `yellow`, notifications `green`, network `red`, bluetooth `blue`. With the
  # flat `basic` variant those `label-color`s show through raw, so the bar was
  # sixteen colours competing and none of them meaning anything.
  #
  # Everything reads in one pair. Colour is then RESERVED for state — the
  # battery thresholds below, and the active workspace — so a coloured thing on
  # this bar is a thing worth looking at.
  mono = {
    icon-color = "fg-muted";
    label-color = "fg-default";
  };

  # `icon-show` DEFAULTS TRUE, and a custom module with no `icon-name` still
  # gets its icon widget — 22px of nothing wedged between two modules. Every
  # script above emits its own glyph in the text, so that slot is only ever
  # empty. Derived from the definition so a new module cannot forget it.
  # docs/gotchas.md -> Wayle.
  monoCustom = map (m: mono // { icon-show = m ? icon-name; } // m) customModules;

  # ── Native module settings ────────────────────────────────────────────────
  #
  # Only where this machine differs from wayle's default. `mango-workspaces` is
  # wayle's OWN module — waybar needed `ext/workspaces` plus a custom layout
  # readout, and this half is native.
  # Every native module a layout can carry, so `mono` reaches all of them with
  # nothing to remember when one is added. lib.recursiveUpdate below lets the
  # per-module settings override a colour where state needs one.
  # NOT mango-workspaces or systray: neither takes icon-color/label-color.
  # Workspaces colours by tag STATE below, and the tray draws other apps'
  # icons, which are theirs. wayle's schema rejects the keys, so this is
  # asserted rather than remembered.
  nativeNames = [
    "clock"
    "media"
    "window-title"
    "notifications"
    "cpu"
    "ram"
    "network"
    "bluetooth"
    "volume"
    "brightness"
    "battery"
  ];

  moduleSettings = lib.recursiveUpdate (lib.genAttrs nativeNames (_: mono)) {
    # No `tooltip-format`: wayle has no such key on clock — the calendar is a
    # DROPDOWN (`left-click = "dropdown:calendar"`, its default), not a tooltip.
    clock = {
      format = "%H:%M";
      # No icon, as waybar's clock has none.
      icon-show = false;
    };

    # WAYLE IS THE NOTIFICATION DAEMON IN THIS MODE. It claims
    # org.freedesktop.Notifications, so swaync must be dead before it starts —
    # the second claimant of a D-Bus name does not error, it just never
    # receives one. tiling/autostart.conf does that, in the order
    # noctalia-start.sh already uses for the same handover. docs/adr/0005, 0045.
    notifications = {
      popup-position = "top-right";
      popup-duration = 5000;
      popup-monitor = "primary";
      popup-layer = "overlay";
    };

    # ── Icons that read as solid ──────────────────────────────────────────
    # wayle's 361 bundled icons are outline, including its Material battery
    # ladder. Two ways round it, no new dependency: the glyph in `format` where
    # the module has no state beyond its number, and a freedesktop name the
    # icon theme already answers — Adwaita's filled symbolics, Papirus's
    # two-tone `battery-level-*`. A native `format` sees only `{{ percent }}`,
    # which is why `volume` and `battery` keep their icon widget — `icon-muted`
    # and `charging-icon` are the only way those states show.
    # docs/gotchas.md -> Wayle. checks/static.sh resolves every name.
    cpu = {
      icon-show = false;
      format = " {{ percent }}%";
    };

    ram = {
      icon-show = false;
      format = " {{ percent }}%";
    };

    volume = {
      level-icons = [
        "audio-volume-low-symbolic"
        "audio-volume-medium-symbolic"
        "audio-volume-high-symbolic"
      ];
      icon-muted = "audio-volume-muted-symbolic";
    };

    # One icon, not a ladder: Adwaita ships a single brightness symbolic, and a
    # one-element array is how `level-icons` says "the same at every level".
    brightness.level-icons = [ "display-brightness-symbolic" ];

    # Icon only. `disconnected-icon` and `connected-icon` already carry the
    # state, so the label was the word "Disconnected" sitting on the bar
    # whenever nothing was paired — which is most of the time.
    bluetooth.label-show = false;

    # The one place accent survives: the active tag is state.
    mango-workspaces = {
      hide-empty = true;
      display-mode = "label";
      # 0.8 puts the active tag block at 34px, waybar's width.
      tag-padding = 0.8;
      icon-gap = 0.15;
      # A separate scale from `button-label-size`, which does not reach tags.
      label-size = 0.85;
      active-color = "accent";
      occupied-color = "fg-default";
      empty-color = "fg-subtle";
    };

    # SHORTER THAN WAYBAR'S 60/40. wayle centres `window-title` on the BAR,
    # not in the space left over, so a long title and a long track name grow
    # toward each other and overlap — observed with a media label and a title
    # both near their caps. waybar packed the three sides instead and could not
    # do this.
    window-title = {
      label-max-length = 45;
    };

    media = {
      label-max-length = 25;
    };

    # NOT in `nativeNames`, so this gets no `mono` — the tray draws other apps'
    # icons and wayle rejects the colour keys on it. `internal-padding` is
    # padding at the ENDS of the tray container, on top of the module's own.
    systray = {
      icon-scale = 0.85;
      internal-padding = 0.1;
    };

    # `thresholds`, not waybar's warning-level/critical-level — wayle has no
    # such keys. Matches upower's ACTION thresholds rather than offering a
    # second opinion on them: waybar warned at 30/15 while upower acted at
    # 20/5, so the colour change marked nothing. checks/static.sh asserts the
    # two still agree.
    # Adwaita's ladder, NOT wayle's bundled `md-battery_android_*` — which these
    # three keys restated verbatim, so they were the default written out.
    # Material's is a 1px frame with a fill bar inside and reads as line art
    # beside bold text.
    #
    # `adw-`, not the bare `battery-level-*` name: that one belongs to
    # freedesktop, so the ICON THEME answers it and Papirus's eleven rungs all
    # render as the same solid battery. pkgs/default.nix carries the mechanism;
    # `adwaitaBatteryIcons` in `home.packages` below carries the files.
    #
    # Eleven, because the ladder is 0-100 in tens and wayle divides the range
    # evenly among however many it is given. docs/gotchas.md -> Wayle.
    battery.level-icons = [
      "adw-battery-level-0-symbolic"
      "adw-battery-level-10-symbolic"
      "adw-battery-level-20-symbolic"
      "adw-battery-level-30-symbolic"
      "adw-battery-level-40-symbolic"
      "adw-battery-level-50-symbolic"
      "adw-battery-level-60-symbolic"
      "adw-battery-level-70-symbolic"
      "adw-battery-level-80-symbolic"
      "adw-battery-level-90-symbolic"
      "adw-battery-level-100-symbolic"
    ];
    # One charging icon is all wayle takes, so it is Adwaita's EMPTY-charging
    # art — a frame with a bolt. Every levelled spelling claims a charge the
    # label beside it contradicts.
    battery.charging-icon = "adw-battery-charging-symbolic";
    battery.alert-icon = "adw-battery-missing-symbolic";

    battery.thresholds = [
      {
        below = 20;
        icon-color = "status-warning";
        label-color = "status-warning";
      }
      {
        below = 5;
        icon-color = "status-error";
        label-color = "status-error";
      }
    ];

  };

  # ── The bar, once ─────────────────────────────────────────────────────────
  #
  # ONE ordered list per side; the three layouts are SUBTRACTIONS from it. Group
  # order is then the same in all three by construction — a layout can drop a
  # group or a module and cannot reposition one, so the picker moves nothing
  # that two layouts share. Three hand-written trees made that an invariant a
  # plausible edit broke in silence, and carried three copies of these comments.
  #
  # A group is wayle's own BarGroup: a shared container with `#<name>` as its
  # CSS id. The divider between two is a `border-left` in
  # dotfiles/wayle/index.scss, not a `separator` module — one of those sits
  # outside any group, where nothing in the sheet can reach its padding.
  # docs/adr/0042, docs/adr/0045.
  #
  # `wlr/taskbar` has NO wayle equivalent and is dropped rather than faked;
  # `full` carried it and nothing else did.
  barSides = {
    left = [
      # Time and weather are one reading of "what is it like now".
      {
        name = "time";
        modules = [
          "clock"
          "custom-weather"
        ];
      }
      {
        name = "workspaces";
        # The tag row alone. The layout-symbol readout was dropped 2026-08-25:
        # SUPER+n switches the layout (universal/bind.conf) and the symbol was
        # not worth a module.
        modules = [ "mango-workspaces" ];
      }
      {
        name = "playing";
        modules = [ "media" ];
      }
    ];
    center = [
      {
        name = "focus";
        modules = [ "window-title" ];
      }
    ];
    right = [
      {
        name = "notify";
        modules = [ "notifications" ];
      }
      {
        name = "load";
        modules = [
          "cpu"
          "ram"
        ];
      }
      # custom-phone is KDE Connect, so it belongs with the radios rather than
      # beside the battery it happens to report.
      {
        name = "radios";
        modules = [
          "network"
          "custom-vpn"
          "bluetooth"
          "custom-phone"
        ];
      }
      {
        name = "output";
        modules = [
          "volume"
          "brightness"
          "custom-night-mode"
        ];
      }
      # One group, as waybar has it. Battery sat in its own until 2026-08-25,
      # back when the within-group gap was 3px and a boundary was the only way
      # to hold the power profile off the battery icon. At waybar's 10px it is
      # the boundary that reads as too much.
      {
        name = "power";
        modules = [
          "custom-idle-inhibitor"
          "custom-power-profile"
          "battery"
        ];
      }
      {
        name = "tray";
        modules = [
          "custom-control-center"
          "systray"
        ];
      }
      {
        name = "session";
        modules = [ "custom-power" ];
      }
    ];
  };

  # What each layout takes OUT. `full` is the list above; the other two name
  # only their difference from it, which is the whole point of the shape.
  #
  #   focus    the daily layout. Drops the cpu/ram and phone readouts. Weather
  #            STAYS — it is ambient rather than diagnostic, and leaving it out
  #            parked the control-centre row at `stale` as its DEFAULT (0038).
  #   minimal  deliberately near-empty. The control-centre button is the way in
  #            to everything it drops, weather included (0038).
  layoutCuts = {
    full = { };
    focus = {
      groups = [ "load" ];
      modules = [ "custom-phone" ];
    };
    minimal = {
      groups = [
        "notify"
        "load"
        "radios"
        "output"
      ];
      # `power` STAYS, emptied down to the battery — it is the group battery
      # lives in now, so dropping it would drop the battery with it.
      modules = [
        "custom-weather"
        "custom-idle-inhibitor"
        "custom-power-profile"
      ];
    };
  };

  # A cut applied: drop the named groups, drop the named modules from what is
  # left, then drop any group the second step emptied.
  cut =
    {
      groups ? [ ],
      modules ? [ ],
    }:
    side:
    lib.filter (g: g.modules != [ ]) (
      map (g: g // { modules = lib.subtractLists modules g.modules; }) (
        lib.filter (g: !(lib.elem g.name groups)) side
      )
    );

  # Every name a layout may carry. Derived from `nativeNames`, so a native
  # module added there is legal here without being spelled twice.
  knownModules =
    customIds
    ++ nativeNames
    ++ [
      "mango-workspaces"
      "systray"
    ];

  # wayle's BarItem is `{ module, class }`, and `class` is the ONLY per-module
  # handle the bar has — wayle names no widget after its module, so `#clock`
  # matches nothing. One class, never a list: GTK's `add_css_class` rejects a
  # name containing a space, so `"mod mod-clock"` is dropped whole.
  #
  # That one slot buys identity rather than a shared class. The shared rules sit
  # on wayle's own `.module`, which is the same widget — so `.mod-clock`,
  # `.mod-battery`, `.mod-custom-weather` are free for per-module spacing.
  # Prefixed because wayle's dropdowns already use bare `.battery`/`.bluetooth`.
  # docs/gotchas.md -> Wayle.
  classed = m: {
    module = m;
    class = "mod-${m}";
  };

  toGroup = g: g // { modules = map classed g.modules; };

  mkLayout =
    location: cuts:
    let
      sides = lib.mapAttrs (_: cut cuts) barSides;
      groups = sides.left ++ sides.center ++ sides.right;
      used = lib.unique (lib.concatMap (g: g.modules) groups);
      unknown = lib.subtractLists knownModules used;
      names = map (g: g.name) groups;
    in
    assert lib.assertMsg (
      lib.length (lib.unique names) == lib.length names
    ) "wayle: two groups share a name, and the name is a CSS id: ${lib.concatStringsSep ", " names}";
    assert lib.assertMsg (
      unknown == [ ]
    ) "wayle: layout references undefined module(s): ${lib.concatStringsSep ", " unknown}";
    {
      # BOTH NAMES MUST RESOLVE. wayle falls back to its own default without a
      # word, so a font this machine does not have looks merely unstyled —
      # `Inter` was here and is not installed. These two are what waybar's CSS
      # asks for and what fonts.nix ships; checks/static.sh asserts they exist.
      general = {
        # TWO FAMILIES, Symbols FIRST — style-solid.css's stack. 3270's
        # advance is too narrow for the glyphs it patches in, so a glyph in a
        # label overflows and eats the space after it. `cpu` and `ram` print
        # theirs as text. docs/gotchas.md -> Wayle.
        font-sans = "Symbols Nerd Font Mono, 3270 Nerd Font";
        font-mono = "JetBrainsMono Nerd Font";
      };

      # ── Minimal ────────────────────────────────────────────────────────────
      # Flat: no button chips, no per-button borders, no group backgrounds. All
      # of those are on by default, and together they draw a box around every
      # module. Sizes are ScaleFactor multipliers, clamped 0.25-3.0.
      bar = {
        inherit location;
        scale = 1.0;
        exclusive = true;
        layer = "top";
        # `bg-base`, not wayle's default `bg-surface`: that token maps to bg1,
        # one step up the ramp from what waybar's `window#waybar` draws.
        bg = "bg-base";
        rounding = "none";
        shadow = "none";
        border-location = "none";

        # ZERO. This key is a margin on the SECTION, so any value insets every
        # module and the active workspace tag cannot reach the bar's edges.
        # index.scss carries the height instead. checks/static.sh asserts it.
        padding = 0.0;

        # `basic`, not the default `block-prefix`: that variant paints a filled
        # block behind each icon, which is most of what makes the default bar
        # look busy. `icon-square` is the other way and is heavier still.
        button-variant = "basic";
        button-bg-opacity = 0;
        button-border-location = "none";
        button-rounding = "none";

        # ── Horizontal spacing ────────────────────────────────────────────
        # These names do not mean what they read like, and two of the keys do
        # nothing. The table is in docs/gotchas.md -> Wayle; index.scss owns the
        # spacing that actually lands.
        #
        # `module-gap` and `button-group-module-gap` are written as 0 rather
        # than dropped: that is the value wanted if they start working.
        # `button-icon-padding` is inert BY DESIGN for this variant, so it is
        # not written at all.
        #
        # `button-gap` is the one gap key that works, and only for native
        # modules — the seven customs print their glyph in the text, where the
        # spacing is a space in the script's output. At the 0.25 ScaleFactor
        # floor a native icon touches its own text.
        button-gap = 0.6;
        module-gap = 0.0;
        button-group-module-gap = 0.0;
        button-label-padding = 0.25; # ScaleFactor floor — 0.2 is clamped to this silently
        padding-ends = 0.35; # 7px, + `.mod`'s 4px + wayle's 1px = waybar's 12px

        # wayle draws a button icon at 1.6rem against its label's 1.04rem, so
        # the default is 1.54x the bar's own text. One knob for the whole bar;
        # the seven customs print their glyph in the text and do not move.
        button-icon-size = 0.7;
        button-label-size = 1.0;
        # `bold`, as style-solid.css sets on `*`. wayle's default is
        # `semibold`.
        button-label-weight = "bold";

        # ── The grouping ──────────────────────────────────────────────────
        # The groups are wayle's own `BarGroup`s and they draw NOTHING here;
        # index.scss puts a `border-left` on each after the first.
        #
        # The block backgrounds were tried first and rejected: a filled box has
        # to hold padding off its contents to look like a box, so every group
        # boundary cost `button-group-padding` twice over. Useful once, for
        # showing exactly where that padding was.
        button-group-background = "transparent";
        button-group-opacity = 0;
        button-group-rounding = "none";
        button-group-border-location = "none";
        button-group-padding = 0.0;
        layout = [
          {
            monitor = "*";
            show = true;
            left = map toGroup sides.left;
            center = map toGroup sides.center;
            right = map toGroup sides.right;
          }
        ];
      };

      styling = {
        # `wayle`, NOT matugen/wallust/pywal: those derive colour from the
        # wallpaper, which is ungated by construction — every contrast floor in
        # checks/static.sh reads a generated file, and a wallpaper-derived
        # palette is written at runtime. Same objection as docs/adr/0036.
        theme-provider = "wayle";
        inherit palette;
      };

      modules = moduleSettings // {
        custom = monoCustom;
      };

      # tiling mode's wallpaper engine. noctalia manages its own in its mode —
      # docs/adr/0045 supersedes 0020's "wallpaper off (awww owns it)".
      wallpaper = {
        engine-enabled = true;
        transition-type = "left";
        transition-duration = 1.0;
      };
    };

  toToml = name: value: (pkgs.formats.toml { }).generate name value;

  # 3 layouts x 2 positions = 6 files, all statically known. The script only
  # picks a filename and re-points the link — the same shape waybar-restart.sh
  # had, and for the same reason: `bar.location` lives in the file, and wayle
  # takes no flag for it.
  layouts = lib.listToAttrs (
    lib.concatMap (name: [
      (lib.nameValuePair "${name}-top.toml" (mkLayout "top" layoutCuts.${name}))
      (lib.nameValuePair "${name}-bottom.toml" (mkLayout "bottom" layoutCuts.${name}))
    ]) (lib.attrNames layoutCuts)
  );
in
{
  services.wayle = {
    enable = true;

    # `{ }` IS THE DECLARATION. See this file's header: one value here claims
    # ~/.config/wayle/config.toml, which wayle-restart.sh owns as a link.
    settings = { };

    # The wallpaper engine needs awww, which this pulls in as `services.awww`.
    # It adds no theme-provider package because `theme-provider` is `wayle`.
    autoInstallDependencies = true;
  };

  # The battery ladder, and it has to be a PACKAGE rather than a name: the icon
  # theme answers `battery-level-*` first and Papirus's rungs are all the same
  # icon once GTK masks them. pkgs/default.nix says why. Here rather than in
  # packages.nix because the bar is its only consumer.
  home.packages = [ pkgs.adwaitaBatteryIcons ];

  # NEITHER UNIT MAY START AT LOGIN. The module wants both on
  # graphical-session.target, which runs in every mode — including noctalia,
  # which draws its own bar and manages its own wallpaper. Two bars and two
  # wallpaper layers, in a mode that asked for neither.
  #
  # `mkForce`, not a merge: the module SETS this list rather than defaulting
  # it. tiling/autostart.conf starts them; noctalia-start.sh stops them.
  systemd.user.services.wayle.Install.WantedBy = lib.mkForce [ ];
  systemd.user.services.awww.Install.WantedBy = lib.mkForce [ ];

  # config.toml is wayle-restart.sh's, and it must EXIST before the first start:
  # wayle with no config falls back to its built-in defaults and renders a bar
  # that is plausible and not this one — the silent half of the same failure
  # that is fatal in foot. Seeded to full/top, matching bar_layout() and
  # bar_position()'s fallbacks in lib.sh — one default, two readers.
  #
  # `[ -e ]` follows symlinks, so a dangling link is repaired too. Same shape as
  # mode-theme.nix's seedModeTheme, and for the same reason.
  home.activation.seedWayleConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    [ -e "$HOME/.config/wayle/config.toml" ] ||
      run ln -sfn "$HOME/.config/wayle/layouts/full-top.toml" \
        "$HOME/.config/wayle/config.toml"
  '';

  xdg.configFile =
    lib.mapAttrs' (
      name: value:
      lib.nameValuePair "wayle/layouts/${name}" {
        source = toToml "wayle-${lib.replaceStrings [ "." ] [ "-" ] name}" value;
      }
    ) layouts
    // {
      # The one colour index.scss needs, generated from the palette so the
      # divider cannot drift from the rest of the bar — the same split waybar has
      # with its generated colors.css beside a hand-written style-solid.css.
      # docs/adr/0028.
      "wayle/styles/_colors.scss".text = ''
        // GENERATED from modules/home/palette.nix — edit that, then rebuild.
        $sep: #${p.overlay};
      '';

      # The stylesheet. HAND-WRITTEN and store-based (tier 2): it is rules, not
      # settings, exactly as waybar's style-*.css is — docs/SYSTEM.md §6.
      #
      # SAFE TO CLAIM, unlike config.toml. wayle only SEEDS this file when it is
      # absent (it appeared the first time the shell ran) and never rewrites one
      # that exists, so a read-only link here has one owner rather than two.
      # config.toml is the opposite case and is left to wayle-restart.sh.
      "wayle/styles/index.scss".source = ../../dotfiles/wayle/index.scss;
    };
}
