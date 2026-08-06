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

  # Renamed from "arch" on 2026-07-30, once Arch was actually deleted. The old
  # name was carried over so the side-by-side period had one less thing
  # changing; it outlived its purpose and made every journal line read
  # `arch systemd[…]` on a machine with no Arch on it. Matches the flake
  # attribute (`nixosConfigurations.thinkpad`) now.
  networking.hostName = "thinkpad";

  # `@home` is reused by this install AND stays mounted by Arch until the
  # side-by-side period ends, so BOTH ids have to be pinned to the live Arch
  # values (`id henry` -> uid=1000 gid=1000(henry)). Leaving them unset gets
  # you uid=1000 by luck but group `users` (gid 100) by default, which would
  # mean every file under /home/henry — all owned by gid 1000 — shows up as an
  # unmapped group on NixOS, and any file NixOS creates shows up as gid 100 on
  # Arch. Pinning both keeps one home directory readable from either system.
  users.groups.henry.gid = 1000;

  # NO PASSWORD IS DECLARED HERE, DELIBERATELY — and that has a consequence you
  # must handle during the install, or you cannot log in.
  #
  # `users.mutableUsers` is true (the default), so passwords live in
  # /etc/shadow. The install creates a *fresh* /etc/shadow on the new @nixos
  # subvolume, and `nixos-install` prompts only for the ROOT password. That
  # leaves henry with a locked account: tuigreet will reject the login even
  # though @home and the uid are reused.
  #
  # Fixed procedurally rather than declaratively, to keep a password hash out
  # of git. Before rebooting out of the installer, run:
  #
  #     sudo nixos-enter --root /mnt -c 'passwd henry'
  #
  # See MIGRATION-GUIDE.md Step 8.3. If you skip it, boot back into Arch (or
  # the installer) and set it from there — nothing is lost.
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

  # Not its compinit — home-manager writes a second one into .zshrc, and running
  # both cost 219 ms per shell.
  programs.zsh.enableCompletion = false;

  security.sudo-rs.enable = true; # you have sudo-rs installed on Arch
  security.sudo.enable = false;

  security.polkit.enable = true;
  security.rtkit.enable = true; # PipeWire realtime priority

  # gnome-keyring, as on Arch.
  services.gnome.gnome-keyring.enable = true;

  # Writes `user_allow_other` into /etc/fuse.conf. Without it the `--allow-other`
  # flag on the rclone ProtonDrive mount (modules/home/default.nix) is refused
  # and the unit fails at start. On Arch this was a hand-edited /etc/fuse.conf.
  programs.fuse.userAllowOther = true;

  # Do not change after first install — this pins stateful defaults, not versions.
  system.stateVersion = "25.11";
}
