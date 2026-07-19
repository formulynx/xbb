#!/usr/bin/env bash
# xbb team-guard: mechanical accounting for maxConcurrentAgents and for
# finding this run's Claude-native teammates (researchers/coders/reviewers)
# to stop. Never spawns or stops anything itself -- Agent (spawn) and
# TaskStop are tool calls only the orchestrator can issue; this script only
# tells it what the team config.json currently supports.
#
# A member's "isActive" field is true only while it is mid-turn; it goes
# false the instant it goes idle -- which covers BOTH "genuinely done" (sent
# its STATUS/VERDICT signal and stopped) AND "merely paused" (sent a live
# escalation and is waiting on the orchestrator's reply). So a `false`
# member from `count`/`gate` is only a *candidate* to stop, never a standing
# instruction -- the caller must cross-check each one against its own
# STATUS-signal bookkeeping before calling TaskStop on it. `sweep` is the
# one exception: call it only once every teammate is already known
# DONE/abandoned (SKILL.md step 6), at which point acting on its output
# unconditionally is safe.
#
# Usage:
#   team-guard.sh count <team-file> <run-id>
#   team-guard.sh gate  <team-file> <run-id> <max-concurrent> <want-n>
#   team-guard.sh sweep <team-file> <run-id>
#
# <run-id> is the 3-char infix shared by this run's teammate names
# (xbbr-<run-id>-NN, xbbc-<run-id>-NN, xbbrv-<run-id>-NN).
set -euo pipefail

usage() {
  echo "Usage: $0 {count|gate|sweep} <team-file> <run-id> [max-concurrent want-n]" >&2
  exit 1
}

cmd="${1:-}"; file="${2:-}"; run_id="${3:-}"
[ -n "$cmd" ] && [ -n "$file" ] && [ -n "$run_id" ] || usage

# name<TAB>true|false, one line per non-team-lead member carrying this run's
# infix. Empty (not an error) when the team file doesn't exist yet or has
# no such members.
rows() {
  [ -f "$file" ] || return 0
  jq -r --arg rid "-$run_id-" \
    '.members[] | select(.name != "team-lead" and (.name | contains($rid)))
     | "\(.name)\t\(.isActive == true)"' "$file"
}

case "$cmd" in
  count)
    echo "ACTIVE $(rows | awk -F'\t' '$2=="true"' | wc -l | tr -d ' ')"
    echo "FINISHED $(rows | awk -F'\t' '$2=="false"' | wc -l | tr -d ' ')"
    echo "ACTIVE_NAMES $(rows | awk -F'\t' '$2=="true"{print $1}' | tr '\n' ' ')"
    echo "FINISHED_NAMES $(rows | awk -F'\t' '$2=="false"{print $1}' | tr '\n' ' ')"
    ;;
  gate)
    max="${4:?max-concurrent required}"; want="${5:?want-n required}"
    active_n=$(rows | awk -F'\t' '$2=="true"' | wc -l | tr -d ' ')
    if [ $((active_n + want)) -le "$max" ]; then
      echo "SPAWN $want"
    else
      need=$((active_n + want - max))
      have=$(rows | awk -F'\t' '$2=="false"' | wc -l | tr -d ' ')
      candidates=$(rows | awk -F'\t' '$2=="false"{print $1}' | head -n "$need" | tr '\n' ' ')
      echo "HOLD need=$need candidates=$candidates"
      [ "$have" -lt "$need" ] && echo "SHORTFALL $((need - have))"
    fi
    ;;
  sweep)
    rows | awk -F'\t' '{print $1}'
    ;;
  *) usage ;;
esac
