# secrets/

`secrets.yaml` is sops-encrypted and **tracked in git**. The age private key is
not: it lives at `/var/lib/sops-nix/key.txt`, root-owned, mode 600, and exists
in no repo and no backup. Recipients are in `../.sops.yaml`.

**Back that key up separately.** Without it this file is unreadable and a fresh
install cannot reach the VPN.

## Edit

```sh
nix develop          # or direnv; sops and age are devShell-only
sops secrets/secrets.yaml
```

`sops` resolves recipients from the `.sops.yaml` in the working directory, so
run it from the repo root. Re-encrypt after changing recipients with
`sops updatekeys secrets/secrets.yaml`.

## Two tiers, and the distinction matters

**Declared** — something reads it, so `modules/system/secrets.nix` names it and
sops-nix decrypts it to `/run/secrets/<name>` at boot:

| Key | Path | Read by |
|---|---|---|
| `pia/username` | `/run/secrets/pia/username` | `dotfiles/mango/scripts/menus/vpn-menu.sh` |
| `pia/password` | `/run/secrets/pia/password` | same |
| `wireguard/homelab` | `/run/secrets/wireguard/homelab` | the template below |

All three are also rendered into `/run/secrets/rendered/networkmanager.env`,
which `networking.networkmanager.ensureProfiles` feeds to `envsubst`. That is
what keeps the credentials out of the world-readable store — see
`docs/adr/0013`.

**Stored only** — kept here so a disk failure cannot lose them, but nothing
declares them, because a declared secret with no consumer is a plaintext file
sitting in `/run/secrets` at every boot for no reason:

| Key | Retrieve with |
|---|---|
| `forge/gh` | `sops -d --extract '["forge"]["gh"]' secrets/secrets.yaml` |
| `forge/glab` | `sops -d --extract '["forge"]["glab"]' secrets/secrets.yaml` |
| `forge/tea` | `sops -d --extract '["forge"]["tea"]' secrets/secrets.yaml` |

The forge tokens stay stored-only on purpose — `gh`, `glab` and `tea` each
rewrite their own config file, so handing them a read-only symlink is the
`corectrl` fight. On a fresh install, extract and run `gh auth login` /
`tea login add`.

See `docs/adr/0012`.
