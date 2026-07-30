{ config, pkgs, lib, ... }:

{
  # --- zsh ------------------------------------------------------------------
  # Your login shell. On Arch, ~/.zshenv sets ZDOTDIR=~/.config/zsh and the
  # real config lives in ~/.config/zsh/conf.d/{10-aliases,20-path,30-bindings,
  # 40-prompt}.zsh.
  #
  # home-manager owns ~/.zshrc, so rather than duplicating those four files in
  # Nix, we keep sourcing them. dotfiles.nix symlinks ~/.config/zsh through as
  # a live (editable) directory.
  programs.zsh = {
    enable = true;
    # Absolute path — relative dotDir is deprecated.
    dotDir = "${config.xdg.configHome}/zsh";

    autosuggestion.enable = true; # zsh-autosuggestions
    syntaxHighlighting.enable = true; # zsh-syntax-highlighting
    enableCompletion = true; # zsh-completions
    historySubstringSearch.enable = true; # zsh-history-substring-search

    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    initContent = ''
      # Source the hand-written config, exactly as on Arch.
      for f in "$ZDOTDIR"/conf.d/*.zsh(N); do
        source "$f"
      done
    '';
  };

  # --- fish -----------------------------------------------------------------
  # Dropped 2026-07-28. CLAUDE.md described fish as the primary shell, but
  # /etc/passwd says zsh and always did, so fish was only ever a secondary
  # interactive shell.
  #
  # It also could not have worked as written: dotfiles.nix linked the whole
  # ~/.config/fish directory out-of-store while `programs.fish.enable` writes
  # ~/.config/fish/config.fish, putting two owners on one path — activation
  # would have failed. The same collision class as the old `gtk` block.
  #
  # The config files were deleted from the repo on 2026-07-30, once Arch was
  # gone and `command -v fish` confirmed the shell is not installed here at
  # all — they were config for a program that does not exist. They remain in
  # git history if wanted. To bring fish back, add the package and restore
  # EITHER `programs.fish.enable` OR a dotfiles link, never both.

  # --- Tools that hook the shell -------------------------------------------
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  # --- Aliases --------------------------------------------------------------
  # Kept minimal on purpose: the interesting ones (the $HOME-only eza filter,
  # the ll/la/lla/lls escape hatches) are shell *functions* in
  # ~/.config/zsh/conf.d/10-aliases.zsh and are sourced above rather than
  # re-expressed here.
  #
  # `pacman`/`pamcan` are gone — the NixOS equivalents are below.
  home.shellAliases = {
    cat = "bat";
    lf = "yazi";
    zed = "zeditor";
    pdf = "xdg-open";
    cleantmp = "~/.scripts/clean_tmp";
    lidaction = "~/.scripts/toggle_lid_action";

    # NixOS replacements for your pacman aliases. The flake lives in the clone
    # at ~/src/nix-config, NOT ~/.config — see dotfiles.nix and INSTALL.md
    # §0.1. ~/.config/nixos is not linked by dotfiles.nix, so it does not exist
    # on the installed system.
    rebuild = "sudo nixos-rebuild switch --flake ~/src/nix-config#thinkpad";
    rebuild-test = "sudo nixos-rebuild test --flake ~/src/nix-config#thinkpad";
    rebuild-boot = "sudo nixos-rebuild boot --flake ~/src/nix-config#thinkpad";
    update = "nix flake update --flake ~/src/nix-config";
    generations = "nixos-rebuild list-generations";
    gc = "sudo nix-collect-garbage --delete-older-than 30d";
    search = "nix search nixpkgs";
  };

  # PATH additions from ~/.config/zsh/conf.d/20-path.zsh. ~/.cargo/bin and
  # ~/.bun/bin still work because you keep rustup/bun user-installed.
  home.sessionPath = [
    "$HOME/.config/emacs/bin"
    "$HOME/.cargo/bin"
    "$HOME/.local/bin"
    "$HOME/.scripts"
    "$HOME/.bun/bin"
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BUN_INSTALL = "$HOME/.bun";
    # Matches the trick your Mangowm keybinds use to point fsel/walker at
    # ~/.config/mango rather than ~/.config.
    # XDG_CONFIG_HOME stays default; the override is per-keybind.
  };

  # NOTE: userName/userEmail/extraConfig were renamed to `settings.*`.
  programs.git = {
    enable = true;
    settings = {
      user.name = "Henry";
      user.email = "henry@dowd.ie";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };
}
