{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Turn the display pipe off/on via the compositor. wlopm needs the Wayland
  # socket, so it runs as the session user — the sleep hooks themselves are root.
  #
  # The loop covers whichever socket the session has; mango comes up as either
  # wayland-0 or wayland-1, so hardcoding one is a silent no-op half the time.
  # `|| true` so a failed hook degrades to "screen stays on" rather than
  # blocking suspend.
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
  # Some NixOS desktop profiles enable power-profiles-daemon, which conflicts
  # with TLP.
  services.power-profiles-daemon.enable = false;

  services.tlp = {
    enable = true;
    settings = {
      # The WiFi half of the ath11k suspend workaround; the resume hook is in
      # networking.nix.
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "off";

      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

      PLATFORM_PROFILE_ON_AC = "performance";
      PLATFORM_PROFILE_ON_BAT = "low-power";

      # ThinkPad battery thresholds — longevity over runtime.
      #
      # START is deliberately wide: on AC the battery parks where it is and only
      # tops up below 75%, so a plug icon at a static sub-100% reading is the
      # hysteresis working, not a stuck module.
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 85;
    };
  };

  # Nothing implements the net.hadess.PowerProfiles D-Bus API here — TLP does
  # not bridge to it, whatever tlp-pd did on Arch — so waybar's built-in
  # power-profiles-daemon module rendered empty. `custom/power-profile` reads
  # the ACPI attribute directly instead, and needs group write on it.
  #
  # A udev rule cannot do this: it is not a device attribute. `z` applies the
  # mode without creating the path, so it no-ops on hardware that lacks it.
  systemd.tmpfiles.rules = [
    "z /sys/firmware/acpi/platform_profile 0664 root wheel -"
  ];

  services.thermald.enable = false; # Intel-only

  # --- zram -----------------------------------------------------------------
  # Priority 5 against the /swap/swapfile's -1, so ordinary swapping never
  # touches the disk. The swapfile exists only to hold a hibernation image,
  # which zram cannot — it lives in the RAM being saved.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # --- Lid / suspend --------------------------------------------------------
  # ~/.scripts/toggle_lid_action cannot set this — it edits
  # /etc/systemd/logind.conf in place, which is a read-only store path here, so
  # it fails with "Permission denied" and sudo does not help.
  #
  # Straight to hibernate, not `suspend-then-hibernate`: a spurious wake ends the
  # s-t-h cycle, and logind's lid re-check ~30 s later degrades to a *plain*
  # suspend that never hibernates, parking the machine in the s2idle amdgpu
  # sometimes never resumes from. See the Power section of docs/gotchas.md.
  services.logind.settings.Login = {
    HandleLidSwitch = "hibernate";
    HandleLidSwitchExternalPower = "hibernate";
    HandleLidSwitchDocked = "ignore";
  };

  # Without this a logind.conf-only change never reaches the running logind: the
  # nixpkgs module sets `reloadIfChanged` but leaves the matching trigger
  # commented out, so `switch` rewrites /etc and the lid keeps the *previous*
  # action until reboot, unlogged. See the Power section of docs/gotchas.md.
  #
  # `restartTriggers`, not `reloadTriggers`: the module already sets
  # `reloadIfChanged`, which turns this into a reload — and setting both warns.
  # Restarting logind would drop the session; reloading does not.
  systemd.services.systemd-logind.restartTriggers = [
    config.environment.etc."systemd/logind.conf".source
  ];

  # --- Power the display down across sleep ----------------------------------
  # This machine only offers s2idle, where the SoC reaches its low-power state
  # only once every IP block is idle — and the DISPLAY block tracks the display
  # PIPE. A lit panel therefore holds s0i3 off and costs ~4 W for the whole
  # suspend, which is a flat battery overnight, not a cosmetic problem.
  #
  # The backlight is not the pipe: brightnessctl and bl_power drive the PWM and
  # leave DISPLAY active, so that fix logs clean and achieves nothing. Only the
  # compositor can do it. See the Suspend section in CLAUDE.md.
  #
  # Nothing here acts on idleness — swayidle has no timeouts — so these hooks
  # are the only thing that turns the panel off. They run after swayidle's sleep
  # inhibitor has put swaylock up.
  powerManagement.powerDownCommands = setDisplayPower "off";

  # Load-bearing: an output left in its off power-mode is not restored by input,
  # so without this the machine wakes to a black screen no keypress fixes.
  powerManagement.resumeCommands = setDisplayPower "on";

  # Avoids a polkit prompt per corectrl launch.
  programs.corectrl.enable = true;

  # Overdrive (`hardware.amdgpu.overdrive.enable`) is deliberately absent: it
  # sets amdgpu.ppfeaturemask, which taints every boot CPU_OUT_OF_SPEC and gets
  # an upstream amdgpu report dismissed unread. Nothing here used it. Re-enabling
  # restores corectrl's clock/voltage control and the taint with it.

  # --- Critical battery -----------------------------------------------------
  # `Hibernate`, not the NixOS default `HybridSleep`: hybrid sleep writes the
  # image and then stays in s2idle at ~3 W, which on this machine flattens the
  # cell to 0% within minutes of triggering. The session survives either way;
  # the battery does not.
  #
  # 3% rather than upower's 2%: one point of slack for the poll interval, since
  # at the 38 W peak this battery has recorded, 1% is only ~40 s. The write
  # itself needs far less — ~30 s against the ~60 s that 1% buys under load.
  # The gauge is trustworthy this low; it has reported 1% repeatedly.
  #
  # percentageLow/Critical/Action must stay strictly descending (20 > 5 > 3) —
  # upower silently reverts to ITS OWN defaults for all three otherwise.
  services.upower = {
    enable = true;
    criticalPowerAction = "Hibernate";
    percentageAction = 3;
  };

  services.fwupd.enable = true; # firmware updates — worth having on a ThinkPad
}
