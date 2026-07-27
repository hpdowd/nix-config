# Hardware / filesystem layout.
#
# IMPORTANT: After booting the NixOS installer, run
#     nixos-generate-config --root /mnt --show-hardware-config
# and diff it against this file. This version was written from your live Arch
# system (`lsblk -f`, /etc/fstab) so the UUIDs are real, but the installer is
# the authority on kernel modules for your exact hardware.
#
# Your current Arch layout on /dev/nvme0n1:
#   p1  vfat  32D9-7457                              -> /boot  (1 GiB ESP)
#   p2  btrfs 3c2d15a1-3a17-4715-99e5-969f27027571   -> subvols @ @home @pkg @log @swap
#
# This config assumes the SIDE-BY-SIDE migration described in MIGRATION.md:
# NixOS gets new subvolumes (@nixos, @nix) on the SAME btrfs filesystem, and
# reuses your existing @home. Nothing in @ or @home is destroyed, so you can
# boot back into Arch from the same ESP until you're happy.
{ config, lib, pkgs, modulesPath, ... }:

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
    options = [ "subvol=@nix" "compress=zstd:3" "ssd" "discard=async" "space_cache=v2" "noatime" ];
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

  # Shared ESP. 1 GiB is tight for NixOS, which keeps a kernel+initrd per
  # generation — see boot.nix, where we cap systemd-boot to 6 entries.
  fileSystems."/boot" = {
    device = espUUID;
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" "errors=remount-ro" ];
  };

  # You currently run zram + a btrfs swapfile in @swap. zram alone is plenty
  # for 14 GiB of RAM unless you want hibernation; see power.nix.
  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # AMD Ryzen 5 Pro 7535U
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
