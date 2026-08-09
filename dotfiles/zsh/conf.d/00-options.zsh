# ~/.config/zsh/conf.d/00-options.zsh
#
# Recovered 2026-07-30 from ~/.config/zsh/.zshrc.hm-bak — the Arch-era .zshrc
# that home-manager displaced at the migration. `programs.zsh` reproduced the
# plugins, the history settings and compinit, but nothing else in that file:
# the options, the completion styling and the zsh/datetime module were all
# lost silently, because a missing setopt has no symptom you can see.
#
# Sourced from the generated ~/.zshrc *after* its own `set_opts` loop, so
# anything set here wins over the home-manager defaults. That is deliberate
# for the two NO_* options below.

# 40-prompt.zsh times commands with $EPOCHSECONDS, which only exists once this
# module is loaded. Without it the parameter is unset, so the timer was
# computing `0 - 0` on every prompt and never displayed anything.
zmodload zsh/datetime

# Hand-dropped completions, kept outside the store so they can be added
# without a rebuild.
[[ -d "$ZDOTDIR/completions" ]] || mkdir -p "$ZDOTDIR/completions"
fpath=("$ZDOTDIR/completions" $fpath)

# Treat / . _ - as word boundaries, so ^W deletes a path segment at a time.
WORDCHARS=${WORDCHARS//[\/._-]/}

# --- Options ---------------------------------------------------------------
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS EXTENDED_GLOB AUTO_PARAM_SLASH GLOB_DOTS

# home-manager's set_opts asserts NO_EXTENDED_HISTORY and NO_APPEND_HISTORY;
# these restore the Arch behaviour on purpose. HIST_VERIFY expands `!!` onto
# the line instead of running it straight away.
setopt HIST_REDUCE_BLANKS HIST_VERIFY EXTENDED_HISTORY INC_APPEND_HISTORY
setopt NO_FLOW_CONTROL # frees ^S and ^Q for tmux

# --- Completion styling ----------------------------------------------------
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$ZDOTDIR/.zcompcache"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{blue}%d%f'
