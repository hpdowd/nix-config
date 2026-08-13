# 0015 — The lid hibernates; there is no suspend phase

**Status:** Accepted (2026-08-11) — the lid half stands; **the title's "there is
no suspend phase" is amended by [0016](0016-idle-suspends-the-lid-hibernates.md)
(2026-08-12)**, which returns the 30-minute idle rung to `systemctl suspend`.
Every observation below is of a *closed lid*; none of it transfers to a rung
that fires with the lid open.

## Context

This firmware exposes only **s2idle** (`/sys/power/mem_sleep` → `[s2idle]`), so
there is no S3 to fall back to. Two independent failures live in that state on
this machine:

- **Long s2idle sometimes never resumes.** A good wake logs `amdgpu … PCIE GART
  … enabled` and `SMU is resuming…`; the failing one logs neither and the
  journal simply stops. On screen it is indistinguishable from a machine that is
  merely asleep — the panel is off and input is dead — so the only recovery is a
  power cycle, which on this hardware can latch the i8042 and produce a greeter
  that accepts no keystrokes.
- **Something wakes it spuriously**, source still unidentified. The standing
  suspect is the Synaptics fingerprint reader dropping off USB bus 1, but the
  wakeup counters reset per boot and it has never been confirmed.

`suspend-then-hibernate` was the obvious answer and was tried twice — first with
AC on a plain `suspend`, then with s-t-h on both power sources. It failed two
different ways:

1. **Degradation.** A spurious wake *ends* the s-t-h cycle rather than resuming
   its countdown. ~30 s later logind re-handles the still-closed lid and logs a
   bare `Suspending...`, not `Suspending, then hibernating...` — an unbounded
   s2idle with no hibernate timer behind it, which is exactly where the resume
   hang lives. Observed on three consecutive boots; every lid close ended in a
   power cycle. Setting both handlers to s-t-h did not help.
2. **Silence.** On 2026-08-11 a lid close logged `Suspending, then
   hibernating...` cleanly and then sat in s2idle for **9h37m** with
   `HibernateDelaySec=30m` set. The timed wake never fired and nothing logged
   its absence. Suspect the alarm RTC — `rtc0` is `acpi-tad` with no `wakealarm`
   attribute at all, and only `rtc1` (`rtc_cmos`) reports "RTC can wake from
   S4" — but this is unproven.

**A suspend phase is what starts both failures.** Remove it and there is no wake
to be spurious and no cycle to degrade.

### What is *not* a reason

For most of this repo's life, suspend was also believed to cost ~3 W because
s0i3 was never reached. That is retracted. The same 9h37m sleep above measured
**0.15 W** — 58% → 54% of a 42.4 Wh cell — which is s0i3 working. The earlier
figure came from short instrumented measurements, which on this machine are
worthless: a six-sample median read 6.88 W at 100% backlight and 7.43 W at 10%.

So the battery argument for hibernating is gone. **The decision does not rest on
it**, and the cheap s2idle is not grounds to revisit this.

## Decision

**Every automatic sleep on this machine goes straight to hibernate. There is no
suspend phase anywhere.**

> ⚠️ Amended by [0016](0016-idle-suspends-the-lid-hibernates.md): the idle rung
> now suspends. The three lid/button/battery rows below are unchanged.

| Trigger | Setting |
|---|---|
| Lid closed, either power source | `HandleLidSwitch` / `HandleLidSwitchExternalPower = "hibernate"` |
| Lid closed **while docked** | `HandleLidSwitchDocked = "ignore"` — clamshell keeps working. logind re-checks the still-closed lid every event loop, so undocking falls through to the row above and hibernates (hence locks). `docs/SYSTEM.md` §9 |
| Power key tapped | `HandlePowerKey = "hibernate"` (long press stays `poweroff`) |
| 30 minutes idle **on battery**, nothing playing | ~~`idle-hibernate`~~ — now `idle-suspend`, see [0016](0016-idle-suspends-the-lid-hibernates.md) |
| Battery at 3% | `services.upower.criticalPowerAction = "Hibernate"` |

`systemd.sleep.settings.Sleep` is deliberately absent — with no suspend phase
there is no `HibernateDelaySec` to tune. `HibernateMode` stays at the default
`platform` (ACPI S4).

Manual `systemctl suspend` is untouched, and remains available from wlogout for
the case where you know you are coming straight back.

## Consequences

**A short lid close is expensive.** Every one costs a ~6 GiB image write and a
~10–30 s resume rather than returning instantly. That is the whole price, and it
is paid on every lid close, not just the long ones.

**Hibernation must keep working, and it fails silently.** `resume_offset` is
valid only for the exact swapfile that exists now; get it wrong and the machine
boots fresh and discards the session, which presents as "hibernate didn't work"
rather than "resume was misconfigured". The 20 GiB swapfile on `@swap` therefore
cannot be recreated casually, and must stay uncompressed. The kernel log cannot
confirm a success either — the image is snapshotted *before* the write, so
success and refusal leave byte-identical traces. The primary signal is physical:
the machine powers off, and shows the firmware screen on the way back.

**More NVMe writes** than a suspend-based policy, by design.

### What would justify revisiting this

Not a power measurement. Only this:

1. The spurious wake source identified and closed, **and**
2. the resume hang either reproduced-and-fixed or shown not to recur across a
   run of long s2idle sleeps.

With both, `suspend-then-hibernate` becomes viable again and buys back the
instant resume. With either one missing, a suspend phase reintroduces a state
this machine does not reliably come back from.

`docs/gotchas.md` → Power carries the journal signatures for all of it;
`docs/SYSTEM.md` §9 is the reference for how it is wired.
