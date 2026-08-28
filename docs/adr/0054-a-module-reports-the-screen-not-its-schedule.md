# 0054 — A module reports the screen, not its own schedule

**Status:** Accepted (2026-08-27).

Applies [0048](0048-state-colour-rides-the-class-the-script-prints.md)'s
resting-state rule to a module that had no resting state, and closes a gap in the
one-glyph-pack check from
[0051](0051-waybar-is-the-tiling-bar-again.md).

## Context

Reported as "night light isn't working". It was working: wlsunset held gamma
control, had computed `sunset 20:09, dusk 21:11`, and was at 6500 K because the
time was 18:53. The bar was wrong in two ways.

`custom/night-mode` reported the unit, not the screen. `do_status` emitted
`class:"on"` whenever the wlsunset service was active, so for most of the day the
moon was lit `@yellow` while the display was unwarmed.

The module also never updated. Its `interval` is `once` and its refresh is
`signal = 9`, and nothing sent that signal — the push was removed when waybar was
retired for wayle, and 0051 restored waybar without restoring it. So the module
ran at bar start and never again: a toggle changed the screen and left the bar
showing the previous state until the next bar restart. The script's comment said
it polled at 5 s.

## Decision

**Three states, read from the temperature wlsunset last applied**: `off` (unit
stopped), `armed` (running, still at the day temperature) and `on` (warming, with
the current temperature in the tooltip). wlsunset has no IPC and takes its
schedule from argv, so its log is the only available reading.

**The bar push returns** as `pkill -RTMIN+9 waybar 2>/dev/null || true`, the form
`weather.sh` uses. Plain `waybar`, because nixpkgs wraps it so `comm` is
`.waybar-wrapped` and it is invoked bare so its cmdline carries no path. `|| true`
because the same script runs in noctalia mode, where the pkill matches nothing.

**Scripts declare glyphs as `$'\UXXXXXXXX'`.** The one-glyph-pack check reads the
generated configs, so it cannot see a glyph a script prints. Two got through
0051's pass: `night-mode.sh` wrote Font Awesome's moon as `printf '\xef\x86\x86'`
(U+F186), and `network-menu.sh` carried seven Font Awesome glyphs as raw
literals, each labelled `# fa-wifi`, `# fa-lock` and so on. `network-menu.sh` had
already documented the escape convention for its ethernet icon and had not
applied it to the lines above it.

## Consequences

- Two assertions: every `\UXXXXXXXX` escape in a tracked script must be nf-md
  (≥ U+F0000), and no script may carry a raw private-use character, which would
  bypass the escape scan. The second is a byte test — U+E000–U+F8FF are the only
  sequences here leading with `0xEE`/`0xEF`, and plane 15 leads with `0xF3`.
  `^[^#]*` excludes a comment about a codepoint; `idle-inhibit.sh` has one.
- The rofi network menu changes appearance, from seven Font Awesome glyphs to
  nf-md equivalents. Each was rendered and checked before adoption;
  `fc-list ':charset=…'` confirms a codepoint exists but not what it draws.
- `armed` needs a style rule or it renders in the bar's default, which is the
  trap 0048 records. It is `@subtext`.
- The reading is a log scrape. If wlsunset changes its message the module falls
  back to reporting the configured temperature instead of the current one. That
  is the same shape as `power-profile.sh` reading `/run/tlp/last_pwr`.
- Nothing about wlsunset, its unit or its arguments changed.
