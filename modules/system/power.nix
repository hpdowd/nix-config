{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Turn the display pipe off/on via the compositor. wlopm speaks
  # zwlr_output_power_manager_v1, so it needs the Wayland socket and therefore
  # has to run as the session user — the sleep hooks themselves run as root.
  #
  # The loop covers whichever socket the session actually has: mango has come up
  # as both wayland-0 and wayland-1, so hardcoding either one is a silent no-op
  # half the time. `|| true` throughout — a sleep hook that fails must never
  # block suspend, and this must degrade to "screen stays on" rather than
  # "machine won't sleep".
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
      # STOP is the source of truth for waybar's `full-at`, which rescales the
      # reading (`shown = real / full-at * 100`): modules/home/waybar.nix reads
      # it from here via osConfig, so the two cannot drift. They were separate
      # values until 2026-08-01, and a STOP of 80 against a full-at of 85 capped
      # the bar at 80/85*100 = 94%, reported as "stuck at 88%".
      #
      # START is deliberately wide: on AC the battery parks wherever it is and
      # only tops back up below 75%, so the bar normally sits *below* 100% —
      # that is the hysteresis working, not a stuck reading.
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 85;
    };
  };

  # `tlp-pd` on Arch bridges TLP to the power-profiles-daemon D-Bus API so
  # desktop applets can switch profiles.
  #
  # THIS COMMENT USED TO CLAIM NixOS's TLP module does the same thing when
  # power-profiles-daemon is disabled. **It does not.** There is no bridge:
  # `busctl --system list | grep -i powerprofile` returns nothing, so the
  # net.hadess.PowerProfiles API is unimplemented on this machine. Waybar's
  # built-in `power-profiles-daemon` module binds that API, so it had nothing
  # to talk to and rendered empty — the module looked absent from the bar
  # rather than broken. Found 2026-07-30.
  #
  # Fixed by not needing a daemon at all. The ThinkPad exposes the same three
  # states through the kernel:
  #
  #   /sys/firmware/acpi/platform_profile_choices -> low-power balanced performance
  #
  # `custom/power-profile` in the waybar config reads that file, and
  # `power-profile-cycle.sh` writes it. Writing needs group permission — the
  # attribute is root-owned 0644 by default — so this tmpfiles rule hands it to
  # `wheel`, which henry is in. Same approach as the micmute LED udev rule in
  # audio.nix; a udev rule is not an option here because
  # /sys/firmware/acpi/platform_profile is not a device attribute.
  #
  # `z` applies the mode to an existing path without creating it, so this is a
  # no-op on hardware that does not expose the file.
  systemd.tmpfiles.rules = [
    "z /sys/firmware/acpi/platform_profile 0664 root wheel -"
  ];

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
  # ~/.scripts/toggle_lid_action (no .sh — the real file has no extension)
  # edits /etc/systemd/logind.conf in place. On NixOS that path is a symlink
  # into /etc/static/, a read-only store path, so the script exits 1 with
  # "Permission denied" and sudo does not help. The setting lives here instead
  # and changing it means a rebuild. Set both to "ignore" if you dock or use an
  # external monitor and want the old lid-does-nothing behaviour.
  # On battery: suspend-then-hibernate. Plain suspend cannot be trusted here
  # because this machine never reaches s0i3 (see below) and idles at ~3 W while
  # "asleep" — a full battery lasts ~14 h, so a night closed in a bag finds it
  # flat. After HibernateDelaySec it writes RAM to /swap/swapfile and powers
  # off properly, costing ~1.5 Wh for the initial suspend window instead of the
  # whole battery.
  #
  # On AC the drain does not matter, so stay on plain suspend and keep the
  # instant resume. This is the one setting where the two differ deliberately.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };

  # 30 minutes at ~3 W is ~1.5 Wh — cheap enough that a short lid-close still
  # resumes instantly, while anything longer goes to disk.
  #
  # The wake that triggers the hibernate needs an RTC alarm. rtc0 here is
  # `acpi-tad`, which has NO wakealarm at all — which is why `rtcwake` fails
  # with "/dev/rtc0 not enabled for wakeup events" and looks like broken
  # firmware. The alarm actually comes from rtc1 (`rtc_cmos`, "RTC can wake
  # from S4"), which the kernel's alarmtimer picks up because it is the only
  # RTC with a wakeup node. Don't "fix" a wakealarm complaint by pointing
  # anything at rtc0.
  # Note this is `settings.Sleep`, not the older `extraConfig` — that option is
  # now a hard assertion failure ("no longer has any effect; please remove
  # it"), not a warning. Same shape as services.logind.settings.Login above.
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "30m";

    # HibernateMode is left at systemd's default of `platform` (ACPI S4), which
    # works here. Do NOT "fix" it to `shutdown` on the strength of the journal
    # looking like an aborted S4 — see the verification note in CLAUDE.md. The
    # resumed system's log always ends with `Restoring platform NVS memory` /
    # `Waking up from system sleep state S4` / `hibernation exit`, on success as
    # well as on failure, because the memory image is snapshotted *before* the
    # write and power-off. Everything logged after that point is not in the
    # image and therefore does not exist after resume.
  };

  # --- Power the display down across sleep ----------------------------------
  # This machine only offers s2idle. `cat /sys/power/mem_sleep` reports
  # `[s2idle]` with no `deep` alternative, because the firmware exposes Modern
  # Standby (s0ix) rather than S3 — so setting `mem_sleep_default=deep` on the
  # kernel command line would achieve nothing.
  #
  # **This is a battery bug, not a cosmetic one.** Under s2idle the SoC only
  # reaches its low-power state (s0i3) once every IP block reports idle, and the
  # DISPLAY block stays active for as long as the display *pipe* is on. So a lit
  # panel does not merely look wrong — it holds s0i3 off entirely, and the
  # machine sits at ~4.1 W for the whole "suspend". Measured 2026-07-31:
  # 790 mWh over 11m34s, `Last S0i3 Status: Unknown/Fail`, and in
  # /sys/kernel/debug/amd_pmc/smu_fw_info every block at 0 except
  # `DISPLAY: 9440595`. A 42.6 Wh battery lasts ~10.4 h at that draw, which is
  # why the laptop was found dead after a night closed on the desk. The kernel
  # says it plainly too: `amd_pmc AMDI0007:00: Last suspend didn't reach
  # deepest state`.
  #
  # **The backlight cannot fix this, and the first attempt at it failed twice
  # over.** brightnessctl only drives the PWM level, and the amdgpu backlight is
  # `type: raw` with no panel-power path — so writing 4 (FB_BLANK_POWERDOWN) to
  # /sys/class/backlight/amdgpu_bl1/bl_power is folded into "set brightness 0"
  # and changes nothing visible. Worse, even a genuinely dark backlight would
  # leave the DISPLAY block active, because the block tracks the CRTC, not the
  # PWM. The 2026-07-30 version of this hook wrote both values, succeeded, exited
  # 0, and left the screen lit and the battery draining.
  #
  # The display pipe belongs to the compositor, so the fix goes through
  # `zwlr_output_power_manager_v1` — which mango does implement
  # (`output_power_mgr_set_mode` is in the binary). An earlier note in this file
  # claimed the DPMS route was impossible because mango advertised no
  # `wl_output` global, so `wlopm --json` returned `[]` and `mmsg get
  # all-monitors` returned `{"monitors":[]}`. **That is no longer true** — both
  # now report eDP-1 correctly, verified 2026-07-31. Whatever it was (the mango
  # 0.15.5 upgrade is the likely culprit), that stale fact is what sent this down
  # the backlight path in the first place. Re-check it before believing any
  # claim here that something "cannot" be done through the compositor.
  #
  # There is no idle daemon on this system (no swayidle/hypridle), so these
  # hooks remain the only thing that ever turns the panel off.
  powerManagement.powerDownCommands = setDisplayPower "off";

  # Without this the machine wakes to a black screen that no keypress brings
  # back — the output stays in its off power-mode until something sets it on,
  # and input does not override it. That is a worse failure than the one being
  # fixed, so if you ever strip a hook, strip the suspend one, never this.
  powerManagement.resumeCommands = setDisplayPower "on";

  # AMD GPU control (corectrl) needs this to avoid a polkit prompt per launch.
  # `programs.corectrl.gpuOverclock.enable` was renamed to the option below.
  programs.corectrl.enable = true;
  hardware.amdgpu.overdrive.enable = true;

  services.upower.enable = true;
  services.fwupd.enable = true; # firmware updates — worth having on a ThinkPad
}
