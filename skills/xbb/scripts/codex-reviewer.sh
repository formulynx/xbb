#!/usr/bin/env bash
# xbb codex-reviewer: the codex reviewer's lifecycle from the orchestrator's
# side. The reviewer runs as a plain OS process wired up via agmsg's
# app-server bridge, never as a Claude Code teammate, so it never appears in
# ~/.claude/teams/*/config.json and TaskStop cannot touch it -- that is why
# this is a script instead of tool calls. Claude-native teammates
# (researchers/coders/the xbb-reviewer *agent*) are a different lifecycle:
# TaskStop, with team-guard.sh locating which ones to stop.
#
# Usage:
#   codex-reviewer.sh preflight
#   codex-reviewer.sh launch  <cmd> <surface-file> <target-cwd>
#   codex-reviewer.sh cleanup <team> <agent-name> <pane-file>
#
# preflight -- verify, once a wang run is confirmed and BEFORE any teammate
# work starts, that a codex review can actually be carried out here:
#   1. reviewer toolchain: codex CLI present, logged in, app-server-capable
#      (0.141+), agmsg installed at a bridge-capable version, node present
#      (codex-bridge.js needs it -- without node the bridge silently degrades:
#      codex launches fine but round-2+ delta delivery never arrives).
#   1b. codex sandbox writable roots: the reviewer is launched with
#      `--sandbox workspace-write` scoped to $HOME/.xbb/codex-cwd, so a
#      codex-side send.sh (ACK/VERDICT delivery) writing to agmsg's shared
#      db/teams/run dirs is denied unless ~/.codex/config.toml grants those
#      as extra writable roots. Confirmed root cause of repeated "attempt to
#      write a readonly database (8)" verdict-delivery failures.
#   2. spawn path: the tmux/cmux socket reachable from inside the Bash
#      sandbox (the one thing the sandbox is known to block; non-tmux
#      launchers run outside the sandbox process tree, nothing to probe).
#   3. app-server live launch: `codex app-server` actually comes up and
#      reports a listening port. It needs write access to ~/.codex, which the
#      Bash sandbox blocks, so the probe runs in a pane placed by `launch`
#      exactly like the reviewer. A detached `tmux new-session` is NOT used --
#      cmux surfaces each tmux session as a new workspace. Skipped when not
#      under tmux.
#   Deliberately NOT covered: the role-session record (bridge arming for
#   round 2+). That is runtime state that only exists after codex's round-1
#   turn runs codex-record-session.sh -- see codex-reviewer-path.md's ACK
#   thread-report step.
#   Never disables the sandbox. On failure prints cause plus fix, exits
#   non-zero so the orchestrator stops the run before spawning teammates.
#
# launch -- place <cmd> in a new pane whose cwd is <target-cwd>, recording
# the pane/surface id in <surface-file>. tmux when $TMUX is set (true both
# for plain tmux and a tmux-backed cmux session -- tmux always wins whenever
# $TMUX is set), else cmux when $CMUX_SOCKET_PATH is set. <surface-file>
# must be this run's own $RUN_DIR file -- a fixed shared path would let two
# concurrent /xbb runs race on it, so `cleanup` could close the wrong run's
# pane. <target-cwd> is passed explicitly because `cmux new-split` has no
# cwd flag; the new surface inherits the caller's cwd, so we `cd` ourselves.
#
# cleanup -- kill the pane/window/surface hosting the reviewer's TUI and
# deregister its agmsg identity. Idempotent. Runs exactly once per run, at
# the true end (PASS, rounds-exhausted, or timeout-abort) -- never before a
# round. <team> is the project-scoped agmsg team SKILL.md's "Team scope"
# step computes (xbb-<basename>-<checksum>); <agent-name> is that step's
# per-run reviewer identity (xbbrv-<RUN_ID>-reviewer), scoping the agmsg
# deregistration to this run's own identity, never a blanket operation.
# <pane-file> is what `launch` wrote -- this design never calls agmsg's
# spawn.sh, so there is no spawn.<team>__<name> placement record; that file
# is the only record of where the reviewer lives.
#   Must run with the sandbox disabled where the default sandbox blocks the
#   tmux control socket (same requirement as `launch`) -- otherwise the
#   teardown calls can silently no-op. That is why cleanup verifies its own
#   result instead of trusting exit status: a sandboxed tmux call commonly
#   still exits 0 having done nothing.
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  codex-reviewer.sh preflight
  codex-reviewer.sh launch  <cmd> <surface-file> <target-cwd>
  codex-reviewer.sh cleanup <team> <agent-name> <pane-file>
USAGE
  exit 1
}

AGMSG_SKILL_DIR="$HOME/.agents/skills/agmsg"

# --- launch -------------------------------------------------------------

launch() {
  local run_cmd="${1:?Usage: codex-reviewer.sh launch <cmd> <surface-file> <target-cwd>}"
  local surface_file="${2:?Usage: codex-reviewer.sh launch <cmd> <surface-file> <target-cwd>}"
  local target_cwd="${3:?Usage: codex-reviewer.sh launch <cmd> <surface-file> <target-cwd>}"
  local mode pane_id sid

  if [ -n "${TMUX:-}" ]; then
    mode=$(jq -r '.codex.tmuxLaunchMode // "split-window"' "$HOME/.xbb/config.json" 2>/dev/null)
    case "$mode" in
      split-window|new-window) ;;
      *) mode="split-window" ;;
    esac
    # cleanup and the Timeout-abort capture-pane step both key off a pane id,
    # so #{pane_id} is captured for both modes even though new-window would
    # more naturally report #{window_id}.
    if [ "$mode" = "new-window" ]; then
      pane_id=$(tmux new-window -d -c "$target_cwd" -P -F '#{pane_id}')
    else
      pane_id=$(tmux split-window -d -c "$target_cwd" -P -F '#{pane_id}')
    fi
    printf '%s\n' "$pane_id" > "$surface_file"
    tmux send-keys -t "$pane_id" "$run_cmd" Enter
  elif [ -n "${CMUX_SOCKET_PATH:-}" ]; then
    sid=$(cmux new-split down --focus false | awk '{print $2}')
    printf '%s\n' "$sid" > "$surface_file"
    cmux send --surface "$sid" "cd $(printf '%q' "$target_cwd") && $run_cmd
"
  else
    echo "codex-reviewer launch: neither \$TMUX nor \$CMUX_SOCKET_PATH is set; no pane backend to launch into." >&2
    return 1
  fi
}

# --- preflight ----------------------------------------------------------

fail() {
  printf 'xbb preflight FAILED: %s\n' "$*" >&2
  printf 'Or switch the reviewer instead: /xbb config reviewer=fable\n' >&2
  exit 1
}

root_covers() {
  # $1 = required absolute dir; checks it against $writable_roots (one per line, may use ~)
  local req="$1" root
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    case "$root" in
      "~"*) root="$HOME${root#\~}" ;;
    esac
    root="${root%/}"
    case "$req" in
      "$root"|"$root"/*) return 0 ;;
    esac
  done <<ROOTS
$writable_roots
ROOTS
  return 1
}

preflight() {
  # --- 1. reviewer toolchain (all platforms) ---
  command -v codex >/dev/null 2>&1 \
    || fail "codex CLI not found on PATH. Install codex or fix PATH."

  codex login status >/dev/null 2>&1 \
    || fail "codex is not logged in. Run: codex login"

  codex app-server --help >/dev/null 2>&1 \
    || fail "this codex build has no app-server subcommand (the agmsg bridge needs codex 0.141+). Update codex."

  local agmsg_codex_dir="$AGMSG_SKILL_DIR/scripts/drivers/types/codex" f
  for f in codex-monitor.sh codex-bridge.js codex-record-session.sh; do
    [ -f "$agmsg_codex_dir/$f" ] \
      || fail "agmsg install lacks drivers/types/codex/$f — the installed agmsg predates the app-server bridge. Update agmsg."
  done

  command -v node >/dev/null 2>&1 \
    || fail "node not found on PATH — codex-bridge.js needs Node. Without it codex launches fine but REVISE-round delta delivery silently never arrives."

  # --- 1b. codex sandbox writable-root check (agmsg's shared state) ---
  # codex-monitor.sh launches codex with `--sandbox workspace-write` scoped to
  # $HOME/.xbb/codex-cwd; agmsg's send.sh/join.sh write outside that cwd
  # (db/teams/run under ~/.agents/skills/agmsg), so codex-side ACK/VERDICT
  # delivery is denied unless config.toml explicitly widens the sandbox.
  local codex_config="${CODEX_HOME:-$HOME/.codex}/config.toml"

  if [ -f "$codex_config" ]; then
    writable_roots="$(awk '
      /^\[sandbox_workspace_write\]/ { insec=1; next }
      /^\[/ { insec=0 }
      insec { print }
    ' "$codex_config" | grep -oE '"[^"]*"' | tr -d '"')"
  else
    writable_roots=""
  fi

  local missing="" sub
  for sub in db teams run; do
    root_covers "$AGMSG_SKILL_DIR/$sub" || missing="$missing $sub"
  done

  if [ -n "$missing" ]; then
    cat >&2 <<MSG
xbb preflight FAILED: codex's workspace-write sandbox has no writable-root
override for agmsg's shared state (missing:${missing# }). Without this, every
codex-side send.sh call (ACK/VERDICT delivery) is denied with "attempt to
write a readonly database (8)" once codex launches with --sandbox
workspace-write scoped to \$HOME/.xbb/codex-cwd.

Fix (one-time): add to $codex_config:

  [sandbox_workspace_write]
  writable_roots = [
      "~/.agents/skills/agmsg/db",
      "~/.agents/skills/agmsg/teams",
      "~/.agents/skills/agmsg/run",
  ]

Or switch the reviewer instead: /xbb config reviewer=fable
MSG
    exit 1
  fi

  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) exit 0 ;; # no Bash sandbox, and no tmux spawn path to probe
  esac

  # Non-tmux launchers (OS terminal via LaunchServices etc.) run outside the
  # sandbox; nothing further to probe. ponytail: only the branch we've seen fail.
  [ -n "${TMUX:-}" ] || exit 0

  # --- 2. sandbox spawn-path probe ---
  local out sock
  out="$(tmux display-message -p ok 2>&1)" && [ "$out" = "ok" ] || {
    sock="${TMUX%%,*}"
    cat >&2 <<MSG
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
MSG
    exit 1
  }

  # --- 3. app-server live-launch probe (throwaway; pane killed after the banner) ---
  local probe_log="${TMPDIR:-/tmp}/xbb-appserver-probe.$$.log"
  local probe_surface="${TMPDIR:-/tmp}/xbb-appserver-probe.$$.pane"
  local probe_pane port ansi_esc
  : > "$probe_log"
  launch "codex app-server --listen ws://127.0.0.1:0 >> '$probe_log' 2>&1" \
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
}

# --- cleanup ------------------------------------------------------------

cleanup() {
  local team="${1:?Usage: codex-reviewer.sh cleanup <team> <agent-name> <pane-file>}"
  local agent_name="${2:?Usage: codex-reviewer.sh cleanup <team> <agent-name> <pane-file>}"
  local pane_file="${3:?Usage: codex-reviewer.sh cleanup <team> <agent-name> <pane-file>}"
  local pane_id="" failed=0

  if [ -f "$pane_file" ]; then
    pane_id="$(cat "$pane_file" 2>/dev/null || true)"
  fi

  # Kill the recorded pane/window/surface first -- for the tmux case this also
  # kills the backgrounded codex-bridge-launcher.sh dispatcher (same process
  # group, dies via SIGHUP on pane teardown). Real stdout/stderr is left
  # visible so a real failure is not hidden behind the verification below.
  # Backend choice mirrors launch(): tmux whenever $TMUX is set, else cmux;
  # a generic OS terminal has no programmatic close (agmsg's own documented
  # limitation -- leave it).
  if [ -n "$pane_id" ]; then
    if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
      case "$pane_id" in
        %*) tmux kill-pane -t "$pane_id" || true ;;
        @*) tmux kill-window -t "$pane_id" || true ;;
        *)  tmux kill-pane -t "$pane_id" 2>/dev/null || tmux kill-window -t "$pane_id" 2>/dev/null || true ;;
      esac
    elif [ -n "${CMUX_SOCKET_PATH:-}" ] && command -v cmux >/dev/null 2>&1; then
      cmux close-surface --surface "$pane_id" 2>/dev/null || true
    fi
  fi

  # Deregister the reviewer identity. Killing the pane alone does not fully
  # tear down the bridge: the per-role bridge child is nohup'd and detached
  # deliberately, so it survives pane teardown and only self-exits once it
  # notices (via its own poll loop) that this (team, name) pair is no longer
  # registered. Best-effort -- do not wait/block on that self-exit.
  bash "$AGMSG_SKILL_DIR/scripts/leave.sh" "$team" "$agent_name" || true

  # Verify -- a tmux call blocked by a sandbox commonly still exits 0 having
  # done nothing.
  if [ -n "$pane_id" ] && command -v tmux >/dev/null 2>&1; then
    if tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane_id" \
      || tmux list-windows -a -F '#{window_id}' 2>/dev/null | grep -qx "$pane_id"; then
      echo "codex-reviewer cleanup: pane/window '$pane_id' for '$agent_name' is still open after kill-pane/kill-window -- if this Bash call ran sandboxed, retry it with the sandbox disabled." >&2
      failed=1
    fi
  fi

  if bash "$AGMSG_SKILL_DIR/scripts/identities.sh" "$HOME/.xbb/codex-cwd" codex 2>/dev/null \
    | awk -F'\t' -v t="$team" -v a="$agent_name" '$1 == t && $2 == a { found=1 } END { exit !found }'; then
    echo "codex-reviewer cleanup: '$team'/'$agent_name' is still registered after leave.sh -- if this Bash call ran sandboxed, retry it with the sandbox disabled." >&2
    failed=1
  fi

  if [ "$failed" -ne 0 ]; then
    echo "status=failed name=$agent_name team=$team pane=${pane_id:-none}"
    exit 1
  fi

  echo "status=ok name=$agent_name team=$team pane=${pane_id:-none}"
}

# --- dispatch -----------------------------------------------------------

cmd="${1:-}"
[ -n "$cmd" ] && shift || usage
case "$cmd" in
  preflight) preflight "$@" ;;
  launch)    launch "$@" ;;
  cleanup)   cleanup "$@" ;;
  *) usage ;;
esac
