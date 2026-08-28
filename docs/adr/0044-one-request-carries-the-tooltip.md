# 0044 — One request carries the tooltip, and the way past it is a link

**Status:** Accepted (2026-08-21). **Amended 2026-08-24 — the control-centre
row is two keys, not a picker** (see the Decision's fourth verb, below).

Extends [0038](0038-weather-is-a-bar-module-the-menu-reads.md): same owner, same
three classes, and every *reading* still comes from the one host. It widens what
one fetch asks for and adds a fourth verb that opens a second one.

## Context

0038 asked open-meteo for eight fields at `forecast_days=1` and rendered five of
them. The rest of the day — what the next hours hold, when the sun sets, whether
the pressure is falling — was one URL parameter away and not asked for.

Three things were true and only the first is obvious:

- **open-meteo returns exactly the fields named and says nothing about the
  rest.** A name dropped from the query is `null` in the cache and an absent
  line in the tooltip, with the six lines around it still right. That is this
  same silent failure in a tidier form.
- **A single response cannot carry a trend.** Pressure now is a number;
  pressure falling is a fact, and it needs a second sample from an hour that has
  already gone.
- **A tooltip has a ceiling**, and past it the honest answer is a link — which
  means choosing a site, which means choosing who else learns where this
  machine is.

## Decision

**One request carries the whole tooltip, asserted in both directions.** Nineteen
fields across `current`, `hourly` and `daily`; `checks/static.sh` reads the
query out of `fetch()` and the `$w.<block>.<field>` references out of
`render()` and fails when either list holds a name the other does not. Compared
per block, so `hourly.is_day` cannot stand in for `current.is_day`.

**The cache is no longer the response verbatim.** It carries `.history`: six
hours of `{t, p}` pressure samples, pruned on write. `render()` compares against
one aged 2–4 h, preferring the closest to three, and **claims no trend when
there is none to claim** — a trend measured over the fifteen minutes since the
last poll is noise with an arrow drawn on it.

**A fourth verb, `open`, and it is the only one that reads nothing and renders
nothing.** Right-click on the bar module; ~~second entry on the control-centre
row, which is therefore a picker now rather than a verb — the shape
`act_network` and `act_volume` already have.~~

> ⚠️ **Amended 2026-08-24.** The picker is gone; the row's two verbs are two
> **keys** on the panel itself — **Enter** opens the forecast, **Ctrl+Enter**
> (`-kb-custom-1`) refetches. A picker was a second rofi surface drawn over the
> reading you opened the panel to look at, to choose between two things, and it
> cost a keystroke to reach either. The panel is a reader (0033); its one
> fetching row now costs one key.
>
> **The modifier on the accept key, because that is what the action is** — the
> other thing to do with *this* row, not a verb of its own. The cost is that
> `Control+Return` is not free: rofi ships it as `kb-accept-custom`, and a key
> with two actions is an **error dialog where the panel should be**. So the
> call unsets it — `-kb-accept-custom ""` — which costs nothing here, since
> `-no-custom` had already left accept-custom with nothing to accept. It was a
> key that did nothing and never said so.
>
> The trap underneath is rofi's, and it is in `docs/gotchas.md` → rofi:
> `-kb-custom-N` is the **only** accept key a `-dmenu` caller can distinguish,
> because Enter, Shift+Enter and Ctrl+Enter all exit 0 on their own bindings —
> the answer is an exit status of 10–28, and the `|| exit 0` every menu here is
> written with reads it as a cancel and closes the panel. The loop captures
> `$?` into a `case`.
>
> `refresh_<id>` is an **optional** second half beside `act_<id>`, and weather
> is its only implementer: it is the one fact here that lives off this machine.
> On every other row Ctrl+Enter falls through to the re-render each press
> already does, which re-reads that row's state, so the key is honest everywhere
> rather than dead on twelve rows. `checks/static.sh` asserts each `refresh_*`
> names a row, that the bind exists, and that the default holding the key is
> unset — four mutations, all caught. **One of them was not, at first:** the
> check grepped for `kb-accept-custom` across the whole file and was satisfied
> by the *comment explaining the unset*, so deleting the unset passed. Comments
> are stripped before the scan now. A check answered by prose about the thing is
> the same silent failure, in the shape of its own fix.

**The page is `local.location.forecastUrl`, beside the coordinates, and it
defaults to weather.com** — `/weather/today/l/<lat>,<lon>`, which resolves to
that site's own city page. **This is a second host learning where the machine
is**, on top of the open-meteo request 0038 counts as the price of the feature.
It buys a forecast page built for reading, which open-meteo has no equivalent of
— its own site is API documentation that happens to plot the coordinates.

Being a trade is exactly why it is a typed option and not a constant in the
script. `https://open-meteo.com/en/docs?latitude=…` tells nobody new and is one
line away; so is windy, or met.ie.

**`setsid -f`, with the failures it hides checked another way.** Both callers
wait on this verb, and `xdg-open` waits on the *browser* when one is not already
running — the control centre's render loop would hang until Zen exits. Forking
loses the exit status, so the two failures worth a sentence (no URL in the
generation, no `xdg-open` on `PATH`) are checked before the fork, and the third
is asserted: **`mimeapps.list` naming a `.desktop` nothing installs**, which
sends the click to whatever else claims the scheme without a word. That is not
hypothetical — it is why `SUPER+b` spawns `zen-beta` directly
(`universal/bind.conf`) after opening chromium for a month.

## Consequences

- **Three assertions, each mutation-tested**: the query and the tooltip agree
  both ways; every verb the bar or the control centre passes is implemented (a
  missing branch prints usage to a stderr nobody reads and exits 1); the https
  handler resolves to a file this generation installs. The third fails on
  `zen.desktop`, which is the bug that already happened.
- `render()` costs **30 ms against 10 ms**. The control-centre render still
  costs its slowest row and this is still not it — 73 ms, measured in 0033.
- The response is **5.3 KB against 1 KB, every 15 minutes**. The fetch is
  unchanged in every other respect — one host, same cadence, and the poll still
  answered off disk four times in five.
- **weather.com is a second party, and only a right-click reaches it.** Nothing
  polls it, nothing caches from it, and it learns the location once per click
  rather than four times an hour. One line in `local.location.forecastUrl`
  removes it.
- **No new glyphs and no new bar class.** The hourly and daily rows call
  `icon_for`, so the thirteen-glyph ladder keeps one owner; colouring the module
  when rain is likely was considered and left out, because `style-solid.css`
  says three classes and means it, and a fourth is a decision about what the bar
  is allowed to shout about.
- The two forecast blocks are **byte-padded**, which aligns them exactly: every
  value in a column carries the same number of multi-byte characters, so a
  constant byte width is a constant printed width. The bar's font is monospace,
  so no Pango markup is involved — but the tooltip is set with
  `set_tooltip_markup`, so the place name is escaped. An `&` there is invalid
  markup and the tooltip does not appear **at all**.
