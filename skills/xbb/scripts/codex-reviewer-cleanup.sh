#!/usr/bin/env bash
# xbb codex-reviewer cleanup: kill the tmux pane/window hosting the codex
# reviewer's TUI and deregister its agmsg identity. Idempotent -- safe to
# call even when nothing is running. Runs exactly once per run, at the true
# end (PASS, rounds-exhausted, or timeout-abort) -- never before a round.
#
# Scope: the codex reviewer only. It runs as a plain OS process wired up via
# agmsg's app-server bridge, never as a Claude Code teammate, so it never
# appears in ~/.claude/teams/*/config.json and TaskStop cannot touch it --
# that's the entire reason this is a bash script instead of a tool call.
# Claude-native teammates (researchers/coders/the xbb-reviewer *agent*) are a
# completely different lifecycle: they're stopped via the TaskStop tool, with
# team-guard.sh (this directory) locating which ones to stop.
#
# Usage: codex-reviewer-cleanup.sh <team> <agent-name> <pane-file>
#
# <team> is the project-scoped agmsg team SKILL.md's "Team scope" step
# computes (e.g. xbb-<basename>-<checksum>) -- stable and reused across every
# run on this project. <agent-name> is that same step's per-run reviewer
# identity (xbbrv-<RUN_ID>-reviewer), used only to scope the agmsg
# deregistration below to this run's own identity, never a blanket operation.
# <pane-file> is the file the Launch step wrote the created pane/window id
# to (SKILL.md's Codex reviewer path, `$RUN_DIR/codex-reviewer-pane`) --
# this design never calls agmsg's spawn.sh, so there is no
# spawn.<team>__<name> placement record to read the pane id from instead;
# this file is the only record of where the reviewer lives.
#
# This must run with the sandbox disabled in an environment where the
# default sandbox blocks the tmux control socket (the same requirement
# Launch has) -- otherwise the teardown calls below can silently no-op. That
# is exactly why this script verifies its own result instead of trusting the
# calls' exit status: a sandboxed tmux call commonly still exits 0 (it just
# did nothing), so only checking afterward that the pane is actually gone
# catches it.
set -uo pipefail

TEAM="${1:?Usage: codex-reviewer-cleanup.sh <team> <agent-name> <pane-file>}"
AGENT_NAME="${2:?Usage: codex-reviewer-cleanup.sh <team> <agent-name> <pane-file>}"
PANE_FILE="${3:?Usage: codex-reviewer-cleanup.sh <team> <agent-name> <pane-file>}"

AGMSG_SKILL_DIR="$HOME/.agents/skills/agmsg"

PANE_ID=""
if [ -f "$PANE_FILE" ]; then
  PANE_ID="$(cat "$PANE_FILE" 2>/dev/null || true)"
fi

# Kill the recorded pane/window/surface first -- for the tmux case this also
# kills the backgrounded codex-bridge-launcher.sh dispatcher (same process
# group, dies via SIGHUP on pane teardown). Real stdout/stderr is left
# visible (not redirected to /dev/null) so a real failure is not hidden
# behind the verification below.
#
# Which command applies depends on how Launch placed the pane, mirroring
# Launch's own decision: tmux split/window when $TMUX is set (checked first,
# same priority order as Launch -- a tmux-backed cmux session also has $TMUX
# set and must use tmux, not cmux close-surface); cmux-spawn-split.sh's
# surface id when $CMUX_SOCKET_PATH is set and $TMUX is not; otherwise a
# generic OS terminal, which has no programmatic close (agmsg's own
# documented limitation -- leave it, same as the old design).
if [ -n "$PANE_ID" ]; then
  if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    case "$PANE_ID" in
      %*) tmux kill-pane -t "$PANE_ID" || true ;;
      @*) tmux kill-window -t "$PANE_ID" || true ;;
      *)  tmux kill-pane -t "$PANE_ID" 2>/dev/null || tmux kill-window -t "$PANE_ID" 2>/dev/null || true ;;
    esac
  elif [ -n "${CMUX_SOCKET_PATH:-}" ] && command -v cmux >/dev/null 2>&1; then
    cmux close-surface --surface "$PANE_ID" 2>/dev/null || true
  fi
fi

# Deregister the reviewer identity. Killing the pane alone does not fully
# tear down the bridge: the per-role bridge child is nohup'd and detached
# deliberately, so it survives pane teardown and only self-exits once it
# notices (via its own poll loop) that this (team, name) pair is no longer
# registered. This is best-effort cleanup -- do not wait/block on that
# self-exit.
bash "$AGMSG_SKILL_DIR/scripts/leave.sh" "$TEAM" "$AGENT_NAME" || true

# Verify -- don't trust the calls above at face value. A tmux call blocked by
# a sandbox commonly still exits 0 having done nothing.
FAILED=0

if [ -n "$PANE_ID" ] && command -v tmux >/dev/null 2>&1; then
  if tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$PANE_ID" \
    || tmux list-windows -a -F '#{window_id}' 2>/dev/null | grep -qx "$PANE_ID"; then
    echo "codex-reviewer-cleanup: pane/window '$PANE_ID' for '$AGENT_NAME' is still open after kill-pane/kill-window -- if this Bash call ran sandboxed, retry it with the sandbox disabled." >&2
    FAILED=1
  fi
fi

if bash "$AGMSG_SKILL_DIR/scripts/identities.sh" "$HOME/.xbb/codex-cwd" codex 2>/dev/null \
  | awk -F'\t' -v t="$TEAM" -v a="$AGENT_NAME" '$1 == t && $2 == a { found=1 } END { exit !found }'; then
  echo "codex-reviewer-cleanup: '$TEAM'/'$AGENT_NAME' is still registered after leave.sh -- if this Bash call ran sandboxed, retry it with the sandbox disabled." >&2
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "status=failed name=$AGENT_NAME team=$TEAM pane=${PANE_ID:-none}"
  exit 1
fi

echo "status=ok name=$AGENT_NAME team=$TEAM pane=${PANE_ID:-none}"
