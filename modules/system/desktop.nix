{ config, pkgs, lib, inputs, ... }:

{
  # --- Session / login ------------------------------------------------------
  # On Arch you have greetd installed but the service is DISABLED — you're
  # logging in on a TTY. This sets greetd up properly. To keep TTY login
  # instead, set `services.greetd.enable = false` and start mango from
  # ~/.zprofile.
  # tuigreet is a TTY greeter, so it can't fail in a way that locks you out of
  # a graphical session — which is what you want on a first boot. Swap to
  # `regreet` or `gtkgreet` (both packaged) if you want something graphical.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd mango";
      user = "greeter";
    };
  };

  # --- Compositor -----------------------------------------------------------
  # MangoWC (mangowm-git). Confirmed present in nixpkgs as `mango` 0.15.5
  # (verified 2026-07-27) — no upstream flake needed.
  programs.mango.enable = true;

  # swaylock MUST have its own PAM service or it can never unlock. It is not
  # setuid and does not read /etc/shadow itself — it authenticates through
  # PAM under the service name `swaylock`, and with no /etc/pam.d/swaylock PAM
  # falls back to /etc/pam.d/other, which on NixOS is pam_warn + pam_deny.
  # Result: every password is rejected, correct or not, and the only tell is
  # `pam_warn(swaylock:auth)` in the journal — the lock screen itself just
  # says the password is wrong. Locked out this way on 2026-07-30.
  #
  # sway and river get this for free because their nixpkgs modules import
  # nixos/modules/programs/wayland/wayland-session.nix, which sets exactly
  # this. `programs.mango.enable` does NOT import it — it only wires up
  # portals and displayManager.sessionPackages — so on mango it has to be
  # declared by hand. Applies to swaylock-effects too; the PAM service name
  # is still `swaylock`.
  security.pam.services.swaylock = { };

  # Everything mango's config, scripts and keybinds shell out to.
  environment.systemPackages = with pkgs; [
    # Bar / notifications / OSD / lock
    waybar
    swaynotificationcenter
    swayosd
    swaylock-effects
    wlogout
    wayfreeze

    # Launchers & menus — all in nixpkgs, verified 2026-07-27
    fsel # your SUPER+Space launcher (overlay bumps it to 3.5.2)
    walker
    elephant
    rofi # nixpkgs `rofi` is 2.0.0, the merged wayland fork; `rofi-wayland` is gone

    # NOTE: DankMaterialShell (`dms-shell`), its stats backend (`dgop`) and
    # `quickshell` are deliberately NOT installed — dropped during the
    # migration. Waybar is the bar; see the `dms` mango mode note in
    # MIGRATION.md if you want the leftover config removed too.

    # Clipboard
    cliphist
    wl-clip-persist
    wl-clipboard

    # Wallpaper / colour
    mpvpaper
    matugen
    awww # nixpkgs renamed `swww` -> `awww`; this is the same fork you run on Arch

    # Utilities the keybinds and mode scripts call. This list was derived by
    # grepping ~/.config/mango/{scripts,waybar} for invoked binaries, not
    # guessed — `notify-send` alone appears 38 times.
    libnotify # notify-send
    jq # used by the mode scripts to patch Equibop's settings.json
    glib # gsettings — mango/scripts/system/gtk-apply.sh depends on it
    libsForQt5.qttools # qdbus — used by scripts/kdeconnect/phone-status.sh
    brightnessctl
    ddcutil
    playerctl
    wev
    grim
    slurp
    wlsunset
    xwayland-satellite
    uwsm
    bluez # bluetoothctl — the bluetooth menu shells out to it 19 times

    # Session bits
    gnome-keyring
    polkit_gnome
    networkmanagerapplet
    blueman
    pavucontrol

    # Theming — Gruvbox Dark baseline, per CLAUDE.md. The GTK/Qt *settings*
    # live in home-manager (modules/home/theme.nix); these are just the
    # packages that have to exist for the theme to resolve.
    gruvbox-gtk-theme
    adw-gtk3
    gnome-themes-extra
    gtk-engine-murrine
    papirus-icon-theme
    papirus-folders
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
    kdePackages.qt6ct # top-level `qt6ct` doesn't exist; it's under qt6Packages/kdePackages
    libsForQt5.qt5ct
    nwg-look
  ];

  # Arch pulls in lxpolkit via lxsession. polkit_gnome is the NixOS-idiomatic
  # equivalent and is started as a user service rather than from autostart.conf
  # (which, as your CLAUDE.md notes, only fires on initial compositor start).
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome authentication agent";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  # --- Portals --------------------------------------------------------------
  # You have xdg-desktop-portal-{gtk,lxqt,wlr}. wlr handles screencast on
  # wlroots-based compositors; gtk handles file chooser and settings.
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
    config.common.default = [ "wlr" "gtk" ];
  };

  # --- Bluetooth ------------------------------------------------------------
  # bluetooth.service is enabled on your Arch install and your Waybar/walker
  # menus drive it via bluetoothctl.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.Experimental = true; # battery reporting for headsets
  };
  services.blueman.enable = true;

  # --- Graphics -------------------------------------------------------------
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Steam / wine
    extraPackages = with pkgs; [
      libva-vdpau-driver # `vaapiVdpau` was the old name for this; don't list both
      libvdpau-va-gl
    ];
  };

  # --- Theming --------------------------------------------------------------
  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  programs.dconf.enable = true;

  # File manager + trash/mount support (thunar, pcmanfm, gvfs, mtp)
  programs.thunar = {
    enable = true;
    # These moved out of the `xfce` set to top level.
    plugins = with pkgs; [ thunar-archive-plugin thunar-volman ];
  };
  services.gvfs.enable = true;
  services.tumbler.enable = true;
  services.udisks2.enable = true;

  # Flatpak — deliberately NOT enabled (decided 2026-07-28).
  #
  # Arch has three flatpaks installed: com.stremio.Stremio,
  # com.hypixel.HytaleLauncher and io.github.wivrn.wivrn. None are wanted on
  # the new system, so neither the apps nor the daemon are carried over.
  # MIGRATION.md §7b.6 previously listed these as an outstanding gap; they are
  # now a dropped-on-purpose item.
  #
  # To bring it back: `services.flatpak.enable = true`, then add the flathub
  # remote and install the apps by hand — NixOS's module ships the daemon
  # only, not any declarative app list.
}
