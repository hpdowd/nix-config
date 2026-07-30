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
    # vscode and vscodium both install into lib/vscode and collide in the
    # home-manager buildEnv (they coexist on Arch only because of separate
    # prefixes). Keeping the MS build for marketplace/Copilot access.
    vscode
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
    # `gfortran` is a full GCC wrapper — it ships gcc/g++/cc/c++ as well as
    # gfortran — so it collides with clang over the generic `cc` and `c++`
    # driver names. buildEnv only errors when the two priorities are EQUAL,
    # and `lowPrio` here did nothing: it moves clang to 10, which is where
    # gfortran already sits. `hiPrio` (-10) breaks the tie from the other
    # side and is what actually builds. Cost: `cc`/`c++` resolve to clang
    # rather than gcc, unlike Arch. gcc/g++/gfortran are all still present
    # from the GCC wrapper — priority only decides contested paths.
    (lib.hiPrio clang)
    gfortran # gcc-fortran
    python313
    # Same collision: both pythons ship bin/python3, bin/pydoc3, bin/idle3 and
    # share/man/man1/python3.1. 3.13 wins the unversioned names; python3.11
    # is still on PATH under its own version-suffixed name.
    (lib.lowPrio python311)
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
    # Replaces freedownloadmanager, which is not in nixpkgs (decided
    # 2026-07-29). Its .desktop file declares exactly the two MIME types the
    # old handler claimed, so xdg.mimeApps in ./default.nix now points at
    # org.qbittorrent.qBittorrent.desktop. Note this covers the torrent half
    # only — FDM's general HTTP download manager has no replacement here.
    qbittorrent

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
    # KDE Connect, not valent. The mango configs are written against KDE
    # Connect: both autostart.conf files run `kdeconnectd`, and the Waybar
    # phone module shells out to `kdeconnect-cli` and queries the
    # `org.kde.kdeconnect` D-Bus name (scripts/kdeconnect/phone-status.sh).
    # Valent is a separate implementation under `ca.andyholmes.Valent`, so it
    # satisfies none of those. Firewall ports 1714-1764 are already open in
    # modules/system/networking.nix and serve either one.
    kdePackages.kdeconnect-kde
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
    # Deliberately NOT wlopm, even though mango/universal/bind.conf binds
    # SUPER+SHIFT+p to it. mango advertises zwlr_output_power_manager_v1 but
    # no `wl_output` global at all, so wlopm enumerates zero outputs
    # (`wlopm --json` returns `[]`) and every invocation is a silent no-op.
    # `mmsg get all-monitors` likewise returns `{"monitors":[]}` while
    # `mmsg watch focusing-client` correctly reports "monitor":"eDP-1".
    # Installing it would only make a broken keybind look supported.
    # Screen blanking across sleep is done via the backlight instead — see
    # modules/system/power.nix.

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
  # ABSENT from nixpkgs — all decided 2026-07-29, nothing here is open:
  #
  #   piavpn-bin          RESOLVED — and it needs no work, because you already
  #                       run PIA through NetworkManager rather than only
  #                       through the proprietary client. Checked 2026-07-29:
  #                       8 OpenVPN profiles exist (algeria, ca_ontario,
  #                       ireland, netherlands, us_chicago, us_east,
  #                       us_houston, us_new_york), all of service-type
  #                       org.freedesktop.NetworkManager.openvpn.
  #
  #                       All three pieces survive the migration already:
  #                         - the profiles live in
  #                           /etc/NetworkManager/system-connections, captured
  #                           by capture-root-state.sh and restored in Part 10
  #                         - `password-flags = 0`, so the passwords are in
  #                           those same files rather than the keyring
  #                         - the CA certs are at
  #                           ~/.local/share/networkmanagement/certificates/,
  #                           which survives via @home and is in the backup
  #                       The absolute cert paths resolve unchanged because
  #                       the uid and home path are pinned identical.
  #
  #                       What you lose is only PIA's own GUI — the kill
  #                       switch and the port-forwarding toggle.
  #
  #   freedownloadmanager REPLACED by `qbittorrent`, above. Torrent half only;
  #                       FDM's HTTP download manager has no equivalent here.
  #
  #   quickmedia, pipemixer, r-quick-share, haroopad, mdview, pdf-compress,
  #   qrookie-vrp         DROPPED. `distrobox` is in the list above — run an
  #                       Arch container for any you actually miss, rather
  #                       than packaging seven things you might not use.
  #
  #   nerd-fonts-sf-mono  DROPPED, and confirmed unused: the only reference is
  #                       a COMMENTED-OUT line in foot/foot.ini (line 7). Also
  #                       not redistributable (Apple).
  #   ttf-phosphor-icons  DROPPED, and confirmed unused: not referenced in any
  #                       waybar, kitty, foot, zed or nvim config. It was a
  #                       DankMaterialShell dependency, and DMS is gone.
  #
  #   torbrowser-launcher `tor-browser` itself is packaged and included.
  #   betterbird-bin      `thunderbird`, the upstream it forks, is included.
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
