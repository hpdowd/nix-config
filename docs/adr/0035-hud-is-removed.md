# 0035 — hud is removed; a mode may not also force a layout

**Status:** Accepted (2026-08-20)

Removes the third desktop mode introduced alongside
[0004](0004-mode-scripts-own-theming.md) and carried through
[0020](0020-noctalia-is-a-desktop-mode.md). Simplifies the ceiling
[0034](0034-colour-follows-the-mode-artefacts-do-not.md) had to assert, and
retires a rough edge recorded against the control centre in
[0033](0033-the-control-centre-is-a-reader.md).

## Context

`hud` was an overlay strip instead of a bar: a mode, sourced from its own
`mango/hud/`, with its own waybar layout and its own 129-line stylesheet. It
was liked in theory and never used in practice.

Unused is not by itself an argument for removal — a mode costs little to leave
alone. What made this worth doing is **what hud was the only instance of**. Four
mechanisms here were general rather than specific for hud's sake alone, and one
of them was a bug:

- **A mode that also forces a layout.** `waybar-restart.sh` picked the layout
  from the MODE when that mode was hud, and from state otherwise. That is why
  the layout was computed there rather than simply read.
- **The consequence, which was a real bug.** `waybar-layout.sh` and the control
  centre's `act_bar` both open a layout picker. In hud mode the pick was
  written to state and then overridden on every restart — accepted, recorded,
  and invisible. `state_bar` carried a branch to avoid *naming* a bar that was
  not on screen, but nothing stopped the picker from lying. Recorded in
  [0033](0033-the-control-centre-is-a-reader.md) as a pre-existing rough edge.
- **A second stylesheet.** `style-hud.css`, hand-written, tier 2, and the only
  consumer of the `surface` colour that `waybar/colors.css` generated.
- **The divergence ceiling in
  [0034](0034-colour-follows-the-mode-artefacts-do-not.md).** waybar and swaync
  are generated ONCE, from `scheme.nix`, and two modes ran them — so the check
  had to assert `tiling` and `hud` agreed *with each other* as well as with the
  artefact scheme.

## Decision

**hud is removed.** Deleted: `dotfiles/mango/hud/`, `scripts/modes/hud.sh`,
`dotfiles/mango/waybar/style-hud.css`, the `hud` layout in `waybar.nix`, and the
`hud` keys in `modes.nix` and `MODES`.

**A desktop mode may set what it draws, but not which of the user's layouts is
drawn.** That is the rule hud broke and the reason its removal deletes branches
rather than only files. `waybar-restart.sh` now reads the layout from state,
full stop; every layout the picker offers is reachable.

Two modes remain, and they differ in kind rather than degree: `tiling` runs
waybar and swaync, `noctalia` replaces both with its own shell
([0020](0020-noctalia-is-a-desktop-mode.md)). The mode machinery itself is
untouched — `apply_mode`, the per-mode configs, the runtime colour swap — because
noctalia keeps every bit of it earning its place.

## Consequences

- **The ceiling collapses to one comparison, and it generalises.** The check no
  longer names `tiling`: it derives the bar-bearing modes from `modes.nix` and
  asserts each wears the artefact scheme, so a mode added later is covered with
  nothing to remember. The floor stays — zero bar-bearing modes fails.
- **`surface` left `waybar/colors.css`.** `style-hud.css` was its only consumer,
  and `checks/static.sh` asserts in both directions: every generated colour used,
  every reference resolved. **The check found this, not a person.** Re-add the
  colour when a stylesheet wants it.
- **The generated-config assertion now names its layouts** rather than counting
  them. A count alone passes when one layout vanishes and another is emitted
  twice, and the layout NAMES are what `waybar-restart.sh` builds a filename
  from — a missing one takes the fallback-to-full path, which logs but keeps
  running.
- **`atBottom` stopped mirroring the vertical margins.** hud was the only layout
  with a non-zero margin (`margin-bottom = -28`, cancelling its own exclusive
  zone). For every remaining layout that swap was arithmetic on zero that read
  as load-bearing. Restore it before adding a layout with a vertical margin.
- **The ADRs that mention hud are left alone.** They are the record of what was
  true when written; this one supersedes the parts about a third mode. The
  *live* descriptions — `SYSTEM.md`, `CLAUDE.md`, `gotchas.md` and the comments
  in the files above — were updated in the same change, because those claim to
  describe the machine as it is.

Two negative tests before it landed: `tiling` given a scheme other than the
artefact one (caught, naming the mode), and `hud` put back into `MODES` with its
files gone (caught four ways — missing conf, missing mode script, no entry in
`modes.nix`, and no `colors-hud.conf` sourced). A check that has never failed
proves nothing.
