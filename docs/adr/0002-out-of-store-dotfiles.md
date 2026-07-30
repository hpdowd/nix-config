# 0002 — Dotfiles a program rewrites stay out-of-store

**Status:** Accepted (2026-07-30)

## Context

`home-manager` can install a config directory two ways:

- **Store-based** — `source = ../../home/kitty`. Nix copies the files into
  `/nix/store` and links there. Read-only, reproducible, carried by the flake.
- **Out-of-store** — `mkOutOfStoreSymlink`. `~/.config/kitty` points at the
  working checkout. Editable with no rebuild, but the flake carries *the
  symlink, not the content*: a fresh clone gets a link to a path that may not
  exist.

Until [0001](0001-flake-at-repo-root.md) only the second was possible. Once
both were, the question became which to use where — and the answer is not
preference. It is a hard constraint: **in the store, a tracked file becomes a
read-only symlink, so any program that rewrites it fails.** Usually silently,
which is the worst version.

## Decision

Store-based by default. Out-of-store **only** where a running program rewrites
a file tracked in this repo, and the blocking writer is named in a comment.

Where the writer can be *relocated*, relocate it and convert — that is strictly
better than accepting a mutable directory. Two were done this way:

- **`nvim`** — lazy.nvim rewrote `lazy-lock.json` in the config directory.
  `lua/config/lazy.lua` now sets `lockfile` to `stdpath("state")` and seeds it
  from the tracked copy on first run, so nothing writes to the config directory
  at all. Plain `source`.
- **`mango`** — the mode scripts `cp tiling/tiling.conf config.conf`. That file
  is gitignored, so it is not in the store and is not being overwritten;
  `recursive = true` leaves the directory writable so the `cp` still works.

Out-of-store as of 2026-07-30, with the blocking writer: `zed` (its UI rewrites
`settings.json`), `htop` (`htoprc` on quit), `ncspot`,
`gtk-3.0`/`gtk-4.0`/`nwg-look` (nwg-look writes `settings.ini`), `Kvantum`
(kvantummanager), `corectrl`.

## Consequences

- Eleven directories plus `~/.scripts` are reproducible and no longer depend on
  the checkout existing.
- The rest are not, and **symlinking them harder will not change that**. The
  real fix is converting each to a native home-manager module — `programs.htop`,
  `gtk.*`, `qt.*` — which *generates* the file from Nix so nothing needs to
  write it. Per-app work, not mechanical.
- `local.checkout` stays alive until the last entry converts.

## The `recursive = true` trap

`recursive = true` symlinks each file individually and leaves the **directory**
writable, which looks like the answer for `mango` — the mode scripts only need
to create `config.conf`, and that file is gitignored.

It is not, when the directory is *already* an out-of-store symlink. `recursive`
does not replace the directory; it writes files **inside** it — straight through
the existing symlink and into the checkout. Converting `mango` this way on
2026-07-30 **replaced 65 tracked files in `home/mango/` with symlinks**, showing
in `git status` as typechanges (` T `), with targets that resolved in a loop, so
the live config broke too. Recovered with `git checkout -- home/mango`.

`nixos-rebuild test` compounds it: it activates **without creating a profile
generation**, so the new store path has no GC root and a later
`nix-collect-garbage` can delete exactly what the repo now points at.

Converting an already-linked directory requires **deleting `~/.config/X`
first**, so home-manager builds a fresh directory rather than writing through
the old link.

That is now automated rather than remembered: the `unlinkStaleConfigDirs`
activation entry in `dotfiles.nix` runs `lib.hm.dag.entryBefore
[ "checkLinkTargets" ]` and removes those paths when — and only when — they are
still symlinks (`-L`). After a successful conversion they are real directories,
so it is a no-op. It stays in place because it also makes the conversion work
unattended on a fresh machine.
