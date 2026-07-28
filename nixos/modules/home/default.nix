{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./packages.nix
    ./shell.nix
    ./dotfiles.nix
    ./theme.nix
  ];

  home.username = "henry";
  home.homeDirectory = "/home/henry";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # --- XDG ------------------------------------------------------------------
  xdg.enable = true;
  xdg.userDirs.enable = true;
  # Default flipped to false in home-manager; keep the legacy behaviour so
  # $XDG_DOWNLOAD_DIR etc. are exported to your session.
  xdg.userDirs.setSessionVariables = true;

  # Your /home/henry/.config/mimeapps.list, expressed declaratively. This file
  # becomes a read-only symlink into the store, so "set as default" in a GUI
  # app will fail — change it here and rebuild instead. If that annoys you,
  # delete this block and manage mimeapps.list by hand.
  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      let
        # Zen, not LibreWolf. `xdg-settings get default-web-browser` returns
        # zen.desktop and librewolf isn't installed at all — the librewolf
        # entries in your Arch mimeapps.list (and in CLAUDE.md) are stale.
        browser = [ "zen.desktop" ];
        pdf = [ "org.pwmt.zathura.desktop" ];
        image = [ "imv.desktop" ];
        media = [ "mpv.desktop" ];
        files = [ "thunar.desktop" ];
        mail = [ "eu.betterbird.Betterbird.desktop" ];
        editor = [ "nvim.desktop" ];
        torrent = [ "freedownloadmanager.desktop" ];
      in
      {
        "text/html" = browser;
        "x-scheme-handler/http" = browser;
        "x-scheme-handler/https" = browser;
        "x-scheme-handler/about" = browser;
        "x-scheme-handler/unknown" = browser;

        "application/pdf" = pdf;

        "image/png" = image;
        "image/jpeg" = image;
        "image/gif" = image;
        "image/webp" = image;
        "image/svg+xml" = image;

        "video/mp4" = media;
        "video/x-matroska" = media;
        "video/webm" = media;
        "audio/mpeg" = media;
        "audio/flac" = media;

        "inode/directory" = files;
        "application/zip" = files;

        "x-scheme-handler/mailto" = mail;
        "text/calendar" = mail;

        "text/markdown" = editor;
        "application/x-shellscript" = editor;
        "text/plain" = editor;

        "application/x-bittorrent" = torrent;
        "x-scheme-handler/magnet" = torrent;

        "x-scheme-handler/discord" = [ "equibop.desktop" ];
        "x-scheme-handler/obsidian" = [ "obsidian.desktop" ];
      };
  };

  # --- Services -------------------------------------------------------------
  services.cliphist.enable = true; # replaces your cliphist autostart
  services.wlsunset = {
    enable = true;
    latitude = "53.35"; # Dublin
    longitude = "-6.26";
  };

  services.nextcloud-client = {
    enable = true;
    startInBackground = true;
  };

  # protonmail-bridge — needs a keyring, hence gnome-keyring in the host config.
  services.protonmail-bridge.enable = true;

  # --- User systemd units ---------------------------------------------------
  # mango/universal/autostart.conf line 2 runs
  #   systemctl --user start mango-session.target
  # On Arch that unit lives in ~/.config/systemd/user/, which is neither on the
  # dotfiles allowlist nor linked by dotfiles.nix — so without this the
  # exec-once fails silently on every boot.
  #
  # Nothing currently Wants or Requires the target; it is a marker other units
  # can hang off. Reproduced as-is from the Arch unit.
  systemd.user.targets.mango-session = {
    Unit = {
      Description = "MangoWC Session Target";
      Requires = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
  };
}
