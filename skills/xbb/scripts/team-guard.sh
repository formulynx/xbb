#!/usr/bin/env bash
# xbb team-guard: mechanical accounting for maxConcurrentAgents and for
# finding this run's Claude-native teammates (researchers/coders/reviewers)
# to stop. Never spawns or stops anything itself -- Agent (spawn) and
# TaskStop are tool calls only the orchestrator can issue; this script only
# tells it what the team config.json currently supports.
#
# A member's "isActive" field is true only while it is mid-turn; it goes
# false the instant it goes idle -- which covers "genuinely done" (sent its
# STATUS/VERDICT signal and stopped), "merely paused" (sent a live
# escalation and is waiting on the orchestrator's reply), AND "finished but
# not yet graded" (sent STATUS: DONE but the orchestrator hasn't read/
# accepted the report yet). None of these close the member's underlying
# tmux pane/process -- only TaskStop does that -- so `gate` weighs ACTIVE
# and FINISHED together against <max-concurrent>: an idle-but-unstopped
# member still occupies a real process slot, not just a mid-turn one. So a
# `false` member from `count`/`gate` is only a *candidate* to stop, never a
# standing instruction -- the caller must cross-check each one against its
# own STATUS-signal bookkeeping before calling TaskStop on it. `sweep` is
# the one exception: call it only once every teammate is already known
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
# infix. A *missing* team file is a hard error (exit 2), never an empty
# result: once this run has spawned anything the file must exist, so
# "unreadable" and "no live members" must not collapse into the same
# `ACTIVE 0` answer -- that ambiguity is what makes a caller mistake a
# mis-resolved path for a dead teammate. Empty output (file present, no
# matching members) is still fine and not an error.
# Checked here, not inside rows(): `count` calls rows() in command
# substitution, where an exit would only kill the subshell and still print
# `ACTIVE 0` with exit 0 -- the exact ambiguity this guard exists to remove.
[ -f "$file" ] || { echo "TEAMFILE-MISSING $file" >&2; exit 2; }

rows() {
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
    total_n=$(rows | wc -l | tr -d ' ')
    have=$(rows | awk -F'\t' '$2=="false"' | wc -l | tr -d ' ')
    if [ $((total_n + want)) -le "$max" ]; then
      echo "SPAWN $want"
    else
      need=$((total_n + want - max))
      candidates=$(rows | awk -F'\t' '$2=="false"{print $1}' | head -n "$need" | tr '\n' ' ')
      echo "HOLD need=$need candidates=$candidates"
      # `if`, not `[ ... ] &&`: the failed test would be the script's last
      # status, exiting 1 on a perfectly normal HOLD -- now that exit 2 means
      # "team file unreadable", a spurious non-zero here is misreadable.
      if [ "$have" -lt "$need" ]; then echo "SHORTFALL $((need - have))"; fi
    fi
    ;;
  sweep)
    rows | awk -F'\t' '{print $1}'
    ;;
  *) usage ;;
esac
