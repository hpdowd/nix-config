# 0024 — The unattended lock follows the mode, and swaylock is its proof

**Status:** Accepted (2026-08-16)

Reverses the one paragraph of [0023](0023-noctalia-owns-its-own-actions.md) that
held the automatic lock back. Extends [0018](0018-lock-background-is-a-pool.md)
(the wrapper this changes) and [0022](0022-noctalia-mode-looks-like-noctalia.md).

## Context

[0023](0023-noctalia-owns-its-own-actions.md) gave `SUPER+Delete` to noctalia's
lock screen in noctalia mode and left `services.swayidle` on `lockscreen -f` —
so the only lock you ever saw *by hand* was noctalia's, and the only lock you
ever saw *after a sleep* was swaylock's. Which is nearly every lock: the lid,
the 5-minute timeout, the 30-minute suspend and `loginctl lock-session` all go
through swayidle. The mode looked like noctalia until you walked away from it.

Two reasons were given for holding it back, and only one of them survives.

**"That path must be synchronous."** It must, and it still is — see the
decision. swayidle holds a logind delay inhibitor and waits for the command to
return; `-f` returns only once swaylock has the lock. Anything replacing it has
to make the same promise, and `noctalia-shell ipc call lockScreen lock` on its
own cannot: it returns as soon as the shell has *read* the message. There is no
IPC that reports the lock is up (`lockScreen` declares exactly one function,
`lock()`, which sets `PanelService.lockScreen.active = true`), and `mmsg` has no
session-lock query — `get` takes ten subcommands and none of them is about the
lock.

**"It must work when noctalia is not running."** True, and it is a fallback
condition, not an argument against trying noctalia first. Two modes out of three
never ask; the third asks `systemctl --user is-active` before it does.

One more thing was wrong independently of the mode. **The lock screen's accent
was orange.** `ring-color` was `d65d0e` and `key-hl-color`/`text-caps-lock-color`
were `fe8019` — gruvbox oranges, and shades this machine uses in no other
surface, while `palette.nix` has said `accent = d79921` since it existed. It was
the last hex typed by hand into `programs.swaylock.settings` rather than read
from the palette, so nothing compared the two, and a drifted palette looks
deliberate.

## Decision

**`lockscreen` picks the locker; the callers do not.** Every lock path already
goes through that one wrapper — swayidle's `before-sleep`, `lock` and 5-minute
timeout, wlogout's button, `power-menu.sh` — so the mode check belongs there and
in exactly one place. It reads `current-mode`, and in `noctalia` mode with the
unit active it asks the shell first.

**swaylock is both the fallback and the proof.** Only one client may hold an
`ext-session-lock-v1` lock, so swaylock exits non-zero — "Failed to lock session
-- is another lockscreen running?" — precisely when the session is already
locked. The wrapper therefore does not need to ask whether noctalia's lock came
up: it runs swaylock afterwards either way, and

- swaylock **fails** ⇒ noctalia holds the lock. Proven, not assumed.
- swaylock **succeeds** ⇒ noctalia did not, and swaylock is now the lock.

Both branches return with the session locked, which is the guarantee swayidle's
inhibitor was built on, and the same guarantee `-f` gave before. This is the
`;`-not-`&&` property from [0018](0018-lock-background-is-a-pool.md) read
forwards: a second lock failing was already the normal case, and it is now load
bearing.

**The one-second wait decides *which* locker wins, never *whether* one does.**
The shell raises its lock asynchronously and there is nothing to poll, so the
wait is a preference with no correctness attached: too short and swaylock takes
the lock instead, which is the previous behaviour, not an unlocked screen. That
is the whole reason the probe is arranged this way — a timing guess that can
only pick the wrong *appearance* is a different kind of risk from one that can
leave the machine open.

**The manual key is unchanged**, and deliberately does not route through the
wrapper: `shell.sh` calls the IPC directly and reports "the shell is not
running" with `notify-send`. You are at the keyboard for that one, so a report
beats a silent substitution; nobody is at the keyboard for the other.

**The swaylock palette comes from `palette.nix`.** `opaque` and `wash` spell the
two alpha values the indicator needs (`ff`, and `55` to let the background pool
through), and the three orange values become `accent` and `warnColor`. The lock
screen now agrees with the bar, the menus and the window borders — and matching
noctalia's Gruvbox scheme matters more now that the two alternate on the same
machine.

### The checks

- **The wrapper's ipc pair is checked against the shipped QML**, alongside
  `shell.sh`'s thirteen ([0023](0023-noctalia-owns-its-own-actions.md)). It is
  scanned as a *built* script, since it is generated in `pkgs/default.nix`.
- **With a floor on the wrapper's half specifically.** `lockScreen lock` also
  appears in `shell.sh`, so a merged list would still contain it after the
  wrapper stopped calling anything — the check would pass by finding nothing
  while the unattended lock had quietly reverted. It asserts the wrapper's own
  matches are non-empty.

## Consequences

- **The lock screen is still the one thing here not verified end to end**, and
  this makes that matter more: [0023](0023-noctalia-owns-its-own-actions.md)
  risked one key, this risks every resume. Confirm noctalia's lock actually
  *unlocks* — `SUPER+Delete`, then type the password — before trusting a sleep
  to it. The way out is unchanged and worth knowing first: `CTRL+ALT+F2` to a
  TTY. Killing the shell does **not** unlock; `ext-session-lock-v1` keeps the
  session locked when the locker dies, by design (`docs/gotchas.md` → swaylock).
- **A lock in noctalia mode costs a second**, on the unattended paths only.
  The manual key does not go through the wrapper and is unaffected.
- **swaylock still runs on every noctalia lock, and fails.** That is the probe.
  It writes one line to the caller's journal, loads a pool image it then throws
  away, and is the reason the outcome is knowable at all.
- **`lockscreen` now depends on `noctalia-shell`.** It is in
  `environment.systemPackages` already, so the closure is unchanged, but
  removing noctalia means editing the wrapper — `docs/SYSTEM.md` §6 names it
  alongside `shell.sh`.
- **Two modes are untouched.** tiling and hud never take the branch: the mode
  check fails, and the wrapper is byte-for-byte the old one from there down.
