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

  # Insecure Electron pins nixpkgs will not build without an explicit opt-in.
  # Name the consumer: an entry that outlives its consumer is an exemption
  # nobody is holding. `nix-store --query --referrers` says who.
  nixpkgs.config.permittedInsecurePackages = [
    "electron-40.10.5" # winboat
  ];

  # Optional but recommended for a laptop: build in the background at low
  # priority so a rebuild doesn't make the machine unusable.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";
}
