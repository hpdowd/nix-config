# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This repo is **single-context**: one `CONTEXT.md` and one `docs/adr/` at the root.

## Before exploring, read these

- **`CLAUDE.md`** at the repo root — for this repo it is the primary standing
  description of the system (shell environment, theming architecture, desktop
  layout, networking, the NixOS migration). Read it first; the skills' generic
  advice to start at `CONTEXT.md` assumes a codebase, and here the equivalent
  knowledge already lives in `CLAUDE.md`.
- **`CONTEXT.md`** at the repo root, if it exists — glossary and ubiquitous
  language.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo (this one):

```
/
├── CLAUDE.md                       ← the standing system description
├── CONTEXT.md                      ← glossary, once one exists
├── flake.nix                       ← the system, at the repo root
├── hosts/  modules/  pkgs/         ← the Nix that builds it
├── home/                           ← the dotfiles (mango, nvim, kitty, zsh, …)
└── docs/
    ├── adr/
    │   ├── 0001-....md
    │   └── 0002-....md
    ├── agents/                     ← these files
    └── archive/                    ← the Arch→NixOS migration, history only
```

Restructured 2026-07-30. Until then the repo was `arch-config`, its root *was*
`~/.config`, the dotfiles sat at the top level and the flake was in a `nixos/`
subdirectory. Anything still describing that layout is stale.

There is no `src/`. The "code" is the Nix under `hosts/`, `modules/` and
`pkgs/`, plus the shell scripts under `home/` — `home/mango/scripts/` is where
most of the real logic lives.

Multi-context (a root `CONTEXT-MAP.md` pointing at per-context `CONTEXT.md`
files) does not apply here and shouldn't be introduced without a reason.

## Note on where decisions already live

Several long-lived architectural decisions are already written down as prose
rather than as ADRs — the mode-script theming architecture in `CLAUDE.md`, and
the migration rationale in `docs/archive/MIGRATION.md` (side-by-side install,
`mkOutOfStoreSymlink` for writable dotfiles, dropping DankMaterialShell).
Treat those as binding in the same way an ADR would be. If `/domain-modeling`
converts any of them into a numbered ADR, link back to the prose rather than
duplicating it.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
