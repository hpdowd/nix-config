# Dotfile strategy.
#
# The tempting mistake when migrating is to rewrite all ~40 of your ~/.config
# subdirectories as Nix expressions on day one. Don't. That is weeks of work,
# it makes every tweak a rebuild, and it front-loads all the risk.
#
# Instead: keep the config files exactly where they are and symlink them in
# with `mkOutOfStoreSymlink`, which produces a symlink to the real path in
# your home directory rather than an immutable copy in /nix/store. The files
# stay editable, live, and git-trackable. You then convert individual configs
# to native home-manager modules whenever you actually feel like it.
#
# Trade-off, stated plainly: out-of-store symlinks are NOT reproducible. A
# fresh install of this flake gets the symlink but not the file contents, so
# ~/.config must be a git repo you clone first. That's the deal — reproducible
# system, hand-managed dotfiles. Move things into the "native" section below
# as you convert them.
{ config, pkgs, lib, ... }:

let
  # Absolute path to your live dotfiles checkout.
  dots = "${config.home.homeDirectory}/.config";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/${path}";
in
{
  xdg.configFile = {
    # --- Desktop environment ------------------------------------------------
    # mango/ contains the compositor config, per-mode overrides, waybar,
    # walker, fsel, elephant, swaync, wlogout, rofi and all the mode scripts.
    # It is the heart of your setup and changes constantly — keep it live.
    "mango".source = link "mango";
    # ~/.config/DankMaterialShell and ~/.config/quickshell are intentionally
    # NOT linked — DMS is dropped in the migration, and quickshell's only
    # remaining config (noctalia-shell) belongs to a shell that isn't
    # installed. Both directories still exist on the Arch side; they simply
    # won't be carried over.

    # --- Editors ------------------------------------------------------------
    "nvim".source = link "nvim";
    "helix".source = link "helix";
    "zed".source = link "zed";

    # --- Terminals ----------------------------------------------------------
    # NOTE: kitty and foot include an `active-theme.*` file that your mode
    # scripts *replace with a symlink* at runtime. That only works because the
    # directory is writable — which is exactly why these are out-of-store
    # symlinks and not `xdg.configFile."kitty/kitty.conf".text = ...`.
    # If you ever convert these to native home-manager modules, the theme
    # switching in mango/scripts/modes/*.sh will break.
    "kitty".source = link "kitty";
    "foot".source = link "foot";
    "ghostty".source = link "ghostty";

    # --- Shell --------------------------------------------------------------
    "zsh/conf.d".source = link "zsh/conf.d";
    "fish".source = link "fish";

    # --- Everything else ----------------------------------------------------
    "yazi".source = link "yazi";
    "bottom".source = link "bottom";
    "htop".source = link "htop";
    "lazygit".source = link "lazygit";
    "glow".source = link "glow";
    "imv".source = link "imv";
    "mpv".source = link "mpv";
    "ncspot".source = link "ncspot";
    "gtk-3.0".source = link "gtk-3.0";
    "gtk-4.0".source = link "gtk-4.0";
    "Kvantum".source = link "Kvantum";
    "nwg-look".source = link "nwg-look";
    "gpu-screen-recorder".source = link "gpu-screen-recorder";
    "corectrl".source = link "corectrl";
    "gh".source = link "gh";
    "glab-cli".source = link "glab-cli";
    "opencode".source = link "opencode";
  };

  # ~/.zshenv sets ZDOTDIR. home-manager writes this itself when
  # programs.zsh.dotDir is set, so it is NOT symlinked here.

  # Your custom scripts (note: none of them have a .sh extension, despite what
  # CLAUDE.md said). Plain bash executables, no Nix packaging needed; only the
  # ones that write to /etc need rethinking:
  #   toggle_lid_action       -> /etc is read-only; see modules/system/power.nix
  #   keyd-application-mapper -> keyd config is generated; see locale.nix
  #   micmute-led   -> wired up as a user service in modules/system/audio.nix
  #   clean_tmp, pdf_to_a4, texpdf -> work unchanged, but pdf_to_a4/texpdf need
  #                                   `ghostscript` and a TeX distribution on
  #                                   PATH; both are in modules/home/packages.nix
  home.file.".scripts".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/.scripts";

  # ~/.hidden — the GTK file-manager clutter list from CLAUDE.md. Small and
  # static, so it's expressed natively rather than symlinked.
  home.file.".hidden".text = ''
    Android
    Applications
    blender
    colors
    go
    log
    R
    share
    temp
    vaults
    winboat
    Zomboid
  '';
}
