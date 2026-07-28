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

  # --- Session environment --------------------------------------------------
  # Reproduces ~/.config/environment.d/, which nothing in the flake referenced
  # (MIGRATION.md §7b.3). It has to be `systemd.user.sessionVariables` rather
  # than `home.sessionVariables`: the latter writes hm-session-vars.sh, which
  # is sourced by interactive shells and NOT by systemd user units — and the
  # whole reason this file exists is xdg-desktop-portal-gtk, which runs as a
  # user unit and ignores settings.ini without GTK_THEME set. This option
  # writes ~/.config/environment.d/10-home-manager.conf, the same mechanism.
  #
  # GTK_THEME is Gruvbox-Yellow-Dark, matching gtk-3.0/settings.ini and
  # gtk-apply.sh line 9. theme.nix no longer declares a competing theme name
  # (the ownership question was settled in favour of the mode scripts), and
  # pkgs/default.nix overrides gruvbox-gtk-theme to actually build that
  # variant — the stock nixpkgs build has only Gruvbox-Dark, so this name
  # would otherwise resolve to nothing and fall back to Adwaita.
  systemd.user.sessionVariables = {
    GTK_THEME = "Gruvbox-Yellow-Dark";
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  };

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

  # rclone FUSE mount of Proton Drive at ~/mnt/ProtonDrive.
  #
  # MIGRATION.md §7b.4 named `rclone-nextcloud.service` as the unit to port.
  # That was wrong: checking ~/.config/systemd/user/default.target.wants shows
  # rclone-nextcloud is NOT enabled — the enabled unit is the template instance
  # `rclone@ProtonDrive.service`. This is that instance, pinned to the one
  # remote actually in use. Nextcloud is handled by the desktop sync client
  # above (services.nextcloud-client), not by a mount.
  #
  # ExecStart is deliberately one line: the Arch unit used backslash
  # continuations, but home-manager writes these values through an INI
  # generator, where an embedded newline would split the file.
  #
  # `--allow-other` needs `user_allow_other` in /etc/fuse.conf, which on NixOS
  # comes from `programs.fuse.userAllowOther` — set in hosts/thinkpad.
  # Credentials live in ~/.config/rclone/rclone.conf, which is gitignored and
  # restored from the backup drive (INSTALL.md §5.1).
  systemd.user.services.rclone-protondrive = {
    Unit = {
      Description = "rclone: FUSE mount for cloud remote ProtonDrive";
      Documentation = [ "man:rclone(1)" ];
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "notify";
      ExecStartPre = "-${pkgs.coreutils}/bin/mkdir -p %h/mnt/ProtonDrive";
      ExecStart =
        "${pkgs.rclone}/bin/rclone mount"
        + " --config=%h/.config/rclone/rclone.conf"
        + " --vfs-cache-mode writes"
        + " --vfs-cache-max-size 100M"
        + " --log-level INFO"
        + " --umask 022"
        + " --allow-other"
        + " --allow-non-empty"
        + " ProtonDrive: %h/mnt/ProtonDrive";
      ExecStop = "${pkgs.fuse}/bin/fusermount -uz %h/mnt/ProtonDrive";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
