# sops-nix. See docs/adr/0012.
{ config, inputs, ... }:
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;

    # Standalone age key rather than one derived from an SSH host key:
    # services.openssh is not enabled here, so /etc/ssh holds no host keys to
    # convert. It must live outside the store, which is world-readable.
    age.keyFile = "/var/lib/sops-nix/key.txt";

    # A secret is DECLARED only where something reads it. The forge tokens are
    # stored in secrets.yaml for recovery and retrieved with `sops -d`;
    # declaring them would decrypt them into /run/secrets on every boot for no
    # consumer. See secrets/README.md.
    # All three are root-owned: since vpn-menu.sh stopped importing .ovpn files
    # the only reader is the template below, rendered by root at activation.
    secrets = {
      "pia/username" = { };
      "pia/password" = { };
      "wireguard/homelab" = { };
    };

    # envsubst input for networking.nix's ensureProfiles. A template rather than
    # three separate secrets because EnvironmentFile wants one KEY=value file,
    # and because it keeps every credential out of the world-readable store.
    templates."networkmanager.env" = {
      content = ''
        PIA_USERNAME=${config.sops.placeholder."pia/username"}
        PIA_PASSWORD=${config.sops.placeholder."pia/password"}
        WG_HOMELAB_PRIVATE_KEY=${config.sops.placeholder."wireguard/homelab"}
      '';
      # Otherwise a credential change re-renders the env file and the profiles
      # keep the old value until the next boot — silently.
      restartUnits = [ "NetworkManager-ensure-profiles.service" ];
    };
  };
}
