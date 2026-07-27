{
  description = "Henry's ThinkPad L14 Gen 5 — NixOS + home-manager (migrated from Arch)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hardware quirks for ThinkPads / AMD laptops.
    nixos-hardware.url = "github:NixOS/nixos-hardware";

    # --- Third-party flakes replacing AUR packages ---------------------------
    # Only two are needed. Verified 2026-07-27 against nixpkgs-unstable:
    # mango, walker, elephant, fsel, dsearch, weathr, sidequest, winboat,
    # valent, silverbullet, proton-authenticator, cursor-cli and
    # github-copilot-cli are ALL in nixpkgs already, so the walker / elephant
    # flake inputs that were here previously have been removed as redundant.
    # The DankMaterialShell and quickshell inputs are gone for a different
    # reason: DMS is being dropped as part of this migration.

    # zen-browser-bin — not in nixpkgs
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # claude-desktop — not in nixpkgs (unofficial Linux build)
    #
    # Deliberately NOT using `inputs.nixpkgs.follows = "nixpkgs"`: this flake
    # references `pkgs.nodePackages`, which was removed from nixpkgs, so
    # forcing it onto our nixpkgs breaks evaluation of the whole system. Let
    # it use its own pinned nixpkgs instead. Cost: a second nixpkgs in the
    # store (~200 MB of eval sources, not a second package set).
    claude-desktop.url = "github:k3d3/claude-desktop-linux-flake";
  };

  outputs = { self, nixpkgs, home-manager, nixos-hardware, ... }@inputs:
    let
      system = "x86_64-linux";

      # Single overlay point for packages that aren't in nixpkgs and for
      # anything you need to override. See ./pkgs/default.nix.
      overlays = [
        (import ./pkgs { inherit inputs; })
      ];
    in
    {
      nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };

        modules = [
          { nixpkgs.overlays = overlays; }

          # ThinkPad + AMD tuning from nixos-hardware.
          nixos-hardware.nixosModules.lenovo-thinkpad
          nixos-hardware.nixosModules.common-cpu-amd
          nixos-hardware.nixosModules.common-gpu-amd
          nixos-hardware.nixosModules.common-pc-laptop-ssd

          ./hosts/thinkpad

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.henry = import ./modules/home;
              backupFileExtension = "hm-bak";
            };
          }
        ];
      };

      # Convenience: `nix fmt`
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
    };
}
