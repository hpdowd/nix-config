# 0046 — The weather panel is wayle's; the reading is not

**Status:** Accepted (2026-08-25).

Extends [0038](0038-weather-is-a-bar-module-the-menu-reads.md) and
[0044](0044-one-request-carries-the-tooltip.md): the script keeps the cache, the
tooltip and the control-centre row. What changes is what a **click** does.

## Context

Left-click on `custom-weather` ran `weather.sh refresh`. That fetch has no
surface: the only thing it can move is the two-digit label, and the label rarely
changes across a quarter of an hour. So the click read as a key that does
nothing — the same complaint [0031](0031-the-idle-inhibitor-outlives-the-bar.md)
records against a state you cannot see.

Three facts about wayle decided the shape:

- **A custom module cannot own a dropdown.** The types are wayle's own —
  `audio`, `battery`, `bluetooth`, `brightness`, `dashboard`, `network`,
  `notification`, `weather` — and there is no way to register a ninth. So a
  panel built from *this* script's cache is not available at any price.
- **A click action is a shell command OR a `dropdown:`, never both.**
  `on-action` runs after **shell** actions only, so it cannot be bolted onto a
  dropdown to make one click do two things.
- **`[modules.weather]` configures a service, not a bar module.** The Weather
  service reports `Service ready` at startup whether or not a layout carries the
  native module, so the panel works with the module nowhere on the bar.

## Decision

**Left-click opens `dropdown:weather`.** `refresh` moves to middle-click; `open`
keeps right-click. The panel carries its own refresh button and its own
"updated N ago", which is the feedback the old click never had.

**`[modules.weather]` is configured and appears in no layout.** It exists only
to aim the panel: `location` is `lat,lon` from `local.location`,
`refresh-interval-seconds` is `weather.sh`'s 900 s TTL, `time-format` is `24h`.
Coordinates, not a place name — a name is the **geocode lookup** 0038 rejected.

**The label stays the script's.** It is the reader that keeps the cache warm for
the control centre (0038) and the owner of the nineteen-field tooltip (0044).
Swapping the bar module for the native one would leave that row permanently
`stale`.

## Consequences

**Two readers of open-meteo, one set of coordinates.** Costs one extra request
per 900 s. This is not the two-owners failure the rest of this repo guards
against: neither side writes state the other reads, and both derive their
location from `local.location`, so the *config* cannot drift even though the two
fetches are independent.

**The panel unconfigured is San Francisco** — a complete, plausible forecast for
somewhere else, which is exactly this repo's signature bug. `checks/static.sh`
therefore asserts both halves in all six generated layouts: that
`[modules.weather].location` matches the generated `WEATHER_LAT`/`WEATHER_LON`
to four decimals, and that `custom-weather`'s left click still says
`dropdown:weather`.

**The tooltip and the panel now say much the same thing.** The tooltip stays:
the control centre reads its `alt` (0044), and hover costs less than a click.

**`minimal` has no weather module, so it has no panel.** Unchanged from 0038 —
the control-centre button is the way in to everything that layout drops.
