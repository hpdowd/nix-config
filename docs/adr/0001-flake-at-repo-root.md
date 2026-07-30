# 0001 — The flake lives at the repo root, dotfiles under `home/`

**Status:** Accepted (2026-07-30)

## Context

The repo was `arch-config`, and its root **was `~/.config`** — the flake sat in
a `nixos/` subdirectory with ~40 config directories above it.

Two consequences, and the second is the one that mattered:

1. `.gitignore` had to be a 119-line **allowlist**. The root was 9.6 GB of
   browser profiles, Electron data, game launchers and real credentials, so the
   only safe rule was ignore `/*` and un-ignore 38 known paths. Anything new
   stayed invisible to git until someone added a `!/name/` line. `rclone.conf`,
   `gh/hosts.yml` and the user systemd units all fell through git *and* the
   backups this way.
2. The dotfiles were **outside the flake root**. A flake can only reference
   paths at or below its own directory, so `../mango` does not resolve. It was
   not that converting configs to store paths was hard — it was structurally
   impossible. That, not writability, is why every entry in `dotfiles.nix` was
   an out-of-store symlink.

## Decision

Move the flake to the repo root and the dotfiles down into `home/`. Rename to
`nix-config`. `.gitignore` becomes an ordinary denylist.

## Consequences

- `source = ../../home/kitty` resolves, so configs can move into the store
  individually. See [0002](0002-out-of-store-dotfiles.md) for which do.
- New config directories are tracked by default. The allowlist's failure mode
  is gone.
- The repo is expected at a known path — see `local.checkout` in
  `modules/home/options.nix`. It cannot be derived; a flake evaluates from a
  store copy of itself.
- **Do not move the flake back down a level.** It re-breaks reference #2, and
  silently: entries keep working through the out-of-store links, so the loss of
  ability is invisible until someone tries to convert one.
