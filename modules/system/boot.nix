{ config, pkgs, lib, ... }:

{
  boot.loader.systemd-boot = {
    enable = true;
    # Your ESP is only 1 GiB and is SHARED with Arch's kernel+initramfs
    # (~60 MiB). NixOS writes a full kernel + initrd per generation, roughly
    # 120 MiB each, so an unbounded list will fill the partition and break
    # `nixos-rebuild`. 6 is a safe ceiling; raise it if you enlarge the ESP.
    configurationLimit = 6;
    editor = false; # don't let anyone type init=/bin/sh at the boot menu
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Arch is running 7.1.4; nixos-unstable's `latest` tracks mainline closely.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Carried over from your systemd-boot entry. zswap is disabled because you
  # use zram (see power.nix) — running both is counterproductive.
  boot.kernelParams = [ "zswap.enabled=0" ];

  boot.supportedFilesystems = [ "btrfs" "ntfs" ];

  # Arch's `linux-firmware` equivalent, plus the sof-firmware you have installed.
  hardware.enableAllFirmware = true;
  hardware.firmware = [ pkgs.sof-firmware ];

  # Snapper: on NixOS this is much less load-bearing than on Arch, because
  # every rebuild already produces a rollback-able generation. Kept for /home,
  # which generations do NOT cover.
  services.snapper = {
    configs.home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "henry" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 5;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 2;
      TIMELINE_LIMIT_YEARLY = 0;
    };
  };
}
