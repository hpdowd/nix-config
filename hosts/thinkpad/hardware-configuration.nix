# Hardware / filesystem layout.
#
# Important: After booting the NixOS installer, run
#     nixos-generate-config --root /mnt --show-hardware-config
# and diff it against this file. This version was written from your live Arch
# system (`lsblk -f`, /etc/fstab) so the UUIDs are real, but the installer is
# the authority on kernel modules for your exact hardware.
#
# Your current Arch layout on /dev/nvme0n1:
#   p1  vfat  32D9-7457                              -> /boot  (1 GiB esp)
#   p2  btrfs 3c2d15a1-3a17-4715-99e5-969f27027571   -> subvols @ @home @pkg @log swap
#
# This config assumes the side-by-side migration described in migration.md:
# NixOS gets new subvolumes (@nixos, @nix) on the same btrfs filesystem, and
# reuses your existing @home. Nothing in @ or @home is destroyed, so you can
# boot back into Arch from the same esp until you're happy.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  # Single source of truth for the btrfs filesystem.
  fsUUID = "/dev/disk/by-uuid/3c2d15a1-3a17-4715-99e5-969f27027571";
  espUUID = "/dev/disk/by-uuid/32D9-7457";

  # Matches your Arch mount options (compress=zstd:3, async discard).
  btrfsOpts = subvol: [
    "subvol=${subvol}"
    "compress=zstd:3"
    "ssd"
    "discard=async"
    "space_cache=v2"
    "relatime"
  ];
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "thunderbolt"
  ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = fsUUID;
    fsType = "btrfs";
    options = btrfsOpts "@nixos";
  };

  # The Nix store gets its own subvolume so `nix-collect-garbage` churn and
  # snapshots of / stay independent. This replaces your @pkg subvol, which
  # existed for the pacman cache and has no NixOS equivalent.
  fileSystems."/nix" = {
    device = fsUUID;
    fsType = "btrfs";
    # noatime matters here: the store is read constantly and never needs atimes.
    options = [
      "subvol=@nix"
      "compress=zstd:3"
      "ssd"
      "discard=async"
      "space_cache=v2"
      "noatime"
    ];
    neededForBoot = true;
  };

  # Reused as-is from your Arch install.
  fileSystems."/home" = {
    device = fsUUID;
    fsType = "btrfs";
    options = btrfsOpts "@home";
  };

  fileSystems."/var/log" = {
    device = fsUUID;
    fsType = "btrfs";
    options = btrfsOpts "@log";
    neededForBoot = true;
  };

  # Shared esp. 1 GiB is tight for NixOS, which keeps a kernel+initrd per
  # generation — see boot.nix, where we cap systemd-boot to 6 entries.
  fileSystems."/boot" = {
    device = espUUID;
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
      "errors=remount-ro"
    ];
  };

  # Hibernation swap, added 2026-07-31. Its own subvolume because a swapfile
  # must be nodatacow and must never be snapshotted — keeping it out of @nixos
  # means a snapshot of / never tries to capture 20 GiB of swap.
  #
  # No compress=zstd:3 here, unlike every other mount in this file. btrfs
  # rejects a compressed swapfile and `swapon` reports `Invalid argument`,
  # which reads like a corrupt file rather than a wrong mount option.
  fileSystems."/swap" = {
    device = fsUUID;
    fsType = "btrfs";
    options = [
      "subvol=@swap"
      "noatime"
    ];
  };

  # zram (power.nix) remains the *working* swap — it takes priority 5 against
  # this file's -1, so ordinary swapping never touches the disk. This file
  # exists purely to hold a hibernation image, which zram cannot do: it lives
  # in the RAM being saved.
  #
  # Created by hand with `btrfs filesystem mkswapfile --size 20g`, and
  # deliberately declared without a `size` attribute — NixOS recreates the file
  # when `size` is set, and the resume_offset below is only valid for the file
  # that exists right now. 20 GiB against 14 GiB of RAM leaves room for zram's
  # compressed pages, which are in RAM and so land in the image too.
  swapDevices = [ { device = "/swap/swapfile"; } ];

  # Resume from hibernation. Both lines are required for a swapfile:
  # resumeDevice names the filesystem, resume_offset locates the image inside
  # it. Getting this wrong does not fail loudly — the machine boots fresh and
  # silently discards the hibernated session, which looks like "hibernate
  # didn't work" rather than "resume was misconfigured".
  #
  # The offset came from `btrfs inspect-internal map-swapfile -r
  # /swap/swapfile` and is valid only for this exact file. Recreating,
  # resizing, defragmenting or `btrfs balance`-ing it moves the image and
  # breaks resume — re-run that command and update this number if the swapfile
  # is ever touched.
  boot.resumeDevice = fsUUID;
  boot.kernelParams = [ "resume_offset=18621696" ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # AMD Ryzen 5 Pro 7535U
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
