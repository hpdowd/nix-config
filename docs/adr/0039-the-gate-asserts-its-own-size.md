# 0039 — the gate asserts its own size

**Status:** Accepted (2026-08-20)

Applies the floor discipline of [0011](0011-shell-is-gated-too.md) to the file
that enforces it. Closes Phase 6 of `docs/PLAN-idiomatic-nix.md`.

## Context

`checks/static.sh` is how nearly every other claim in this repo is held true.
Every scan *inside* it already has a floor — script count ≥30, waybar configs
=8, terminating traps ≥2 — each carrying the same comment: *the scan is broken,
not the repo*. That discipline exists because of [0014](0014-declare-the-namer-not-just-the-file.md):
a scan that stops matching passes by finding nothing, and a check that finds
nothing is indistinguishable from a check that passes.

**The file as a whole had no such floor.** It ended with

```sh
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
```

so deleting an entire section — by a bad merge, an early `exit`, a `return` from
a sourced fragment, or a stray `fi` swallowing the block — printed a smaller
number and exited **green**. The one place the discipline was not applied was
the place that mattered most, because it is the place that catches everything
else.

This is not hypothetical arithmetic. Sections here are long and brace-nested;
`static.sh` is 2,400 lines and deliberately not split
(`docs/PLAN-idiomatic-nix.md` → *Deliberately NOT*), precisely because a section
in its own file is a section that can stop being sourced. Refusing the split
without adding this floor left the same hole with fewer ways to notice it.

## Decision

**`static.sh` records the number of assertions it expects to run and fails when
fewer do.**

```sh
# 115 on 2026-08-20. docs/PLAN-idiomatic-nix.md §6a.
ASSERTION_FLOOR=115
```

Three properties, each deliberate:

- **A floor, not a ratchet.** The test is `PASS + FAIL < FLOOR`, not equality.
  Adding an assertion stays a one-line change; nobody has to touch the constant
  to make the gate go green.
- **Raised in the commit that adds assertions**, never after the fact. The
  `mango -p` check landed alongside this and moved it 114 → 115.
- **Counted, not enumerated.** A list of expected section names would need
  maintaining in two places and would drift; the count is a single integer that
  only ever moves deliberately.

Lowering it is legitimate — assertions do get retired — but it is an edit
someone has to *make*, with the diff visible in review. That is the whole
mechanism: convert a silent absence into a deliberate act.

## Consequences

- Deleting a section now fails the build naming the count, instead of quietly
  reporting a smaller one. Verified: with the *Fonts* section removed the run
  prints `112 passed, 0 failed` and then `✗ only 112 assertions ran, floor is
  115`, exiting 1. The same deletion exited 0 before this change.
- The constant is a small recurring cost — one line per phase that adds
  assertions. That is the intended cost, and it is paid in the commit that
  earns it.
- A section that *runs* but whose scan finds nothing is still caught by that
  scan's own floor, as before. The two floors are complementary: the inner ones
  guard the regex, this one guards the section.
- It does not catch a section that runs and asserts something vacuous. Nothing
  does, which is why every new assertion in the plan must be confirmed against
  a planted defect before it counts as landed.
