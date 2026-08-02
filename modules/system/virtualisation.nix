{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Replaces: podman, podman-compose, distrobox
  virtualisation.podman = {
    enable = true;
    dockerCompat = true; # `docker` -> podman shim
    defaultNetwork.settings.dns_enabled = true;
  };
  virtualisation.containers.enable = true;

  # Replaces: qemu-desktop, virt-manager, libvirt
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true; # Windows 11 guests (you run winboat)
      # NOTE: the `ovmf` submodule was removed from NixOS — all OVMF images
      # shipped with QEMU are now available by default, so UEFI guests work
      # with no extra config.
    };
  };
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  environment.systemPackages = with pkgs; [
    distrobox
    podman-compose
    virtiofsd
  ];

  # --- Gaming ---------------------------------------------------------------
  # steam, gamescope, lutris, heroic, prismlauncher, wine
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
  };
  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };
  programs.gamemode.enable = true;
}
