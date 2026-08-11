{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  lockCmd = "${pkgs.swaylock-effects}/bin/swaylock -f";

  # The last rung of the idle ladder, with the two exceptions worth making.
  idleHibernate = pkgs.writeShellApplication {
    name = "idle-hibernate";
    runtimeInputs = [
      pkgs.systemd
      pkgs.playerctl
    ];
    text = ''
      # On AC, locked and blanked is enough. A missing AC node counts as
      # on-battery, so the sleep still happens.
      if [ "$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo 0)" != 0 ]; then
        exit 0
      fi

      # Music with the lid open should not hibernate. Only this rung checks:
      # dimming and locking over an album is right, and video needs no check at
      # all — mpv and Firefox hold a zwp_idle_inhibit surface, which stops the
      # ladder before it starts. `-x` so "Paused" does not match.
      if playerctl --all-players status 2>/dev/null | grep -qx Playing; then
        exit 0
      fi

      systemctl hibernate
    '';
  };
in
{
  imports = [
    ./options.nix
    ./packages.nix
    ./shell.nix
    # Native home-manager program modules. Anything here GENERATES its config
    # from Nix; dotfiles.nix carries what is still a hand-written file. New
    # conversions go into programs.nix and come out of dotfiles.nix in the same
    # change — a config with two owners fails activation.
    ./programs.nix
    ./waybar.nix
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

  # mimeapps.list becomes a read-only store symlink, so "set as default" in a
  # GUI app fails — change it here and rebuild.
  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      let
        # `zen-beta.desktop`, NOT `zen.desktop` — the flake installs the beta
        # channel, and the wrong name makes xdg fall back silently (it reported
        # chromium for https until 2026-07-30). Confirm the filename in
        # `/etc/profiles/per-user/henry/share/applications/` after a channel
        # change rather than assuming it.
        browser = [ "zen-beta.desktop" ];
        pdf = [ "org.pwmt.zathura.desktop" ];
        image = [ "imv.desktop" ];
        media = [ "mpv.desktop" ];
        files = [ "thunar.desktop" ];
        mail = [ "eu.betterbird.Betterbird.desktop" ];
        editor = [ "nvim.desktop" ];
        # qBittorrent rather than freedownloadmanager, which is not in nixpkgs.
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

  # The only thing that locks the screen on sleep. NOT a power.nix sleep hook:
  # that cgroup is killed on resume, taking swaylock with it — SYSTEM.md §9.
  #
  # Absolute paths throughout: swayidle runs commands via `sh -c` with a PATH of
  # bash and nothing else.
  #
  # Safe to lock on idle because mango advertises zwp_idle_inhibit_manager_v1 —
  # mpv and Firefox suppress the whole ladder during playback. Confirm with
  # `wayland-info | grep inhibit` before assuming that of another compositor.
  services.swayidle = {
    enable = true;
    events = {
      before-sleep = lockCmd;
      lock = lockCmd;
    };
    timeouts = [
      # Dim as the warning that the lock is coming. -s/-r save and restore
      # whatever level you were on, in $XDG_RUNTIME_DIR.
      {
        timeout = 240;
        command = "${pkgs.brightnessctl}/bin/brightnessctl -s set 10%";
        resumeCommand = "${pkgs.brightnessctl}/bin/brightnessctl -r";
      }
      # Lock, THEN kill the display pipe — `-f` forks only once the lock is up,
      # so this order cannot flash the desktop. wlopm is the panel-off the
      # backlight cannot do (SYSTEM.md §9), and an output left in its off
      # power-mode is not restored by input, hence the resume.
      #
      # `;` not `&&`: only one client may hold the session lock, so a swaylock
      # started over a manual lock exits non-zero, and `&&` would leave the panel
      # lit for the rest of the idle period. Blanking is right either way.
      {
        timeout = 300;
        command = "${lockCmd}; ${pkgs.wlopm}/bin/wlopm --off '*'";
        resumeCommand = "${pkgs.wlopm}/bin/wlopm --on '*'";
      }
      # Idle with the panel dead is still ~3 W, which is a flat battery
      # overnight; suspended it is 0.15 W.
      {
        timeout = 1800;
        command = "${idleHibernate}/bin/idle-hibernate";
      }
    ];
  };

  # Nothing else warns about a low battery: upower's percentages are policy
  # inputs, and waybar only recolours. Without this the first unmissable signal
  # is the machine hibernating at 3%.
  #
  # -S limits it to power supplies (else the headphones alert too); -s drops the
  # burst of current-state events at startup.
  services.poweralertd = {
    enable = true;
    extraArgs = [
      "-s"
      "-S"
    ];
  };

  # nixpkgs' swaync ships a user unit wanted by graphical-session.target, which
  # races the `exec=` line in autostart.conf. The autostart copy wins the bus
  # name and the unit sits permanently failed — invisible, because notifications
  # work throughout. autostart owns the lifecycle (it respawns on mode switch so
  # a restyle applies), so the unit is masked. Never run both.
  #
  # An empty file rather than a symlink to /dev/null: both load as masked, and
  # pure evaluation refuses the absolute path.
  xdg.configFile."systemd/user/swaync.service".text = "";

  # Night light. NOT `services.wlsunset` — that bakes the temperatures into a
  # static ExecStart, and wlsunset has no runtime IPC, so the waybar picker
  # could not change them. The runner reads the chosen temperature from
  # ~/.local/state/mango/night-temp at start; night-mode.sh writes it and
  # restarts this unit.
  #
  # This unit owns the process. Never let the script spawn its own copy too —
  # only one client can hold a Wayland gamma control, and the loser fails
  # silently.
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
        "PATH=${
          lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.wlsunset
          ]
        }"
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

  # --- Session environment --------------------------------------------------
  # `systemd.user.sessionVariables`, not `home.sessionVariables`: the latter
  # writes hm-session-vars.sh, which interactive shells source and systemd user
  # units do not — and the point of this block is xdg-desktop-portal-gtk, a user
  # unit that ignores settings.ini unless GTK_THEME is set.
  #
  # Must match theme.nix's `gtk.theme.name`; pkgs/default.nix is what makes the
  # yellow variant exist at all.
  systemd.user.sessionVariables = {
    GTK_THEME = "Gruvbox-Yellow-Dark";
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  };

  # --- User systemd units ---------------------------------------------------
  # mango/universal/autostart.conf starts this target; without it the exec-once
  # fails silently on every boot. Nothing Wants or Requires it — it is a marker
  # for other units to hang off.
  systemd.user.targets.mango-session = {
    Unit = {
      Description = "MangoWC Session Target";
      Requires = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
  };

  # Proton Drive is deliberately NOT mounted — removed 2026-07-30. Proton blocks
  # rclone's standard access method, and Nextcloud is the cloud sync here.
  #
  # Worth carrying forward: the ported unit could never start, and its
  # `Restart=on-failure` with no start limit turned that into 230 retries, then
  # HTTP 429, then an account-level abuse flag on Proton. Anything that talks to
  # a remote API needs a StartLimitBurst — docs/adr/0006.
}
