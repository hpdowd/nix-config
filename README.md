# nix-config

Henry's NixOS system for a ThinkPad L14 Gen 5 — the flake that builds the
machine, and the dotfiles it installs.

## Layout

```
flake.nix          the system, at the ROOT so it can reference everything below
hosts/thinkpad/    host config + hardware-configuration.nix
modules/system/    boot, locale, networking, audio, desktop, fonts, power, …
modules/home/      home-manager: packages, shell, dotfiles, theme
home/              the dotfiles themselves (mango, nvim, kitty, foot, zsh, …)
pkgs/              overlay for anything not in nixpkgs
docs/              adr/ and agents/; archive/ holds the Arch→NixOS migration
```

Rebuild with `rebuild` — an alias for
`sudo nixos-rebuild switch --flake ~/src/nix-config#thinkpad`. Also
`rebuild-test` (applies without changing the boot default), `rebuild-boot`,
`update`, `generations`, `gc`.

---

## Start here

| I want to… | Read |
|---|---|
| Work on the configs themselves | [`CLAUDE.md`](CLAUDE.md) — the standing description of how this machine is put together |
| Understand a past design decision | [`docs/adr/`](docs/adr/) |
| Read the migration history | [`docs/archive/`](docs/archive/) — `MIGRATION.md`, `MIGRATION-GUIDE.md`, `INSTALL.md`, `WORK-LOG.md`. The Arch→NixOS migration finished 2026-07-29; these are kept for their post-mortems, **not** as live instructions |

---

## Layout

```
.
├── CLAUDE.md          the standing description of the system
├── nixos/             the NixOS flake + all migration documentation
├── mango/             Mangowm: compositor, waybar, walker, fsel, modes, scripts
├── nvim/  helix/  zed/            editors
├── kitty/  foot/  ghostty/        terminals
├── zsh/conf.d/                    shell (zsh is the login shell)
├── gtk-3.0/  gtk-4.0/  Kvantum/   theming
├── docs/agents/                   config for the engineering agent skills
└── yazi/ bottom/ htop/ lazygit/ glow/ imv/ ncspot/ nwg-look/ corectrl/
```

`nixos/` is the flake. It is **not** symlinked into `~/.config` on the
installed system — `nixos-rebuild` runs against the checkout directly.

---

## The `.gitignore` is an ordinary denylist

It was an **allowlist** until 2026-07-30, and it had to be: the repo root was
literally `~/.config`, ~9.6 GB of browser profiles, Electron app data, caches
and real credentials. Ignoring everything with `/*` and un-ignoring 38 known
paths was the only safe rule — and the cost was that any new directory stayed
invisible to git until someone added a `!/name/` line. That is how
`rclone.conf`, `gh/hosts.yml` and the user systemd units all fell through both
git *and* the backups at once.

The restructure moved the dotfiles under `home/`, so the root is now an
ordinary project root. Add a new config directory by just adding it.

Credential directories (`gh`, `glab-cli`, `opencode`, `gpu-screen-recorder`)
are still excluded deliberately and are **not** linked by the flake — see
`docs/archive/WORK-LOG.md` §1 for why linking them would have been worse than
not having them.

---

## Where the dotfiles live

`home/` in this repo; `~/.config/*` are symlinks into it, created by
home-manager. The flake sits at the repo root specifically so it *can*
reference `home/` — when it lived in a `nixos/` subdirectory the dotfiles were
outside the flake root and unreachable by any relative path.

Those links are `mkOutOfStoreSymlink`, so the directories stay **writable**.
That is still required for `home/mango/`, because the mode scripts write
`config.conf` into it. It is no longer required for `kitty/`, `foot/`, `nvim/`
and the rest — the `active-theme.*` indirection they needed was removed on
2026-07-30, so those can move into the store (`.source = ../../home/kitty`
with `recursive = true`) whenever the rebuild-per-tweak cost is acceptable.

`nixos-rebuild` reads this checkout, not `~/.config`.

---

## Applying changes

| Component | Reload |
|---|---|
| Mangowm | `~/.config/mango/scripts/reload.sh` |
| Switch mode | `~/.config/mango/scripts/modes/<mode>.sh` |
| kitty | `kill -SIGUSR1 $KITTY_PID` |
| foot | restart the terminal |
| Neovim plugins | `:Lazy sync` |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |
| NixOS (after migrating) | `rebuild` — see `nixos/modules/home/shell.nix` |

The system is still Arch. The flake is verified but has not been installed.
