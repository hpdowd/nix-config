#!/usr/bin/env bash
# Usage: scratch-toggle.sh <appid> <launch-command>
# A one-line wrapper over the compositor's own verb, kept only because
# modules/home/wayle.nix names it — universal/bind.conf dispatches directly.
# scratch-watch.sh, which tracked the state for waybar's scratchpad modules, went
# with them (docs/adr/0051); nothing reads /tmp/scratch-<pad> any more.
mmsg dispatch "toggle_named_scratchpad,$1,none,$2"
