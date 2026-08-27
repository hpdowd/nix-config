{
  config,
  pkgs,
  lib,
  ...
}:

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
    ../../modules/system/secrets.nix
  ];

  networking.hostName = "thinkpad"; # matches the flake attribute

  # Both ids are pinned because `@home` came from Arch owned by uid/gid 1000.
  # Unset, the group would default to `users` (gid 100) and every file under
  # /home/henry would show an unmapped group.
  users.groups.henry.gid = 1000;

  # No password here on purpose — `mutableUsers` is on, so it lives in
  # /etc/shadow and stays out of git. On a fresh install `nixos-install` prompts
  # only for root, leaving this account locked; set it from the installer with
  # `nixos-enter --root /mnt -c 'passwd henry'`.
  # step 8.3.
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

  # Not its compinit — home-manager writes a second one, and both cost 219 ms
  # per shell.
  programs.zsh.enableCompletion = false;

  # …but that flag also gates `pathsToLink`, so turning it off deleted
  # share/zsh from every profile and left fpath pointing at nothing.
  # See docs/gotchas.md → nixpkgs and NixOS.
  environment.pathsToLink = [ "/share/zsh" ];

  security.sudo-rs.enable = true;
  security.sudo.enable = false;

  security.polkit.enable = true;
  security.rtkit.enable = true; # PipeWire realtime priority

  # Credential store for the nextcloud-client unit and the browsers.
  services.gnome.gnome-keyring.enable = true;

  # Writes `user_allow_other` into /etc/fuse.conf, for fuse mounts using
  # `--allow-other`. NOTE: its only stated consumer was the rclone ProtonDrive
  # mount, removed 2026-07-30 — kept unaudited rather than dropped blind.
  programs.fuse.userAllowOther = true;

  # Do not change after first install — this pins stateful defaults, not versions.
  system.stateVersion = "25.11";
}
