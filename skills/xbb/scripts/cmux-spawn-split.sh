#!/usr/bin/env bash
# agmsg --terminal target: run the boot script in a new cmux surface (same workspace)
sid=$(cmux new-split down --focus false | awk '{print $2}')
printf '%s\n' "$sid" > "$HOME/.xbb/last-reviewer-surface"
cmux send --surface "$sid" "$1
"
