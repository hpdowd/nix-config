# Architecture decision records

Numbered records of decisions that were **expensive to learn** and would be
expensive to re-litigate. Started 2026-07-30, after the Arch→NixOS migration,
by extracting decisions that already existed as prose.

`CLAUDE.md` remains the standing description of *how the system is now*. These
records explain *why it is that way*, and — more usefully — what happened when
it was the other way. Where the reasoning already lives in `CLAUDE.md` or
`docs/archive/`, these link to it rather than duplicating it, per
`docs/agents/domain.md`.

| # | Decision | Status |
|---|---|---|
| [0001](0001-flake-at-repo-root.md) | The flake lives at the repo root, dotfiles under `home/` | Accepted |
| [0002](0002-out-of-store-dotfiles.md) | Dotfiles a program rewrites stay out-of-store | Accepted |
| [0003](0003-state-outside-config-tree.md) | Runtime state and user data live outside the config tree | Accepted |
| [0004](0004-mode-scripts-own-theming.md) | Mode scripts own theming; no `active-theme` indirection | Accepted |
| [0005](0005-one-owner-per-daemon.md) | Exactly one owner per daemon | Accepted |
| [0006](0006-start-limits-on-remote-units.md) | Any unit touching a remote API needs a start limit | Accepted |
| [0007](0007-language-servers-declared.md) | Language servers are declared, not per-editor | Accepted |
| [0008](0008-arch-removed.md) | Arch removed outright; no dual boot | Accepted |

## Format

Each record: **Status**, **Context** (what was true, and what went wrong),
**Decision**, **Consequences** (including what it costs). Write the failure
mode down — a decision whose motivating bug is not recorded gets undone by the
next person who thinks it looks redundant.
