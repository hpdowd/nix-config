# Waybar layouts, generated from one shared set of module definitions.
#
# There are four layouts and they differ only in which modules they carry, but
# they used to be four hand-maintained .jsonc files — so every module appeared
# up to four times and had to be edited in four places. They drifted anyway:
# the clock/title rearrangement on 2026-07-31 needed a manual re-sync pass, and
# an audit before this conversion still found `custom/window` carrying
# max-length 60 in two files and 80 in a third.
#
# Here each module is defined ONCE in `modules` below, and a layout is a list of
# names. `lib.genAttrs` then emits definitions for exactly the modules that
# layout uses — so an unused definition cannot linger, and more importantly a
# NAME THAT HAS NO DEFINITION IS AN EVAL ERROR rather than an empty module.
# That last part is the real win: this repo's signature bug is a waybar module
# that renders as nothing and reads as "missing from the bar" (see the exit-127
# scripts and the power-profile glyph in CLAUDE.md).
#
# The JSON and the palette are generated. `style-*.css` stay hand-written files
# because they are hand-tuned presentation, not settings, and transcribing them
# into Nix attrsets buys nothing but a chance of a silent typo. (yazi's flavor
# is the other file kept on that reasoning — docs/SYSTEM.md §6.)
#
# `colors.css` is the exception, and the line between them is worth stating:
# the style sheets are *rules*, colors.css was thirteen `@define-color` lines
# of pure *data* that also existed in modules/home/palette.nix and in rofi's
# theme. A palette that has drifted between three files looks deliberate —
# there is no way to tell a considered accent from a typo by looking at it —
# so this one is derived and the others are not.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  s = "~/.config/mango/scripts";

  # The shared palette, in GTK CSS spelling. `style-*.css` `@import` this and
  # refer to the names, so a colour is written once here and nowhere else.
  p = import ./palette.nix;

  # ── Module definitions — one copy each ────────────────────────────────────
  modules = {
    clock = {
      format = "{:%H:%M}";
      format-alt = "{:%a %d %b}";
      tooltip-format = "<tt>{calendar}</tt>";
    };

    "ext/workspaces" = {
      format = "{icon}";
      ignore-hidden = true;
      on-click = "activate";
      on-click-right = "deactivate";
      on-scroll-up = "mmsg dispatch viewtoleft_have_client";
      on-scroll-down = "mmsg dispatch viewtoright_have_client";
      sort-by-id = true;
      format-icons = {
        "1" = "1";
        "2" = "2";
        "3" = "3";
        "4" = "4";
        "5" = "5";
        "6" = "6";
        "7" = "7";
        "8" = "8";
        "9" = "9";
        default = " ";
        urgent = " ";
      };
    };

    # Was `mmsg -g -l | awk '{print $3}'` — dwl-era flags mango no longer takes.
    # mmsg answers an unknown command with {"error":"unknown command"} AND EXITS
    # 0, so this module has been rendering nothing and clicking it has done
    # nothing, silently. There is no `get layout` either; the layout symbol
    # lives on the monitor object. `switch_layout` is real — universal/bind.conf
    # binds it to SUPER+n.
    "custom/layout" = {
      exec = "mmsg get all-monitors | jq -r '.monitors[] | select(.active) | .layout_symbol'";
      interval = 1;
      on-click = "mmsg dispatch switch_layout";
      tooltip = false;
    };

    mpris = {
      format = "{status_icon} {dynamic}";
      dynamic-len = 30;
      dynamic-importance-order = [
        "title"
        "artist"
        "album"
      ];
      status-icons = {
        playing = " ";
        paused = " ";
      };
      ignored-players = [ "firefox" ];
      on-click = "${s}/scratchpad/scratch-toggle.sh Spotify spotify";
      on-click-right = "playerctl play-pause";
      on-scroll-up = "playerctl next";
      on-scroll-down = "playerctl previous";
    };

    # min-width must stay <= icon-size. waybar packs the icon at the START of
    # the button box, so any width beyond the icon becomes empty space on the
    # RIGHT only, and no symmetric padding can correct it. The two numbers are
    # coupled — change icon-size, change min-width in both stylesheets.
    "wlr/taskbar" = {
      format = "{icon}";
      icon-size = 14;
      all-outputs = false;
      tooltip-format = "{title}";
      on-click = "activate";
      on-click-right = "close";
      ignore-list = [ "Rofi" ];
    };

    # Not waybar's built-in dwl/window: mango 0.15.5 dropped the dwl IPC
    # protocol that module binds, and its absence makes waybar SIGSEGV on
    # startup. CSS selector is #custom-window, not #window.
    "custom/window" = {
      exec = "${s}/waybar/window-title.sh";
      return-type = "json";
      format = "{}";
      max-length = 60;
      escape = true;
    };

    cpu = {
      format = "  {usage}%";
      tooltip-format = "CPU: {usage}%\nLoad: {load}";
      interval = 2;
      states = {
        warning = 70;
        critical = 90;
      };
      on-click-right = "${s}/scratchpad/scratch-toggle.sh sysmonitor ${s}/system/sysmonitor.sh";
    };

    memory = {
      format = "  {percentage}%";
      format-alt = "  {used:0.1f}·{total:0.1f}G";
      tooltip-format = "{used:0.1f} / {total:0.1f} GiB";
      interval = 5;
      states = {
        warning = 70;
        critical = 90;
      };
      on-click = "alt";
      on-click-right = "${s}/scratchpad/scratch-toggle.sh sysmonitor ${s}/system/sysmonitor.sh";
    };

    "custom/notification" = {
      tooltip = false;
      format = "{icon}";
      format-icons = {
        notification = " ";
        none = " ";
        dnd-notification = " ";
        dnd-none = " ";
        inhibited-notification = " ";
        inhibited-none = " ";
        dnd-inhibited-notification = " ";
        dnd-inhibited-none = " ";
      };
      return-type = "json";
      exec-if = "which swaync-client";
      exec = "swaync-client -swb";
      on-click = "sleep 0.1s && swaync-client -t -sw";
      on-click-right = "swaync-client -d -sw";
      escape = true;
    };

    network = {
      interval = 3;
      format-wifi = "  {essid}";
      format-ethernet = "󰈀  {ifname}";
      format-linked = "  No IP";
      format-disconnected = "  ✗";
      format-disabled = "";
      tooltip-format = "{ifname}  {ipaddr}/{cidr}\nGateway: {gwaddr}\nStrength: {signalStrength}%";
      format-alt = "↓{bandwidthDownBytes} ↑{bandwidthUpBytes}";
      on-click-right = "${s}/menus/network-menu.sh";
    };

    "custom/vpn" = {
      exec = "${s}/menus/vpn.sh";
      return-type = "json";
      interval = 5;
      signal = 10;
      on-click = "${s}/menus/vpn.sh toggle";
      on-click-right = "${s}/menus/vpn-menu.sh";
      tooltip = true;
    };

    bluetooth = {
      format = "";
      format-disabled = "󰂳";
      format-connected = "";
      format-connected-battery = " {device_battery_percentage}%";
      tooltip-format = "{controller_alias}\n{num_connections} connected";
      tooltip-format-connected = "{controller_alias}\n\n{device_enumerate}";
      tooltip-format-enumerate-connected = "{device_alias}";
      tooltip-format-enumerate-connected-battery = "{device_alias} {device_battery_percentage}%";
      on-click = "bluetoothctl power on; ${s}/menus/bluetooth-menu.sh";
      on-click-right = "bluetoothctl power off";
    };

    pulseaudio = {
      # `{format_source}` is the microphone, and it repeats into `format-muted`
      # because that REPLACES `format` rather than adding to it. Both source
      # glyphs are non-empty deliberately. docs/gotchas.md -> Waybar for why
      # each of those is load-bearing; docs/adr/0033 for why there is no
      # `custom/microphone`.
      format = "{icon}  {volume}%  {format_source}";
      format-muted = "  muted  {format_source}";
      format-source = ""; # nf-fa-microphone, U+F130
      format-source-muted = ""; # nf-fa-microphone_slash, U+F131
      tooltip = false;
      on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
      on-click-right = "${s}/menus/volume-menu.sh";
      # Reads backwards on purpose. `trackpad_natural_scrolling=1` in
      # mango/universal/settings.conf inverts the axis before waybar sees it,
      # so fingers-UP arrives as on-scroll-DOWN — this is what makes swiping up
      # raise the volume. `-l 1.5` is a ceiling and belongs on the increase.
      on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-";
      on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5";
      format-icons = {
        headphone = "";
        headset = "";
        default = [
          ""
          ""
          ""
        ];
      };
    };

    backlight = {
      format = "{icon}  {percent}%";
      format-icons = [
        "󰖔"
        "󰖨"
      ];
      # Inverted for the same reason as pulseaudio above — natural scrolling
      # delivers fingers-up as on-scroll-down.
      on-scroll-up = "brightnessctl --class=backlight set 2%-";
      on-scroll-down = "brightnessctl --class=backlight set 2%+";
    };

    "custom/night-mode" = {
      format = "{}";
      exec = "${s}/menus/night-mode.sh status";
      return-type = "json";
      interval = "once";
      signal = 9;
      on-click = "${s}/menus/night-mode.sh toggle";
      on-click-right = "${s}/menus/night-mode.sh menu";
      tooltip = true;
    };

    # "Do not sleep" — the escape hatch for a long build on battery, and the
    # only thing that stops swayidle's ladder from inside the session.
    #
    # Was waybar's built-in `idle_inhibitor`, which held the inhibitor on the
    # bar's own layer surface. That worked, but the state was a bool in the
    # waybar PROCESS: it could only be toggled by clicking the widget — waybar
    # offers no IPC and no signal for it — and it was released, silently, by
    # every `waybar-reload`, mode switch and layout switch. Now the inhibitor is
    # a user unit that outlives the bar, this module only reports it, and
    # SUPER+SHIFT+A reaches the same script. docs/adr/0031.
    #
    # `interval` as well as `signal`: the signal makes a toggle instant, and the
    # poll is the floor. If wlinhibit dies on its own the bar must stop claiming
    # the machine is held awake within 30s rather than never.
    "custom/idle-inhibitor" = {
      format = "{}";
      exec = "${s}/system/idle-inhibit.sh status";
      return-type = "json";
      interval = 30;
      signal = 12;
      on-click = "${s}/system/idle-inhibit.sh toggle";
      tooltip = true;
    };

    # Reads TLP's active profile from /run/tlp/last_pwr. Replaced waybar's
    # built-in power-profiles-daemon module, which bound a D-Bus API nothing
    # here implements — ppd is disabled because it conflicts with TLP, so the
    # module rendered empty and read as missing from the bar. It then spent a
    # year reporting the ACPI platform profile, which moves nothing the
    # scheduler sees; docs/adr/0017.
    "custom/power-profile" = {
      exec = "${s}/system/power-profile.sh";
      return-type = "json";
      interval = 30;
      signal = 11;
      on-click = "${s}/system/power-profile-cycle.sh";
      on-click-right = "${s}/system/power-profile-cycle.sh toggle-fanless";
    };

    # The control centre, as a bar button. It runs menus/shell.sh rather than
    # control-center.sh directly, so the button and SUPER+C go through the ONE
    # router that knows which surface a mode has — in noctalia mode this reaches
    # noctalia's own control centre instead (docs/adr/0023, docs/adr/0033). A
    # bind or an on-click naming the implementation is a dead key in the other
    # mode that still exits 0.
    #
    # No `exec`: there is nothing to report. A custom module with only a format
    # is a static button, which is why this one cannot render empty the way the
    # exec-backed ones can.
    #
    # U+F1DE (nf-fa-sliders), checked against BOTH bar fonts before picking —
    # `fc-list ':charset=F1DE' family`. The bar is "3270 Nerd Font" and
    # "Symbols Nerd Font Mono", NOT the Hack the menus use, and U+F6FF is the
    # standing proof that assuming coverage is how a glyph becomes a box.
    # Deliberately not the `bars` glyph: the control centre's own waybar row
    # already wears that, and two meanings for one glyph is worse than either.
    "custom/control-center" = {
      format = "";
      tooltip = false;
      on-click = "${s}/menus/shell.sh control-center";
    };

    "custom/phone" = {
      exec = "${s}/kdeconnect/phone-status.sh";
      return-type = "json";
      interval = 30;
      # A verb, not `kdeconnect-cli -d <id> --ring`: the device ID belongs in
      # the script that already holds it, or the bar, the script and the
      # control-centre row end up with three copies of one string.
      on-click = "${s}/kdeconnect/phone-status.sh ring";
      on-click-right = "kdeconnect-cli --refresh";
    };

    # `bat`/`adapter` are named rather than left to waybar's auto-detection,
    # which walks /sys/class/power_supply in readdir order and keeps the LAST
    # entry carrying `online` or `status` as the adapter. This machine exposes
    # four supplies — AC, BAT0 and two ucsi-source-psy-USBC000:00* — and the
    # ucsi pair carry both attributes, so the adapter is currently AC only
    # because AC happens to sort last. Whichever one wins decides Plugged vs
    # Discharging when TLP's stop threshold parks BAT0 at `Not charging`.
    #
    # `interval` is explicit because waybar's default is 60s: the module is
    # otherwise event-driven (udev power_supply + an inotify watch on
    # BAT0/uevent) and falls back to a once-a-minute poll, so an unplug could
    # sit unreflected for a minute even when nothing is wrong.
    #
    # There is deliberately NO `full-at`. It rescaled the reading as
    # `shown = real / full-at * 100` to make TLP's 85% charge stop read as
    # 100%, at the cost of the bar permanently disagreeing with every other
    # reading on the machine — 27% real showed as 32% against fastfetch's 27%,
    # which is how a frozen module got misdiagnosed as a rescale bug twice.
    # Showing the raw percentage costs only that the bar parks at 85% on AC.
    battery = {
      bat = "BAT0";
      adapter = "AC";
      interval = 5;
      # Matched to upower's PercentageLow/Critical in power.nix, so the colour
      # change marks a point the system actually acts on. Was 30/15.
      states = {
        warning = 20;
        critical = 5;
      };
      format = "{icon} {capacity}%";
      format-charging = "󰂄 {capacity}%";
      format-plugged = "󰁹 {capacity}%";
      format-icons = [
        "󰂎"
        "󰁺"
        "󰁻"
        "󰁼"
        "󰁽"
        "󰁾"
        "󰁿"
        "󰂀"
        "󰂁"
        "󰂂"
        "󰁹"
      ];
      # Left click swaps to draw/time; the tooltip carries health and cycles.
      # Both were a `focus` tweak until 2026-08-09, so the same click gave a
      # different answer depending on the layout.
      #
      # The toggle only bites while DISCHARGING. update() overrides whatever
      # the click selected with `format-{status}` when one exists, so on AC
      # `format-plugged` wins and clicking does nothing (battery.cpp:730). The
      # focus tweak carried a `format-alt-charging` to patch that; waybar reads
      # only `format-alt` and `format-alt-click`, never a per-status alt, so it
      # was dead config and is not carried over.
      format-alt = "{power}W · {time}";
      format-time = "{H}:{m}";
      tooltip-format = "{time}\n{health} · {cycles}";
    };

    tray = {
      icon-size = 14;
      spacing = 6;
    };

    # Glyph is nf-linux-nixos (U+F313), which not every Nerd Font carries — the
    # bar renders in 3270 Nerd Font, which does. `fc-list ':charset=f313'
    # family` lists fonts that have it; a missing glyph is an empty box with
    # nothing in any log.
    "custom/power" = {
      format = " ";
      tooltip = false;
      # `-b` is a column count: keep it equal to the wlogout entry count in
      # programs.nix, or the overflow wraps into a row the margins leave no
      # room for. The margins are absolute pixels sized for eDP-1's 1920x1200
      # (§1) — they set the button size, and at -T/-B 320 the buttons were
      # 320x560 boxes holding a 52px icon.
      on-click = "wlogout -b 6 -c 12 -r 12 -T 505 -B 505 -L 290 -R 290 --protocol layer-shell";
      on-click-right = "sleep 0.1s && swaync-client -t -sw";
    };
  };

  # ── Shared bar settings ───────────────────────────────────────────────────
  #
  # All margins are 0, for every layout, since hud left (docs/adr/0035). They
  # used to be `margin-top = 6; margin-left/right = 8` — a floating bar — but
  # nothing ever rendered that: `waybar-restart.sh` zeroed all three with sed on
  # every launch, because the only mode with a bar is `tiling` and tiling wants
  # it flush. Those values were residue from the removed `dms` mode.
  barBase = {
    layer = "top";
    position = "top";
    height = 32;
    margin-top = 0;
    margin-bottom = 0;
    margin-left = 0;
    margin-right = 0;
    spacing = 0;
  };

  # Assemble a layout. `tweaks` patches a module for this layout only; every
  # such entry is a deliberate divergence and should say why at the call site.
  mkBar =
    {
      left,
      center ? [ "custom/window" ],
      right,
      bar ? { },
      tweaks ? { },
    }:
    let
      used = left ++ center ++ right;
      unknown = lib.subtractLists (lib.attrNames modules) used;
      # A tweak for a module this layout does not carry is silently ignored by
      # waybar — which is how the old hand-written config-hud.jsonc ended up
      # defining a custom/power it never displayed.
      deadTweaks = lib.subtractLists used (lib.attrNames tweaks);
      defs = lib.genAttrs used (n: modules.${n} // (tweaks.${n} or { }));
    in
    assert lib.assertMsg (
      unknown == [ ]
    ) "waybar: layout references undefined module(s): ${lib.concatStringsSep ", " unknown}";
    assert lib.assertMsg (
      deadTweaks == [ ]
    ) "waybar: tweaks for module(s) not in this layout: ${lib.concatStringsSep ", " deadTweaks}";
    barBase
    // bar
    // defs
    // {
      modules-left = left;
      modules-center = center;
      modules-right = right;
    };

  toWaybar = name: value: (pkgs.formats.json { }).generate name value;

  # ── The three layouts ─────────────────────────────────────────────────────
  # The clock leads modules-left in every layout and custom/window sits in the
  # centre, so switching layout with SUPER+/ never moves them.
  #
  # These are position-INDEPENDENT. The top/bottom variants are derived below
  # rather than written out.
  baseLayouts = {
    # full — everything.
    full = mkBar {
      left = [
        "clock"
        "ext/workspaces"
        "custom/layout"
        "mpris"
        "wlr/taskbar"
      ];
      right = [
        "custom/notification"
        "cpu"
        "memory"
        "network"
        "custom/vpn"
        "bluetooth"
        "pulseaudio"
        "backlight"
        "custom/night-mode"
        "custom/idle-inhibitor"
        "custom/power-profile"
        "custom/phone"
        "battery"
        "tray"
        "custom/power"
      ];
    };

    # focus — drops the taskbar and the cpu/memory/phone readouts.
    focus = mkBar {
      left = [
        "clock"
        "ext/workspaces"
        "custom/layout"
        "mpris"
      ];
      right = [
        "custom/notification"
        "custom/control-center"
        "network"
        "custom/vpn"
        "bluetooth"
        "pulseaudio"
        "backlight"
        "custom/night-mode"
        "custom/idle-inhibitor"
        "custom/power-profile"
        "battery"
        "tray"
        "custom/power"
      ];
    };

    # minimal — battery, tray and power only, plus the one way in to everything
    # else. This is where a single entry point is worth most: the toggles this
    # layout drops are exactly the ones the control centre still reaches.
    minimal = mkBar {
      left = [
        "clock"
        "ext/workspaces"
        "custom/layout"
        "mpris"
      ];
      right = [
        "custom/control-center"
        "battery"
        "tray"
        "custom/power"
      ];
      # More room on the right, so the title gets more characters.
      tweaks."custom/window".max-length = 80;
    };

  };

  # ── Position variants, enumerated at BUILD time ───────────────────────────
  #
  # A bar at the bottom edge is the same bar with `position` flipped and the
  # vertical margins mirrored. `position` cannot be passed on the command line
  # — `waybar --help` offers only -c, -s and -b — so the value has to be in the
  # file, and there are exactly two possible files per layout.
  #
  # This used to happen at RUNTIME: waybar-restart.sh rewrote the generated
  # JSON with `sed -E` into ~/.local/state/mango/waybar-config.jsonc on every
  # switch. That inverted the layering — regex substitution mutating typed
  # output that Nix had just produced — and it cost a real workaround: sed
  # applies each -e to the same line in sequence, so a plain top->bottom +
  # bottom->top pair renamed the key and renamed it straight back, and the swap
  # had to be routed through a `margin-swap` placeholder to survive.
  #
  # Enumerating instead: 3 layouts x 2 positions = 6 files, all statically
  # known. The script now only picks a filename.
  # Only `position` differs. The vertical margins used to be MIRRORED here too,
  # which mattered for exactly one layout: hud cancelled its own exclusive zone
  # with `margin-bottom = -28`. hud is gone (docs/adr/0035) and every remaining
  # layout has all four margins at 0, so mirroring them was arithmetic on zero
  # that read as load-bearing. Restore it before adding any layout with a
  # non-zero vertical margin.
  atBottom = bar: bar // { position = "bottom"; };

  layouts = lib.listToAttrs (
    lib.concatMap (name: [
      (lib.nameValuePair "config-${name}-top.jsonc" baseLayouts.${name})
      (lib.nameValuePair "config-${name}-bottom.jsonc" (atBottom baseLayouts.${name}))
    ]) (lib.attrNames baseLayouts)
  );
in
{
  # Generated into ~/.config/mango/waybar/ alongside the hand-written CSS. The
  # `mango` entry in dotfiles.nix is `recursive = true`, so home-manager links
  # files individually and these coexist with it — but ONLY because the four
  # .jsonc files were deleted from home/mango/waybar/. Two owners for one path
  # is an activation failure, not a merge.
  xdg.configFile =
    lib.mapAttrs' (
      name: value:
      lib.nameValuePair "mango/waybar/${name}" {
        source = toWaybar (lib.replaceStrings [ "." ] [ "-" ] name) value;
      }
    ) layouts
    // {
      # Derived from modules/home/palette.nix, so this file is NOT in
      # dotfiles/mango/waybar/ — one path, one owner. The names are the bar's own
      # vocabulary and the style sheets are written against them, which is why
      # they are spelled out rather than emitted by iterating the palette: a
      # renamed role should break the build here, not silently stop matching in
      # a `@import`ed stylesheet where GTK ignores the unknown colour without a
      # word.
      #
      # `surface` was here until hud left (docs/adr/0035) — style-hud.css was
      # its only consumer, and a generated colour nothing imports is exactly
      # what the both-directions assertion in checks/static.sh exists to catch.
      # Re-add it the moment a stylesheet wants it; the check enforces both ways.
      "mango/waybar/colors.css".text = ''
        /* GENERATED from modules/home/palette.nix — edit that, then rebuild.
           Imported by every style-*.css. */
        @define-color base    #${p.base};
        @define-color overlay #${p.overlay};
        @define-color text    #${p.text};
        @define-color subtext #${p.subtext};
        @define-color accent  #${p.accent};
        @define-color green   #${p.okColor};
        @define-color red     #${p.errColor};
        @define-color yellow  #${p.warnColor};
        @define-color blue    #${p.infoColor};
      '';
    };
}
