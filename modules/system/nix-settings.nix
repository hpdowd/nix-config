{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true; # hardlink identical files in /nix/store
    trusted-users = [
      "root"
      "henry"
    ];

    # Prebuilt binaries so you're not compiling Chromium locally.
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

    # 12 threads on the 7535U.
    max-jobs = "auto";
    cores = 0;
  };

  # Garbage collection. Without this /nix/store grows without bound — the
  # single most common complaint from new NixOS users.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Pin `nixpkgs` (for `nix shell nixpkgs#foo` and legacy nix-* commands) to
  # the exact revision the system was built from, instead of letting it fetch
  # a second, drifting copy of nixpkgs.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  nixpkgs.config.allowUnfree = true; # steam, spotify, vscode, obsidian, teams…

  # Logseq is pinned to Electron 39.8.10, which nixpkgs marks insecure (known
  # unpatched CVEs in the bundled Chromium). Arch shipped you the same binary
  # without saying anything — this isn't a new risk, just a newly visible one.
  # Nix refuses to build it unless you opt in explicitly:
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10" # logseq
    "electron-40.10.5" # (your Arch install carries electron40-bin too)
  ];
  # Remove this line and drop `logseq` from modules/home/packages.nix if you'd
  # rather not run it. Obsidian and silverbullet are both installed and cover
  # much of the same ground.

  # Optional but recommended for a laptop: build in the background at low
  # priority so a rebuild doesn't make the machine unusable.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";
}
