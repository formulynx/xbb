#!/usr/bin/env bash
# reviewer-spawn-preflight.sh — verify the codex reviewer's spawn path is
# reachable from inside the Bash sandbox BEFORE any teammate work starts.
#
# Run by the /xbb orchestrator once per wang-mode run when reviewer=codex.
# agmsg's spawn.sh picks its launcher deterministically, so only the branch
# it will actually take needs probing:
#   - $TMUX set (tmux, or a tmux-backed cmux session): spawn goes through the
#     tmux client, which connects to a unix socket — the one thing the Bash
#     sandbox is known to block (Operation not permitted, errno 1).
#   - non-tmux macOS: spawn goes through `open -a Terminal` (LaunchServices);
#     the launched terminal runs OUTSIDE the sandbox process tree, so there is
#     nothing to allowlist. Verified reachable from inside the sandbox.
#   - Windows: Claude Code's Bash sandbox does not apply — nothing to probe.
#
# This script never disables the sandbox. On failure it prints the raw probe
# error (which names the blocked resource) plus the settings fix, and exits
# non-zero so the orchestrator stops the run before spawning teammates.
# Once the setting is in place, the probe passes silently on every later run.
set -u

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) exit 0 ;; # no Bash sandbox on Windows
esac

# Non-tmux launchers (OS terminal via LaunchServices etc.) run outside the
# sandbox; nothing to probe. ponytail: only the branch we've seen fail.
[ -n "${TMUX:-}" ] || exit 0

out="$(tmux display-message -p ok 2>&1)" && [ "$out" = "ok" ] && exit 0

sock="${TMUX%%,*}"
cat >&2 <<EOF
xbb preflight FAILED: the codex reviewer cannot be spawned from inside the
Bash sandbox in this environment. Probe \`tmux display-message\` returned:

  $out

Fix (one-time): allow the tmux/cmux socket in ~/.claude/settings.json under
sandbox.network.allowUnixSockets, then START A NEW Claude Code session —
sandbox config is fixed at session start and does not reload mid-session.
Entries match as literal subpaths, not globs — list the containing
directory, no wildcards:

  "sandbox": {
    "network": {
      "allowUnixSockets": [
        "~/.local/state/cmux"
      ]
    }
  }

This session's tmux socket: $sock
If the error above names a different socket path, allowlist that path's
containing directory instead (e.g. plain tmux: "/private/tmp/tmux-<uid>").
See the xbb README, section "Codex reviewer under the Bash sandbox".
EOF
exit 1
