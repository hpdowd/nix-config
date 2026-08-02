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

      # Tooling only, and deliberately WITHOUT the overlay: a formatter or lint
      # result must not depend on a package override.
      pkgs = nixpkgs.legacyPackages.${system};

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

      # `nix flake check` — the only gate that runs before you do.
      #
      # This exists because the previous one could not do the job. Prior to
      # 2026-08-03 the only pre-rebuild check was verify-packages.sh, which
      # *evaluated* package names and said so itself: it "cannot catch profile
      # collisions or a derivation that fails to build". Meanwhile CLAUDE.md
      # names buildEnv collisions as THE expected failure mode when adding
      # packages. The thing most likely to break was the thing nothing tested.
      #
      # `system` and `home` are real build products, so checking them builds
      # the whole closure: collisions, failing derivations and eval errors all
      # surface here rather than halfway through a `switch`.
      checks.${system} = {
        system = self.nixosConfigurations.thinkpad.config.system.build.toplevel;
        home = self.nixosConfigurations.thinkpad.config.home-manager.users.henry.home.activationPackage;

        # Lints. Both are configured to fire only on real findings — a check
        # that always fails is one you learn to ignore, which is worse than no
        # check. See statix.toml for why `repeated_keys` is off.
        statix = pkgs.runCommandLocal "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
          cd ${self}
          statix check
          touch $out
        '';

        # `--no-lambda-pattern-names` excludes the `{ config, lib, pkgs, ... }`
        # module headers. Those are boilerplate the module system requires, and
        # flagging 37 of them buries the 2 findings that are real.
        deadnix = pkgs.runCommandLocal "deadnix-check" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
          deadnix --fail --no-lambda-pattern-names ${self}
          touch $out
        '';
      };

      # Convenience: `nix fmt`.
      #
      # nixfmt (RFC 166), NOT nixpkgs-fmt — that project is archived upstream.
      # Plain `nixfmt`, not `nixfmt-rfc-style`: at this pin they are the same
      # derivation and the -rfc-style alias emits a deprecation warning on
      # every evaluation. (`nixfmt-classic` is the pre-RFC formatter.)
      formatter.${system} = pkgs.nixfmt;

      # `nix develop`, or automatically via .envrc if you install direnv.
      # Pins the tooling so it is not an ad-hoc PATH dependency.
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.nixfmt
          pkgs.statix
          pkgs.deadnix
          pkgs.nix-tree # inspect closures
          pkgs.nvd # diff two generations
        ];
      };
    };
}
