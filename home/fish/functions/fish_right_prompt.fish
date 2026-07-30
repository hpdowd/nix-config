function fish_right_prompt
    # Execution time — only shown when last command took > 5s
    if test $CMD_DURATION -gt 5000
        set -l s (math -s0 "$CMD_DURATION / 1000")
        if test $s -lt 60
            set -l t "$s"s
        else if test $s -lt 3600
            set -l t (math -s0 "$s / 60")m(math -s0 "$s % 60")s
        else
            set -l t (math -s0 "$s / 3600")h(math -s0 "$s % 3600 / 60")m
        end
        set_color a89984
        echo -n "$t  "
        set_color normal
    end

    set_color a89984
    echo -n (date '+%H:%M')
    set_color normal
end
