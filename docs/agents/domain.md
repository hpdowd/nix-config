# Domain docs

How the engineering skills should consume this repo's documentation.

This repo is **single-context**: one `docs/adr/` at the root, no `CONTEXT.md`.

## Read before exploring

- **`CLAUDE.md`** — the rules that apply to every change here, and the routing
  table to everything else. Read it first. The skills' generic advice to start at
  `CONTEXT.md` assumes a codebase; here that knowledge lives in `CLAUDE.md`.
- **`docs/gotchas.md`** — the failure catalogue. Read the section for the area
  you are about to touch.
- **`docs/adr/`** — read the ADRs covering that area before changing it.
- **`docs/ANATOMY.md`** — what every file in the repo is for, and how the flake
  and the lock fit together.
- **`docs/SYSTEM.md`** — how to use the machine: keybinds, services,
  troubleshooting.

`CONTEXT.md` does not exist and is created lazily by `/domain-modeling`, if terms
ever need resolving. **Proceed silently when a file is absent** — don't flag it,
don't suggest creating it upfront.

## The code is not in `src/`

There is none. The code is the Nix under `hosts/`, `modules/` and `pkgs/`, plus
the shell under `dotfiles/`, and `dotfiles/mango/scripts/` is where most of the
logic lives. Most failures this repo has catalogued are shell failures, so weight
exploration accordingly.

> The repo was restructured on 2026-07-30. Until then it was `arch-config`, its
> root *was* `~/.config`, the dotfiles sat at the top level and the flake lived in
> `nixos/`. Anything still describing that layout — or a top-level `home/` — is
> stale.

## Where decisions already live

Some long-lived decisions are written as prose rather than as ADRs: the
mode-script theming architecture in `CLAUDE.md`, the tier rules in
`docs/SYSTEM.md` §6, and the structural rationale in `docs/ANATOMY.md` §6.
**Treat these as binding in the same way an ADR would be.** If
`/domain-modeling` converts one into a numbered ADR, link back to the prose
rather than duplicating it.

If your output contradicts an ADR, surface it rather than silently overriding:

> _Contradicts ADR-0009 (generate config from Nix) — but worth reopening
> because…_
