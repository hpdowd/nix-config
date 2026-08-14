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
| [0002](0002-out-of-store-dotfiles.md) | Dotfiles a program rewrites stay out-of-store | Accepted (default superseded by [0009](0009-generated-config-over-linked-files.md)) |
| [0003](0003-state-outside-config-tree.md) | Runtime state and user data live outside the config tree | Accepted |
| [0004](0004-mode-scripts-own-theming.md) | Mode scripts own theming; no `active-theme` indirection | Accepted, **amended 2026-07-30 — Nix owns the GTK theme** |
| [0005](0005-one-owner-per-daemon.md) | Exactly one owner per daemon | Accepted |
| [0006](0006-start-limits-on-remote-units.md) | Any unit touching a remote API needs a start limit | Accepted |
| [0007](0007-language-servers-declared.md) | Language servers are declared, not per-editor | Accepted |
| [0008](0008-arch-removed.md) | Arch removed outright; no dual boot | Accepted |
| [0009](0009-generated-config-over-linked-files.md) | Generate config from Nix where a module exists; link files only where one does not | Accepted |
| [0010](0010-flake-check-is-the-gate.md) | `nix flake check` is the gate; lints tuned to fire only on real findings | Accepted (retires `verify-packages.sh`) |
| [0011](0011-shell-is-gated-too.md) | Shell is gated too; static assertions run inside the build | Accepted (extends [0010](0010-flake-check-is-the-gate.md)) |
| [0012](0012-secrets-in-sops.md) | Secrets live in sops-nix; only what is read is declared | Accepted |
| [0013](0013-networkmanager-profiles-declared.md) | The nine credential-bearing NetworkManager profiles are declared | Accepted (follows [0012](0012-secrets-in-sops.md)) |
| [0014](0014-declare-the-namer-not-just-the-file.md) | Declaring a file is not declaring the config — declare what names it | Accepted (extends [0009](0009-generated-config-over-linked-files.md), [0011](0011-shell-is-gated-too.md)) |
| [0015](0015-hibernate-not-suspend-on-the-lid.md) | The lid hibernates; there is no suspend phase | Accepted (the lid half; amended by [0016](0016-idle-suspends-the-lid-hibernates.md)) |
| [0016](0016-idle-suspends-the-lid-hibernates.md) | The idle rung suspends; the lid still hibernates | Accepted (amends [0015](0015-hibernate-not-suspend-on-the-lid.md)) |
| [0017](0017-tlp-profiles-not-platform-profile.md) | Power modes are TLP profiles; `platform_profile` was a placebo | Accepted |
| [0018](0018-lock-background-is-a-pool.md) | The lock background is a pre-generated pool, picked per lock | Accepted |
| [0019](0019-elephant-builds-only-reached-providers.md) | elephant builds only the providers something reaches | Accepted (extends [0014](0014-declare-the-namer-not-just-the-file.md), [0011](0011-shell-is-gated-too.md)) |

## Format

Each record: **Status**, **Context** (what was true, and what went wrong),
**Decision**, **Consequences** (including what it costs). Write the failure
mode down — a decision whose motivating bug is not recorded gets undone by the
next person who thinks it looks redundant.
