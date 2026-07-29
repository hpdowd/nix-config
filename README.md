# arch-config

Henry's personal dotfiles and application configuration for a ThinkPad L14
Gen 5, plus a NixOS flake that reproduces the same machine.

The repo is checked out in two places, and **which one is live depends on
which OS is booted** — see [Two working trees](#two-working-trees) below.

---

## Start here

| I want to… | Read |
|---|---|
| **Migrate this machine to NixOS** | [`nixos/MIGRATION-GUIDE.md`](nixos/MIGRATION-GUIDE.md) — standalone, start to finish |
| Know what was fixed in the config, and why | [`nixos/WORK-LOG.md`](nixos/WORK-LOG.md) |
| Understand the *design* decisions | [`nixos/MIGRATION.md`](nixos/MIGRATION.md) — why side-by-side, why these packages |
| Skip the explanation and just run the steps | [`nixos/INSTALL.md`](nixos/INSTALL.md) |
| Work on the configs themselves | [`CLAUDE.md`](CLAUDE.md) — the standing description of how this machine is put together |

Copies of all four migration documents also live on the backup drive, so they
can be read from another machine while this one is mid-install.

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

## The `.gitignore` is an allowlist

`~/.config` is ~9.6 GB, nearly all of it browser profiles, Electron app data
and caches — plus real credentials. So `.gitignore` ignores **everything** at
the top level and then un-ignores what is worth versioning.

**Adding a tool means adding a `!/toolname/` line at the same time**, or its
config is invisible to git *and* to any backup that copies tracked paths only.
That is exactly how `rclone.conf`, `gh/hosts.yml` and the user systemd units
all fell through both nets at once.

Credential directories (`gh`, `glab-cli`, `opencode`, `gpu-screen-recorder`)
are excluded deliberately and are **not** linked by the flake — see
`nixos/WORK-LOG.md` §1 for why linking them would have been worse than not
having them.

---

## Two working trees

| Booted | Live config | The other tree |
|---|---|---|
| **Arch** | `~/.config` — the real directories | `~/src/arch-config` goes stale |
| **NixOS** | `~/src/arch-config` — via the `~/.config/*` symlinks | `~/.config` is bypassed |

On NixOS the flake uses `mkOutOfStoreSymlink`, so `~/.config/mango`,
`~/.config/nvim` and friends are symlinks into the checkout and stay
**writable** — which the Mangowm mode scripts require, because they rewrite
`active-theme.*` and `jq`-patch Equibop's settings at runtime.

Keep the two in sync with an ordinary `git push` / `git pull`. `nixos-install`
and `nixos-rebuild` both read the checkout, not `~/.config`.

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
