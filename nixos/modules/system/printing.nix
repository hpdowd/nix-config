{ config, pkgs, lib, ... }:

{
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      gutenprint
      gutenprintBin
      hplip
      # Your Brother MFC-L3740CDW. nixpkgs has generic Brother drivers but not
      # this exact AUR package (brother-mfc-l3740cdw). Options, in order of
      # preference:
      #   1. brlaser — open-source, covers most Brother mono/colour lasers
      #   2. cups-filters' driverless IPP Everywhere (this model supports it,
      #      so it may Just Work with no driver at all — try that first)
      #   3. package the AUR driver yourself; see pkgs/README.md
      cups-filters
      brlaser
    ];
  };

  # Driverless discovery over mDNS. With avahi (networking.nix) this is often
  # enough for a modern Brother — check `lpinfo -v` before installing drivers.
  services.printing.browsing = true;
  services.printing.browsedConf = ''
    BrowseDNSSDSubTypes _cups,_print
    BrowseLocalProtocols all
    BrowseRemoteProtocols dnssd cups
    CreateIPPPrinterQueues All
  '';

  # Scanning — hplip and Brother MFCs both need SANE.
  hardware.sane = {
    enable = true;
    extraBackends = with pkgs; [ hplipWithPlugin ];
  };
  users.users.henry.extraGroups = [ "scanner" "lp" ];
}
