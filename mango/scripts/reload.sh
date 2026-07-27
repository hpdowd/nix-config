#!/bin/bash
~/.config/mango/scripts/mode.sh
mmsg -s -d reload_config
pkill -x elephant; elephant &
