#!/usr/bin/env bash
# agmsg --terminal target: run the boot script in a new cmux surface (same workspace)
# Usage: cmux-spawn-split.sh <cmd> <surface-file> <target-cwd>
# <surface-file> must be this run's own $RUN_DIR/reviewer-surface -- a fixed
# shared path here would let two concurrent /xbb runs race on the same
# file, so codex-reviewer-cleanup.sh could close the wrong run's surface.
# <target-cwd> is required because `cmux new-split` has no cwd/target-directory
# flag -- the new surface's shell always inherits the caller's own cmux
# surface cwd, so we must `cd` into place ourselves before running <cmd>.
SURFACE_FILE="${2:?Usage: cmux-spawn-split.sh <cmd> <surface-file> <target-cwd>}"
TARGET_CWD="${3:?Usage: cmux-spawn-split.sh <cmd> <surface-file> <target-cwd>}"
sid=$(cmux new-split down --focus false | awk '{print $2}')
printf '%s\n' "$sid" > "$SURFACE_FILE"
cmux send --surface "$sid" "cd $(printf '%q' "$TARGET_CWD") && $1
"
