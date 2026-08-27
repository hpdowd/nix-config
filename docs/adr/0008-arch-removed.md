# 0008 — Arch removed outright; no dual boot, no fallback

**Status:** Accepted (2026-07-30)

## Context

NixOS was installed side-by-side on 2026-07-29: new `@nixos` and `@nix` btrfs
subvolumes on the existing `nvme0n1p2`, reusing `@home` and the shared ESP, with
Arch left bootable. The plan was to keep Arch for a month as a fallback.

Reusing `@home` is what made the migration survivable — profiles, credentials,
VPN certs and Bluetooth pairings all carried across untouched. It is also what
made the *residue* survive: Arch-era systemd user units in
`~/.config/systemd/user/` silently shadow the ones the flake generates, because
that directory takes precedence over `/etc/systemd/user/`. `micmute-led.service`
was shadowed this way and had restart-looped **6,464 times**, because the stale
copy had no `PATH=` and could not find `pactl`.

By 2026-07-30 the NixOS side was doing everything the Arch side did, the residue
had been swept, and keeping a bootable Arch mainly meant keeping a second set of
answers to "why is this behaving oddly?".

## Decision

Remove Arch: subvolumes, boot entry and EFI residue. No dual boot, no fallback.

## Consequences

- `/etc/fstab` mounts only `@nixos`, `@home`, `@nix` and `@log`.
- Anything Arch-conditional is dead code, not a compatibility shim — the
  `command -v lxpolkit` guard in `mango/universal/autostart.conf` will never
  fire again, and `pacman` aliases are gone.
- Rollback is now **NixOS generations**, not another distro. That is why
  `rebuild-test` matters for structural changes: it applies without touching the
  boot default, so a mistake is one reboot from gone.
- The residue lesson generalises: **`~/.config/systemd/user/` overrides
  `/etc/systemd/user/`**. When a declared unit misbehaves, check for a shadowing
  copy before debugging the declaration.
