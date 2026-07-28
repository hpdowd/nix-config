{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix

    ../../modules/system/boot.nix
    ../../modules/system/locale.nix
    ../../modules/system/networking.nix
    ../../modules/system/audio.nix
    ../../modules/system/desktop.nix
    ../../modules/system/fonts.nix
    ../../modules/system/power.nix
    ../../modules/system/printing.nix
    ../../modules/system/virtualisation.nix
    ../../modules/system/nix-settings.nix
  ];

  networking.hostName = "arch"; # keep the name; rename here if you'd rather not

  # `@home` is reused by this install AND stays mounted by Arch until the
  # side-by-side period ends, so BOTH ids have to be pinned to the live Arch
  # values (`id henry` -> uid=1000 gid=1000(henry)). Leaving them unset gets
  # you uid=1000 by luck but group `users` (gid 100) by default, which would
  # mean every file under /home/henry — all owned by gid 1000 — shows up as an
  # unmapped group on NixOS, and any file NixOS creates shows up as gid 100 on
  # Arch. Pinning both keeps one home directory readable from either system.
  users.groups.henry.gid = 1000;

  users.users.henry = {
    isNormalUser = true;
    uid = 1000;
    group = "henry";
    description = "Henry";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel" # sudo
      "networkmanager"
      "video" # brightnessctl / ddcutil
      "input"
      "libvirt" # virt-manager
      "kvm"
      "podman"
      "keyd"
      "wireshark"
    ];
  };

  # zsh must be enabled system-wide for it to be a valid login shell.
  programs.zsh.enable = true;

  security.sudo-rs.enable = true; # you have sudo-rs installed on Arch
  security.sudo.enable = false;

  security.polkit.enable = true;
  security.rtkit.enable = true; # PipeWire realtime priority

  # gnome-keyring, as on Arch.
  services.gnome.gnome-keyring.enable = true;

  # Do not change after first install — this pins stateful defaults, not versions.
  system.stateVersion = "25.11";
}
