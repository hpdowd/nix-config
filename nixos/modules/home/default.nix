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
        # Zen, not LibreWolf — librewolf isn't installed at all, so the
        # librewolf entries in the Arch mimeapps.list were stale.
        #
        # `zen-beta.desktop`, NOT `zen.desktop`: the zen-browser flake installs
        # the beta channel, whose desktop file, binary and Wayland app_id are
        # all `zen-beta`. Arch's zen-browser-bin shipped `zen.desktop`, so
        # carrying that name over pointed every http/https association at a
        # desktop file that does not exist — and xdg silently fell back to
        # chromium, which is what `xdg-mime query default` reported until this
        # was fixed on 2026-07-30. Verify with
        # `ls /etc/profiles/per-user/henry/share/applications/` after a channel
        # change rather than assuming the name.
        browser = [ "zen-beta.desktop" ];
        pdf = [ "org.pwmt.zathura.desktop" ];
        image = [ "imv.desktop" ];
        media = [ "mpv.desktop" ];
        files = [ "thunar.desktop" ];
        mail = [ "eu.betterbird.Betterbird.desktop" ];
        editor = [ "nvim.desktop" ];
        # freedownloadmanager is not in nixpkgs, so this pointed at a handler
        # that would not exist — magnet links and .torrent files would have
        # opened nothing. Verified the replacement's filename by building it
        # and reading share/applications rather than guessing.
        torrent = [ "org.qbittorrent.qBittorrent.desktop" ];
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

  # Mask the swaync unit that ships inside the SwayNotificationCenter package.
  #
  # This is the same one-owner problem as wlsunset below, but arrived by a
  # different route: nixpkgs' swaync ships its own user unit with
  # `WantedBy=graphical-session.target`, and Arch's package did not. So on
  # NixOS the unit auto-starts at login and races the `exec=` line in
  # mango/{tiling,hud}/autostart.conf, which is the copy that actually matters
  # because it passes `-s ~/.config/mango/swaync/style.css`. The autostart copy
  # wins the org.freedesktop.Notifications bus name; the unit exits 1 with
  # "An instance of SwayNotificationCenter is already running!", five times,
  # then lands in start-limit-hit. Notifications work throughout, which is why
  # this sat unnoticed as a permanently failed unit until 2026-07-30.
  #
  # Masking rather than overriding ExecStart: autostart owns swaync's lifecycle
  # (it pkills and respawns on every mode switch, so a restyle takes effect),
  # and nothing in mango/scripts calls systemctl for it. If you ever want
  # systemd to own it instead, drop the autostart line and give the unit the
  # `-s` argument — do not do both.
  #
  # An empty file rather than the usual symlink to /dev/null: per systemd.unit(5)
  # both load as "masked", and `source = "/dev/null"` is an absolute path, which
  # pure evaluation refuses outright.
  xdg.configFile."systemd/user/swaync.service".text = "";

  # Night light. NOT `services.wlsunset` — that module bakes the temperatures
  # into a static ExecStart, and wlsunset has no runtime IPC, so the waybar
  # temperature picker in mango/scripts/menus/night-mode.sh could not change
  # them. Worse, the script used to `pkill` wlsunset and spawn its own copy;
  # only one client can hold a Wayland gamma control, so whichever lost printed
  # `gamma control of output eDP-1 failed` and silently did nothing.
  #
  # So: the service owns the process, and the runner reads the user-chosen
  # night temperature from ~/.config/mango/state/night-temp at start.
  # night-mode.sh writes that file and restarts this unit.
  systemd.user.services.wlsunset = {
    Unit = {
      Description = "Day/night gamma adjustments (night light)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "%h/.config/mango/scripts/system/night-light-run.sh";
      # This PATH is the unit's entire PATH. `bash` is mandatory: the runner's
      # shebang is `#!/usr/bin/env bash` and NixOS has no /bin/bash, so env
      # would exit 127 without it.
      Environment = [
        "PATH=${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.wlsunset ]}"
        "NIGHT_LAT=53.35" # Dublin
        "NIGHT_LONG=-6.26"
        "NIGHT_DAY_TEMP=6500"
      ];
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
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

  # rclone FUSE mount of Proton Drive at ~/ProtonDrive.
  #
  # The mount point is deliberately NOT ~/mnt/ProtonDrive, which is what the
  # Arch template unit used (`%h/mnt/%i`). `~/mnt` is a symlink to
  # /run/media/henry — the udisks removable-media directory, which does not
  # exist unless a drive happens to be mounted. So `mkdir -p %h/mnt/ProtonDrive`
  # failed with "File exists" (mkdir -p reports that for a dangling symlink),
  # rclone could not create the mount point, and `Restart=on-failure` retried
  # every 5s until Proton answered 429 with a one-hour backoff — 230 restarts
  # deep when it was caught on 2026-07-30. Hence also the restart limit below:
  # a broken mount must not be able to hammer a remote API unattended.
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
      # Give up after 5 failures in 10 minutes rather than retrying forever.
      # Without this the unit is an unattended request loop against Proton's
      # API, which is how the 429 above was earned.
      StartLimitIntervalSec = 600;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "notify";
      # Not prefixed with `-`: if the mount point cannot be created there is no
      # point starting rclone, and a hard failure here is visible in the journal
      # instead of being swallowed.
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/ProtonDrive";
      ExecStart =
        "${pkgs.rclone}/bin/rclone mount"
        + " --config=%h/.config/rclone/rclone.conf"
        + " --vfs-cache-mode writes"
        + " --vfs-cache-max-size 100M"
        + " --log-level INFO"
        + " --umask 022"
        + " --allow-other"
        + " --allow-non-empty"
        + " ProtonDrive: %h/ProtonDrive";
      ExecStop = "${pkgs.fuse}/bin/fusermount -uz %h/ProtonDrive";
      Restart = "on-failure";
      RestartSec = 30;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
