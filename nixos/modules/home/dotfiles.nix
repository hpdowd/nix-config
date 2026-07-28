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
# the dotfiles repo must be cloned to ~/src/arch-config first. That's the deal
# — reproducible system, hand-managed dotfiles. Move things into the "native"
# section below as you convert them.
{ config, pkgs, lib, ... }:

let
  # Absolute path to your live dotfiles checkout.
  #
  # This MUST NOT be ~/.config. `xdg.configFile.<name>` writes to
  # ~/.config/<name>, so pointing `dots` at ~/.config makes every entry below a
  # symlink to itself: ~/.config/mango -> store -> ~/.config/mango. Combined
  # with `backupFileExtension = "hm-bak"` in flake.nix, first activation
  # renames the real directory aside and then links to the path it just
  # vacated — a dangling symlink, silently, with no error printed.
  #
  # So the repo is cloned to ~/src/arch-config and linked from there. See
  # INSTALL.md §0.1.
  dots = "${config.home.homeDirectory}/src/arch-config";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/${path}";
in
{
  xdg.configFile = {
    # --- Desktop environment ------------------------------------------------
    # mango/ contains the compositor config, per-mode overrides, waybar,
    # walker, fsel, elephant, swaync, wlogout, rofi and all the mode scripts.
    # It is the heart of your setup and changes constantly — keep it live.
    "mango".source = link "mango";
    # ~/.config/DankMaterialShell and ~/.config/quickshell are gone — DMS and
    # the dms mode were removed on 2026-07-27 (see MIGRATION.md §6c).

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
    # NOTE: `zsh/conf.d`, not `zsh` — home-manager owns ~/.config/zsh/.zshrc,
    # so linking the parent directory would put two owners on one path. That
    # is exactly the collision `fish` used to have; see shell.nix.
    "zsh/conf.d".source = link "zsh/conf.d";

    # --- Everything else ----------------------------------------------------
    "yazi".source = link "yazi";
    "bottom".source = link "bottom";
    "htop".source = link "htop";
    "lazygit".source = link "lazygit";
    "glow".source = link "glow";
    "imv".source = link "imv";
    "ncspot".source = link "ncspot";
    "gtk-3.0".source = link "gtk-3.0";
    "gtk-4.0".source = link "gtk-4.0";
    "Kvantum".source = link "Kvantum";
    "nwg-look".source = link "nwg-look";
    "corectrl".source = link "corectrl";
  };

  # NOT linked, deliberately — see MIGRATION.md §7b.2. Every one of these was
  # listed above at some point, but none of them is in the repo, so a fresh
  # clone produces a link to a path that does not exist:
  #
  #   gh, glab-cli, gpu-screen-recorder, opencode
  #       Excluded by the ~/.config/.gitignore allowlist because they hold
  #       credentials (gh/hosts.yml, gpu-screen-recorder/restore_token,
  #       glab-cli/config.yml). They must stay out of git, so they must also
  #       stay out of this list — linking them would rename the real
  #       directories to *.hm-bak and leave dangling links in their place,
  #       exactly the B1 failure mode. They are restored from the backup
  #       drive instead; see INSTALL.md §5.1.
  #   mpv
  #       The allowlist un-ignores /mpv/, but the directory is empty, so git
  #       carries nothing and the clone has no mpv/ at all.
  #
  # If you want any of them managed, put real (credential-free) content in the
  # repo first, then add the link back.

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
  #
  # ~/.scripts is intentionally NOT declared here. It used to be
  #   home.file.".scripts".source = mkOutOfStoreSymlink "${config.home.homeDirectory}/.scripts";
  # which is the same self-referential bug as B1 — `home.file.".scripts"`
  # *writes to* ~/.scripts, so that linked ~/.scripts at ~/.scripts. The B1 fix
  # repointed `dots` and missed this one entry because it does not go through
  # `link`. With backupFileExtension = "hm-bak" it would have renamed
  # ~/.scripts to ~/.scripts.hm-bak and left a dangling link, silently taking
  # out `cleantmp`, `lidaction`, keyd-application-mapper and the
  # micmute-led.service ExecStart (%h/.scripts/micmute-led).
  #
  # There is nothing to point it at: ~/.scripts is not in this repo and not in
  # any other. It survives the migration because @home is reused, and
  # home.sessionPath already puts it on PATH. To make it reproducible, move the
  # scripts into this repo and link them like everything else above.

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
