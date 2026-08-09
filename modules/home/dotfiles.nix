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
{
  config,
  pkgs,
  lib,
  ...
}:

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
  # With the flake at the root that constraint is gone. `.source = ../../dotfiles/kitty`
  # now resolves and puts the files in the store; pair it with
  # `recursive = true` so the target directory stays writable for generated
  # files (mango/config.conf is the one that still needs this). Convert entries
  # one at a time — `link` stays for whatever must remain mutable.
  # Declared in options.nix, not written out here — it is also needed by the
  # rebuild aliases in shell.nix, and one literal path in two files is how they
  # drift apart. See that option's description for why Nix cannot work this out
  # on its own.
  dots = config.local.checkout;
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/dotfiles/${path}";
in
{
  xdg.configFile = {
    # --- Desktop environment ------------------------------------------------
    # mango/ contains the compositor config, per-mode overrides, waybar,
    # walker, fsel, elephant, swaync, wlogout, rofi and all the mode scripts.
    #
    # Store-based with `recursive = true`.
    #
    # `recursive` is required, not cosmetic: a plain `source` makes
    # ~/.config/mango ONE symlink to a read-only store directory, and the mode
    # scripts must be able to create `config.conf` inside it (`tiling.sh` does
    # `cp tiling/tiling.conf config.conf`). `recursive` symlinks each tracked
    # file individually and leaves the DIRECTORY writable, which is exactly
    # that. Tracked files are still read-only, so nothing else may write here.
    #
    # THIS CONVERSION IS DESTRUCTIVE IF ~/.config/mango IS ALREADY AN
    # OUT-OF-STORE SYMLINK. `recursive` does not replace the directory, it
    # writes files inside it — straight through the old link and into the
    # checkout. The first attempt on 2026-07-30 replaced 65 tracked files in
    # home/mango/ with symlinks (` T ` typechanges in git status) whose targets
    # resolved in a loop, breaking the live config too. Recovered with
    # `git checkout -- home/mango`. See docs/adr/0002.
    #
    # The `unlinkStaleConfigDirs` activation entry below is what makes it safe
    # to do at all: it removes the stale symlink *before* home-manager links
    # anything, so there is nothing to write through.
    "mango" = {
      source = ../../dotfiles/mango;
      recursive = true;
    };
    # ~/.config/DankMaterialShell and ~/.config/quickshell are gone — DMS and
    # the dms mode were removed on 2026-07-27 (see MIGRATION.md §6c).

    # --- Editors ------------------------------------------------------------
    # Store-based as of 2026-07-30. The blocker was lazy.nvim rewriting
    # `lazy-lock.json` in the config directory; `lua/config/lazy.lua` now sets
    # `lockfile` to stdpath("state") and seeds it from the tracked copy on
    # first run, so nothing writes in here any more. Plain `source`, not
    # `recursive` — with the lockfile gone there is nothing to create.
    "nvim".source = ../../dotfiles/nvim;
    # helix, kitty, foot, zed → programs.nix (2026-08-01). helix's THEME is
    # still a file — see the note there — but it is declared alongside the
    # module rather than here.
    #
    # ghostty was dropped entirely in the same pass: home/ghostty/config.ghostty
    # was a ZERO-BYTE file, so linking it configured nothing. The package stays
    # in packages.nix and runs on its defaults, exactly as it did before.

    # --- Shell --------------------------------------------------------------
    # NOTE: `zsh/conf.d`, not `zsh` — home-manager owns ~/.config/zsh/.zshrc,
    # so linking the parent directory would put two owners on one path. That
    # is exactly the collision `fish` used to have; see shell.nix.
    "zsh/conf.d".source = ../../dotfiles/zsh/conf.d;

    # --- Read-only at runtime: store-based ----------------------------------
    # yazi and imv → programs.nix (2026-08-01).
    #
    # bottom and lazygit were deleted rather than converted, and the reason is
    # worth recording so nobody "restores" them: home/lazygit/config.yml was
    # ZERO BYTES, and home/bottom/bottom.toml was bottom's 317-line sample file
    # with every single line commented out. Both configured nothing. Linking an
    # empty config is indistinguishable from linking a correct one, which is
    # how they survived the migration unexamined.
    "glow".source = ../../dotfiles/glow; # no home-manager module at this pin

    # Moved out of home/mango/ on 2026-07-31. They lived there because the
    # config tree doubled as the backup unit — only the directories worth
    # keeping were nested under mango/. Everything is in git and in the store
    # now, so that rationale is gone, and the nesting had an ongoing cost:
    # neither app was at the XDG path it looks in by default, so every call
    # site had to name the config explicitly —
    #
    #   swaync  -s ~/.config/mango/swaync/style.css
    #   wlogout -C ~/.config/mango/wlogout/style.css -l ~/.config/mango/wlogout/layout
    #
    # eight hardcoded paths across both autostart.conf files and three waybar
    # layouts. At the default locations both apps find their own configs and
    # every one of those flags is deleted. Hardcoded paths are the recurring
    # silent-failure mode in this repo (the wlogout icons, the `.sh` suffixes,
    # the dead `mmsg -s -d` flags), so removing them is worth more than tidiness.
    #
    # These are also plain store paths, with no `recursive = true`. Under
    # mango/ they inherited that flag, which exists solely so the mode scripts
    # can create the gitignored config.conf — a writability exemption neither
    # of these needs.
    #
    # wlogout → programs.nix (2026-08-01). Its five PNGs used to be referenced
    # RELATIVELY from style.css, which worked only because this entry linked
    # the whole directory. The module renders style.css as a standalone store
    # file, so the icons now have to be interpolated as absolute store paths —
    # see the long note in programs.nix before touching them.
    #
    # swaync stays HERE, deliberately, and not because it lacks a module.
    # `services.swaync` exists and would work — but it declares
    # `systemd.user.services.swaync`, which is exactly the unit masked in
    # default.nix. mango/{tiling,hud}/autostart.conf owns swaync's lifecycle so
    # that a restyle takes effect on mode switch; adopting the module means
    # handing that to systemd and restyling via `systemctl --user restart`.
    # That is a real behaviour change and deserves its own decision, not a line
    # in a bulk conversion. If you do adopt it: drop the mask, drop the
    # autostart exec= line, and never run both.
    "swaync".source = ../../dotfiles/swaync;

    # --- Managed as FILES, not directories ----------------------------------
    # Introduced 2026-07-30. These were out-of-store because a program rewrites
    # something in the directory. Pinning the individual *file* solves it: the
    # tracked config lands read-only in the store, while the DIRECTORY stays
    # writable, so sibling runtime files still work. `ncspot/userstate.cbor`
    # is the case that proves it — ncspot writes playback state next to its
    # config, and it was previously committed to git, which it should never
    # have been (docs/adr/0003).
    #
    # htop, ncspot and zed moved on to programs.nix (2026-08-01) — their
    # home-manager modules use precisely this file-not-directory technique
    # internally, so the workaround became upstream's problem instead of a
    # local special case. What is left below has no module at this pin.
    #
    # The trade-off is real and intended: the config file can no longer be
    # changed from inside the app. Edit it here and rebuild.
    "Kvantum/kvantum.kvconfig".source = ../../dotfiles/Kvantum/kvantum.kvconfig;
    # The theme directory is literally named `Gruvbox#`, and `#` starts a
    # comment in Nix — a bare `../../dotfiles/Kvantum/Gruvbox#;` swallows the
    # semicolon and fails with "syntax error, unexpected '='" pointing at the
    # NEXT line. Concatenating a string onto the path avoids the lexer.
    "Kvantum/Gruvbox#".source = ../../dotfiles/Kvantum + "/Gruvbox#";

    # nwg-look is a GTK-settings GUI, and Nix owns GTK as of 2026-07-30
    # (theme.nix). Running it would fight the declared config, so pinning its
    # own state read-only is a feature rather than a cost.
    "nwg-look/config".source = ../../dotfiles/nwg-look/config;

    # gtk-3.0/gtk-4.0: settings.ini, gtk.css and bookmarks are GENERATED by the
    # `gtk` block in theme.nix. Only the assets the theme references are
    # carried here. (`colors.css` in both directories is imported by nothing —
    # only waybar has a colors.css, and that is a different file — but it is
    # cheap to keep and removing it is a separate decision.)
    "gtk-3.0/assets".source = ../../dotfiles/gtk-3.0/assets;
    "gtk-3.0/colors.css".source = ../../dotfiles/gtk-3.0/colors.css;
    "gtk-4.0/colors.css".source = ../../dotfiles/gtk-4.0/colors.css;

    # --- The one genuine holdout --------------------------------------------
    # corectrl writes corectrl.ini AND profiles/*.ccpro from its GUI, and that
    # GUI is the whole point of the program — fan curves and power profiles are
    # meant to be tuned interactively. There is no home-manager module, and
    # pinning the files would break the only way the tool is used. This is what
    # an honest out-of-store entry looks like: not "not converted yet", but
    # "converting it would remove functionality".
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
  # `source = ../../dotfiles/scripts` (not `link`) is deliberate: nothing writes
  # into ~/.scripts, so there is no reason for it to be mutable, and being in
  # the store is what makes it reproducible. Nix preserves the executable bit,
  # so the files stay runnable. `home.sessionPath` already puts it on PATH.
  #
  # Note the earlier trap this replaces: `home.file.".scripts".source =
  # mkOutOfStoreSymlink "${config.home.homeDirectory}/.scripts"` *writes to*
  # ~/.scripts while pointing at ~/.scripts — a symlink to itself. That is the
  # same self-referential bug as B1, and with backupFileExtension = "hm-bak" it
  # fails silently rather than loudly.
  home.file.".scripts".source = ../../dotfiles/scripts;

  # Removes a config directory that is still an out-of-store SYMLINK before
  # home-manager links anything into it.
  #
  # This exists because converting an already-linked directory to a store path
  # is otherwise destructive. home-manager creates the new generation's files
  # before tearing down the old links, so with `recursive = true` it writes
  # *through* the surviving symlink and into ~/src/nix-config — which on
  # 2026-07-30 replaced 65 tracked files in home/mango/ with symlinks into the
  # store. See docs/adr/0002 for the full account.
  #
  # `-L` is the whole test: after a successful conversion these are real
  # directories, so this becomes a no-op. It stays anyway, because it also
  # makes the conversion reproducible on a fresh machine rather than a manual
  # step someone has to remember.
  #
  # The list is DERIVED from xdg.configFile, not written out. An earlier
  # version hardcoded `mango` and `nvim`, and when htop/ncspot/zed/Kvantum/
  # nwg-look/gtk-3.0/gtk-4.0 were converted the next day, the guard silently
  # did not cover them — so activation wrote through their surviving directory
  # symlinks and clobbered ten tracked files in the repo, exactly the failure
  # the guard exists to prevent. A hand-maintained list of "things that must
  # not be forgotten" is the same bug waiting to happen, so it maintains
  # itself: every top-level name under ~/.config that this module manages is
  # covered automatically.
  home.activation.unlinkStaleConfigDirs =
    let
      # "gtk-3.0/assets" and "htop/htoprc" both guard "~/.config/<first
      # segment>", because that is the path a stale symlink would sit at.
      topLevel = lib.unique (
        map (n: lib.head (lib.splitString "/" n)) (lib.attrNames config.xdg.configFile)
      );
    in
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] (
      lib.concatMapStrings (d: ''
        if [ -L "${config.xdg.configHome}/${d}" ]; then
          run rm $VERBOSE_ARG "${config.xdg.configHome}/${d}"
        fi
      '') topLevel
    );

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
