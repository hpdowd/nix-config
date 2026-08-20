# Architecture decision records

Numbered records of decisions that were **expensive to learn** and would be
expensive to re-litigate. Started 2026-07-30, after the Arch→NixOS migration,
by extracting decisions that already existed as prose.

`CLAUDE.md` remains the standing description of *how the system is now*. These
records explain *why it is that way*, and — more usefully — what happened when
it was the other way. Where the reasoning already lives in `CLAUDE.md` or
`docs/archive/`, these link to it rather than duplicating it, per
`docs/agents/domain.md`.

| # | Decision | Status |
|---|---|---|
| [0001](0001-flake-at-repo-root.md) | The flake lives at the repo root, dotfiles under `home/` | Accepted |
| [0002](0002-out-of-store-dotfiles.md) | Dotfiles a program rewrites stay out-of-store | Accepted (default superseded by [0009](0009-generated-config-over-linked-files.md)) |
| [0003](0003-state-outside-config-tree.md) | Runtime state and user data live outside the config tree | Accepted |
| [0004](0004-mode-scripts-own-theming.md) | Mode scripts own theming; no `active-theme` indirection | Accepted, **amended 2026-07-30 — Nix owns the GTK theme** |
| [0005](0005-one-owner-per-daemon.md) | Exactly one owner per daemon | Accepted |
| [0006](0006-start-limits-on-remote-units.md) | Any unit touching a remote API needs a start limit | Accepted |
| [0007](0007-language-servers-declared.md) | Language servers are declared, not per-editor | Accepted |
| [0008](0008-arch-removed.md) | Arch removed outright; no dual boot | Accepted |
| [0009](0009-generated-config-over-linked-files.md) | Generate config from Nix where a module exists; link files only where one does not | Accepted |
| [0010](0010-flake-check-is-the-gate.md) | `nix flake check` is the gate; lints tuned to fire only on real findings | Accepted (retires `verify-packages.sh`) |
| [0011](0011-shell-is-gated-too.md) | Shell is gated too; static assertions run inside the build | Accepted (extends [0010](0010-flake-check-is-the-gate.md)) |
| [0012](0012-secrets-in-sops.md) | Secrets live in sops-nix; only what is read is declared | Accepted |
| [0013](0013-networkmanager-profiles-declared.md) | The nine credential-bearing NetworkManager profiles are declared | Accepted (follows [0012](0012-secrets-in-sops.md)) |
| [0014](0014-declare-the-namer-not-just-the-file.md) | Declaring a file is not declaring the config — declare what names it | Accepted (extends [0009](0009-generated-config-over-linked-files.md), [0011](0011-shell-is-gated-too.md)) |
| [0015](0015-hibernate-not-suspend-on-the-lid.md) | The lid hibernates; there is no suspend phase | Accepted (the lid half; amended by [0016](0016-idle-suspends-the-lid-hibernates.md)) |
| [0016](0016-idle-suspends-the-lid-hibernates.md) | The idle rung suspends; the lid still hibernates | Accepted (amends [0015](0015-hibernate-not-suspend-on-the-lid.md)) |
| [0017](0017-tlp-profiles-not-platform-profile.md) | Power modes are TLP profiles; `platform_profile` was a placebo | Accepted |
| [0018](0018-lock-background-is-a-pool.md) | The lock background is a pre-generated pool, picked per lock | Accepted |
| [0019](0019-elephant-builds-only-reached-providers.md) | elephant builds only the providers something reaches | **Superseded** by [0021](0021-rofi-replaces-walker-and-elephant.md) — kept for the measurement that decided it |
| [0020](0020-noctalia-is-a-desktop-mode.md) | noctalia is a desktop mode, not a second desktop | Accepted, **corrected 2026-08-16 — its mango bar integration does not work** (extended by [0022](0022-noctalia-mode-looks-like-noctalia.md), [0023](0023-noctalia-owns-its-own-actions.md)) |
| [0021](0021-rofi-replaces-walker-and-elephant.md) | rofi replaces walker and elephant | Accepted (supersedes [0019](0019-elephant-builds-only-reached-providers.md); follows [0014](0014-declare-the-namer-not-just-the-file.md)) |
| [0022](0022-noctalia-mode-looks-like-noctalia.md) | noctalia mode owns its look; its settings are seeded *and* pinned | Accepted (extends [0020](0020-noctalia-is-a-desktop-mode.md), amending its seeding half) |
| [0023](0023-noctalia-owns-its-own-actions.md) | In noctalia mode the keys do noctalia's actions, through one table | Accepted, **amended 2026-08-16 — the automatic lock moved too** ([0024](0024-the-unattended-lock-follows-the-mode.md)) |
| [0024](0024-the-unattended-lock-follows-the-mode.md) | The unattended lock follows the mode; swaylock is its fallback *and* its proof | Accepted (amends [0023](0023-noctalia-owns-its-own-actions.md); extends [0018](0018-lock-background-is-a-pool.md)) |
| [0025](0025-patch-noctalias-mango-backend.md) | Patch noctalia's mango backend where it speaks dwl's dead flags, rather than route around it | Accepted (follows the correction on [0020](0020-noctalia-is-a-desktop-mode.md)) |
| [0026](0026-serve-the-ppd-bus-name-from-tlp.md) | Serve the power-profiles-daemon bus name from TLP, rather than leave it unowned | Accepted (follows [0017](0017-tlp-profiles-not-platform-profile.md), [0005](0005-one-owner-per-daemon.md); closes an inert widget from [0020](0020-noctalia-is-a-desktop-mode.md)) |
| [0027](0027-one-editor-nvim.md) | One editor: nvim. Helix is removed | Accepted (amends [0009](0009-generated-config-over-linked-files.md), [0007](0007-language-servers-declared.md)) |
| [0028](0028-one-palette-reaches-every-config-it-can.md) | One palette reaches every config it can; six theme packages it cannot | Accepted (extends [0009](0009-generated-config-over-linked-files.md); follows [0027](0027-one-editor-nvim.md)) |
| [0029](0029-the-lock-ramp-asserts-hue-not-greyness.md) | The lock ramp asserts the palette's hue, not greyness | Accepted (amends [0018](0018-lock-background-is-a-pool.md); forced by the migration [0028](0028-one-palette-reaches-every-config-it-can.md) enabled) |
| [0030](0030-the-scheme-is-a-file-not-an-option.md) | The scheme is a file, not an option; and contrast is asserted | Accepted (follows [0028](0028-one-palette-reaches-every-config-it-can.md), [0029](0029-the-lock-ramp-asserts-hue-not-greyness.md)) |
| [0031](0031-the-idle-inhibitor-outlives-the-bar.md) | The idle inhibitor is a unit, not a bool in the bar | Accepted (extends [0023](0023-noctalia-owns-its-own-actions.md)) |
| [0032](0032-the-theme-file-owns-its-artefacts.md) | The theme file owns its artefacts, and contrast is measured where it is drawn | Accepted (completes [0030](0030-the-scheme-is-a-file-not-an-option.md); amends [0029](0029-the-lock-ramp-asserts-hue-not-greyness.md)) |
| [0033](0033-the-control-centre-is-a-reader.md) | The control centre is a reader, not a second owner | Accepted (extends [0023](0023-noctalia-owns-its-own-actions.md); follows [0031](0031-the-idle-inhibitor-outlives-the-bar.md)) |
| [0034](0034-colour-follows-the-mode-artefacts-do-not.md) | Colour follows the mode; artefacts do not | Accepted (completes [0032](0032-the-theme-file-owns-its-artefacts.md); extends [0030](0030-the-scheme-is-a-file-not-an-option.md)) |
| [0035](0035-hud-is-removed.md) | hud is removed; a mode may not also force a layout | Accepted (simplifies [0034](0034-colour-follows-the-mode-artefacts-do-not.md); retires a rough edge from [0033](0033-the-control-centre-is-a-reader.md)) |
| [0036](0036-noctalias-templates-stay-off.md) | noctalia's auto-theming templates stay off | Accepted (settles phase 3b of [0034](0034-colour-follows-the-mode-artefacts-do-not.md); protects [0028](0028-one-palette-reaches-every-config-it-can.md)) |
| [0037](0037-night-light-does-not-cross-a-mode-switch.md) | Night light does not cross a mode switch; noctalia mode ends it | Accepted (extends [0005](0005-one-owner-per-daemon.md); follows the handover in [0031](0031-the-idle-inhibitor-outlives-the-bar.md)) |
| [0038](0038-weather-is-a-bar-module-the-menu-reads.md) | Weather is a bar module the menu reads, and a stale reading says so | Accepted (applies [0033](0033-the-control-centre-is-a-reader.md) to a fact with no owner) |
| [0039](0039-the-gate-asserts-its-own-size.md) | The gate asserts its own size | Accepted (applies the floor discipline of [0011](0011-shell-is-gated-too.md) and [0014](0014-declare-the-namer-not-just-the-file.md) to the file that enforces it) |

## Format

Each record: **Status**, **Context** (what was true, and what went wrong),
**Decision**, **Consequences** (including what it costs). Write the failure
mode down — a decision whose motivating bug is not recorded gets undone by the
next person who thinks it looks redundant.
