# 0012 — Secrets live in sops-nix, and only what is read is declared

**Status:** Accepted (2026-08-04)

Prerequisite for [0013 — NetworkManager profiles](0013-networkmanager-profiles-declared.md)
(Phase 2, not yet written).

## Context

Until this landed, "reproducible" carried an asterisk. A fresh install of this
flake produced a machine that could not reach the VPN or `git.henrydowd.dev`,
because three kinds of credential existed only on this disk:

| Secret | Where it lived | Survived via |
|---|---|---|
| PIA username + password | `~/.local/state/mango/pia-auth`, plaintext, mode 600 | `@home` |
| `homelab` WireGuard key | `/etc/NetworkManager/system-connections/`, root-owned | hand restore |
| `gh` / `glab` / `tea` tokens | `~/.config/{gh,glab-cli,tea}/` | `@home` |

None of them is in any repo or backup. The `@home` subvolume is one disk
failure from taking all of them, and the migration audit of 2026-08-01 already
listed this as the biggest genuine gap.

The plaintext `pia-auth` was the sharpest edge, because it was *inside* the
config tree until 2026-07-30 and stayed out of git only because `.gitignore`
said so — a credential one `git add -A` away from history.

## Decision

**sops-nix, with a standalone age key, and a distinction between a secret that
is *stored* and one that is *declared*.**

### The age key is standalone, not derived from an SSH host key

The usual recipe converts a host SSH key with `ssh-to-age`. It cannot work
here: `services.openssh` is not enabled, so `/etc/ssh` holds `ssh_config` and
`ssh_known_hosts` and no host keys at all. The key is generated directly with
`age-keygen` into `/var/lib/sops-nix/key.txt` — outside the repo, and outside
the store, which is world-readable.

**That key is now a single point of failure and is in no backup.** Losing it
makes `secrets/secrets.yaml` unreadable. This is the cost, stated plainly
rather than discovered.

### A secret is DECLARED only where something reads it

`sops.secrets.<name>` decrypts to `/run/secrets/<name>` on every boot. So
declaring a secret nothing consumes puts a plaintext file on a running system
for no reason.

- **Declared:** `pia/username`, `pia/password` — read by `vpn-menu.sh`.
- **Stored only:** the WireGuard key and the three forge tokens. They are in
  `secrets.yaml` so a disk failure cannot lose them, and come back out with
  `sops -d --extract`.

`wireguard/homelab` becomes declared in Phase 2, when `ensureProfiles` gives it
a consumer. The forge tokens stay stored-only: `gh`, `glab` and `tea` each
rewrite their own config file, so handing them a read-only symlink is the same
fight as `corectrl` in [0002](0002-out-of-store-dotfiles.md).

### The PIA credentials became read-only, and the in-session setter is gone

`vpn-menu.sh` did not merely *read* `pia-auth` — it wrote it, from a "Set PIA
credentials" menu entry that prompted through walker. A sops secret is
root-installed at mode 0400, so that write path could not survive.

It was deleted rather than kept as a fallback. A fallback would have left a
writable plaintext path, which makes "no plaintext secret outside sops"
unenforceable — and an invariant that cannot be checked is one this repo has
repeatedly discovered was already violated. `ensure_credentials` now fails
loudly with a notification naming `secrets/secrets.yaml`.

Two secrets rather than one two-line file, which also retires the `head -1` /
`tail -1` parsing.

### `checks/static.sh` asserts the file is encrypted

**An unencrypted `secrets.yaml` looks exactly like an encrypted one** unless
you open it, and the mistake is unrecoverable once pushed. sops always writes a
`sops:` metadata block, so its absence means plaintext. The check asserts a
floor in the house style — zero files found is a failure, not a pass.

## Consequences

- **Changing the PIA credentials now needs a rebuild.** `sops
  secrets/secrets.yaml`, then `rebuild`. Slower than the walker prompt; the
  prompt is what could not be kept.
- **`/var/lib/sops-nix/key.txt` must be backed up separately**, by the same
  argument that applies to `~/.config/zen` — it is real state in no repo.
- **A fresh install needs the key present before the first rebuild.** Without
  it activation fails at secret installation rather than producing a machine
  that silently has no credentials, which is the better failure.
- **`sops` and `age` are devShell-only, not in `packages.nix`.** `sops`
  resolves recipients from the `.sops.yaml` in the working directory, so having
  it on the global PATH invites running it somewhere it picks up no rules.
- **Phase 2 is now unblocked** — `ensureProfiles.environmentFiles` has a source
  for the WireGuard key and the PIA passwords.
