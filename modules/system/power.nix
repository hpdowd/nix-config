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
  # The two power sources differ deliberately: this machine never reaches s0i3
  # and idles at ~3 W asleep, so on battery a lid-close must eventually hit
  # disk. On AC the drain is irrelevant and instant resume is worth more.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };

  # 30 min at ~3 W is ~1.5 Wh, so a short lid-close still resumes instantly.
  #
  # `settings.Sleep`, not `extraConfig` — the latter is now a hard assertion
  # failure rather than a warning.
  #
  # The triggering wake comes from rtc1 (rtc_cmos), not rtc0 (acpi-tad, which
  # has no wakealarm) — don't point anything at rtc0 to satisfy an `rtcwake`
  # complaint.
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "30m";

    # HibernateMode stays at the default `platform` (ACPI S4), which works.
    # Do NOT switch it to `shutdown` because the journal looks like an aborted
    # S4 — success and failure log identically, since the memory image is
    # snapshotted before the write. CLAUDE.md has the real checks.
  };

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

  services.upower.enable = true;
  services.fwupd.enable = true; # firmware updates — worth having on a ThinkPad
}
