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

  users.users.henry = {
    isNormalUser = true;
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
