{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Display power via the compositor — wlopm needs the Wayland socket, so it
  # runs as the session user while the sleep hooks are root. The loop covers
  # whichever socket the session got (mango takes wayland-0 or wayland-1);
  # `|| true` degrades a failed hook to "screen stays on". docs/SYSTEM.md §9.
  setDisplayPower = mode: ''
    for sock in /run/user/*/wayland-[0-9]; do
      [ -e "$sock" ] || continue
      rundir=$(${pkgs.coreutils}/bin/dirname "$sock")
      uid=$(${pkgs.coreutils}/bin/basename "$rundir")
      user=$(${pkgs.coreutils}/bin/id -nu "$uid" 2>/dev/null) || continue
      ${pkgs.util-linux}/bin/runuser -u "$user" -- \
        ${pkgs.coreutils}/bin/env \
          "XDG_RUNTIME_DIR=$rundir" \
          "WAYLAND_DISPLAY=$(${pkgs.coreutils}/bin/basename "$sock")" \
          ${pkgs.wlopm}/bin/wlopm --${mode} '*' || true
    done
  '';
in
{
  # --- TLP ------------------------------------------------------------------
  services.power-profiles-daemon.enable = false; # conflicts with TLP

  services.tlp = {
    enable = true;
    settings = {
      # WiFi half of the ath11k resume workaround; the rest is in networking.nix.
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "off";

      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

      PLATFORM_PROFILE_ON_AC = "performance";
      PLATFORM_PROFILE_ON_BAT = "low-power";

      # Longevity over runtime. On AC the battery parks where it is and only
      # tops up below START, so a static sub-100% reading is correct — see
      # docs/SYSTEM.md §9.
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 85;
    };
  };

  # waybar's custom/power-profile reads this ACPI attribute directly (nothing
  # here implements the PowerProfiles D-Bus API) and needs group write. A udev
  # rule cannot do it — not a device attribute. `z` sets the mode without
  # creating the path. docs/gotchas.md → Waybar.
  systemd.tmpfiles.rules = [
    "z /sys/firmware/acpi/platform_profile 0664 root wheel -"
  ];

  services.thermald.enable = false; # Intel-only

  # --- zram -----------------------------------------------------------------
  # Priority 5 against the swapfile's -1, so ordinary swapping never hits disk.
  # The swapfile exists only for hibernation images, which zram cannot hold.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # --- Lid / suspend --------------------------------------------------------
  # Hibernate, not suspend-then-hibernate: a spurious wake degrades s-t-h to a
  # plain suspend the machine sometimes never resumes from. docs/adr/0015.
  # (The idle rung suspends — docs/adr/0016. Different evidence.)
  services.logind.settings.Login = {
    HandleLidSwitch = "hibernate";
    HandleLidSwitchExternalPower = "hibernate";
    HandleLidSwitchDocked = "ignore";

    # Tap matches the lid, long press is the hard stop. The systemd defaults
    # are the other way round, so a brushed button ended the session.
    HandlePowerKey = "hibernate";
    HandlePowerKeyLongPress = "poweroff";
  };

  # Without this a logind.conf-only change never reaches the running daemon and
  # the lid keeps its previous action until reboot, unlogged. `restartTriggers`
  # not `reloadTriggers`: the module's `reloadIfChanged` turns it into a reload,
  # and setting both warns. docs/gotchas.md → Power.
  systemd.services.systemd-logind.restartTriggers = [
    config.environment.etc."systemd/logind.conf".source
  ];

  # --- Power the display down across sleep ----------------------------------
  # A lit panel holds s0i3 off and costs ~4 W through the whole suspend. The
  # backlight cannot do this — brightnessctl drives the PWM and leaves the
  # DISPLAY block active. Overlaps swayidle's own wlopm timeout harmlessly.
  # docs/SYSTEM.md §9.
  powerManagement.powerDownCommands = setDisplayPower "off";

  # Load-bearing: an output left off is not restored by input, so without this
  # the machine wakes to a black screen no keypress fixes.
  powerManagement.resumeCommands = setDisplayPower "on";

  programs.corectrl.enable = true; # avoids a polkit prompt per launch

  # Overdrive is deliberately absent: it sets amdgpu.ppfeaturemask, which taints
  # every boot CPU_OUT_OF_SPEC and gets upstream reports dismissed unread.
  # Nothing here used it. docs/gotchas.md → Power.

  # --- Critical battery -----------------------------------------------------
  # `Hibernate`, not the NixOS default `HybridSleep`, which writes the image and
  # then stays in s2idle at the one moment the machine must draw nothing. Also
  # the backstop under the idle suspend (docs/adr/0016).
  #
  # 3%, one point above upower's default, for poll-interval slack. The three
  # percentages must stay strictly descending or upower silently discards all
  # three for its own. docs/SYSTEM.md §9.
  services.upower = {
    enable = true;
    criticalPowerAction = "Hibernate";
    percentageAction = 3;
  };

  services.fwupd.enable = true;
}
