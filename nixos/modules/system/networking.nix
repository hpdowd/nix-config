{ config, pkgs, lib, ... }:

{
  networking.networkmanager = {
    enable = true;
    wifi.powersave = false; # see the ath11k note below
    plugins = with pkgs; [ networkmanager-openvpn ];
  };

  # You have BOTH NetworkManager and systemd-networkd enabled on Arch, which is
  # a genuine conflict — networkd is enabled by preset and NM is doing the real
  # work. NixOS refuses to let both manage interfaces, so only NM is enabled.
  networking.useNetworkd = false;
  networking.useDHCP = false;

  services.resolved.enable = true;

  networking.firewall = {
    enable = true;
    # Warpinator (file transfer) and KDE Connect need these open.
    allowedTCPPorts = [ 42000 42001 ];
    allowedTCPPortRanges = [{ from = 1714; to = 1764; }]; # KDE Connect
    allowedUDPPortRanges = [{ from = 1714; to = 1764; }];
  };

  # mDNS — you run avahi for CUPS printer discovery.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      userServices = true;
    };
  };

  # --- WiFi resume fix ------------------------------------------------------
  # Your Arch system carries /etc/systemd/system-sleep/wifi-resume.sh because
  # the ath11k_pci driver on the QCNFA765 does not reassociate cleanly with the
  # Minerva_2 router after suspend. That hook is reproduced here as a proper
  # systemd unit. `wifi.powersave = false` above replaces the TLP
  # WIFI_PWR_ON_{AC,BAT}=off half of the fix.
  systemd.services.wifi-resume = {
    description = "Cycle the WiFi radio after resume (ath11k_pci reassociation workaround)";
    after = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
    wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "wifi-resume" ''
        sleep 3
        ${pkgs.networkmanager}/bin/nmcli radio wifi off
        sleep 1
        ${pkgs.networkmanager}/bin/nmcli radio wifi on
      '';
    };
  };

  # Regulatory database for the WiFi card.
  hardware.wirelessRegulatoryDatabase = true;

  services.tor = {
    enable = true;
    client.enable = true;
  };

  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark; # Qt GUI
  };
}
