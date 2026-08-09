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

    # Secrets. Until this landed, "reproducible" carried an asterisk: a fresh
    # install of this flake produced a machine that could not reach the VPN or
    # git.henrydowd.dev. `follows` is correct here — unlike claude-desktop
    # below, sops-nix builds fine against our nixpkgs.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixos-hardware,
      ...
    }@inputs:
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

        # Shell is the layer that actually breaks here. Every failure
        # catalogued in CLAUDE.md is a shell failure, not a Nix one — the
        # #!/bin/bash exit-127s, the `mmsg -s -d` flags that return 0, `pkill
        # -x` against a wrapped binary, the state path one reader disagreed
        # about. Until 2026-08-03 those 2,100 lines were gated by nothing while
        # the Nix was gated by a full build and two linters.
        #
        # SC1091 is excluded permanently: shellcheck cannot resolve a
        # `. "$HOME/.config/…"` source path statically, and that will not
        # change. Everything else runs at default severity.
        shellcheck =
          pkgs.runCommandLocal "shellcheck-check"
            {
              nativeBuildInputs = [
                pkgs.shellcheck
                pkgs.findutils
              ];
            }
            ''
              cd ${self}
              find . -type f -not -path './docs/archive/*' -print0 \
                | while IFS= read -r -d "" f; do
                    # tr strips the null bytes binary files would otherwise
                    # feed to the substitution, which bash warns about.
                    case "$(head -c 64 "$f" 2>/dev/null | tr -d '\0' | head -1)" in
                      '#!'*bash*) printf '%s\0' "$f" ;;
                    esac
                  done > "$TMPDIR/scripts"

              # A pattern that stops matching would make this pass by finding
              # nothing, which is the failure this repo keeps having.
              found=$(tr -cd '\0' < "$TMPDIR/scripts" | wc -c)
              if [ "$found" -lt 30 ]; then
                echo "shellcheck: only $found scripts found — the shebang scan is broken" >&2
                exit 1
              fi

              xargs -0 -r shellcheck -e SC1091 < "$TMPDIR/scripts"
              echo "shellcheck: $found scripts clean"
              touch $out
            '';

        # The assertions CLAUDE.md makes, minus the two that need a running
        # compositor. Each exists because a documented claim silently stopped
        # being true and cost real debugging time; until now re-checking them
        # was a manual step nobody was forced to run. verify-claims.sh keeps
        # the live ones and says so in its header.
        static =
          pkgs.runCommandLocal "static-check"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.jq
                pkgs.findutils
                pkgs.gnugrep
              ];
            }
            ''
              bash ${self}/checks/static.sh ${self} \
                ${self.nixosConfigurations.thinkpad.config.home-manager.users.henry.home.activationPackage} \
                ${self.nixosConfigurations.thinkpad.config.system.build.toplevel}
              touch $out
            '';
      };

      # `nix fmt`.
      #
      # nixfmt (RFC 166), NOT nixpkgs-fmt — that project is archived upstream.
      # Plain `nixfmt`, not `nixfmt-rfc-style`: at this pin they are the same
      # derivation and the -rfc-style alias emits a deprecation warning on
      # every evaluation. (`nixfmt-classic` is the pre-RFC formatter.)
      #
      # WRAPPED, because `formatter = pkgs.nixfmt` does not work. nixfmt takes
      # FILES: given no arguments it reads stdin and dies on the empty input
      # with a bare "unexpected end of input", and given a directory it throws
      # a Haskell backtrace. `nix fmt` passes no arguments at all, so the
      # obvious one-line formatter output fails both ways — and neither error
      # names the real problem.
      #
      # If this ever needs to format more than Nix (shell, markdown, TOML),
      # replace the wrapper with treefmt-nix rather than growing it.
      formatter.${system} = pkgs.writeShellApplication {
        name = "fmt-nix";
        runtimeInputs = [
          pkgs.nixfmt
          pkgs.findutils
        ];
        text = ''
          find "''${1:-.}" -type f -name '*.nix' \
            -not -path '*/.git/*' -not -path '*/.direnv/*' -print0 \
            | xargs -0 -r nixfmt
        '';
      };

      # `nix develop`, or automatically via .envrc if you install direnv.
      # Pins the tooling so it is not an ad-hoc PATH dependency.
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.nixfmt
          pkgs.statix
          pkgs.deadnix
          pkgs.shellcheck
          pkgs.nix-tree # inspect closures
          pkgs.nvd # diff two generations

          # Secrets. Here rather than in packages.nix because they are only
          # ever used against this repo, and `sops` needs .sops.yaml to be the
          # working directory's to pick the right recipients.
          pkgs.sops
          pkgs.age
        ];

        # sops looks here instead of ~/.config/sops/age/keys.txt, so there is
        # one key rather than an editing key and a host key. It is henry-owned
        # mode 600 for that reason; root reads it at activation regardless.
        SOPS_AGE_KEY_FILE = "/var/lib/sops-nix/key.txt";
      };
    };
}
