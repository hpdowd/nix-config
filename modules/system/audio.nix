{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Replaces: pipewire, pipewire-alsa, pipewire-jack, pipewire-pulse,
  #           wireplumber, gst-plugin-pipewire
  services.pulseaudio.enable = false;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
  };

  # --- ThinkPad mic-mute LED -----------------------------------------------
  # Your ~/.scripts/micmute-led.sh runs as a user service and syncs the
  # hardware LED with PipeWire's default-source mute state via `pactl
  # subscribe`. Reproduced as a home-manager-free system user service so it
  # survives even if you rework your dotfiles.
  #
  # Writing to the LED needs permission: this udev rule hands the sysfs
  # attribute to the `input` group, which henry is in.
  services.udev.extraRules = ''
    SUBSYSTEM=="leds", KERNEL=="platform::micmute", ACTION=="add", \
      RUN+="${pkgs.coreutils}/bin/chgrp input /sys/class/leds/%k/brightness", \
      RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
  '';

  systemd.user.services.micmute-led = {
    description = "Sync ThinkPad mic-mute LED with PipeWire default source";
    wantedBy = [ "default.target" ];
    after = [ "pipewire.service" ];
    # `bash` is required, not optional: the script's shebang is
    # `#!/usr/bin/env bash` (it has to be — NixOS has no /bin/bash), and this
    # `path` is the unit's *entire* PATH, so without bash here env exits 127
    # with `env: 'bash': No such file or directory` and systemd restart-loops.
    path = with pkgs; [
      bash
      pulseaudio
      coreutils
      gnugrep
      gawk
    ];
    serviceConfig = {
      # Points at the STORE, not %h/.scripts/micmute-led.
      #
      # Until 2026-07-30 this was `%h/.scripts/micmute-led`, and ~/.scripts was
      # in no repo and no backup — so this unit, which is fully declarative,
      # depended on a file the flake did not carry. A fresh install got the
      # unit and the udev rule and then failed on a missing ExecStart. The
      # scripts now live in `home/scripts/` and this references one directly,
      # so the unit no longer depends on the home directory at all.
      #
      # The `#!/usr/bin/env bash` shebang still resolves: NixOS does provide
      # /usr/bin/env, and `path` above supplies bash. Note: no .sh extension —
      # the real filename is `micmute-led`.
      ExecStart = "${../../dotfiles/scripts/micmute-led}";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # swayosd draws the volume/brightness/caps OSD; it needs a system service
  # for the backlight-writing helper.
  services.udev.packages = [ pkgs.swayosd ];
  systemd.services.swayosd-libinput-backend = {
    description = "SwayOSD libinput backend";
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.swayosd}/bin/swayosd-libinput-backend";
      Restart = "on-failure";
    };
  };
}
