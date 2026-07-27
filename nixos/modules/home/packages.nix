# Translated from `pacman -Qe` (282 explicit packages) on 2026-07-26.
#
# Packages that Arch pulls in as *dependencies* are deliberately omitted —
# Nix handles those via closures. Likewise anything replaced by a NixOS module
# (pipewire, tlp, keyd, cups, podman, steam, …) lives in modules/system/, not
# here.
#
# Anything in the LAST section has no confirmed nixpkgs equivalent. Run
# ./verify-packages.sh before your first rebuild; it will tell you exactly
# which of these names resolve.
{ config, pkgs, lib, inputs, ... }:

{
  home.packages = with pkgs; [
    # --- Shell / CLI core ---------------------------------------------------
    bat
    eza
    fd
    ripgrep
    fzf
    zoxide
    yazi
    tree
    htop
    bottom # `btm`
    gdu
    tealdeer # `tldr`
    sysstat
    powertop
    unzip
    unrar
    p7zip
    jq
    wget
    curl
    rsync
    man-pages
    man-pages-posix

    # --- Git / forge --------------------------------------------------------
    git
    git-filter-repo
    lazygit
    gh # github-cli
    glab
    tea # gitea CLI

    # --- Editors ------------------------------------------------------------
    neovim
    helix
    vis
    vscode
    vscodium
    code-cursor # cursor-bin
    zed-editor
    jetbrains.pycharm # attr is `pycharm`; `pycharm-professional` doesn't exist

    # --- AI / dev assistants ------------------------------------------------
    claude-code
    opencode
    codex # openai-codex
    cursor-cli
    github-copilot-cli

    # --- Terminals / multiplexer -------------------------------------------
    kitty
    foot
    ghostty
    tmux

    # --- Languages / toolchains --------------------------------------------
    rustup
    clang
    gfortran # gcc-fortran
    python313
    python311
    python3Packages.pip
    lua5_1
    nodejs
    bun

    # --- Kubernetes / cloud -------------------------------------------------
    kubectl
    kubernetes-helm
    argocd
    kubeseal

    # --- Networking / security ---------------------------------------------
    nmap
    masscan
    tcpdump
    dnsutils # `bind` — dig, nslookup
    netcat-openbsd # openbsd-netcat
    wireguard-tools
    openresolv
    sshfs
    rclone
    restic
    lynx

    # --- Documents / writing ------------------------------------------------
    pandoc
    typst
    typstyle
    # Matches your Arch set exactly: texlive-{latex,latexextra,xetex,
    # fontsrecommended}. `texliveFull` would work but pulls in ~20 GiB of
    # collections you don't have installed today.
    (texlive.withPackages (ps: with ps; [
      scheme-basic
      collection-latex
      collection-latexrecommended
      collection-latexextra
      collection-xetex
      collection-fontsrecommended
    ]))
    glow
    libreoffice-fresh
    hunspellDicts.en_GB-ise
    hyphen
    zathura
    pdftk
    exiftool # perl-image-exiftool
    ghostscript # your ~/.scripts/pdf_to_a4.sh needs `gs`

    # --- Notes / PKM --------------------------------------------------------
    obsidian
    logseq
    anki
    iotas

    # --- Media --------------------------------------------------------------
    mpv
    imv
    yt-dlp
    gimp3
    blender
    spotify
    spicetify-cli
    ncspot
    gpu-screen-recorder
    gst_all_1.gst-libav
    gst_all_1.gst-plugins-good

    # --- Browsers / comms ---------------------------------------------------
    # NOTE: librewolf was dropped — it is not installed on your Arch system
    # despite CLAUDE.md describing it as the default browser. Zen (a flake
    # input, below) is the real default.
    firefox
    chromium
    vivaldi
    tor-browser # torbrowser-launcher isn't packaged, but this is the browser itself
    equibop
    teams-for-linux
    bitwarden-desktop
    warpinator
    valent
    thunderbird # betterbird is NOT in nixpkgs; this is the upstream it forks
    proton-authenticator
    cloudflare-warp
    silverbullet
    rstudio

    # --- Games --------------------------------------------------------------
    lutris
    heroic
    prismlauncher
    dolphin-emu
    luanti
    itch
    nethack
    sl
    wineWow64Packages.stable # `wineWowPackages` is deprecated upstream
    winetricks
    sidequest
    winboat

    # --- System / disk ------------------------------------------------------
    btrfs-progs
    btdu
    snapper
    ntfs3g
    ddcutil
    brightnessctl
    fastfetch
    eyedropper
    libqalculate
    distrobox
    dsearch
    weathr

    # --- Desktop utilities --------------------------------------------------
    pcmanfm
    pavucontrol
    wl-clipboard
    grim
    slurp

    # --- Android / misc tooling --------------------------------------------
    apktool # android-apktool
    android-tools
  ]
  # --- Third-party flakes (AUR replacements) --------------------------------
  ++ [
    # `pkgs.system` is deprecated in favour of pkgs.stdenv.hostPlatform.system
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop
  ];

  # ==========================================================================
  # NOT MIGRATED — verified against nixpkgs-unstable on 2026-07-27
  # ==========================================================================
  #
  # This list is now short. Everything else your Arch system has is either in
  # nixpkgs (see above), handled by a NixOS module, or in ../../pkgs.
  #
  # CONFIRMED ABSENT from nixpkgs — decide on each:
  #   piavpn-bin            Private Internet Access. Proprietary + ships its
  #                         own systemd service. `wireguard-tools` and
  #                         `networkmanager-openvpn` are installed, so a plain
  #                         WireGuard config is the low-effort alternative.
  #   freedownloadmanager   your torrent/magnet handler. Nothing equivalent;
  #                         consider qbittorrent (in nixpkgs) instead. NOTE:
  #                         xdg.mimeApps in ./default.nix still points magnet:
  #                         and .torrent at freedownloadmanager.desktop —
  #                         update that if you switch.
  #   quickmedia, pipemixer, r-quick-share, haroopad, mdview, pdf-compress,
  #   qrookie-vrp, retext
  #   nerd-fonts-sf-mono    not redistributable (Apple SF Mono)
  #   ttf-phosphor-icons    drop the TTFs in ~/.local/share/fonts instead
  #   torbrowser-launcher   but `tor-browser` itself is packaged and included
  #   betterbird-bin        `thunderbird` (the upstream) is included instead
  #
  # HANDLED IN ../../pkgs/default.nix:
  #   fsel (version bump 3.1.0 -> 3.5.2), brother-mfc-l3740cdw, curseforge
  #
  # DROPPED — Arch-specific, no meaning on NixOS:
  #   paru-git, pacman-contrib, cachyos-*-mirrorlist, cachyos-keyring
  #   base, base-devel, linux, linux-firmware, amd-ucode, efibootmgr
  #   zram-generator (-> zramSwap), ly (unused), lxsession (-> polkit_gnome)
  #   tlpui (edit modules/system/power.nix instead)
  #   electron37, electron40-bin, openssl-1.1, mbedtls2, gconf, libpng-apng,
  #   python310, and the ~25 python-* / perl-* packages that are AUR
  #   dependencies of markitdown et al — Nix resolves these automatically.
}
