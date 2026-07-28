# Issue tracker: Gitea

Issues and PRDs for this repo live as **Gitea issues** on the self-hosted
instance at `https://git.henrydowd.dev`, repo `henry/arch-config`. Use the
[`tea`](https://gitea.com/gitea/tea) CLI for all operations.

`tea` is already authenticated: login `henry`, marked default. Verify with
`tea logins list`.

## Network caveat — read this before assuming a command failed

`git.henrydowd.dev` resolves to `192.168.1.200`, which is reachable **only over
the `homelab` WireGuard tunnel**. When that tunnel is down, every `tea` command
hangs and then fails, and so does `git push`.

Check the tunnel before concluding anything is wrong with the tracker:

```bash
ping -c2 -W2 10.0.0.1        # tunnel peer
ip -s link show homelab      # RX 0 bytes = no handshake, tunnel is dead
```

If the tunnel is down, **say so and stop** — do not silently fall back to
writing tickets somewhere else, and do not retry in a loop.

## Conventions

Commands infer the repo from `git remote -v` when run inside the clone. Add
`--repo henry/arch-config` to run from elsewhere.

- **Create an issue**: `tea issues create --title "..." --description "..."`.
  Use a heredoc via `$(cat <<'EOF' ... EOF)` for multi-line descriptions.
  Labels and assignees at creation: `--labels "a,b"`, `--assignees henry`.
- **List issues**: `tea issues list --output json`, with `--labels "..."`,
  `--state open|closed|all`, `--keyword "..."` as filters. Default state is
  `open` and the default page limit is 30 — pass `--limit` for more.
- **Read one issue**: `tea` 0.14 has **no `issues view` subcommand**. Fetch the
  body through the API and the comments separately:

  ```bash
  tea api repos/henry/arch-config/issues/<n>
  tea comments list <n>
  ```

- **Comment**: `tea comments add <n> "..."` (the bare `tea comment <n> "..."`
  shorthand also still works).
- **Apply / remove labels**: `tea issues edit <n> --add-labels "..."` /
  `--remove-labels "..."`. Note `--add-labels` **takes precedence over**
  `--remove-labels`, so do not pass both for the same label in one call.
- **Close**: `tea issues close <n>`. It takes no closing comment, so post the
  explanation first with `tea comments add <n> "..."`, then close. Reopen with
  `tea issues reopen <n>`.
- **Create a label**: `tea labels create --name "..." --color "..." --description "..."`.
  See `triage-labels.md` for the five this repo expects.
- **Pull requests**: `tea pulls ...` (`list`, `create`, `checkout`, ...).

Gitea numbers issues and pull requests from a **single shared sequence** per
repo, as GitHub does and unlike GitLab — so `#42` is either an issue or a PR,
never both.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external
pull requests as feature requests; `/triage` reads this flag.)_

This is a personal dotfiles repo on a private instance, so external PRs are not
expected. If that changes, flip the flag and use the `tea pulls` equivalents of
the commands above.

## When a skill says "publish to the issue tracker"

Create a Gitea issue with `tea issues create`.

## When a skill says "fetch the relevant ticket"

Run `tea api repos/henry/arch-config/issues/<n>` for the body, then
`tea comments list <n>` for the discussion.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as
tickets.

- **Map**: an issue labelled `wayfinder:map` holding the Notes /
  Decisions-so-far / Fog body —
  `tea issues create --labels wayfinder:map --title "..."`.
- **Child ticket**: an issue carrying `Part of #<map>` at the top of its
  description, labelled `wayfinder:<type>`
  (`research`/`prototype`/`grilling`/`task`). Assign it on claim.
- **Blocking**: Gitea has no native blocking link exposed through `tea`, so use
  a `Blocked by: #<n>, #<n>` line at the top of the description. A ticket is
  unblocked once every issue named there is closed.
- **Frontier query**: `tea issues list --output json` scoped to the map's
  children; drop any with an unclosed issue in its `Blocked by` line or with an
  assignee. First in map order wins.
- **Claim**: `tea issues edit <n> --add-assignees henry` — the session's first
  write.
- **Resolve**: `tea comments add <n> "<answer>"`, then `tea issues close <n>`,
  then append a context pointer to the map's Decisions-so-far.
