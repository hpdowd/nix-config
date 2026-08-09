# The amdgpu/TTM freeze — evidence, and the bisect kit if it is still needed

**Read this first: the kernel-version theory is dead, and a bisect is probably
not what this needs.** Measured 2026-08-06 from the surviving Arch journal, the
differentiating variable is **Overdrive**, not the kernel:

| | Arch (to 2026-07-29) | NixOS (from 2026-07-29) |
|---|---|---|
| Kernel | `7.1.5-arch1-1` | `7.1.5` (nixpkgs) |
| `amdgpu.ppfeaturemask` | **absent** | `0xfffd7fff` |
| Crash signatures in journal | **0** over ~6 weeks | **3** in 6 days |

Same upstream version, comparable workload (walker included, and walker is the
faulting process in both traces that have one). `hardware.amdgpu.overdrive` is
now off in `modules/system/power.nix` and the taint reads `0`.

**So the immediate task is not a bisect — it is waiting.** Three crashes in six
days sets the bar; a clean fortnight is real evidence that Overdrive was the
cause. Everything below is the contingency for if it recurs anyway.

Caveat, stated so nobody over-reads the table: `7.1.5-arch1-1` is Arch's patched
build with Arch's kernel *config*, not nixpkgs' 7.1.5. Config differences are not
excluded — only the version is.

## The git history independently confirms it, and kills the bisect outright

Checked against a linux-stable clone 2026-08-06:

| Question | Answer |
|---|---|
| Commits touching `drm/ttm` in `v7.1.4..v7.1.5` | **0** (7 in range, all amdgpu) |
| Commits touching `drm/ttm/` in `v7.1..master` (7.2.0-rc6) | **2**, neither in `ttm_resource.c` |
| Last functional change to `ttm_lru_bulk_move_tail` | **2021-07-16**, `6a9b02899402` |

**The bulk-move LRU code has been unchanged for five years.** So there is nothing
to bisect between 7.1.4 and 7.1.5 — the code is identical — and no fix is pending
in 7.1.6 or 7.2-rc. **Upgrading or downgrading the kernel will not help.**

That makes this a **latent bug in long-stable code, triggered environmentally**.
The two candidate triggers are `ppfeaturemask` (now off) and nixpkgs' kernel
*config* versus Arch's. Nothing else survives the evidence.

For reference, `b2ed01e7ad3d` (2026-04-28, *"Fix ttm_bo_swapout() infinite LRU walk
on swapout failure"*) is the CVE-2026-52949 family — already fixed, and unrelated
to this.

## The crash

```
Oops: general protection fault, probably for non-canonical address 0xe0b60016e5724c8e
RIP: 0010:ttm_lru_bulk_move_tail+0x144/0x1d0 [ttm]
  amdgpu_vm_move_to_lru_tail+0x29/0x40 [amdgpu]
  amdgpu_cs_ioctl+0x1a00/0x1c00 [amdgpu]
  drm_ioctl_kernel -> drm_ioctl -> amdgpu_drm_ioctl
Comm: .walker-wrapped
note: .walker-wrapped[3311] exited with preempt_count 1
```

Three instances: 2026-08-01 21:39, -08-05 18:32, -08-06 22:33. Two byte-identical.

- **It freezes rather than panicking** because the faulting task dies holding the
  TTM `lru_lock` (`preempt_count 1`). Every later GPU client then piles up in
  `native_queued_spin_lock_slowpath` — mango, Xwayland, zen, spotify, swaync — so
  the symptom is a total desktop hang, not an oops. `kernel.panic_on_oops = 1` in
  `boot.nix` now converts this into a clean reboot.
- **2026-08-06 landed as a NULL deref at `address: 0000000000000008`**, not a GPF.
  Same corrupted bulk-move list, different wild pointer. That `+0x8` offset
  matches the symptom of Christian König's 2022 *"drm/ttm: fix bulk move handling
  during resource init"* — long merged, so this is a **regression of a known
  class**.
- Not **CVE-2026-52949**, a different TTM LRU bug (infinite LRU walk in
  `ttm_bo_shrink()` on backup failure).

**The resume correlation is weaker than it looks** — 108 s after resume on Aug 5,
but ~2 h on Aug 6 and ~9 h on Aug 1. Do not lead a report with "happens after lid
resume" unless it holds up under testing.

## Collect the evidence

```sh
sudo bisect/collect-report.sh ~/ttm-crash-report
```

Gathers hardware, kernel identity and taint, every crash in the current journal,
all pstore dumps (the full backtraces — the journal only ever caught the first
three lines, since the freeze killed journald before it could flush), and the
Arch history that produced the table above.

Note the script's caveat next to any zero: an unreadable journal greps to zero
exactly like a clean one. Confirm the `Linux version` lines are non-empty before
believing a `0`. The Arch `system@*.journal` files are ACL'd to GID 981 plus
`corectrl` and `avahi` — so unprivileged reads see only the 16 `user-1000@`
session files and find no kernel messages at all. That mistake was made once here.

## If it recurs with Overdrive off

Then it is a genuine upstream bug independent of Overdrive, and worth reporting.
In that case the useful contribution is a **KASAN trace**, not a bisect — there is
no version boundary to bisect between, since Arch and NixOS ran the same 7.1.5.

`bisect/kernel.nix` builds a kernel from a local checkout. Add to
`hosts/thinkpad/default.nix` **temporarily** — never commit it:

```nix
boot.kernelPackages = import ../../bisect/kernel.nix {
  inherit pkgs;
  src = "/home/henry/src/linux";
  version = "7.1.5";   # must equal the tree's `make kernelversion`
  kasan = true;
};
```

KASAN catches the use-after-free **at the point of corruption**, naming the
allocating and freeing stacks, instead of the arbitrary downstream fault. A report
with those two stacks tends to get fixed; one with only a wild pointer tends to
sit. ~2–3× slower. It also enables `DEBUG_LIST`, `DEBUG_SPINLOCK` and
`PROVE_LOCKING`, and `PROVE_LOCKING` may catch the `lru_lock` misuse directly.

Use `nixos-rebuild boot`, not `switch` — a bad kernel then costs a menu selection
rather than a broken running system. `version` must match the tree or modules
install where the boot cannot find them and the machine comes up with no modules
at all; `LOCALVERSION_AUTO` is forced off in `kernel.nix` for the same reason.

Capture with `journalctl -k -b -1` after the reboot, or from `/sys/fs/pstore`.
Send the **whole** KASAN block, from `BUG: KASAN:` to the end of the freed-by
stack.

### If you do still want a bisect

`candidates.sh` lists the drm/ttm + amdgpu commits between two tags, for reading
before building — five commits read beats ten kernels built:

```sh
bisect/candidates.sh ~/src/linux v7.1.4 v7.1.5
```

Point-release tags only exist in **linux-stable**, not `torvalds/linux`:

```sh
git clone https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git ~/src/linux
```

But note there is no known-good version to anchor against. A more useful
comparison would be **nixpkgs 7.1.5 vs Arch's 7.1.5 config**, since that is the
only difference the evidence has not excluded.

## Reporting

Upstream takes email patches, not GitHub PRs.

- Bug: <https://gitlab.freedesktop.org/drm/amd/-/issues>
- List: `amd-gfx@lists.freedesktop.org`, CC `dri-devel@lists.freedesktop.org`
- Christian König maintains the TTM bulk-move code and is the right CC.

Include hardware and iGPU, exact kernel version, `/proc/cmdline`, taint value, the
full decoded oops, the KASAN report, and the reproducer. **Taint must read `0`** —
`ppfeaturemask` taints `CPU_OUT_OF_SPEC` and a tainted report gets closed unread.

If Overdrive turns out to be the trigger, that is still a legitimate report:
enabling Overdrive should not corrupt kernel memory. Frame it as
"`ppfeaturemask=0xfffd7fff` on <hardware> corrupts TTM bulk-move lists", and say
plainly that the taint is expected because the flag is the subject of the report.
