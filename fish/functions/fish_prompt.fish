function fish_prompt
    set -l last_status $status

    # ── Context indicators ───────────────────────────────────────────
    if set -q SSH_CONNECTION
        set_color bryellow
        echo -n '󰒍  '
        set_color normal
    end

    if set -q CONTAINER_ID
        set_color cyan
        echo -n '󰏗  '
        set_color normal
    end

    if set -q IN_NIX_SHELL
        set_color magenta
        echo -n '󱄅  '
        set_color normal
    end

    # ── Python venv ──────────────────────────────────────────────────
    if set -q VIRTUAL_ENV
        set_color brgreen
        echo -n '󰌠 ('(basename $VIRTUAL_ENV)')  '
        set_color normal
    else if set -q CONDA_DEFAULT_ENV; and test "$CONDA_DEFAULT_ENV" != base
        set_color brgreen
        echo -n '󰌠 ('$CONDA_DEFAULT_ENV')  '
        set_color normal
    end

    # ── Directory ────────────────────────────────────────────────────
    if not test -w .
        set_color brred
        echo -n '󰌾 '
        set_color normal
    end

    set_color yellow
    echo -n (prompt_pwd --full-length-dirs 2)
    set_color normal

    # ── Language icons ───────────────────────────────────────────────
    if test -f package.json -o -f bun.lockb
        set_color brgreen
        echo -n '  󰎙'
        set_color normal
    end
    if test -f Cargo.toml
        set_color magenta
        echo -n '  󱘗'
        set_color normal
    end
    if test -f go.mod
        set_color cyan
        echo -n '  󰟓'
        set_color normal
    end
    if test -f Gemfile
        set_color brred
        echo -n '   󰴭'
        set_color normal
    end
    if test -f composer.json
        set_color cyan
        echo -n '  󰌟'
        set_color normal
    end

    # ── Git ──────────────────────────────────────────────────────────
    set -l git_raw (command -q git; and git status --porcelain --branch 2>/dev/null)
    if test -n "$git_raw"
        set -l branch_line $git_raw[1]
        set -l file_lines $git_raw[2..-1]

        # Branch name — strip leading "## " and everything from "..." onward
        set -l branch (string replace -r '^## ' '' -- $branch_line | string replace -r '\.\.\..*' '')

        # Ahead / behind remote
        set -l ahead_m (string match -r 'ahead (\d+)'  -- $branch_line)
        set -l behind_m (string match -r 'behind (\d+)' -- $branch_line)
        set -l ahead (test (count $ahead_m)  -ge 2; and echo $ahead_m[2];  or echo '')
        set -l behind (test (count $behind_m) -ge 2; and echo $behind_m[2]; or echo '')

        # File counts
        set -l staged (string match -r '^[^ ?]'  -- $file_lines | count)
        set -l modified (string match -r '^.[^ ?]' -- $file_lines | count)
        set -l untracked (string match -r '^\?\?'   -- $file_lines | count)
        set -l stashed (git stash list 2>/dev/null | count)

        echo -n '  '

        # Branch — green if clean, yellow if dirty
        if test $staged -eq 0 -a $modified -eq 0 -a $untracked -eq 0
            set_color brgreen
        else
            set_color bryellow
        end
        echo -n " $branch"
        set_color normal

        # Ahead / behind
        if test -n "$ahead"
            set_color cyan
            echo -n " ↑$ahead"
            set_color normal
        end
        if test -n "$behind"
            set_color magenta
            echo -n " ↓$behind"
            set_color normal
        end

        # File status counts
        if test $staged -gt 0
            set_color brgreen
            echo -n " +$staged"
            set_color normal
        end
        if test $modified -gt 0
            set_color brred
            echo -n " ~$modified"
            set_color normal
        end
        if test $untracked -gt 0
            set_color bryellow
            echo -n " ?$untracked"
            set_color normal
        end
        if test $stashed -gt 0
            set_color white
            echo -n " \$$stashed"
            set_color normal
        end
    end

    # ── Background jobs ──────────────────────────────────────────────
    set -l job_count (jobs | count)
    if test $job_count -gt 0
        set_color white
        echo -n "  ⚙ $job_count"
        set_color normal
    end

    echo

    # ── Prompt char ──────────────────────────────────────────────────
    if test $last_status -eq 0
        set_color brgreen
        echo -n '❯ '
    else
        set_color brred
        echo -n '✗ '
    end
    set_color normal
end
