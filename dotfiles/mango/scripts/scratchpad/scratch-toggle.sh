#!/usr/bin/env bash
# Usage: scratch-toggle.sh <appid> <launch-command>
# State tracking is handled by scratch-watch.sh; this just dispatches the toggle.
mmsg dispatch "toggle_named_scratchpad,$1,none,$2"
