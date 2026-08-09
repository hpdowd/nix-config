# 0013 — The nine credential-bearing NetworkManager profiles are declared

**Status:** Accepted (2026-08-09)

Follows [0012 — secrets in sops](0012-secrets-in-sops.md), which was its
prerequisite.

## Context

38 connection profiles lived only in `/etc/NetworkManager/system-connections/`,
root-owned mode 600, restored by hand after the migration. Nine of them carry a
credential or can take the default route: the `homelab` WireGuard tunnel and
eight PIA OpenVPN exits.

This is the gap that has **actually bitten**. Restoring the profiles by hand
reintroduces `autoconnect=yes`; `homelab` then grabs the default route, pushes
an unreachable nameserver onto every link, and all DNS dies. It presents as
total name-resolution failure with nothing in the symptom identifying itself as
a VPN problem. `autoconnect=no` was *remembered*, not *enforced* — one restore
from a backup away from coming back.

Two things found while scoping it, both of which shaped the result:

- **The PIA CA lived in `$HOME`.** Every profile referenced
  `~/.local/share/networkmanagement/certificates/nm-openvpn/<name>-ca.pem`, left
  behind by `nmcli connection import`. NetworkManager runs as root and reads
  that path from a user's home directory. All eight files are byte-identical.
- **`vpn-menu.sh`'s importer is dead.** Its second path builds a server list
  from `~/Downloads/openvpn/*.ovpn` and injects credentials from sops on import.
  That directory does not exist, so the list is always empty and the branch is
  unreachable. The nine profiles are the entire menu.

## Decision

**Declare the nine in `networking.networkmanager.ensureProfiles`, with
credentials substituted at runtime from a sops template. Leave the other 29 to
NetworkManager's own state.**

### Declaring a subset is the supported shape, not a compromise

`ensureProfiles` writes to `/run/NetworkManager/system-connections/` and
**deletes nothing**. Undeclared profiles are untouched, so the ~29 ordinary
access points keep working exactly as before. Declaring them would mean putting
29 PSKs into sops to buy nothing — a hotel WiFi password is not a secret worth
managing, and losing one costs a re-type.

### Credentials are `$VAR`, never literals

The unit runs each generated keyfile through `envsubst` with
`EnvironmentFile=` pointing at a sops template. `/nix/store` is world-readable,
so an inlined password is a leak that looks identical to a working profile.
`sops.templates."networkmanager.env"` renders the three values to
`/run/secrets/rendered/`, mode 0400, and carries
`restartUnits = [ "NetworkManager-ensure-profiles.service" ]` — otherwise a
credential change re-renders the env file and the profiles keep the old value
until the next boot, silently.

`wireguard/homelab` moves from *stored* to *declared* under 0012's rule: it now
has a consumer.

### The PIA CA is vendored

`modules/system/pia-ca.pem` — PIA's public self-signed CA, valid to 2034,
shipped in every one of their `.ovpn` bundles. Public information, so plaintext
in git is correct; putting it in `secrets/` would be actively misleading. The
profile now references a store path, which removes the last undeclared file the
VPN depended on.

### The existing UUIDs are kept

Reusing them makes this a *replacement* rather than an addition. New UUIDs would
have produced nine duplicate entries in the VPN menu, distinguishable only by
which one actually connects.

### `checks/static.sh` asserts both invariants

- **No profile may omit `autoconnect=false`** — the failure this ADR exists to
  prevent.
- **Every `password` / `private-key` / `psk` must be a `$`-placeholder.**

Both read the keyfiles the unit will actually write — parsed out of the built
unit script — rather than the option that produced them, because the question is
what lands in `/run`. Both were confirmed to fail against a planted defect.

## Consequences

- **The `/etc` copies had to be moved aside.** All three keyfile directories are
  read, and a UUID present in both `/etc` and `/run` resolves to one file with
  the other ignored. Leaving them would have made the whole declaration a silent
  no-op — this repo's signature failure, in the change meant to end it. Verify
  with `nmcli -f NAME,FILENAME,AUTOCONNECT con show`: the nine must report a
  `/run/...` filename.
- **A VPN profile can no longer be edited from a GUI.** `nmcli con modify` on
  one of the nine writes a new file into `/etc`, which then shadows the
  declaration — the same two-owners trap as
  [0002](0002-out-of-store-dotfiles.md), in a different medium. Change
  `networking.nix` and rebuild.
- **`~/.local/share/networkmanagement/` is now unused** by these profiles, and
  `~/Downloads/openvpn/` was already unused. Neither is deleted here; the dead
  importer branch in `vpn-menu.sh` belongs to the Phase 4 sweep.
- **A fresh install now reaches the VPN**, which is what 0012 set out to make
  true and could not finish alone.
