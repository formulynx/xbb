#!/usr/bin/env bash
# xbb codex-reviewer cleanup: kill the codex reviewer's OS process and close
# whatever pane/surface hosted it, regardless of how it was placed.
# Idempotent -- safe to call even when nothing is running.
#
# Scope: the codex reviewer only. It runs as a plain OS process wired up via
# agmsg, never as a Claude Code teammate, so it never appears in
# ~/.claude/teams/*/config.json and TaskStop cannot touch it -- that's the
# entire reason this is a bash script instead of a tool call. Claude-native
# teammates (researchers/coders/the xbb-reviewer *agent*) are a completely
# different lifecycle: they're stopped via the TaskStop tool, with
# team-guard.sh (this directory) locating which ones to stop.
#
# Usage: codex-reviewer-cleanup.sh <team> <agent-name> <run-dir>
#
# <team> is the project-scoped agmsg team SKILL.md's "Team scope" step
# computes (e.g. xbb-<basename>-<checksum>) -- stable and reused across
# every run on this project, since it's no longer what makes a run unique.
# <agent-name> is that same step's per-run codex actas identity
# (xbbrv-<RUN_ID>-reviewer) -- codex has no dedicated session-name flag, so
# agmsg passes this as the trailing positional prompt argument to the codex
# process itself, meaning it's fully visible in `ps`/`pkill -f`, same as any
# other argv content. A pkill matching only on the role-shaped name
# "xbb-reviewer" (shared across every project) would kill a DIFFERENT
# project's -- or a DIFFERENT run's -- live reviewer process; scoping on the
# run-unique <agent-name> instead avoids that regardless of whether --cd or
# team happen to be shared. <run-dir> must be this run's $RUN_DIR (step 3),
# needed only for locating the reviewer-surface marker below.
#
# This must run with the sandbox disabled in an environment where the
# default sandbox blocks the tmux/cmux control socket (the same requirement
# Spawn has) -- otherwise the teardown calls below can silently no-op. That
# is exactly why this script verifies its own result instead of trusting
# despawn.sh's exit status: a sandboxed tmux/cmux call commonly still exits
# 0 (it just did nothing), so only checking afterward that the process and
# pane are actually gone catches it.
set -uo pipefail

TEAM="${1:?Usage: codex-reviewer-cleanup.sh <team> <agent-name> <run-dir>}"
AGENT_NAME="${2:?Usage: codex-reviewer-cleanup.sh <team> <agent-name> <run-dir>}"
RUN_DIR="${3:?Usage: codex-reviewer-cleanup.sh <team> <agent-name> <run-dir>}"

# Capture the recorded tmux placement BEFORE tearing anything down --
# despawn.sh --force deletes this record as part of its own teardown, so it
# would be gone by the time we could check it afterward otherwise.
PANE_ID=""
AGMSG_SKILL_DIR="$HOME/.agents/skills/agmsg"
if [ -n "${TMUX:-}" ] && [ -f "$AGMSG_SKILL_DIR/scripts/lib/actas-lock.sh" ]; then
  SKILL_DIR="$AGMSG_SKILL_DIR"
  # shellcheck disable=SC1091
  . "$AGMSG_SKILL_DIR/scripts/lib/instance-id.sh" 2>/dev/null || true
  # shellcheck disable=SC1091
  . "$AGMSG_SKILL_DIR/scripts/lib/actas-lock.sh" 2>/dev/null || true
  if command -v agmsg_spawn_path >/dev/null 2>&1; then
    SPAWN_REC="$(agmsg_spawn_path "$TEAM" "$AGENT_NAME" 2>/dev/null || true)"
    [ -n "$SPAWN_REC" ] && [ -f "$SPAWN_REC" ] && PANE_ID="$(cut -f1 "$SPAWN_REC" 2>/dev/null || true)"
  fi
fi

pkill -f "actas $AGENT_NAME" 2>/dev/null || true

if [ -n "${TMUX:-}" ]; then
  # agmsg always prefers a tmux pane over any --terminal override whenever
  # $TMUX is set (true both for plain tmux and for a tmux-backed cmux
  # session, e.g. `cmux claude-teams`). Real stdout/stderr is left visible
  # (not redirected to /dev/null) so a real despawn.sh failure is not hidden
  # behind the verification below.
  bash "$AGMSG_SKILL_DIR/scripts/despawn.sh" "$TEAM" team-lead "$AGENT_NAME" --force || true
elif [ -f "$RUN_DIR/reviewer-surface" ]; then
  # A non-tmux-backed cmux session that actually took the --terminal
  # template path.
  cmux close-surface --surface "$(cat "$RUN_DIR/reviewer-surface")" 2>/dev/null || true
  rm -f "$RUN_DIR/reviewer-surface"
fi
# Otherwise: a plain OS-terminal spawn -- no way to close the window
# programmatically; leave it (agmsg's own documented limitation).

# Verify -- don't trust the calls above at face value. A tmux/cmux call
# blocked by a sandbox commonly still exits 0 having done nothing.
FAILED=0

if command -v pgrep >/dev/null 2>&1 && pgrep -f "actas $AGENT_NAME" >/dev/null 2>&1; then
  echo "codex-reviewer-cleanup: process for '$AGENT_NAME' is still running after pkill/despawn -- if this Bash call ran sandboxed, retry it with the sandbox disabled." >&2
  FAILED=1
fi

if [ -n "$PANE_ID" ] && command -v tmux >/dev/null 2>&1; then
  if tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$PANE_ID"; then
    echo "codex-reviewer-cleanup: tmux pane '$PANE_ID' for '$AGENT_NAME' is still open after despawn --force -- if this Bash call ran sandboxed, retry it with the sandbox disabled." >&2
    FAILED=1
  fi
fi

if [ "$FAILED" -ne 0 ]; then
  echo "status=failed name=$AGENT_NAME team=$TEAM pane=${PANE_ID:-none}"
  exit 1
fi

echo "status=ok name=$AGENT_NAME team=$TEAM pane=${PANE_ID:-none}"
