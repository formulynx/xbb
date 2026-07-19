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
# Usage: codex-reviewer-cleanup.sh <team>
#
# <team> must be the exact team name SKILL.md's "Team scope" step computes
# for this run (e.g. xbb-<basename>-<checksum>-<rundir>, scoped to both the
# project and this specific run directory). The role name "xbb-reviewer" is
# the same literal string for every project, so a pkill matching only on
# "actas xbb-reviewer" would kill a DIFFERENT project's live reviewer
# process. Scoping on <team> via the reviewer's own --cd path (unique per
# project, guaranteed to appear verbatim in `ps`) avoids that.
TEAM="${1:?Usage: codex-reviewer-cleanup.sh <team>}"

pkill -f "codex .*--cd $HOME/.xbb/$TEAM " 2>/dev/null || true

if [ -n "${TMUX:-}" ]; then
  # agmsg always prefers a tmux pane over any --terminal override whenever
  # $TMUX is set (true both for plain tmux and for a tmux-backed cmux
  # session, e.g. `cmux claude-teams`).
  bash ~/.agents/skills/agmsg/scripts/despawn.sh "$TEAM" team-lead xbb-reviewer --force 2>/dev/null || true
elif [ -f ~/.xbb/last-reviewer-surface ]; then
  # A non-tmux-backed cmux session that actually took the --terminal
  # template path.
  cmux close-surface --surface "$(cat ~/.xbb/last-reviewer-surface)" 2>/dev/null || true
  rm -f ~/.xbb/last-reviewer-surface
fi
# Otherwise: a plain OS-terminal spawn -- no way to close the window
# programmatically; leave it (agmsg's own documented limitation).
