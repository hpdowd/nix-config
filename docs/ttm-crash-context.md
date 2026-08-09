# amdgpu/TTM freeze — investigation context

Handoff note for picking this up in a fresh session. Written 2026-08-06.
Live detail lives in `CLAUDE.md` ("The amdgpu/TTM freeze") and `bisect/README.md`;
this file is the narrative and the open questions.

## The reported symptom

Machine freezes solid. After power-cycling, the login screen accepts **no
keystrokes**, so a *second* hard reset is needed before it is usable. Suspected
to follow closing the lid for a few minutes and reopening.

Those are **one bug and one consequence**, not two bugs.

## What it actually is

### 1. The freeze — a kernel crash in amdgpu/TTM

Three logged, two byte-identical:

```
Oops: general protection fault, probably for non-canonical address 0xe0b60016e5724c8e
RIP: 0010:ttm_lru_bulk_move_tail+0x144/0x1d0 [ttm]
  amdgpu_vm_move_to_lru_tail+0x29/0x40 [amdgpu]
  amdgpu_cs_ioctl+0x1a00/0x1c00 [amdgpu]
  drm_ioctl_kernel -> drm_ioctl -> amdgpu_drm_ioctl
Comm: .walker-wrapped
note: .walker-wrapped[3311] exited with preempt_count 1
```

| When | Signature | Faulting task |
|---|---|---|
| 2026-08-01 21:39:06 | GPF, non-canonical `0xe0b60016e5724c8e` | `.walker-wrapped` |
| 2026-08-05 18:32:34 | GPF, non-canonical `0xd8d825ac8ff41d4b` | `.walker-wrapped` |
| 2026-08-06 22:33:49 | NULL deref, `address: 0000000000000008` | (pstore, root-only) |

**Why it freezes instead of panicking — the key mechanism.** The faulting task
dies *still holding* the TTM `lru_lock` (`exited with preempt_count 1`). Nothing
releases it, so every process that later touches the GPU deadlocks in
`native_queued_spin_lock_slowpath`. Observed piling up: mango, Xwayland, zen,
spotify, swaync, nextcloud, electron. The result is cascading `soft lockup`
watchdog reports with the machine powered and completely unresponsive. One oops
became a total hang through a single leaked lock.

The `+0x8` NULL deref matches the symptom of Christian König's 2022 *"drm/ttm: fix
bulk move handling during resource init"* — long merged, so this is a **regression
of a known class**, not a novel bug. It is **not** CVE-2026-52949 (a different
TTM bug: infinite LRU walk in `ttm_bo_shrink()`).

### 2. The dead keyboard — a latched i8042, caused by the hard power-off

In the boot after the crash:

```
atkbd serio0: Failed to deactivate keyboard on isa0060/serio0
atkbd serio0: Failed to enable keyboard on isa0060/serio0
```

and `serio: i8042 AUX port` plus the TrackPoint are **absent entirely** (both
present in a healthy boot). The input device was still created, so keyd bound to
it and tuigreet looked completely normal — but the hardware was never enabled, so
there were no keystrokes to deliver. greetd logged `error: check_children: greeter
exited without creating a session`.

**Nothing was wrong with PAM, greetd or tuigreet.** Cutting power mid-freeze
latches the embedded controller; a warm reboot does not clear it, a full power
cycle does. Same family as the swaylock PAM lockout — a dead login prompt whose
cause is nowhere near the login stack.

## The finding that overturned the first theory

Initially this looked like a 7.1.4→7.1.5 kernel regression, on the strength of a
`boot.nix` comment saying Arch ran 7.1.4. **That comment was wrong.** The Arch
journals survived the migration and say otherwise:

| | Arch (to 2026-07-29) | NixOS (from 2026-07-29) |
|---|---|---|
| Kernel | `7.1.5-arch1-1` | `7.1.5` (nixpkgs) |
| `amdgpu.ppfeaturemask` | **absent** | `0xfffd7fff` |
| Crashes | **0** over ~6 weeks | **3** in 6 days |

**Same upstream kernel version. The differentiating variable is Overdrive.** There
is no version boundary to bisect between.

Not excluded: `7.1.5-arch1-1` is Arch's patched build with Arch's *config*, so
kernel config differences remain a live possibility. Only the version is ruled out.

### The git history confirms it independently

Checked against a linux-stable clone (`~/src/linux`) on 2026-08-06:

| Question | Answer |
|---|---|
| Commits touching `drm/ttm` in `v7.1.4..v7.1.5` | **0** (7 in range, all amdgpu) |
| Commits touching `drm/ttm/` in `v7.1..master` (7.2.0-rc6) | **2**, neither in `ttm_resource.c` |
| Last functional change to `ttm_lru_bulk_move_tail` | **2021-07-16**, `6a9b02899402` |

**The bulk-move LRU code has been unchanged for five years.** Two consequences,
both important:

1. **There is nothing to bisect.** The code is byte-identical across 7.1.4 and
   7.1.5. The bisect avenue is closed on the evidence, not merely deprioritised.
2. **No kernel version change will fix this** — no fix is pending in 7.1.6 or
   7.2-rc either. Do not upgrade or downgrade hoping to resolve it.

So this is a **latent bug in long-stable code, triggered environmentally**. Only
two candidate triggers survive: `ppfeaturemask` (now off) and nixpkgs' kernel
*config* versus Arch's.

### A methodological trap worth remembering

An early pass reported "zero crashes on Arch" **before** establishing the journals
were readable. They are not: `system@*.journal` is ACL'd to GID 981 plus
`corectrl` and `avahi`, none of which `henry` is in, so an unprivileged
`journalctl -D` silently reads only the 16 `user-1000@` session files — which
contain no kernel messages and therefore grep to zero exactly like a clean
history. Always confirm the `Linux version` lines are non-empty before believing a
zero. `bisect/collect-report.sh` prints this caveat inline.

## What was changed (all applied and verified on hardware)

Branch `fix/amdgpu-ttm-crash-mitigations`. `nix flake check` passes all 12.

| Change | File | Effect |
|---|---|---|
| `hardware.amdgpu.overdrive.enable` removed | `power.nix` | Drops `ppfeaturemask=0xfffd7fff`; taint `4`→`0`. Prime suspect for the crash |
| `kernel.panic_on_oops = 1`, `kernel.panic = 10` | `boot.nix` | Oops → panic → clean reboot in 10 s, instead of freezing behind the leaked lock. **This is what breaks the double-hard-reset chain** |
| `kernel.sysrq = 1` (was 16) | `boot.nix` | `Alt+SysRq+S,U,B` as an escape from a hang without cutting power |
| `bisect/` added | — | Report tooling; `kernel.nix` builds from a local git checkout, incl. KASAN |

Verified post-reboot: `tainted 0`, no `ppfeaturemask` in `/proc/cmdline`,
`panic_on_oops 1`, `panic 10`, `sysrq 1`, boot generation == running generation.

Overdrive was safe to drop because **nothing used it**: corectrl neither running
nor autostarted, `power_dpm_force_performance_level` = `auto`, and
`pp_od_clk_voltage` at stock 200–1899 MHz exactly matching `OD_RANGE`.

### The `rebuild-test` trap this hit

Dropping `ppfeaturemask` changes a **kernel parameter**, so it only applies at
boot — but `nixos-rebuild test` deliberately writes no boot entry. `test` then
reboot lands back on the *previous* generation with the taint intact and the
sysctls reverted, looking exactly like the change not working. Cost two reboots
here. The tell: `/nix/var/nix/profiles/system` still pointing at the old store
path while `/run/current-system` points at the new one. Use `switch` or `boot`
for anything touching `boot.kernelParams` — the general "prefer `rebuild-test`
for structural changes" advice is exactly wrong for that one case.

## Where it stands / what to do next

1. **Wait.** Three crashes in six days sets the bar. A clean fortnight with
   Overdrive off is real evidence it was the cause. This is the whole test.
2. **If it recurs**: it is a genuine upstream bug independent of Overdrive. The
   valuable artefact is then a **KASAN trace** — see `bisect/README.md`. KASAN
   names the allocating and freeing stacks at the point of corruption rather than
   the arbitrary downstream fault. **Not a bisect**: the code is five years
   unchanged, so there is no version boundary to find.
3. **If reporting**: `gitlab.freedesktop.org/drm/amd/-/issues`, or
   `amd-gfx@lists.freedesktop.org` CC `dri-devel`, CC Christian König (he owns the
   TTM bulk-move code). Email patches, not GitHub PRs. Taint must read `0`.
4. **Do not** "fix" this by dropping to `pkgs.linuxPackages` (6.18.40). Arch ran
   the same 7.1.5 cleanly; that changes the wrong variable.
5. **Open question worth pursuing** if it recurs: nixpkgs' 7.1.5 kernel *config*
   vs Arch's. It is the only difference the evidence has not excluded.

## Artefacts

- `~/ttm-crash-report/` — collected bundle (`arch-history.txt` is the important
  one; `pstore/` holds the five full backtraces)
- `/var/lib/systemd/pstore/` — raw crash dumps, root-only
- `/var/log/journal/adfaa3a0727f4a0bbf2c913e2fd2c290/` — Arch journals, root-only,
  back to 2026-06-20
- `~/src/linux` — linux-stable clone (blobless), for KASAN builds

## Reproducer status

Unconfirmed. `.walker-wrapped` is the faulting process in both traces that have a
`Comm`, so launching walker (`SUPER+W` / `SUPER+P`) is the best lead. The
lid-resume correlation is **weak** — 108 s after resume on Aug 5, but ~2 h on
Aug 6 and ~9 h on Aug 1 — so do not lead a report with it.
