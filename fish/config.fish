if status is-interactive
    set fish_greeting

    set -gx VIRTUAL_ENV_DISABLE_PROMPT 1 # prevent activate.fish from wrapping our prompt

    set scripts /home/henry/.scripts

    alias pamcan pacman
    alias pacman 'sudo pacman'
    alias l ls
    alias ls 'eza --color=always --icons=always'
    #alias la 'eza -a --color=auto --icons=auto'
    #alias ll 'eza -la --no-time'
    alias lla 'eza -lah --total-size'
    alias lls 'eza -lah --total-size'
    alias zed zeditor
    #alias cat bat
    alias lf yazi
    #alias cd z
    alias sudo sudo-rs
    alias lidt 'sudo $scripts/toggle_lid_action.sh /etc/systemd/logind.conf'
    alias cleantmp 'sudo $scripts/clean_tmp.sh'
    alias pdf xdg-open
    alias zen zen-browser
    alias mntandroid simple_mtpfs

    alias ..='cd ../'
    alias ...='cd ../..'
    alias ....='cd ../../..'
    alias .....='cd ../../../..'
end

function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    command yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

fish_add_path ~/.config/emacs/bin
fish_add_path ~/.cargo/bin
fish_add_path ~/.local/bin
#fish_add_path ~/.scripts

command -q zoxide; and zoxide init fish | source

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
