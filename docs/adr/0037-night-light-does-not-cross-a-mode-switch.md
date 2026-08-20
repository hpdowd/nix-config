# 0037 — Night light does not cross a mode switch

**Status:** Accepted (2026-08-20)

Extends [0005](0005-one-owner-per-daemon.md); follows the handover
[0031](0031-the-idle-inhibitor-outlives-the-bar.md) records for the idle
inhibitor.

## Context

Night light is `wlsunset`, a systemd user unit driven by
`scripts/menus/night-mode.sh`. Its only two controls are the `custom/night`
waybar module and the control centre's `night` row — **both tiling-mode
furniture**. noctalia mode runs no waybar, and `SUPER+C` there goes to
noctalia's own panel ([0033](0033-the-control-centre-is-a-reader.md)).

noctalia's own night light is pinned off
([0020](0020-noctalia-is-a-desktop-mode.md)) because only one Wayland client may
hold the gamma control and wlsunset has it. So that panel's switch moves a
setting driving nothing, and cannot reach wlsunset either.

The night light therefore **survived into the one mode with no way to reach
it**: warm screen, every control gone, nothing logged. And the unit is
`WantedBy=graphical-session.target`, so logging straight into noctalia produced
it with no mode switch to hook.

## Decision

**Entering noctalia stops `wlsunset.service`, and it does not come back.** The
stop lives in `scripts/modes/noctalia-start.sh`, beside the waybar, swaync and
dsearch handovers, so it runs on every entry — which is what covers the login
case. `notify-send` fires when something was actually turned off.

**`systemctl --user stop`, never `pkill`.** The unit is `Restart=always`
precisely because noctalia SIGTERMs wlsunset on every start
(`docs/gotchas.md` → night light); a kill is undone three seconds later.

Two alternatives, both declined:

- **Restore it entering tiling.** A second record of a fact the unit's own state
  already carried, to save one click.
- **Run noctalia's night light in its mode.** The temperature would live in two
  places — the state file `night-light-run.sh` reads at runtime, and a Nix pin
  no picker can move — drifting, with nothing able to compare them.
  [0028](0028-one-palette-reaches-every-config-it-can.md)'s failure in a
  different file.

## Consequences

- **noctalia mode has no night light**, and a round trip through it leaves the
  light off. Announced when it happens rather than discovered at midnight; one
  click on the bar restarts it.
- **The handover is asserted.** `checks/static.sh` reads `night-mode.sh`'s
  `UNIT=`, requires the generation to carry that unit, requires
  `noctalia-start.sh` to stop that name, and rejects a `pkill` of it. A drifted
  name errors nowhere at runtime: `is-active` answers "inactive" for a unit that
  does not exist, so the guard would just stop matching.
- **Both branches were made to fail first.** The `pkill` branch fired on the
  script's own comment about noctalia pkilling wlsunset — the grep strips
  comments now.
- **Removing noctalia removes this with it.** The stop is in a file
  `docs/SYSTEM.md` §6 already deletes; the assertion is inside the gate that
  skips when `dotfiles/mango/noctalia/` is absent.
