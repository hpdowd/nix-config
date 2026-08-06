# sops-nix. See docs/adr/0012.
{ inputs, ... }:
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;

    # Standalone age key rather than one derived from an SSH host key:
    # services.openssh is not enabled here, so /etc/ssh holds no host keys to
    # convert. It must live outside the store, which is world-readable.
    age.keyFile = "/var/lib/sops-nix/key.txt";

    # A secret is DECLARED only where something reads it. The WireGuard key and
    # the forge tokens are stored in secrets.yaml for recovery and retrieved
    # with `sops -d`; declaring them would decrypt them into /run/secrets on
    # every boot for no consumer. See secrets/README.md.
    secrets = {
      "pia/username".owner = "henry";
      "pia/password".owner = "henry";
    };
  };
}
