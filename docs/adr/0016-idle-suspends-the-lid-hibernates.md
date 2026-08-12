# 0016 — The idle rung suspends; the lid still hibernates

**Status:** Accepted (2026-08-12)
**Amends:** [0015](0015-hibernate-not-suspend-on-the-lid.md), whose *"no suspend
phase anywhere"* covered the idle rung without evidence for it.

## Context

0015's evidence is entirely about a **closed lid**: a spurious wake ends the
`suspend-then-hibernate` cycle, logind re-handles the still-shut lid ~30 s later
and degrades it to a bare `Suspending...`, and that unbounded s2idle is where
the resume hang lives. logind re-handling a lid that is still shut is the
mechanism, and there is no lid switch to re-handle when the idle rung fires.

The rung was folded in by symmetry. It cost a multi-GiB write and a 10–30 s
resume every 30 idle minutes to buy the gap between 0.15 W and 0 W.

**NVMe endurance is not the argument.** The drive is a Samsung MZVL2512HCJQ
(PM9A1 512 GB, ~300 TBW); four hibernates a day at ~6 GiB is ~8.8 TB/year, about
34 years of headroom. The cost of hibernating here is latency.

## Decision

**The 30-minute idle rung calls `systemctl suspend`.** `idle-hibernate` →
`idle-suspend`; both gates unchanged (AC stops it, MPRIS `Playing` bails).

**The lid, the power key and the 3% critical action still hibernate.**

**upower's 3% `Hibernate` is the backstop**, and is why this does not extend to
the lid. An idle suspend nobody returns to drains at 0.15 W and hibernates on
the way down, so the worst case is a slow resume, not a lost session. The lid
has no floor — its failure mode is not resuming to *reach* 3%.

## Consequences

**The rung is now the instrument for closing 0015.** Nothing suspended
automatically before this, so neither failure could be observed; hibernating
everywhere froze the investigation. Every idle suspend is a sample.

**0015's observations predate the `wlopm` hooks**, i.e. a machine that never
reached s0i3 and sat at ~4 W through what it called sleep. That does not make
them wrong, but they describe a state it no longer enters. The one long s2idle
measured since — 9h37m, 58% → 54% — neither woke spuriously nor failed to
resume.

**A lead on the wake source.** The Synaptics reader (`06cb:00f9`) is at `1-3`,
the only device on USB bus 1. Its own `power/wakeup` is `disabled`, but its
parent XHCI controller `0000:74:00.3` is `enabled` — the path by which a device
leaving the bus raises a PME. Disabling it costs nothing. Untried on purpose:
0015 wants the source *confirmed*, and the fix would remove the symptom.

### What still gates the lid

Unchanged from 0015, and both are required:

1. The wake source identified and closed.
2. The resume hang fixed, or shown not to recur across long s2idle sleeps.

The rung generates evidence for (2) as a side effect. It generates none for the
lid's *degradation* failure, which needs a lid re-check to occur at all.
