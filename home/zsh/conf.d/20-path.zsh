# ~/.config/zsh/conf.d/20-path.zsh

typeset -U path

path=(
  "$HOME/.config/emacs/bin"(N/)
  "$HOME/.cargo/bin"(N/)
  "$HOME/.local/bin"(N/)
  "$HOME/.scripts"(N/)
  $path
)

if [[ -d "$HOME/.bun" ]]; then
  export BUN_INSTALL="$HOME/.bun"
  path=("$BUN_INSTALL/bin" $path)
fi
