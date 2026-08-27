# 0050 — The weather panel is rofi's, because a dropdown answers no key

**Status:** Accepted (2026-08-26).

Reverses the click clause of
[0046](0046-the-weather-panel-is-wayles.md), which put the detailed reading on
`dropdown:weather`. Everything 0046 kept — the script owns the cache, the
tooltip and the control-centre row ([0038](0038-weather-is-a-bar-module-the-menu-reads.md),
[0044](0044-one-request-carries-the-tooltip.md)) — is unchanged.

## Context

0046 was right about the constraint and wrong about what followed from it. The
constraint: **a custom module cannot own a dropdown**, and a click action is a
shell command *or* a `dropdown:`, never both. So if the detailed reading is a
dropdown, it is wayle's dropdown, and 0046 pointed `[modules.weather]` at this
machine so the panel would at least be about the right place.

Two things that were not weighed then, both confirmed against wayle 0.7.0:

- **The dropdown set is closed at ten** — `audio`, `battery`, `bluetooth`,
  `brightness`, `calendar`, `dashboard`, `media`, `network`, `notification`,
  `weather` — enumerated in wayle's own `schema.json`. `CustomModuleDefinition`
  has 28 keys and not one of them is a panel. There is no eleventh to write.
- **Nothing opens a dropdown from outside the bar.** `com.wayle.Shell1` exposes
  `BarShow`, `BarHide`, `BarToggle` and no more; `wayle panel` has
  start/stop/restart/status/settings/inspect/hide/show/toggle. This is the same
  finding [0047](0047-a-retired-daemon-is-a-call-that-exits-0.md) recorded for
  the notification history, which is why `CTRL+ALT+\` is a rofi list.

So the detailed reading was reachable by **one mouse click on one bar module**,
in a shell whose every other menu answers a key. It was also the only surface
here drawn by something other than the menus — a different font stack, a
different edge, a different idea of what a panel is.

The reading itself was never wayle's: `weather.sh` already computes current
conditions, humidity, UV band, wind, a three-hour pressure trend, sun times, an
hourly forecast and a five-day one, and hands the lot to a tooltip. Drawing that
in rofi was a rendering problem, not a data one.

## Decision

**`weather.sh panel` draws the reading in rofi. `dropdown:weather` is gone, and
`[modules.weather]` with it.**

- The header block is `-mesg`, which is Pango markup: the temperature at
  `xx-large`, the place and condition under it, then the six detail lines.
- The list is the forecast — eight hourly rows at two-hour steps, then four
  daily — in **one column layout**, so hourly and daily line up as one table.
- **Enter opens the forecast page, `Ctrl+Enter` refetches and redraws.** Both
  act on the panel rather than on the selected row, so no row is inert.
- `custom-weather`'s left click and **`clock`'s right click** both call the
  verb. The clock is not incidental: wayle's default for `clock.right-click`
  *is* `dropdown:weather`, so leaving that key unwritten would have left a
  second way into an unconfigured panel — complete, plausible, and at wayle's
  default San Francisco once `[modules.weather]` came out.
- **`SUPER+CTRL+w`**, in `bind-shared.conf` beside the network, VPN and
  bluetooth menus. This key could not have existed before.

One reading, four ways in, and `hour_rows 2` is the only difference between what
the tooltip shows and what the panel does.

## Consequences

- **A key opens it**, which is the whole point, and the same surface appears in
  every desktop mode rather than only where wayle runs.
- **`weather.sh` grew a refactor before it grew a verb.** The jq, the detail
  block and the row formatter are now shared by the tooltip and the panel;
  three renderings of one read, rather than a second copy of the formatting.
- **The tooltip's hourly picks moved** from +1/+4/+7/+10 hours to +1/+5/+9/+13.
  Eight picks are emitted for the panel and the tooltip takes every other one.
- **`-mesg` has its first caller**, so `config.rasi`'s `message` rule stopped
  being speculative. It also turned up a rofi bug worth knowing: rofi sizes the
  window from the **configured font's metrics, not the rendered layout**, so a
  markup span larger than `font:` overflows and the last line is clipped. Fixed
  with 12px of bottom padding, measured both ways.
- **The check changed shape.** It asserted that the click said
  `dropdown:weather` and that `[modules.weather]` named this machine. It now
  asserts the verb exists, that no layout still names `dropdown:weather` or
  carries `[modules.weather]`, and that a key names the verb. The same scan also
  reads wayle's layouts for weather verbs now — it read only waybar's config
  until today, which left every click on the bar in service unchecked.
- **wayle's other nine dropdowns are untouched**, and `dropdown:calendar` is
  still the clock's left click. This is one panel, not a policy.
