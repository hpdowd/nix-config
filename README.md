# nix-config

Henry's NixOS system for a ThinkPad L14 Gen 5 — the flake that builds the
machine, and the dotfiles it installs.

**This is the booted system.** NixOS was installed 2026-07-29; Arch was removed
2026-07-30. There is no dual boot and no fallback.

## Layout

```
flake.nix          the system, at the ROOT so it can reference everything below
flake.lock         pinned inputs — re-lock deliberately with `update`
hosts/thinkpad/    host config + hardware-configuration.nix
modules/system/    boot, locale, networking, audio, desktop, fonts, power, …
modules/home/      home-manager: packages, shell, dotfiles, theme
home/              the dotfiles themselves (mango, nvim, kitty, foot, zsh, …)
pkgs/              overlay for anything not in nixpkgs
docs/agents/       config for the engineering agent skills
docs/archive/      the Arch→NixOS migration — history, not live instructions
verify-packages.sh checks that package names still resolve in nixpkgs
```

`docs/adr/` and `CONTEXT.md` do not exist yet. That is deliberate — see
`docs/agents/domain.md`; they get created lazily, when a decision or a term
actually needs recording.

## Rebuilding

| Alias | Runs |
|---|---|
| `rebuild` | `nixos-rebuild switch --flake "$HOME/src/nix-config#thinkpad"` |
| `rebuild-test` | `nixos-rebuild test` — applies **without** changing the boot default |
| `rebuild-boot` | `nixos-rebuild boot` — next boot only |
| `update` | `nix flake update` |
| `generations` | `nixos-rebuild list-generations` |
| `gc` | `nix-collect-garbage --delete-older-than 30d` |

Use **`rebuild-test`** for anything structural: it applies without touching the
boot default, so a mistake is one reboot from gone. Defined in
`modules/home/shell.nix`.

**Quote flake refs in zsh.** `EXTENDED_GLOB` is on (`zsh/conf.d/00-options.zsh`),
which makes `#` a pattern operator — so an unquoted `~/src/nix-config#thinkpad`
is globbed, matches nothing, and fails with `zsh: no matches found:` before
`nixos-rebuild` runs at all.

---

## Start here

| I want to… | Read |
|---|---|
| Work on the configs themselves | [`CLAUDE.md`](CLAUDE.md) — the standing description of how this machine is put together |
| Know how agents should use this repo | [`docs/agents/`](docs/agents/) — domain docs, issue tracker, triage labels |
| Read the migration history | [`docs/archive/`](docs/archive/) — `MIGRATION.md`, `MIGRATION-GUIDE.md`, `INSTALL.md`, `WORK-LOG.md`. Kept for their post-mortems, **not** as live instructions |

---

## Where the dotfiles live

`home/` in this repo; `~/.config/*` are symlinks into it, created by
home-manager. The flake sits at the repo root specifically so it *can*
reference `home/` — when it lived in a `nixos/` subdirectory the dotfiles were
outside the flake root and unreachable by any relative path.

Those links are `mkOutOfStoreSymlink`, so the directories stay **writable**, and
edits take effect immediately without a rebuild. That is still required for
`home/mango/`, because the mode scripts write `config.conf` into it. It is no
longer required for `kitty/`, `foot/`, `nvim/` and the rest — the
`active-theme.*` indirection they needed was removed on 2026-07-30, so those can
move into the store (`.source = ../../home/kitty` with `recursive = true`)
whenever the rebuild-per-tweak cost is acceptable.

`nixos-rebuild` reads this checkout directly. The repo is expected at
**`~/src/nix-config`** — `dotfiles.nix` hardcodes that path, and it cannot be
`~/.config` itself, since that is where the links are written *to*.

---

## The `.gitignore` is an ordinary denylist

It was an **allowlist** until 2026-07-30, and it had to be: the repo root was
literally `~/.config`, ~9.6 GB of browser profiles, Electron app data, caches
and real credentials. Ignoring everything with `/*` and un-ignoring 38 known
paths was the only safe rule — and the cost was that any new directory stayed
invisible to git until someone added a `!/name/` line. That is how
`rclone.conf`, `gh/hosts.yml` and the user systemd units all fell through both
git *and* the backups at once.

The restructure moved the dotfiles under `home/`, so the root is now an ordinary
project root. Add a new config directory by just adding it.

What is still ignored is specific and intentional: generated files
(`home/mango/config.conf`), the wallpaper, zsh's compdump/cache, and the
credential directories (`gh`, `glab-cli`, `opencode`, `gpu-screen-recorder`).
Those credential dirs are **not** linked by the flake either — see
`docs/archive/WORK-LOG.md` §1 for why linking them would have been worse than
not having them.

One consequence worth knowing: **flakes copy only git-tracked files**. A file
that is ignored, or merely untracked, does not exist as far as the build is
concerned — which is why `home/mango/wallpaper/` cannot move into the store as
things stand.

---

## Applying changes

| Component | Reload |
|---|---|
| NixOS / home-manager | `rebuild` (or `rebuild-test`) |
| Mangowm | `~/.config/mango/scripts/reload.sh` |
| Switch mode | `~/.config/mango/scripts/modes/<mode>.sh` |
| zsh | open a new shell, or `source ~/.config/zsh/conf.d/<file>.zsh` |
| kitty | `kill -SIGUSR1 $KITTY_PID` |
| foot | restart the terminal |
| Neovim plugins | `:Lazy sync` |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |

Dotfile edits under `home/` need no rebuild — the out-of-store symlinks make
them live. Anything in `modules/`, `hosts/`, `pkgs/` or `flake.nix` does.
