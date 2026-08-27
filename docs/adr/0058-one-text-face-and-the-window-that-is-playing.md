# 0058 — One text face, one calendar surface, and the window that is playing

**Date** 2026-08-28
**Status** Accepted
**Follows** [0057](0057-one-glyph-pack-was-never-enforced.md), which did the
same for the icons
**Font clause reversed** by
[0059](0059-the-bar-is-3270-body-text-is-hack.md) — the bar is 3270 again. The
calendar, the media click and the ADR-pointer check below all stand.

## Context

0057 put every glyph on one pack. Three seams were left.

**The bar was the only surface not reading in Hack.** `style-solid.css` asked
for 3270 Nerd Font; the rofi menus, GTK, fontconfig's `monospace` default and
the terminal all use Hack. So the type changed shape when the control centre
opened over the bar that opened it, and `nerd-fonts._3270` was in `fonts.nix`
for one file.

**The clock's calendar was a waybar tooltip.** `{calendar}` in
`tooltip-format`: it could not be navigated to another month, could not be kept
open, and appeared wherever the pointer happened to be. `menus/shell.sh` already
had a `calendar` row with `fb=none` — a key that reported "Only in noctalia
mode" in the mode it is used in.

**The media module's click was hardcoded to Spotify.** `mpris` shows whichever
player is active, and its left click ran
`scratch-toggle.sh Spotify spotify`. With a video playing in the browser the
label said one thing and the click did another, putting Spotify over the window
being listened to.

## Decision

**Hack everywhere, at 12px, normal weight.** Symbols Nerd Font Mono stays first
in the stack: a text face patches Nerd Font icons in at its own cap height, and
rendering Hack alone draws them visibly small. `nerd-fonts._3270` is removed,
and `checks/static.sh` asserts no surface asks for it — an undeclared family
falls back to generic monospace in silence. wlogout and wayle moved with the
bar.

**`menus/calendar.sh`, built on the weather panel.** Month grid with ISO week
numbers, today bold and underlined, Ctrl+Enter and Shift+Enter for the next and
previous month, Enter to return to today and then to close. The clock's left
click opens it and `SUPER+d` is bound for every mode; `format-alt-click = 3`
moves the label toggle to the right button. The grid is built in the script
rather than parsed out of `cal -w`, so the cell that is today is known rather
than located by counting columns.

**`media/media-focus.sh`, matching on pid.** D-Bus gives the process that owns
`org.mpris.MediaPlayer2.<player>`; mango reports a pid per client; the two join
on a fact neither invented. A named scratchpad gets `toggle_named_scratchpad`
because `focusid` cannot reveal one — which is why the hardcoded call worked for
Spotify and only Spotify.

**Every `docs/adr/NNNN` pointer is asserted to resolve.** Nothing checked this
before, and retiring four records in this pass left 24 comments citing them.

## Consequences

- Hack is wider than 3270. At 13px the right side overflowed and pushed
  `custom/notification` off the bar; 12px fits, and costs about six characters
  of media title. Both numbers came from rendering the whole bar at each.
- Dropping `font-weight: bold` was part of the size change, not separate: the
  bold was propping up 3270's thin bitmap-derived regular.
- MPRIS bus names and mango appids do not agree — zen-beta publishes
  `org.mpris.MediaPlayer2.firefox` — so any name table would have needed a row
  per browser and would have gone stale in silence. The pid match needs none.
- A player with no window of its own reports that rather than exiting 0 on a
  click that appears to do nothing.

## Removed in the same pass

`docs/WORK-LOG.md`, `docs/archive/`, both `docs/PLAN-*.md`, and ADRs 0019, 0021,
0035 and 0046 — 8,300 lines describing subsystems with no remaining
configuration, or superseded by a later record. 0045 was trimmed to the
wallpaper decision that is still in force. The Wayle section of
`docs/gotchas.md` went from 497 lines to the two constraints a rebuild still has
to satisfy. `git log` has all of it.
