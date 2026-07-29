{ config, pkgs, lib, ... }:

{
  # --- TLP ------------------------------------------------------------------
  # Mirrors your /etc/tlp.conf. Note that NixOS enables
  # power-profiles-daemon by default in some desktop profiles and the two
  # conflict — explicitly off here.
  services.power-profiles-daemon.enable = false;

  services.tlp = {
    enable = true;
    settings = {
      # The WiFi half of your ath11k suspend workaround. The other half (the
      # resume hook) is in networking.nix.
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
      # STOP must stay in sync with `"full-at"` in mango/waybar/config-focus.jsonc,
      # which rescales the reading (`shown = real / full-at * 100`). full-at is 85,
      # so a STOP of 80 capped the bar at 80/85*100 = 94% and never read 100%.
      #
      # START is deliberately wide: on AC the battery parks wherever it is and
      # only tops back up below 40%, so the bar normally sits *below* 100% —
      # that is the hysteresis working, not a stuck reading.
      START_CHARGE_THRESH_BAT0 = 40;
      STOP_CHARGE_THRESH_BAT0 = 85;
    };
  };

  # `tlp-pd` on Arch bridges TLP to the power-profiles-daemon D-Bus API so
  # desktop applets can switch profiles. NixOS's TLP module does this itself
  # when power-profiles-daemon is disabled.

  services.thermald.enable = false; # Intel-only; you're on AMD

  # --- zram -----------------------------------------------------------------
  # Replaces zram-generator + /etc/systemd/zram-generator.conf. You also have a
  # btrfs swapfile in swap on Arch; with 14 GiB RAM zram alone is enough
  # unless you want hibernation, so hardware-configuration.nix leaves
  # swapDevices empty. Add the swapfile back there if you want to hibernate.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # --- Lid / suspend --------------------------------------------------------
  # Your ~/.scripts/toggle_lid_action.sh edits /etc/systemd/logind.conf in
  # place. That file is read-only on NixOS, so the setting moves here and
  # changing it means a rebuild. Set to "ignore" if you dock/use an external
  # monitor and want the old toggle behaviour permanently.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };

  # AMD GPU control (corectrl) needs this to avoid a polkit prompt per launch.
  # `programs.corectrl.gpuOverclock.enable` was renamed to the option below.
  programs.corectrl.enable = true;
  hardware.amdgpu.overdrive.enable = true;

  services.upower.enable = true;
  services.fwupd.enable = true; # firmware updates — worth having on a ThinkPad
}
