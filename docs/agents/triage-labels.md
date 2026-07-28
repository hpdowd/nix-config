# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## Creating them on the Gitea repo

These labels do not exist on `henry/arch-config` yet — Gitea seeds a new repo
with its own default set, which does not include any of them. Create them once
(requires the homelab tunnel to be up; see `issue-tracker.md`):

```bash
tea labels create --name needs-triage    --color "#d4c5f9" --description "Maintainer needs to evaluate this issue"
tea labels create --name needs-info      --color "#fbca04" --description "Waiting on reporter for more information"
tea labels create --name ready-for-agent --color "#0e8a16" --description "Fully specified, ready for an AFK agent"
tea labels create --name ready-for-human --color "#1d76db" --description "Requires human implementation"
tea labels create --name wontfix         --color "#ffffff" --description "Will not be actioned"
```

Check what's already there first with `tea labels list` — if any of these names
already exist under different colours, leave them alone and edit the table
above instead of creating duplicates.
