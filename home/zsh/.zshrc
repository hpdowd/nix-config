# ~/.config/zsh/.zshrc

: "${ZDOTDIR:=$HOME}"

# --- Modules & Environment -----------------------------------------
zmodload zsh/datetime

# Ensure local completions directory exists and is added to fpath
[[ -d "$ZDOTDIR/completions" ]] || mkdir -p "$ZDOTDIR/completions"
fpath=("$ZDOTDIR/completions" $fpath)

# --- History & Core Options ----------------------------------------
HISTFILE="$ZDOTDIR/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
WORDCHARS=${WORDCHARS//[\/._-]/}

setopt SHARE_HISTORY          # share live across all sessions
setopt HIST_IGNORE_DUPS       # drop older dupes of a command
setopt HIST_IGNORE_SPACE      # ' command' (leading space) is not recorded
setopt HIST_REDUCE_BLANKS     # tidy whitespace
setopt EXTENDED_HISTORY       # record timestamps + duration
setopt HIST_VERIFY            # expand !! etc. into the line before running
setopt INC_APPEND_HISTORY     # commands are synced to history globally
setopt NO_FLOW_CONTROL        # free ^S and ^Q for tmux

setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS EXTENDED_GLOB AUTO_PARAM_SLASH GLOB_DOTS

# --- Completion Styling (zstyle) -----------------------------------
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$ZDOTDIR/.zcompcache"
zstyle ':completion:*' menu select                          
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"     
zstyle ':completion:*' group-name ''                        
zstyle ':completion:*:descriptions' format '%F{blue}%d%f'   

# --- Source Modular Configs ----------------------------------------
for f in "$ZDOTDIR"/conf.d/*.zsh(N); do source "$f"; done

# --- External Tool Integrations (fzf) ------------------------------
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

# --- Autocompletion (compinit) -------------------------------------
autoload -Uz compinit
() {
  local dump=("$ZDOTDIR"/.zcompdump(Nmh-24))
  if (( $#dump )); then compinit -C; else compinit; fi
}

# --- Plugins -------------------------------------------------------
ZSH_PLUGIN_DIR=${ZSH_PLUGIN_DIR:-/usr/share/zsh/plugins}
for p in zsh-autosuggestions/zsh-autosuggestions \
         zsh-history-substring-search/zsh-history-substring-search \
         zsh-syntax-highlighting/zsh-syntax-highlighting; do
  f="$ZSH_PLUGIN_DIR/$p.zsh"
  [[ -r $f ]] && source "$f"
done
