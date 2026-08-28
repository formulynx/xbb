#!/usr/bin/env bash
# reviewer-spawn-preflight.sh — verify, at the moment a wang run is confirmed
# and BEFORE any teammate work starts, that a codex review can actually be
# carried out in this environment:
#
#   1. reviewer toolchain: codex CLI present, logged in, app-server-capable
#      (0.141+), agmsg installed at a bridge-capable version, node present
#      (codex-bridge.js needs it — without node the bridge silently degrades:
#      codex launches fine but round-2+ delta delivery never arrives).
#   2. spawn path: the tmux/cmux socket reachable from inside the Bash sandbox
#      (the one thing the sandbox is known to block; non-tmux launchers run
#      outside the sandbox process tree, so there is nothing to probe there).
#   3. app-server live launch: `codex app-server` actually comes up and reports
#      a listening port. The app-server needs write access to ~/.codex, which
#      the Bash sandbox blocks, so the probe runs in a tmux pane (outside the
#      sandbox — the same reason the reviewer itself spawns via tmux), placed
#      via codex-tmux-launch.sh exactly like the reviewer launch: honoring
#      ~/.xbb/config.json's codex.tmuxLaunchMode, default split-window. A
#      detached `tmux new-session` is NOT used — cmux surfaces each tmux
#      session as a new workspace, so a probe session pops a workspace.
#      Skipped when not under tmux.
#   4. codex sandbox writable roots: the reviewer is launched with
#      `--sandbox workspace-write` scoped to its own cwd ($HOME/.xbb/codex-cwd),
#      so a codex-side `send.sh` (ACK/VERDICT delivery) writing to agmsg's
#      shared db/teams/run dirs is denied unless ~/.codex/config.toml grants
#      those as extra writable roots. Confirmed root cause of repeated
#      "attempt to write a readonly database (8)" verdict-delivery failures.
#
# What this deliberately does NOT cover: the role-session record (bridge arming
# for round 2+). That is runtime state that only exists after codex's round-1
# turn runs codex-record-session.sh — see codex-reviewer-path.md's ACK
# thread-report step.
#
# This script never disables the sandbox. On failure it prints the cause plus
# the fix and exits non-zero so the orchestrator stops the run before spawning
# teammates.
set -u

fail() {
  printf 'xbb preflight FAILED: %s\n' "$*" >&2
  printf 'Or switch the reviewer instead: /xbb config reviewer=fable\n' >&2
  exit 1
}

# --- 1. reviewer toolchain (all platforms) ---

command -v codex >/dev/null 2>&1 \
  || fail "codex CLI not found on PATH. Install codex or fix PATH."

codex login status >/dev/null 2>&1 \
  || fail "codex is not logged in. Run: codex login"

codex app-server --help >/dev/null 2>&1 \
  || fail "this codex build has no app-server subcommand (the agmsg bridge needs codex 0.141+). Update codex."

AGMSG_CODEX_DIR="$HOME/.agents/skills/agmsg/scripts/drivers/types/codex"
for f in codex-monitor.sh codex-bridge.js codex-record-session.sh; do
  [ -f "$AGMSG_CODEX_DIR/$f" ] \
    || fail "agmsg install lacks drivers/types/codex/$f — the installed agmsg predates the app-server bridge. Update agmsg."
done

command -v node >/dev/null 2>&1 \
  || fail "node not found on PATH — codex-bridge.js needs Node. Without it codex launches fine but REVISE-round delta delivery silently never arrives."

# --- 1b. codex sandbox writable-root check (agmsg's shared state) ---
# codex-monitor.sh launches codex with `--sandbox workspace-write` scoped to
# $HOME/.xbb/codex-cwd; agmsg's send.sh/join.sh write outside that cwd
# (db/teams/run under ~/.agents/skills/agmsg), so codex-side ACK/VERDICT
# delivery is denied unless config.toml explicitly widens the sandbox.
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_CONFIG="$CODEX_HOME/config.toml"
AGMSG_DIR="$HOME/.agents/skills/agmsg"

if [ -f "$CODEX_CONFIG" ]; then
  writable_roots="$(awk '
    /^\[sandbox_workspace_write\]/ { insec=1; next }
    /^\[/ { insec=0 }
    insec { print }
  ' "$CODEX_CONFIG" | grep -oE '"[^"]*"' | tr -d '"')"
else
  writable_roots=""
fi

root_covers() {
  # $1 = required absolute dir; checks it against $writable_roots (one per line, may use ~)
  req="$1"
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    case "$root" in
      "~"*) root="$HOME${root#\~}" ;;
    esac
    root="${root%/}"
    case "$req" in
      "$root"|"$root"/*) return 0 ;;
    esac
  done <<EOF
$writable_roots
EOF
  return 1
}

missing=""
for sub in db teams run; do
  root_covers "$AGMSG_DIR/$sub" || missing="$missing $sub"
done

if [ -n "$missing" ]; then
  cat >&2 <<EOF
xbb preflight FAILED: codex's workspace-write sandbox has no writable-root
override for agmsg's shared state (missing:${missing# }). Without this, every
codex-side send.sh call (ACK/VERDICT delivery) is denied with "attempt to
write a readonly database (8)" once codex launches with --sandbox
workspace-write scoped to \$HOME/.xbb/codex-cwd.

Fix (one-time): add to $CODEX_CONFIG:

  [sandbox_workspace_write]
  writable_roots = [
      "~/.agents/skills/agmsg/db",
      "~/.agents/skills/agmsg/teams",
      "~/.agents/skills/agmsg/run",
  ]

Or switch the reviewer instead: /xbb config reviewer=fable
EOF
  exit 1
fi

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) exit 0 ;; # no Bash sandbox, and no tmux spawn path to probe
esac

# Non-tmux launchers (OS terminal via LaunchServices etc.) run outside the
# sandbox; nothing further to probe. ponytail: only the branch we've seen fail.
[ -n "${TMUX:-}" ] || exit 0

# --- 2. sandbox spawn-path probe ---

out="$(tmux display-message -p ok 2>&1)" && [ "$out" = "ok" ] || {
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
}

# --- 3. app-server live-launch probe (throwaway; pane killed after the banner) ---

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
probe_log="${TMPDIR:-/tmp}/xbb-appserver-probe.$$.log"
probe_surface="${TMPDIR:-/tmp}/xbb-appserver-probe.$$.pane"
: > "$probe_log"
bash "$SCRIPT_DIR/codex-tmux-launch.sh" \
  "codex app-server --listen ws://127.0.0.1:0 >> '$probe_log' 2>&1" \
  "$probe_surface" "$HOME" \
  || fail "could not place the app-server probe pane via tmux."
probe_pane="$(cat "$probe_surface" 2>/dev/null)"
rm -f "$probe_surface"

port=""
ansi_esc="$(printf '\033')"
for _ in $(seq 1 150); do
  # codex 0.144+ colorizes the banner even into a redirected file.
  port="$(sed -e "s/${ansi_esc}\[[0-9;]*m//g" "$probe_log" 2>/dev/null \
    | sed -n 's#.*listening on: ws://127\.0\.0\.1:\([0-9][0-9]*\).*#\1#p' | head -1)"
  [ -n "$port" ] && break
  tmux display-message -p -t "$probe_pane" ok >/dev/null 2>&1 || break
  sleep 0.1
done
[ -n "$probe_pane" ] && tmux kill-pane -t "$probe_pane" 2>/dev/null || true

if [ -z "$port" ]; then
  {
    printf 'xbb preflight FAILED: codex app-server did not report a listening port.\n'
    printf 'Its output was:\n\n'
    sed 's/^/  /' "$probe_log" 2>/dev/null
    printf '\nLikely cause: a codex release changed the app-server interface. Update codex or agmsg.\n'
    printf 'Or switch the reviewer instead: /xbb config reviewer=fable\n'
  } >&2
  rm -f "$probe_log"
  exit 1
fi
rm -f "$probe_log"
exit 0
