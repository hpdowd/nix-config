# 0011 — Shell is gated too, and the static assertions run inside the build

**Status:** Accepted (2026-08-03)

Extends [0010](0010-flake-check-is-the-gate.md). Narrows `verify-claims.sh` to
the live-session checks.

## Context

0010 built a careful gate and pointed it at the wrong layer.

| | Lines | Files | Gated by |
|---|---|---|---|
| Nix | 3,930 | 22 | full closure build + statix + deadnix |
| **Shell** | **2,100** | **39** | **nothing** |

**Every failure catalogued in `CLAUDE.md` is a shell failure.** The
`#!/bin/bash` shebangs that exit 127 and render a waybar module empty. The
`mmsg -s -d` flags that answer `{"error":…}` *and exit 0*, leaving five scripts
and four waybar layouts dead while reporting success. `pkill -x` against a
nixpkgs wrapper, which leaked an elephant process per reload. The state path
one reader disagreed about, which made the mode switch one-way in silence. The
`cp` that produced a mode-0444 `config.conf`. Not one of them was a Nix error,
and not one of them was loud.

Separately, `verify-claims.sh` existed precisely because these claims decay —
but six of its eight checks needed no live system, so they were a manual step
nobody was obliged to run. One had already rotted: the battery/`full-at`
coupling check reported "could not read" after the generated waybar config it
read stopped existing under that name, and a check that fails *soft* is
indistinguishable from one that passes.

## Decision

**`nix flake check` gates shell as well as Nix, and every assertion that can be
decided without a running compositor is decided inside the build.**

Two new checks:

| Check | What it proves |
|---|---|
| `shellcheck` | every tracked bash script is clean at **default severity** |
| `static` | `checks/static.sh` — 11 assertions about the source and the build output |

### shellcheck runs at default severity, not `-S warning`

There were only 24 findings (0 errors, 4 warnings, 20 notes), so fixing them
outright cost less than staging the threshold down, and leaves no permanent
exemption to forget about. `SC1091` is excluded permanently — shellcheck cannot
resolve a `. "$HOME/.config/…"` source path statically, and that will not
change.

**16 of the 24 were SC2015, which is not a style nit.** `A && B || C` is not
if-then-else: C also runs when A succeeds and B fails. Every instance was
`<action> && notify-send success || notify-send -u critical failure`, so an
action that worked but whose notification failed reported failure.
`bluetooth-menu.sh` was worse than cosmetic — `[ "$power" = yes ] &&
bluetoothctl power off || bluetoothctl power on` turns the radio back **on** if
the off command fails.

### The static checks live in a script, not in `flake.nix`

`checks/static.sh` is a file so that the shellcheck gate lints it too. Shell
embedded in a Nix string is exactly the unchecked shell this record exists to
eliminate. It takes the source root and the home-manager generation as
arguments, so it also runs by hand against the working tree.

It runs against **`${self}`**, which contains tracked files only — so it sees
what a fresh clone gets, not what happens to be lying in the working directory.

### Every scan asserts a floor

This is the part most likely to be removed as paranoid. **A scan that stops
matching passes by finding nothing**, which is the exact shape of every bug
listed above. So the script count (≥30), the generated waybar config count
(=8) and the waybar script-reference count (>0) each fail rather than pass when
they come up empty.

The motivating incident is concrete: during the audit behind this change,
`nix run nixpkgs#shellcheck -- … 2>/dev/null` swallowed every finding and
reported **zero**, which reads exactly like a clean bill of health. Use
`nix shell nixpkgs#shellcheck -c …`.

### `verify-claims.sh` keeps only what needs a session

Two checks: `wlopm` enumerates an output, and `mmsg` reports a monitor. Both
are live-system facts no build can see, and the first one guards the belief
that once cost a flat battery overnight.

## Consequences

- **A new script is unchecked until it is `git add`ed**, because the flake
  source is the tracked tree. Not a flaw to fix — but know it, or a script can
  look gated while it is not.
- **`static` depends on the home-manager generation**, so it builds the home
  closure. That is already the `home` check, so it is cached, but a cold
  `nix flake check` now has one more consumer of it.
- **Three assertions are now enforced that were previously prose**: no
  `#!/bin/bash`, no dash-flag `mmsg`, and every `~/.config/mango/scripts/…`
  path in the eight generated waybar configs exists and is executable (46
  references, `on-click` handlers included).
- **Verify a gate by breaking something.** Both checks were confirmed to fail
  on a planted defect — an unquoted `rm -rf $var` for shellcheck, an
  `mmsg -s -d` call for static. A gate only ever observed passing has not been
  observed at all.
- **This does not cover `dotfiles/zsh/conf.d/*.zsh`.** They have no shebang and
  shellcheck does not do zsh. Still ungated, deliberately, and worth
  remembering before assuming all shell here is checked.
