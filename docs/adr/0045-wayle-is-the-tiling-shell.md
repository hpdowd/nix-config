# 0045 — wayle is the tiling mode's shell, and each mode owns its wallpaper

**Status:** Accepted (2026-08-24)

Supersedes the wallpaper clause of
[0020](0020-noctalia-is-a-desktop-mode.md) — *"`wallpaper` off (`awww` owns
it)"*. The rest of 0020 stands.

## Context

waybar drew the tiling bar and swaync served its notifications; noctalia mode
replaced both with one shell. So tiling ran two programs where noctalia ran one,
and the seam showed: the idle inhibitor, the night-light toggle and the
power-profile cycle were each a script the bar polled, because a bar is not a
shell and had no state of its own to offer.

wayle is a shell — bar, notification daemon, OSD and wallpaper engine — with a
**native `mango-workspaces` module**, which waybar needed a custom script for.
nixpkgs has it, home-manager has `services.wayle`, and its `[[modules.custom]]`
runs a command and templates its JSON, so this repo's seven custom scripts port
unchanged.

Three things about it decided the shape:

- **`services.wayle.settings` claims `~/.config/wayle/config.toml`** the moment
  it holds one value. The bar has three layouts and two positions, switchable
  at runtime, so that path has to stay a link this repo re-points.
- **It is a notification daemon.** Running it beside swaync means two claimants
  for `org.freedesktop.Notifications`, and the second does not error — it just
  never receives one ([0005](0005-one-owner-per-daemon.md)).
- **It has no signal IPC.** waybar took a push (`pkill -RTMIN+N waybar`) from
  whichever script changed the state. wayle offers `poll`, `watch` and
  `on-action`, and nothing else.

## Decision

**wayle is the tiling mode's shell.** It draws the bar, owns notifications and
drives the wallpaper engine there. noctalia is unchanged and still does all
three itself in its own mode.

**Two layers, the same split waybar has** — and this is the load-bearing part:

| Layer | What | Where |
|---|---|---|
| generated TOML | layouts, module settings, colours | `modules/home/wayle.nix` → `wayle/layouts/<layout>-<position>.toml` |
| hand-written SCSS | the spacing rhythm and the group dividers | `dotfiles/wayle/index.scss` → `wayle/styles/index.scss` |
| generated SCSS | the one colour the sheet needs | `wayle/styles/_colors.scss`, from `palette.nix` |

The sheet is not optional polish. wayle's two tightest spacing knobs,
`button-gap` and `button-label-padding`, are `ScaleFactor` and **clamp at
0.25**, silently — so the config layer cannot produce a dense bar at all. The
stylesheet overrides the built-in styling outright, which is where waybar's
density came from too (`style-solid.css`, never waybar's JSON).

- **Six generated layouts, and `config.toml` is not one of them.**
  `settings = { }` leaves it unclaimed and
  `scripts/wayle/wayle-restart.sh` re-points it per layout and position — the
  mechanism `apply_theme` uses for its four links
  ([0034](0034-colour-follows-the-mode-artefacts-do-not.md)), and the reason
  `programs.ncspot.settings` is empty. Asserted absent from the generation.
- **`index.scss` IS claimed**, because wayle only seeds it when absent and
  never rewrites one that exists. One owner, unlike `config.toml`.
- **Grouping is wayle's own `BarGroup`**, `{ name, modules }`, rendering a
  container whose CSS id is the name. The group name is an id, so a duplicate
  is an eval assertion.
- **Dividers are a `border-left` on the group**, not wayle's `separator`
  module. A border costs no width, being drawn inside the group's own box.
  `style-solid.css` does the same for waybar.
- **One colour, and state is the exception.** Everything is
  `fg-muted`/`fg-default`; colour is reserved for the battery thresholds and
  the active tag.
- **Each custom module carries `on-action` AND an interval.** wayle has no
  signal IPC, so the click path and the changed-from-elsewhere path are
  separate. The `pkill -RTMIN+N waybar` lines came out of the five scripts in
  the same change.
- **swaync is dead in tiling**, killed by `tiling/autostart.conf` *before* wayle
  starts — the order `noctalia-start.sh` already uses for the same handover.
- **Each mode owns its wallpaper.** wayle's engine drives `awww` in tiling;
  noctalia's `wallpaper.enabled` is now `true`.
- **Neither unit starts at login.** Both want `graphical-session.target`, which
  runs in every mode; both are `mkForce [ ]` and the mode scripts own them.

**waybar and swaync are still generated and still declared.** Nothing starts
them. Removing them is a separate change, deliberately: until wayle has been
lived with, reverting is one line in `tiling/autostart.conf`.

## Consequences

- **State renamed `waybar-layout`/`waybar-position` → `bar-layout`/`bar-position`**,
  with `mode_has_waybar` → `mode_has_bar`. One reset to the defaults, taken in
  the same change rather than later: a half-renamed state file is the one-way
  mode switch `lib.sh`'s header describes.
- **`wlr/taskbar` is gone.** wayle has no equivalent, and only `full` carried
  it. Not faked.
- **Feedback on a keybind toggle is up to one poll interval**, where a signal
  was instant — 5s for night mode, 30s for the idle inhibitor and the power
  profile.
- **Seven assertions in `checks/static.sh`**: `config.toml` absent from the
  generation, six layouts present, every custom module's command executable,
  every `custom-*` id defined, every layout group carrying a wrapper rule in
  `index.scss` *and no others*, this scheme's background in all six, and both
  font names resolving. The group/stylesheet one exists because the sheet
  reaches the module wrapper only through `#<group> > *` — a group added to a
  layout and not to the sheet keeps wayle's spacing while every other group
  loses it, and the bar renders either way.
- **The layouts are generated once, from `scheme.nix`**, so tiling must wear the
  artefact scheme. That is the ceiling `checks/static.sh` already asserted for
  waybar and swaync; it now names wayle.
- **Wallpaper-derived theming stays off** (`theme-provider = "wayle"`, not
  matugen/wallust/pywal). Every contrast floor in the gate reads a generated
  file, and a wallpaper-derived palette is written at runtime — the same
  objection as [0036](0036-noctalias-templates-stay-off.md).
- **`wayle config schema` is the check that caught four invented keys.**
  Validating the six generated files against it is now the routine before
  believing any new key works. `docs/gotchas.md` → Wayle has the catalogue.
