# 0025 — patch noctalia's mango backend, rather than route around it

**Status:** Accepted (2026-08-16)

The fifth dead `DwlIpc`-era path found in this shell, and the first one fixed
instead of avoided. Follows the correction on
[0020](0020-noctalia-is-a-desktop-mode.md) and the `logout()` finding in
[0023](0023-noctalia-owns-its-own-actions.md).

## Context

A lifecycle audit asked whether noctalia leaves anything behind when the mode is
switched away. It does not — the unit is `KillMode=control-group` and
quickshell's "detached" spawn only calls `setsid()`, which does not change
cgroup, so `systemctl --user stop noctalia` takes the whole tree. Verified by
running a `setsid` grandchild inside a transient user unit and stopping it.

The audit found something else. **`MangoService.spawn()` runs
`mmsg -s -d spawn_shell,<cmd>`** — the dwl-era flag form. mango 0.16 answers
`{"error":"unknown command"}` and **exits 0**. Measured:

```
$ mmsg -s -d 'spawn_shell,true'    → {"error":"unknown command"}   exit 0
$ mmsg dispatch 'spawn_shell,true' → {"success":true}              exit 0
$ mmsg dispatch 'not_a_func,true'  → {"error":"unknown function"}  exit 0
```

That call is the launcher's default path: `ApplicationsProvider` →
`CompositorService.spawn()` → `backend.spawn()`. So **picking an application in
noctalia's launcher did nothing**, except for desktop entries whose `Exec`
carries quoted or spaced arguments — those take an earlier branch,
`app.execute()`, and worked. A launcher that works for some entries and silently
does nothing for the rest is worse than one that is simply absent, and it is why
[0023](0023-noctalia-owns-its-own-actions.md) could record the launcher as bound
and reachable without noticing.

Four more call sites in the same file share the spelling: `killclient`,
`disable_monitor`, `enable_monitor`, and the `-s -q` behind `logout()` that
[0023](0023-noctalia-owns-its-own-actions.md) already found inert. All five verb
names exist in mango 0.16's own function table.

Two sites do **not** share it. `mmsg -g -A` (display scales) and `mmsg -s -t`
(tag switch) need a different call *shape*, not a different spelling — they are
the `DwlIpc` half the correction on [0020](0020-noctalia-is-a-desktop-mode.md)
records, and rewriting the flags there would produce output the QML cannot
parse.

## Decision

**Patch the package.** `pkgs/default.nix` overrides `noctalia-shell` with a
`postPatch` that rewrites the five flag calls to `mmsg dispatch`.

The alternative was noctalia's own `appLauncher.customLaunchPrefix` setting,
which routes the launcher through `Quickshell.execDetached` and bypasses
`MangoService` entirely. It was rejected on two counts. It fixes **one** of the
five call sites — the dock, the taskbar and the workspace context menus keep the
dead path. And it launches applications as children of *the shell*, inside
`noctalia.service`, where `KillMode=control-group` means **a mode switch kills
everything you launched**. `mmsg dispatch spawn_shell` makes them children of
**mango**, in the session scope — verified: the spawned process appears with
mango's PID as its parent, in `session-10.scope`, not in the unit's cgroup. The
patch is the smaller change *and* the one that fixes the lifetime.

**`--replace-fail`, so a rename upstream is a build error.** This is a patch
against a moving target; the way it fails is the whole question. `substituteInPlace`
with `--replace-fail` cannot apply a patch that no longer matches without
stopping the build, and it rewrites *every* occurrence, so a new call site
upstream is carried automatically rather than being missed.

**The logout button stays disabled.** Its call is patched with the rest —
`quit` is in mango's function table — but it is the one action that cannot be
tested without ending the session, and
[0023](0023-noctalia-owns-its-own-actions.md) turned the button off because it
was inert. Turning it back on is a one-line settings change once someone has
confirmed it, and a button that has never been fired is not evidence.

### The checks

- **Every verb noctalia dispatches is a function mango declares.** Taken from
  the *built* QML and matched against whole tokens extracted from the mango
  binary, so `quit` cannot match inside `quitting`. `mmsg` reports an unknown
  function the same way it reported the unknown command — `{"error":…}`, exit 0
  — so this is the same class of failure, moved to build time.
- **With a floor of five.** An unapplied patch leaves every call in the flag
  form, which empties the list rather than mismatching: the check would pass by
  finding nothing while the launcher went back to doing nothing.
- **The check's first version reported a false failure**, and the cause is worth
  the line it takes: it fed the 2,000-name list into `grep -q`, which exits at
  the first match and SIGPIPEs the writer. On a *hit* that is only noise
  (`printf: write error: Broken pipe` in the build log); on a *miss* the reader
  never sees the rest of the list, so the answer is decided by how much of it
  got through. It reads through a file now. A check that answers from a
  truncated input is the same class of bug as everything else here.

## Consequences

- **This repo now carries a patch against nixpkgs' `noctalia-shell`.** A version
  bump can fail the build, which is the intended cost. Check upstream first —
  this is their bug, and it is worth reporting rather than carrying forever.
- **Applications launched from noctalia now survive a mode switch**, because
  mango owns them. That was not the motivation; it fell out of using the
  compositor's own spawn rather than the shell's.
- **Two dead paths remain, knowingly.** Display scales and tag switching still
  speak dwl. They are recorded in the correction on
  [0020](0020-noctalia-is-a-desktop-mode.md), and the workspace widget they
  serve is the failure that correction exists to describe.
- **Removing noctalia now touches `pkgs/default.nix` too** — `docs/SYSTEM.md` §6
  names it alongside `shell.sh` and the `lockscreen` wrapper.
