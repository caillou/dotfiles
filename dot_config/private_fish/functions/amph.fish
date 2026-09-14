function amph -d "Keep this Mac awake, the way Amphetamine did"
    set -l statefile "$HOME/.cache/amph.pid"
    if set -q XDG_CACHE_HOME
        set statefile "$XDG_CACHE_HOME/amph.pid"
    end
    mkdir -p (path dirname $statefile)

    # A session counts as live only while its caffeinate is still there: a
    # timed one exits on its own, and the state file outlives it. The name is
    # checked too, because the kernel reuses a pid and killing whatever
    # inherited this one is not what `amph off` promises.
    set -l pid ""
    if test -f $statefile
        set pid (cat $statefile)
        set -l name (ps -p $pid -o comm= 2>/dev/null | path basename)
        if test "$name" != caffeinate
            set pid ""
            rm -f $statefile
        end
    end

    switch "$argv[1]"
        case off stop
            if test -n "$pid"
                kill $pid
                rm -f $statefile
                echo "amph: off"
            else
                echo "amph: not running"
            end
            return 0
        case status
            if test -n "$pid"
                echo "amph: on (pid $pid)"
            else
                echo "amph: off"
            end
            return 0
    end

    # Bare `amph` toggles a running session off. With hours it is a restart
    # instead, handled below: the old caffeinate has to go before the new one
    # starts, or its assertion outlives the pid the state file tracks and
    # nothing can reach it again.
    if test -n "$pid"; and not set -q argv[1]
        kill $pid
        rm -f $statefile
        echo "amph: off"
        return 0
    end

    # Hours, decimals allowed, the h optional: 2h, 1.5h, .5, 0.25h.
    set -l secs 0
    set -l label ""
    if set -q argv[1]
        set -l hours (string replace -r 'h$' '' -- $argv[1])
        if not string match -qr '^[0-9]*\.?[0-9]+$' -- $hours
            echo "amph: hours, decimals allowed: amph 2h, amph 1.5h, amph .5h" >&2
            return 1
        end
        set secs (math -s0 "$hours * 3600")
        if test $secs -lt 1
            echo "amph: $argv[1] is less than a second" >&2
            return 1
        end
        set label (math "$hours")h
    end

    # Only ever this function's own caffeinate: one started by anything else
    # is not ours to kill, and the state file is what tells them apart.
    set -l replaced ""
    if test -n "$pid"
        kill $pid
        rm -f $statefile
        set replaced ", replacing pid $pid"
    end

    if test $secs -gt 0
        caffeinate -di -t $secs &
        set pid $last_pid
        disown $pid
        echo $pid >$statefile
        echo "amph: on for $label (pid $pid$replaced)"
    else
        caffeinate -di &
        set pid $last_pid
        disown $pid
        echo $pid >$statefile
        echo "amph: on, indefinitely (pid $pid$replaced) — 'amph off' to stop"
    end
end
