#!/usr/bin/env bash
~/.config/mango/scripts/mode.sh
mmsg -s -d reload_config

# `pkill -x elephant` was here until 2026-07-30 and had been a silent no-op
# since the migration: nixpkgs ships elephant as a wrapper, so the process
# `comm` is `.elephant-wrapped` — and the kernel truncates comm to 15 chars,
# so it actually reads `.elephant-wrapp`. `-x` matches comm exactly, so it
# never matched, and every reload leaked another elephant. Match the command
# line instead, which is the stable `/nix/store/…/bin/elephant`.
pkill -f 'bin/elephant$'

# setsid + redirect: without them elephant inherits this script's stdout, so
# any caller that pipes reload.sh (`reload.sh | tail`) hangs forever waiting
# for EOF on a pipe the daemon is holding open.
setsid elephant >/dev/null 2>&1 < /dev/null &
disown
