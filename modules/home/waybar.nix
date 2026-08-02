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
# Only the JSON is generated. style*.css stay hand-written files for the same
# reason helix/themes/gruvbox.toml does — they are hand-tuned presentation, not
# settings, and transcribing them into Nix attrsets buys nothing but a chance
# of a silent typo.
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  s = "~/.config/mango/scripts";

  # `full-at` rescales the reading as `shown = real / full-at * 100`, so it MUST
  # equal TLP's charge-stop threshold or the bar misreports: at STOP 80 against
  # full-at 85 it peaked at 94% and showed 88% at a real 75%, reported as "stuck
  # at 88%". Read from power.nix rather than copied, so the two cannot diverge.
  fullAt = osConfig.services.tlp.settings.STOP_CHARGE_THRESH_BAT0;

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
      on-click = "bluetoothctl power on; ${s}/walker/walker.sh -m bluetooth";
      on-click-right = "bluetoothctl power off";
    };

    pulseaudio = {
      format = "{icon}  {volume}%";
      format-muted = "  muted";
      tooltip = false;
      on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
      on-click-right = "${s}/walker/walker.sh -m wireplumber";
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

    # Reads the ACPI platform profile directly. Replaced waybar's built-in
    # power-profiles-daemon module, which bound a D-Bus API nothing here
    # implements — ppd is disabled because it conflicts with TLP, so the module
    # rendered empty and read as missing from the bar.
    "custom/power-profile" = {
      exec = "${s}/system/power-profile.sh";
      return-type = "json";
      interval = 30;
      signal = 11;
      on-click = "${s}/system/power-profile-cycle.sh";
      on-click-right = "${s}/system/power-profile-cycle.sh low-power";
    };

    "custom/phone" = {
      exec = "${s}/kdeconnect/phone-status.sh";
      return-type = "json";
      interval = 30;
      on-click = "kdeconnect-cli -d ca2da407b0d74e098414a3a0d76b1502 --ring";
      on-click-right = "kdeconnect-cli --refresh";
    };

    battery = {
      states = {
        warning = 30;
        critical = 15;
      };
      format = "{icon} {capacity}%";
      format-charging = "󰂄 {capacity}%";
      format-plugged = "󰁹 {capacity}%";
      format-alt = "{icon} {timeTo}";
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
      tooltip-format = "{timeTo}";
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
      on-click = "wlogout -b 5 -c 20 -T 320 -B 320 --protocol layer-shell";
      on-click-right = "sleep 0.1s && swaync-client -t -sw";
    };
  };

  # ── Shared bar settings ───────────────────────────────────────────────────
  barBase = {
    layer = "top";
    position = "top";
    height = 32;
    margin-top = 6;
    margin-bottom = 0;
    margin-left = 8;
    margin-right = 8;
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
      # waybar — which is how config-hud.jsonc ended up defining a custom/power
      # it never displayed.
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

  # ── The four layouts ──────────────────────────────────────────────────────
  # The clock leads modules-left in every non-hud layout and custom/window sits
  # in the centre, so switching layout with SUPER+/ never moves them.
  layouts = {
    # full — everything.
    "config.jsonc" = mkBar {
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
        "custom/power-profile"
        "custom/phone"
        "battery"
        "tray"
        "custom/power"
      ];
    };

    # focus — drops the taskbar and the cpu/memory/phone readouts.
    "config-focus.jsonc" = mkBar {
      left = [
        "clock"
        "ext/workspaces"
        "custom/layout"
        "mpris"
      ];
      right = [
        "custom/notification"
        "network"
        "custom/vpn"
        "bluetooth"
        "pulseaudio"
        "backlight"
        "custom/night-mode"
        "custom/power-profile"
        "battery"
        "tray"
        "custom/power"
      ];
      # The only layout that rescales the battery reading, and the only one with
      # the richer power/health tooltip — the others show the raw percentage, so
      # SUPER+/ changes the number you see. That is longstanding behaviour.
      tweaks.battery = {
        full-at = fullAt;
        format-alt = "{power}W · {time}";
        format-alt-charging = "{power}W · {time}";
        format-time = "{H}:{m}";
        tooltip-format = "{time}\n{health} · {cycles}";
      };
    };

    # minimal — battery, tray and power only.
    "config-minimal.jsonc" = mkBar {
      left = [
        "clock"
        "ext/workspaces"
        "custom/layout"
        "mpris"
      ];
      right = [
        "battery"
        "tray"
        "custom/power"
      ];
      # More room on the right, so the title gets more characters.
      tweaks."custom/window".max-length = 80;
    };

    # hud — an overlay strip, not a bar. margin-bottom cancels the exclusive
    # zone against the 28px height; waybar-position.sh mirrors it when the bar
    # moves to the bottom edge.
    "config-hud.jsonc" = mkBar {
      left = [ ];
      center = [ ];
      right = [
        "ext/workspaces"
        "custom/phone"
        "battery"
        "clock"
      ];
      bar = {
        layer = "overlay";
        height = 28;
        margin-top = 0;
        margin-bottom = -28;
        margin-left = 0;
        margin-right = 0;
        exclusive = 0;
        exclusive-zone = 0;
      };
      tweaks = {
        # Dots rather than numbers — the hud is glanceable, not interactive.
        "ext/workspaces".format-icons = {
          active = "●";
          default = "○";
          urgent = "!";
        };
      };
      # NOTE: config-hud.jsonc also defined `custom/power` (pointing at
      # menus/power-menu.sh rather than wlogout) but never listed it in
      # modules-right, so it has never rendered. Not carried over. To bring it
      # back, add "custom/power" to `right` and re-add the tweak here.
    };
  };
in
{
  # Generated into ~/.config/mango/waybar/ alongside the hand-written CSS. The
  # `mango` entry in dotfiles.nix is `recursive = true`, so home-manager links
  # files individually and these coexist with it — but ONLY because the four
  # .jsonc files were deleted from home/mango/waybar/. Two owners for one path
  # is an activation failure, not a merge.
  xdg.configFile = lib.mapAttrs' (
    name: value:
    lib.nameValuePair "mango/waybar/${name}" {
      source = toWaybar (lib.replaceStrings [ "." ] [ "-" ] name) value;
    }
  ) layouts;
}
