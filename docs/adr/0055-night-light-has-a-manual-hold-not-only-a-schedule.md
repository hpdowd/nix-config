# 0055 — Night light has a manual hold, not only a schedule

**Status:** Accepted (2026-08-27).

Corrects [0054](0054-a-module-reports-the-screen-not-its-schedule.md), which made
the module report a schedule accurately without asking whether a schedule was the
only thing it should offer.

## Context

Every temperature in the night-light menu was the night value of a geographic
schedule. Picking 2700K in daylight stored the value and changed nothing visible,
because wlsunset stays at the day temperature until sunset. There was no way to
warm the screen now.

0054 fixed the reporting and left that premise alone.

## Decision

**Two modes, in `night-mode` state.** `auto` is the schedule: day temperature
until sunset, night temperature after. `manual` holds one colour all day, and the
menu's temperature rows set it, so picking a temperature means now.

**`manual` is a one-kelvin spread.** wlsunset has no constant-temperature flag
and rejects an equal pair:

```
$ wlsunset -l 53.35 -L -6.26 -T 2700 -t 2700
high temp (2700) must be higher than low (2700) temp
```

So `-T $((temp + 1)) -t temp`. One kelvin is not visible, and the sun's position
cannot move it. Checked at 19:26, before the 20:09 sunset: `manual` applied
3001 K immediately, `auto` applied 6500 K at the same moment.

**The click is a manual override.** It used to start and stop the unit, so in
`auto` before sunset clicking "on" started a schedule that would do nothing for
hours, changing neither the screen nor the bar. It now asks whether the screen is
warm rather than whether the unit is running: warm turns off, anything else warms
now by switching to `manual`.

**`Auto` is a toggle row that reports its state** — `Auto on · follows sunset`
against `Auto off · holding 2700K`. It is the only way back to scheduling once a
click or a temperature has overridden it, and a one-way row would not show which
way it currently points. `Off` is a row too, replacing `6500K (off)`.

**The label is the moon alone.** It briefly carried the sunset time so that
enabling night light in daylight produced a visible change. `manual` answers that
directly, because the moon lights when the screen is warm.

## Consequences

- `armed` and `off` are separated only by weight, `@subtext` against `@subtext`
  at half opacity. That is workable now: the state needing clear feedback is
  "I just asked for night light", which is `manual` and lights the moon.
- `night-mode` is absent by default and `state night-mode auto` supplies the
  fallback, so an existing machine keeps scheduling with nothing to migrate.
- `restart` starts a stopped unit, so choosing any mode also turns night light
  on. Only `Off` stops it.
- A click leaves `auto` behind. An override that restored itself would be its own
  surprise, and the Auto row names the way back.
- `is_warming` reads the journal, so a click costs one `journalctl` call. The
  cheaper alternative, trusting the unit's active state, is the bug being fixed.
- The one-kelvin spread looks like a typo. It is commented at the line with the
  error wlsunset gives for the obvious alternative.
