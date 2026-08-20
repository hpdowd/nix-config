# 0038 — Weather is a bar module the menu reads, and a stale reading says so

**Status:** Accepted (2026-08-20)

Applies [0033](0033-the-control-centre-is-a-reader.md) to the first fact on this
machine that had **no owner at all**; the location option follows
[0030](0030-the-scheme-is-a-file-not-an-option.md)'s shape.

## Context

The control centre's first three additions — microphone, phone, a bar button —
each read a fact something already owned. Weather owns nothing. Nothing in the
repo mentioned it, and the obvious build is a control-centre row that runs
`curl`.

That inverts [0033](0033-the-control-centre-is-a-reader.md). A row that fetches
makes a *menu* the owner of a fact the bar cannot see, and the bar is where a
glanceable reading belongs. It also puts the fetch on the menu's render path:
`menus/control-center.sh` renders every row in parallel and costs its slowest
one — 73 ms measured — so a ten-second socket there is the whole menu failing
to appear.

Two further things were true and neither is obvious:

- **noctalia resolves coordinates through `api.noctalia.dev/geocode` and
  `/geolocate`.** Copying its widget copies a third-party indirection between
  this machine and its own location. `open-meteo` needs no such thing: it takes
  latitude and longitude directly, and `timezone=auto` resolves the zone from
  them, so `time.timeZone` is not duplicated either.
- **A weather widget's characteristic failure is looking right.** The fetch
  fails, the last reading is served, and yesterday's temperature renders in the
  same font as today's. Nothing errors and nothing logs — this repo's signature
  bug with a nicer glyph.

## Decision

**`scripts/system/weather.sh` is the one owner. `custom/weather` and the
control-centre row are both readers of it**, exactly as `night`, `awake`,
`power` and `phone` read theirs. The bar module was built first and the row
second, deliberately: the module is what keeps the reading current.

**Three verbs, and only two may touch the network.**

| Verb | Who runs it | Network |
|---|---|---|
| `status` | `custom/weather` | fetches when the cache has expired |
| `read` | the control-centre row | **never** — cache or an error |
| `refresh` | Enter on that row | always, past the TTL, then signals waybar |

`read` exists for the render path. It is asserted by `checks/static.sh` rather
than left to the comment above it, because the symptom of getting it wrong is a
menu that does not appear — not an error anyone would go looking for.

**A stale reading is a different answer, and wears a different class.** The
cache is served when the fetch fails, because losing the reading is worse — but
as `class` `stale`, greyed by `style-solid.css` and carrying its age in both the
tooltip and `alt`. `error` is no reading at all and renders `?`, never a
plausible number. Three classes, three appearances.

**Coordinates are declared, once, as `local.location` in
`modules/home/options.nix`,** typed `float`. `dotfiles.nix` generates
`mango/universal/weather-location.env` from it and the script sources that. A
transposed sign is then an eval error rather than a request for the weather in
the sea — which open-meteo answers cheerfully, since every point on the globe
has weather. The script **refuses** when that file is missing rather than
defaulting, because `set -u` plus an unset variable sends
`latitude=&longitude=`, and 0°N 0°E is in the Gulf of Guinea and has weather too.

**The description reaches the row as `alt`, not as a substring of the tooltip.**
`alt` is one of waybar's own custom-module keys and is unused here because
`format` is `{}`. The first attempt cut the phrase out of the tooltip and
rendered `light` for `light drizzle`.

**`custom/weather` is in `full` and `focus`, not `minimal`.** It was `full`
only for one rebuild, on the reasoning that `focus` drops the readouts — but
`focus` drops the *diagnostic* readouts (`cpu`, `memory`, the taskbar) and
weather is ambient, like the clock. `focus` is also the daily layout, so leaving
it out put the control-centre row at `stale` as its **default** rather than its
edge case, since nothing else was keeping the cache warm. `minimal` keeps
nothing: the row is the way in there, and `stale` is honest for a bar that
carries four modules on purpose.

## Consequences

- Four new assertions in `checks/static.sh`, each covering something invisible
  when wrong: the generated coordinates reach the script under the names it
  sources; the refresh signal number agrees between `weather.sh` and
  `waybar.nix`; the control-centre row calls `read`; and every WMO code
  `describe()` has a phrase for, `icon_for()` has a glyph for. All four were
  mutation-tested — each fails when its fact is broken.
- The WMO 4677 table is written out in full — 28 codes — rather than to the one
  value a test fetch returned. Same lesson as the phone row's five classes
  ([0033](0033-the-control-centre-is-a-reader.md)): a code with no branch is
  `unknown (code N)` and says so, because silently drawing "clear" for an
  unknown code is the one failure a weather widget can have that looks like
  success.
- **This machine tells open-meteo where it is, every 15 minutes, unauthenticated
  over TLS.** That is the cost of the feature and it is not reduced by caching.
  It is one host rather than noctalia's two, and it is the host answering the
  question.
- The cache lives at `$STATE_DIR/weather.json` and is named in the script and
  nowhere else — so the drift the design note worried about (a path in Nix and a
  path in a script) does not exist to check. Nix names the *coordinates* file;
  the script names the cache.
- A `location.nix` beside `scheme.nix` was declined for now. One consumer does
  not earn a file; a second one does.
