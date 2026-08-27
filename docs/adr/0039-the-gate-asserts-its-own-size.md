# 0039 — the gate asserts its own size

**Status:** Accepted (2026-08-20)

Applies the floor discipline of [0011](0011-shell-is-gated-too.md) to the file
that enforces it.

## Context

`checks/static.sh` is what holds nearly every other claim in this repo true.
Every scan inside it already has a floor — script count ≥30, waybar configs =8,
terminating traps ≥2 — each with the same comment: *the scan is broken, not the
repo*. [0014](0014-declare-the-namer-not-just-the-file.md) is why: a scan that
stops matching finds nothing and passes, and that looks the same as a scan that
found nothing wrong.

**The file as a whole had no floor.** It ended with

```sh
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
```

so losing a whole section — to a bad merge, an early `exit`, a `return` from a
sourced fragment, a stray `fi` swallowing the block — printed a smaller number
and exited **green**.

Sections here are long and brace-nested, and `static.sh` is 2,400 lines that we
deliberately do not split, because a section in its own file can stop being
sourced. Refusing the split
without adding this floor kept the same hole and removed some of the ways to
notice it.

## Decision

**`static.sh` records how many assertions it expects to run and fails when fewer
do.**

```sh
# 115 on 2026-08-20. docs/adr/0039.
ASSERTION_FLOOR=115
```

Three choices worth stating:

- **A floor, not a ratchet.** The test is `PASS + FAIL < FLOOR`, not equality,
  so adding an assertion stays a one-line change and nobody has to touch the
  constant to get the gate green.
- **Raised in the commit that adds the assertions.** The `mango -p` check landed
  alongside this one and moved it 114 → 115.
- **A count, not a list of section names.** A list would need maintaining in two
  places and would drift. The count is one integer, and it only moves when
  somebody moves it.

Lowering it is fine — assertions do get retired — but it takes an edit, and the
edit shows up in the diff. That is the point: a section going missing becomes
something somebody has to do on purpose.

## Consequences

- Deleting a section now fails the build and names the count. Verified: with the
  *Fonts* section removed the run prints `112 passed, 0 failed` and then
  `✗ only 112 assertions ran, floor is 115`, exit 1. Before this change the same
  deletion exited 0.
- It costs one line per phase that adds assertions, paid in the commit that adds
  them.
- A section that runs but whose scan finds nothing is still caught by that
  scan's own floor. The inner floors guard the regex; this one guards the
  section.
- It does not catch a section that runs and asserts something vacuous. Nothing
  does, which is why every new assertion has to be confirmed against a planted
  defect before it counts as landed.
