# ~/.config/zsh/conf.d/10-aliases.zsh

scripts="$HOME/.scripts"

# --- ls / eza ------------------------------------------------------
# NixOS's /etc/zshrc (programs.zsh.enable) predefines ls/l/ll from
# environment.shellAliases. `ls` being an alias makes the ls() function below
# a parse error, which aborts the rest of this file — so clear them first.
unalias ls l ll 2>/dev/null

alias l='ls'
# `ls`/`l` hide personal top-level dirs *only while in $HOME* (mirrors ~/.hidden).
# Elsewhere, or with any argument (e.g. `ls foo`), nothing is filtered.
# `ll`, `la`, `lla`, `lls` are unfiltered — use them to see everything.
_HOME_HIDE='Android|Applications|blender|colors|go|log|R|share|temp|vaults|winboat|Zomboid'
ls() {
  if [[ $PWD == $HOME && $# -eq 0 ]]; then
    command eza --color=always --icons=always --ignore-glob="$_HOME_HIDE"
  else
    command eza --color=always --icons=always "$@"
  fi
}
alias la='eza -a --color=auto --icons=auto'
alias ll='eza -la --no-time'
alias lla='eza -lah --total-size'
alias lls='eza -lah --total-size'

# --- general -------------------------------------------------------
alias zed='zeditor'
alias cat='bat'
alias lf='yazi'
alias open='xdg-open'
alias zen='zen-browser'
alias mntandroid='simple_mtpfs'

# dot-dot navigation
alias ..='cd ../'
alias ...='cd ../../'
alias ....='cd ../../../'
alias .....='cd ../../../../'

# git
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate'

# --- Privilege & System Commands -----------------------------------
#if (( EUID != 0 )); then
#  alias sudo='sudo-rs'
#  alias lidt="sudo \"$scripts\"/toggle_lid_action.sh /etc/systemd/logind.conf"
#  alias cleantmp="sudo \"$scripts\"/clean_tmp.sh"
#  
#  function pacman() {
#    case $1 in
#      -S|-D|-R|-U|--sync|--database|--remove|--upgrade) command sudo pacman "$@" ;;
#      *) command pacman "$@" ;;
#    esac
#  }
#else
  # Safely neuter sudo if operating cleanly as root
#  alias sudo='command '
#fi

# --- yazi integration (y) ------------------------------------------
y() {
  local tmp cwd
  tmp=$(mktemp -t "yazi-cwd.XXXXXX") || return 1
  command yazi "$@" --cwd-file="$tmp"
  if [[ -f $tmp ]]; then
    cwd=$(<"$tmp")
    if [[ -n $cwd && $cwd != "$PWD" && -d $cwd ]]; then
      builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
  fi
}

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init --cmd cd zsh)"
fi
