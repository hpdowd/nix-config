# 0042 — Bar separators belong to the layout, not to the module

**Status:** Accepted (2026-08-21)

Extends [0009](0009-generated-config-over-linked-files.md) — the layouts were already
generated; their *grouping* was still hand-written, in a different file, keyed by
the wrong thing.

## Context

`style-solid.css` drew the bar's separators with fifteen `border-left` /
`border-right` rules keyed by module id: `#network`, `#pulseaudio`, `#battery`
and so on. A separator was therefore a property of a **module**, while the thing
it separates is a property of **position**.

Those two come apart the moment a layout drops a module, and they had:

```
focus    notification │ weather control-center │ network │ vpn │ bluetooth │ …
full     notification │ weather cpu memory     │ network │ vpn │ bluetooth │ …
minimal  control-center │ battery │ tray │ power
```

`custom/weather` carried one `border-left`, and it opened a group containing
`cpu memory` in one layout and `custom/control-center` in another. Neither
grouping was chosen by anyone. Twelve of `full`'s sixteen right-hand modules
carried a border, so nearly every boundary was a line and nothing read as
grouped at all. `custom/control-center` had no border rule, so in `minimal` it
butted straight against the centre window title.

This is the repo's usual shape: it renders, it renders *plausibly*, and nothing
can tell you it is wrong.

## Decision

**A layout side is a list of groups.** `mkBar` flattens it and appends `#sep` to
the first module of each group after the first. waybar splits a module name on
`#` (`factory.cpp:129`), names the widget after the part before it and adds the
part after as a **style class** (`ALabel.cpp:34`, and the same three lines in
`wlr/taskbar.cpp`, `sni/tray.cpp` and `ext/workspace_manager.cpp`). One rule in
the stylesheet — `.sep { border-left: … }` — draws every separator.

Grouping is now declared where the order is declared, and a separator cannot
move because a neighbouring module was dropped.

**One canonical group order across all three layouts**, so a layout may drop a
module but never reposition one and SUPER+/ moves nothing that two layouts share.
That was previously a comment asking a reader to maintain it by hand
(*"so SUPER+/ does not move it"*) on a file where a module is one line in a list;
it is now an assertion.

`custom/weather` moves to `modules-left` beside the clock — one reading of what
it is like now — which the old note called out as wanted and rejected only
because modules-left had to be identical across layouts. The canonical order
subsumes that constraint.

## Consequences

- The stylesheet lost 15 border declarations and gained 1. It no longer decides
  anything about structure.
- Three `padding: 0 8px` overrides and two `min-width: 28px` floors went with
  them, and ten `format` strings lost a double space. All were compensation for
  the 0.54em advance — a glyph whose ink overflowed its cell needed the box
  padded out and the text pushed away. With an honest advance they were just
  gaps wider than the ones between groups.
- `mkBar` strips `#…` before checking a name against `modules` and before
  matching a tweak, so both existing assertions keep working. Definitions are
  emitted under the **suffixed** key, because waybar looks a tagged module's
  config up as `config_[name]`, not `config_[ref]` — settings under the bare name
  render waybar's defaults silently.
- Four scans in `checks/static.sh` had to strip the tag. Two of them caught the
  omission on the first run, which is the point of them.
- If a group's leading module hides — `custom/phone` when the phone is
  unreachable, `#taskbar.empty` — its separator hides with it. That degrades to
  a missing line, never a line in the wrong place. A CSS `:first-child` approach
  fails the other way: a hidden first child leaves the first *visible* module
  drawing a border against the screen edge.
- **`.sep` carries the group's spacing as well as its line**, because grouping
  only looks like grouping if the gap between groups beats the gap inside one.
  It takes **both** a `margin-left` and a `padding-left`: a border is drawn
  between the two, so margin is the only way to put space before the line and
  padding the only way to put space after it. Setting just the margin — as this
  first shipped — puts the whole gap on one side and looks like every group
  shifted left against its own separator.
- The base padding is therefore on **`.module`** — waybar's own class
  (`AModule.hpp:15`), added to the same widget as the `#id` and the `#sep` tag —
  and the base margin on `*`, so `.sep` can override both. Any `#id` rule that
  sets either takes the group gap off one side of a separator for the module it
  names, silently.
- Two wrong widgets were tried first, and each failed in its own way. `*` also
  matches the label inside a workspace button, the image inside a taskbar button
  and the icon inside a tray item, so its padding stacked on the button's own —
  visible as excessive spacing on the left of the bar and in the tray.
  `.modules-right > *` matches waybar's EventBox *wrapper*, one level out from
  everything else this sheet styles, so the padding went somewhere that does not
  draw it: modules rendered flush against each other, `cpu`'s `6%` touching
  `memory`'s icon, while `.sep` alone still had its gap.
- Measured on screen: 11px either side of every separator, against ≤12px total
  between modules inside a group — where both were 12–13px when the borders came
  off.

## The assertions

`checks/static.sh` gained four, each verified to fail when broken:

- every `#id` rule in the sheet belongs to a module some layout carries — the
  inverse direction, which was missing. `#custom-scratch-spotify` and
  `#custom-scratch-equibop` had outlived their modules with nothing to say so.
- modules carry `#sep` tags **and** the sheet has a `.sep` rule. Either half
  alone is silent: tags with no rule draw nothing.
- no module-keyed `border-left`/`border-right` comes back.
- two layouts never order a shared module differently.
