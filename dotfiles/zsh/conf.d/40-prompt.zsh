# ~/.config/zsh/conf.d/40-prompt.zsh

setopt prompt_subst

PROMPT_MAX_DIR_LEN=40
PROMPT_SHOW_TIME_ABOVE=5
PROMPT_MULTI_LINE=true

# --- Helpers -------------------------------------------------------
prompt_short_pwd() {
  local pwd="${PWD/#$HOME/~}"
  local max=$PROMPT_MAX_DIR_LEN

  if (( ${#pwd} > max )); then
    local IFS='/'
    local parts=(${pwd})
    local out=()
    local i
    for ((i=1; i<=${#parts[@]}-2; i++)); do
      [[ -n ${parts[i]} ]] && out+="${parts[i]:0:1}"
    done
    out+="${parts[-2]}"
    out+="${parts[-1]}"
    pwd="/${(j:/:)out}"
  fi
  print -r -- "$pwd"
}

prompt_git_info() {
  local branch dirty symbols=""
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || \
  branch=$(git rev-parse --short HEAD 2>/dev/null) || return 0

  if ! git diff --no-optional-locks --quiet --ignore-submodules -- 2>/dev/null; then
    dirty="*"
  fi

  symbols="($branch$dirty)"
  print -r -- "$symbols"
}

# --- Async Logic ---------------------------------------------------
TRAPUSR1() {
  ASYNC_GIT_INFO=$(<"${ZDOTDIR:-$HOME}/.zsh_tmp_git_$$" 2>/dev/null)
  zle && zle reset-prompt
}

async_git_fetch() {
  {
    local info
    info=$(prompt_git_info)
    print -r -- "$info" > "${ZDOTDIR:-$HOME}/.zsh_tmp_git_$$"
    kill -USR1 $$
  } &!
}

# --- Render --------------------------------------------------------
preexec() {
  PROMPT_CMD_START=$EPOCHSECONDS
}

precmd() {
  local exit_status=$?
  local duration="" pwd="" status_symbol="" status_color="green"

  if (( exit_status == 0 )); then
    status_symbol="✔"
    status_color="green"
  else
    status_symbol="✘ $exit_status"
    status_color="red"
  fi

  if (( PROMPT_SHOW_TIME_ABOVE > 0 && PROMPT_CMD_START > 0 )); then
    local delta=$(( EPOCHSECONDS - PROMPT_CMD_START ))
    if (( delta >= PROMPT_SHOW_TIME_ABOVE )); then
      duration=" (${delta}s)"
    fi
  fi

  pwd=$(prompt_short_pwd)
  async_git_fetch

  if [[ $PROMPT_MULTI_LINE == true ]]; then
    print -P "%F{cyan}%n@%m%f %F{blue}${pwd}%f %F{magenta}${ASYNC_GIT_INFO}%f%F{yellow}${duration}%f"
    PROMPT="%F{$status_color}${status_symbol}%f %# "
  else
    PROMPT="%F{$status_color}${status_symbol}%f %F{blue}${pwd}%f %F{magenta}${ASYNC_GIT_INFO}%f%F{yellow}${duration}%f %# "
  fi
}

# Cleanup async temp file when exiting shell
zshexit() {
  rm -f "${ZDOTDIR:-$HOME}/.zsh_tmp_git_$$"
}
