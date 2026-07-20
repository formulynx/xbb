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
TEAM="${1:?Usage: codex-reviewer-cleanup.sh <team> <agent-name> <run-dir>}"
AGENT_NAME="${2:?Usage: codex-reviewer-cleanup.sh <team> <agent-name> <run-dir>}"
RUN_DIR="${3:?Usage: codex-reviewer-cleanup.sh <team> <agent-name> <run-dir>}"

pkill -f "actas $AGENT_NAME" 2>/dev/null || true

if [ -n "${TMUX:-}" ]; then
  # agmsg always prefers a tmux pane over any --terminal override whenever
  # $TMUX is set (true both for plain tmux and for a tmux-backed cmux
  # session, e.g. `cmux claude-teams`).
  bash ~/.agents/skills/agmsg/scripts/despawn.sh "$TEAM" team-lead "$AGENT_NAME" --force 2>/dev/null || true
elif [ -f "$RUN_DIR/reviewer-surface" ]; then
  # A non-tmux-backed cmux session that actually took the --terminal
  # template path.
  cmux close-surface --surface "$(cat "$RUN_DIR/reviewer-surface")" 2>/dev/null || true
  rm -f "$RUN_DIR/reviewer-surface"
fi
# Otherwise: a plain OS-terminal spawn -- no way to close the window
# programmatically; leave it (agmsg's own documented limitation).
