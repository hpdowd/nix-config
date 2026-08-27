# 0056 — a declared refresh signal needs a sender

**Status:** Accepted (2026-08-27).

Generalises the bar-push half of
[0054](0054-a-module-reports-the-screen-not-its-schedule.md) to every module that
declares one.

## Context

`SUPER+SHIFT+A` was reported as not toggling the idle inhibitor. It did: the
script ran, the unit changed state, and it exited 0. The bar did not move,
because `custom/idle-inhibitor` declares `signal = 12` and nothing sent
`RTMIN+12`. Its poll interval is 30 s, so the glyph was correct within half a
minute and wrong for the press itself.

The same audit found three more. Four of the five modules that declare a refresh
signal had no sender:

| module | signal | sender |
|---|---|---|
| `custom/night-mode` | 9 | restored in 0054 |
| `custom/vpn` | 10 | none |
| `custom/power-profile` | 11 | none |
| `custom/idle-inhibitor` | 12 | none |
| `custom/weather` | 13 | present |

All four were removed for the same reason, recorded in each script: waybar was
retired for wayle, wayle takes no signal, so `pkill -RTMIN+N waybar` matched
nothing and returned 1, which made the toggle exit non-zero.
[0051](0051-waybar-is-the-tiling-bar-again.md) brought waybar back and restored
none of them.

## Decision

**Every module declaring `signal = N` has a script sending `RTMIN+N`**, in the
form `weather.sh` already used: `pkill -RTMIN+N waybar 2>/dev/null || true`.
Plain `waybar`, because nixpkgs wraps it so `comm` is `.waybar-wrapped` and it is
invoked bare so its cmdline carries no path. `|| true` because the same scripts
run in noctalia mode, where the pkill matches nothing.

**`idle-inhibit.sh` keeps the exit status across the push.** `do_on` returns 1
when wlinhibit does not stay up, and `push_bar` ends in `|| true`, so pushing
last would report success for a key that inhibited nothing. The dispatch saves
`$?` and exits with it.

**`checks/static.sh` asserts the pairing**, reading the signal numbers from the
generated config and looking for a sender in the scripts. `^[^#]*` so that a
comment explaining a removed push does not count as one — all four scripts had
exactly such a comment.

## Consequences

- The failure is invisible without the check. A module with a dead signal still
  updates on its poll interval, so it is correct most of the time and wrong for
  the seconds after a key press. That reads as an unreliable keybind rather than
  a missing line.
- The check depends on the pkill spelling. A sender written some other way, or
  one that signals by PID, would pass the eye and fail here.
- `custom/weather` was already correct and is the reference for the form.
