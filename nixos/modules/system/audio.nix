{ config, pkgs, lib, ... }:

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
    path = with pkgs; [ pulseaudio coreutils gnugrep gawk ];
    serviceConfig = {
      # Keeping this as an external file means you can iterate on it without a
      # nixos-rebuild. Note: no .sh extension — the real filename is
      # ~/.scripts/micmute-led (CLAUDE.md documented it with one; it doesn't).
      ExecStart = "%h/.scripts/micmute-led";
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
