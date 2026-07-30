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
# the dotfiles repo must be cloned to ~/src/nix-config first. That's the deal
# — reproducible system, hand-managed dotfiles. Move things into the "native"
# section below as you convert them.
#
# UPDATE 2026-07-30: the "weeks of work" framing above is no longer the real
# constraint, and it was never the whole story. The blocker was structural —
# the flake lived in a `nixos/` subdirectory *below* the dotfiles, so they were
# outside the flake root and unreachable by any relative path. The restructure
# fixed that. What remains is a genuine trade-off about iteration speed (every
# tweak becomes a rebuild), not an impossibility. See the `let` block below.
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
  # Restructured 2026-07-30. The repo is now `nix-config`, the flake sits at
  # its ROOT, and the dotfiles live under `home/`. Previously the flake was in
  # a `nixos/` subdirectory with the dotfiles *above* it, which put them
  # outside the flake root — so the flake could not reference them at all.
  # That, not just writability, is why every entry below is an out-of-store
  # symlink: there was no other way to reach the files.
  #
  # With the flake at the root that constraint is gone. `.source = ../../home/kitty`
  # now resolves and puts the files in the store; pair it with
  # `recursive = true` so the target directory stays writable for generated
  # files (mango/config.conf is the one that still needs this). Convert entries
  # one at a time — `link` stays for whatever must remain mutable.
  dots = "${config.home.homeDirectory}/src/nix-config";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/home/${path}";
in
{
  xdg.configFile = {
    # --- Desktop environment ------------------------------------------------
    # mango/ contains the compositor config, per-mode overrides, waybar,
    # walker, fsel, elephant, swaync, wlogout, rofi and all the mode scripts.
    #
    # STAYS OUT-OF-STORE. It was converted to `{ source = ../../home/mango;
    # recursive = true; }` on 2026-07-30 and reverted the same day, because
    # that conversion **ate the repo**. Do not retry it the naive way.
    #
    # What happens: ~/.config/mango is already an out-of-store symlink to
    # ~/src/nix-config/home/mango. `recursive = true` does not replace the
    # directory — it creates files *inside* ~/.config/mango. Those writes
    # follow the existing symlink straight into the checkout, so activation
    # overwrote 65 tracked files in home/mango/ with symlinks pointing back
    # into the store. `git status` showed them as typechanges (` T `), and
    # every one of those store targets resolved in a loop, so the live config
    # was unreadable too. Recovered with `git checkout -- home/mango`.
    #
    # It is made worse by `nixos-rebuild test`, which activates WITHOUT
    # creating a profile generation — so the new store path has no GC root and
    # a later `nix-collect-garbage` can delete the very files the repo now
    # points at.
    #
    # Converting this safely means removing ~/.config/mango *before*
    # activating, so home-manager builds a fresh directory instead of writing
    # through the old link — i.e. a manual step, not something a rebuild does
    # on its own. The prize is small (config.conf still has to be generated
    # into it), so it stays mutable until there is a reason.
    "mango".source = link "mango";
    # ~/.config/DankMaterialShell and ~/.config/quickshell are gone — DMS and
    # the dms mode were removed on 2026-07-27 (see MIGRATION.md §6c).

    # --- Editors ------------------------------------------------------------
    # nvim stays MUTABLE: lazy.nvim rewrites `lazy-lock.json` in the config
    # directory on every `:Lazy sync`, and that file is tracked here — so in
    # the store it becomes a read-only symlink and the lock can never update.
    "nvim".source = link "nvim";
    # helix writes nothing to its config dir (it looks for a `runtime/` there,
    # does not find one, and falls back to the store copy — that is the warning
    # `hx --health` prints, and it is harmless).
    "helix".source = ../../home/helix;
    # zed stays MUTABLE: editing settings through Zed's own UI rewrites
    # settings.json, which is tracked.
    "zed".source = link "zed";

    # --- Terminals ----------------------------------------------------------
    # kitty and foot USED to include an `active-theme.*` file that the mode
    # scripts replaced with a symlink at runtime, which is why they had to be
    # writable and therefore out-of-store. That indirection was removed on
    # 2026-07-30 — both modes pointed it at the same gruvbox files, so it
    # selected nothing, and kitty.conf/foot.ini now name the theme directly.
    #
    # Converted to store paths 2026-07-30. Nothing writes into any of these, so
    # there is no reason for them to be mutable, and in the store they stop
    # depending on ~/src/nix-config existing at all.
    "kitty".source = ../../home/kitty;
    "foot".source = ../../home/foot;
    "ghostty".source = ../../home/ghostty;

    # --- Shell --------------------------------------------------------------
    # NOTE: `zsh/conf.d`, not `zsh` — home-manager owns ~/.config/zsh/.zshrc,
    # so linking the parent directory would put two owners on one path. That
    # is exactly the collision `fish` used to have; see shell.nix.
    "zsh/conf.d".source = ../../home/zsh/conf.d;

    # --- Read-only at runtime: store-based ----------------------------------
    "yazi".source = ../../home/yazi;
    "bottom".source = ../../home/bottom;
    "lazygit".source = ../../home/lazygit;
    "glow".source = ../../home/glow;
    "imv".source = ../../home/imv;

    # --- Rewritten at runtime: must stay mutable ----------------------------
    # Each of these has a tracked file that a running program overwrites. In
    # the store that file becomes a read-only symlink, so the write fails —
    # usually silently, which is the worst version of this bug. The named
    # writer is the blocker in every case:
    #
    #   htop      htoprc          rewritten on quit if you change any setting
    #   ncspot    config.toml     rewritten when settings change in-app
    #   gtk-3.0   settings.ini    nwg-look writes the theme/font/cursor here
    #   gtk-4.0   settings.ini    same
    #   Kvantum   *.kvconfig      kvantummanager writes the active theme
    #   nwg-look  config          its own saved state
    #   corectrl  corectrl.ini    plus profiles/*.ccpro, written by the GUI
    #
    # These do not become declarative by symlinking them harder. The real fix
    # is to convert each to a native home-manager module — `programs.htop`,
    # `gtk.*`, `qt.*` — which GENERATES the file from Nix, so nothing needs to
    # write to it at runtime. That is a per-app job, not a mechanical one.
    "htop".source = link "htop";
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
  # ~/.scripts — moved into the repo 2026-07-30 and now STORE-BASED.
  #
  # Until then it existed only on this disk: in no git repo, in no backup, and
  # yet `modules/system/audio.nix` declared a systemd unit whose ExecStart was
  # `%h/.scripts/micmute-led`. A fresh install of this flake produced the unit,
  # the udev rule and the PATH entry — and then failed, because the script it
  # runs was never part of the flake. That is the exact gap this file's header
  # warns about, left open on the one directory that most needed closing.
  #
  # `source = ../../home/scripts` (not `link`) is deliberate: nothing writes
  # into ~/.scripts, so there is no reason for it to be mutable, and being in
  # the store is what makes it reproducible. Nix preserves the executable bit,
  # so the files stay runnable. `home.sessionPath` already puts it on PATH.
  #
  # Note the earlier trap this replaces: `home.file.".scripts".source =
  # mkOutOfStoreSymlink "${config.home.homeDirectory}/.scripts"` *writes to*
  # ~/.scripts while pointing at ~/.scripts — a symlink to itself. That is the
  # same self-referential bug as B1, and with backupFileExtension = "hm-bak" it
  # fails silently rather than loudly.
  home.file.".scripts".source = ../../home/scripts;

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
