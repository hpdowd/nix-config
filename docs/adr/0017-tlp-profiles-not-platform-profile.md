# 0017 — Power modes are TLP profiles; `platform_profile` was a placebo

**Status:** Accepted (2026-08-12)

## Context

`SUPER+SHIFT+p` and the waybar module cycled
`/sys/firmware/acpi/platform_profile` between `low-power`, `balanced` and
`performance`, and had done since 2026-07-30. The bar changed. The machine did
not.

Diffed across all three settings on battery, every value the scheduler reads is
byte-identical:

| | low-power | balanced | performance |
|---|---|---|---|
| `scaling_governor` | powersave | powersave | powersave |
| `energy_performance_preference` | power | power | power |
| `scaling_min_freq` | 1115770 | 1115770 | 1115770 |
| `scaling_max_freq` | 4630443 | 4630443 | 4630443 |
| `boost` | 1 | 1 | 1 |

`platform_profile` is a `thinkpad_acpi` DYTC attribute. It hands the firmware a
STAPM/PPT hint and touches nothing in the cpufreq path. **TLP** owned governor,
EPP and everything else, keyed on AC-vs-battery alone — never on
`platform_profile`, which it also rewrites on every charger transition. So the
toggle was overwritten as well as inert.

The symptom that exposed it: the fan runs at ~2340 RPM at 45–52 °C, idle, on
battery, in "low-power". Nothing in that mode caps anything. `EPP=power` biases
how eagerly the governor ramps but sets no ceiling, so with `boost=1` and no
`scaling_max_freq`, a keystroke-sized task still reaches 4.63 GHz and spikes the
package to ~30 W. **On this chassis the fan tracks bursts, not averages.**
`scaling_min_freq` was also parked at `lowest_nonlinear` (1115770), 2.7× the
418414 the hardware allows.

## Decision

**A power mode is a TLP profile.** TLP 1.9 carries a third profile beyond its
AC/BAT split — `SAV`, applied by `tlp power-saver` — and every setting takes an
`_ON_SAV` variant. `TLP_AUTO_SWITCH=2` ("smart") keeps a manually chosen
power-saver across a charger transition, so it is a mode rather than a
power-source state. That is the fanless mode, and it needed no new mechanism.

`SAV` caps `scaling_max_freq` at **1115770** (`lowest_nonlinear`) — the highest
clock still at minimum core voltage, so the best perf-per-watt point on the
curve. Boost off, floor at 418414, `platform_profile=low-power`, ABM 3.

**Efficiency is the objective only because the thermal one is unreachable.** Two
`fan-calibrate` runs put the EC trip at **~47–48 °C** against an idle plateau
that lands anywhere from 40 to 46 °C with ambient. Twelve threads cross that even
at 418 MHz, the hardware minimum: run 1 (40 °C baseline) held at 418 MHz and spun
at 800 MHz; run 2 (46 °C baseline) spun at 418 MHz. **No cap makes sustained
all-core load fanless on this chassis**, so a cap below `lowest_nonlinear` buys
silence it cannot deliver and costs real speed.

**Every profile must state both bounds.** An unset `CPU_SCALING_MAX_FREQ_ON_AC`
is not "no limit": `set_cpu_scaling_min_max_freq` logs `not_configured` and skips
the write, so the previous profile's cap survives. Leaving fanless left the cores
pinned at its ceiling while the bar read `performance` — observed live at
`max=1115770` in the performance profile.

**The everyday battery profile loses boost too**, and drops to the same floor.
That is the single biggest fan lever and costs little that is felt.

**Left-click toggles `balanced ↔ performance`; fanless is right-click only.**
Both call `power-mode`, a root wrapper in `modules/system/power.nix`. wheel may
run *that one script* NOPASSWD — not `tlp`, which also carries `discharge`,
`setcharge` and `recalibrate`.

Fanless is off the left-click path because of what the measurement turned it
into. At 418 MHz it is not a mild power saving that costs a little
responsiveness; it is a mode you choose when silence beats speed. A three-way
cycle would drop you there by pressing one time too many, with no obvious cause.
Right-click toggles it, returning to what the supply implies, because
`TLP_AUTO_SWITCH=2` holds fanless across a charger change by design — nothing
reverts it on its own, so set-only left no way back out.

The `systemd.tmpfiles` rule that made `platform_profile` group-writable is
deleted. Nothing writes it by hand any more.

## Consequences

**The iGPU pin cannot live in TLP.** Its amdgpu branch handles `PP_BAL` and
`PP_SAV` in one arm and reads only `RADEON_DPM_PERF_LEVEL_ON_BAT`; there is no
`_ON_SAV`. Setting one is accepted into `tlp.conf` and never read — configured,
inert, silent, this repo's signature bug. `power-mode` writes
`power_dpm_force_performance_level` itself, which is the whole reason it exists
rather than the toggle shelling out to `tlp` directly.

**The pin and the CPU cap are lifted for the duration of a sleep.** A 2026-08-13
lid-close hung the machine in hibernation's entry phase, 2.5 s after a switch to
`power-saver` — that phase preallocates ~5.8 GiB and compresses into zram before
it can snapshot, and doing it at 1115770 kHz with boost off stretches a 7 s
window to 22 s. `powerManagement.powerDownCommands` now un-throttles before
`sleep.target`; `tlp resume` reapplies the AC/BAT profile afterwards. So the mode
a sleep is entered in is not the mode it is left in — which was already true of
any resume, since `tlp resume` has never restored a manual mode.
`docs/gotchas.md` → Power.

**The waybar module reads `/run/tlp/last_pwr`**, not `tlp-stat` (0.25 s per
poll). Format is `<profile> <power-source>`, `PP_PRF=0 PP_BAL=1 PP_SAV=2` and
`PS_AC=0 PS_BAT=1`, from `tlp-func-base`; verified live on both supplies. An
unrecognised code renders a question glyph rather than an empty string, because
an empty custom module is indistinguishable from an absent one.

**The name overpromises, and the measurement is what proved it.** "Fanless"
means *quiet in ordinary use*, not silent under load. The remaining lever for
literal silence is forcing the EC (`thinkpad_acpi.fan_control=1`, `level 0`),
considered and rejected: it disables thermal protection for as long as the mode
is on.

**`fan-calibrate` took two goes to become trustworthy, and both flaws flattered
the result.** First it cooled only until the fan read 0 — a stopped fan is not a
cooled heatsink, so each step began hotter than the last and was condemned by its
predecessor. Fixing that exposed the second: the *baseline itself* was taken at
whichever temperature the fan happened to cut out, which was 40 °C one run and
46 °C the next, and with a ~47 °C trip that 6 °C decided the whole sweep. It now
settles to a plateau — temperature stops falling — before recording a baseline.
Ascending order stays deliberate: the EC has hysteresis, so sweeping down from
hot gives a lower answer than the machine needs.

**The everyday win was never the fanless mode.** Balanced — boost off, clamped to
the 2.9 GHz base — idles fan-free at ~40 °C where the old low-power mode ran at
2340 rpm. That is what fixed the original complaint; fanless is a deliberate
extra.

**`tlpctl` is not available.** TLP 1.9.1 ships its manpage — profile holds,
`tlpctl launch --profile` — but no binary. Do not write anything against it.
