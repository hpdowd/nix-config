# 0006 — Any unit touching a remote API needs a start limit

**Status:** Accepted (2026-07-30)

## Context

`rclone-protondrive.service` was ported faithfully from an Arch template,
including its mount point `%h/mnt/%i`. But `~/mnt` is a symlink to
`/run/media/henry` — the udisks removable-media directory, which does not exist
unless a drive is mounted. `mkdir -p` reports `File exists` for a dangling
symlink rather than creating anything, so rclone could never make its mount
point.

The unit had `Restart=on-failure` and no start limit. It retried every 5
seconds. By the time it was noticed it was **230 restarts** deep.

The damage did not stay local. Proton first answered HTTP 429 with a one-hour
backoff, then escalated to **422 Code=2028** — *"unusual activity targeting your
account … we have temporarily limited access"*. That is an account-level abuse
restriction, not a backoff. It required either time or an appeal.

Two aggravating details: the *old* Arch template
(`rclone@ProtonDrive.service`) was never disabled and was separately
restart-looping on `/usr/bin/rclone` (203/EXEC, a path that does not exist on
NixOS) — two enabled units for one mount, see
[0005](0005-one-owner-per-daemon.md). And a local misconfiguration was the sole
cause; nothing about it was Proton's fault.

## Decision

- Every unit that contacts a remote service declares `StartLimitBurst` and
  `StartLimitIntervalSec` alongside `Restart=`, and a `RestartSec` measured in
  tens of seconds, not units.
- Proton Drive itself was **removed rather than repaired** — Proton actively
  blocks rclone's standard access method, and the mount was inherited config
  that nothing here used. Cloud sync is Nextcloud.

## Consequences

- **A `Restart=` without a `StartLimitBurst=` is a loaded gun.** When the target
  is someone else's API, the blast radius includes the account, not just the
  machine.
- Do not restart a rate-limited unit "to test" — each attempt reinforces the
  flag.
- Do not re-add Proton Drive.
- When porting a unit from another distro, check that every path in it exists
  *on this system*. `%h/mnt/%i` was valid syntax pointing at nothing.
