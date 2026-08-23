#!/usr/bin/env bash
SURFACE_FILE="${2:?Usage: codex-tmux-launch.sh <cmd> <surface-file> <target-cwd>}"
TARGET_CWD="${3:?Usage: codex-tmux-launch.sh <cmd> <surface-file> <target-cwd>}"

mode=$(jq -r '.codex.tmuxLaunchMode // "split-window"' "$HOME/.xbb/config.json" 2>/dev/null)
case "$mode" in
  split-window|new-window) ;;
  *) mode="split-window" ;;
esac

# codex-reviewer-cleanup.sh and the Timeout-abort capture-pane step both key
# off a pane id in $SURFACE_FILE, so #{pane_id} is captured for both modes
# even though new-window would more naturally report #{window_id}.
if [ "$mode" = "new-window" ]; then
  pane_id=$(tmux new-window -d -c "$TARGET_CWD" -P -F '#{pane_id}')
else
  pane_id=$(tmux split-window -d -c "$TARGET_CWD" -P -F '#{pane_id}')
fi

printf '%s\n' "$pane_id" > "$SURFACE_FILE"
tmux send-keys -t "$pane_id" "$1" Enter
