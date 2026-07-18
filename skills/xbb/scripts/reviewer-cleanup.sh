#!/usr/bin/env bash
# xbb codex-reviewer cleanup: kill the process and close whatever pane/
# surface hosted it, regardless of how it was placed. Idempotent -- safe to
# call even when nothing is running.
pkill -f 'codex .*actas xbb-reviewer' 2>/dev/null || true

if [ -n "${TMUX:-}" ]; then
  # agmsg always prefers a tmux pane over any --terminal override whenever
  # $TMUX is set (true both for plain tmux and for a tmux-backed cmux
  # session, e.g. `cmux claude-teams`).
  bash ~/.agents/skills/agmsg/scripts/despawn.sh xbb team-lead xbb-reviewer --force 2>/dev/null || true
elif [ -f ~/.xbb/last-reviewer-surface ]; then
  # A non-tmux-backed cmux session that actually took the --terminal
  # template path.
  cmux close-surface --surface "$(cat ~/.xbb/last-reviewer-surface)" 2>/dev/null || true
  rm -f ~/.xbb/last-reviewer-surface
fi
# Otherwise: a plain OS-terminal spawn -- no way to close the window
# programmatically; leave it (agmsg's own documented limitation).
