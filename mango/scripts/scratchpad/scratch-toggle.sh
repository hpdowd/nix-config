#!/bin/bash
# Usage: scratch-toggle.sh <appid> <launch-command>
# State tracking is handled by scratch-watch.sh; this just dispatches the toggle.
mmsg -s -d "toggle_named_scratchpad,$1,none,$2"
