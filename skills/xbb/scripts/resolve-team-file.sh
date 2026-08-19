#!/usr/bin/env bash
# xbb resolve-team-file: prints the team config.json path for a Claude Code
# session id. Pure computation, no file I/O beyond printing -- callers use
# this to get a provisional path before the first spawn confirms it (see
# SKILL.md's Concurrency guard).
#
# Usage:
#   resolve-team-file.sh <session-id>
set -euo pipefail

usage() {
  echo "Usage: $0 <session-id>" >&2
  exit 1
}

session_id="${1:-}"
[ -n "$session_id" ] || usage

echo "$HOME/.claude/teams/session-${session_id:0:8}/config.json"
