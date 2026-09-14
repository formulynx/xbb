#!/usr/bin/env bash
# xbb-admin: mechanical half of /xbb's `clean` and `config` modes.
# SKILL.md owns every question to the user; this script only measures,
# validates, and writes. `clean delete` is only ever called after the user
# confirmed on `clean measure` output.
#
# Usage:
#   xbb-admin.sh clean measure
#   xbb-admin.sh clean delete
#   xbb-admin.sh config get                 -> effective config JSON (defaults merged; creates the file)
#   xbb-admin.sh config set <key>=<value>... -> validate all, then write; prints the new config
#   xbb-admin.sh config sync                -> fills missing keys, drops stale ones (written
#                                               immediately), reports invalid values unchanged;
#                                               prints {"added":[],"removed":[],"invalid":[],"config":{}}
#
# Keys: reviewer, reviewerEffort, maxConcurrentAgents, reviewMaxRounds,
#       handoffLeftRatio, coder.model, coder.effort, researcher.model,
#       researcher.effort, codex.model, codex.effort, codex.pingTimeoutSec,
#       codex.replyTimeoutSec, codex.tmuxLaunchMode
# Any invalid assignment rejects the whole `set` (exit 1, file untouched).
# `reviewer=codex` additionally runs codex-reviewer.sh preflight before saving.
set -euo pipefail

usage() {
  sed -n '/^# Usage:/,/^# `reviewer=codex`/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HOME/.xbb/config.json"
DEFAULTS='{
  "reviewer": "fable",
  "reviewerEffort": "medium",
  "coder": { "model": "sonnet", "effort": "high" },
  "researcher": { "model": "sonnet", "effort": "medium" },
  "codex": { "model": "gpt-5.6-terra", "effort": "medium", "pingTimeoutSec": 180, "replyTimeoutSec": 300, "tmuxLaunchMode": "split-window" },
  "maxConcurrentAgents": 4,
  "reviewMaxRounds": 8,
  "handoffLeftRatio": 0.3
}'

# --- clean ---------------------------------------------------------------

clean() {
  local R="${TMPDIR:-${TEMP:-${TMP:-/tmp}}}"
  [ -n "$R" ] || { echo "TEMP-ROOT-UNRESOLVED" >&2; exit 2; }
  if ! compgen -G "$R"/xbb-run-*/ > /dev/null; then
    echo "nothing to clean"
    exit 0
  fi
  case "${1:-}" in
    measure)
      du -sh "$R"/xbb-run-*/ 2>/dev/null | sort -h
      du -shc "$R"/xbb-run-*/ 2>/dev/null | tail -1
      ;;
    delete)
      local freed count
      freed=$(du -shc "$R"/xbb-run-*/ 2>/dev/null | tail -1 | awk '{print $1}')
      count=$(compgen -G "$R"/xbb-run-*/ | wc -l | tr -d ' ')
      rm -rf "$R"/xbb-run-*/
      echo "Deleted $count dir(s), freed $freed"
      ;;
    *) usage ;;
  esac
}

# --- config --------------------------------------------------------------

config_get() {
  mkdir -p "$(dirname "$CONFIG")"
  [ -f "$CONFIG" ] || printf '%s\n' "$DEFAULTS" > "$CONFIG"
  jq -S --argjson d "$DEFAULTS" '$d * .' "$CONFIG"
}

# Prints the jq-typed value for key, or a reason on stderr and non-zero.
validate() {
  local key="$1" val="$2"
  case "$key" in
    reviewer)
      case "$val" in fable|opus|sonnet|codex) printf '"%s"' "$val" ;; *) echo "reviewer must be one of fable/opus/sonnet/codex (got '$val')" >&2; return 1 ;; esac ;;
    codex.effort|reviewerEffort|coder.effort|researcher.effort)
      case "$val" in low|medium|high|xhigh) printf '"%s"' "$val" ;; *) echo "$key must be one of low/medium/high/xhigh (got '$val')" >&2; return 1 ;; esac ;;
    codex.tmuxLaunchMode)
      case "$val" in split-window|new-window) printf '"%s"' "$val" ;; *) echo "codex.tmuxLaunchMode must be split-window or new-window (got '$val')" >&2; return 1 ;; esac ;;
    codex.model|coder.model|researcher.model)
      [ -n "$val" ] && printf '%s' "$val" | jq -R . || { echo "$key must be non-empty" >&2; return 1; } ;;
    maxConcurrentAgents|reviewMaxRounds|codex.pingTimeoutSec|codex.replyTimeoutSec)
      case "$val" in ''|*[!0-9]*|0) echo "$key must be a positive integer (got '$val')" >&2; return 1 ;; *) printf '%s' "$val" ;; esac ;;
    handoffLeftRatio)
      awk -v v="$val" 'BEGIN { exit !(v ~ /^[0-9]+(\.[0-9]+)?$/ && v + 0 >= 0.1 && v + 0 <= 0.9) }' \
        && printf '%s' "$val" || { echo "handoffLeftRatio must be a number in 0.1-0.9 (got '$val')" >&2; return 1; } ;;
    *) echo "unknown key '$key'" >&2; return 1 ;;
  esac
}

leaf_paths() { jq -c '[paths(scalars) as $p | $p | join(".")]'; }

config_sync() {
  mkdir -p "$(dirname "$CONFIG")"
  [ -f "$CONFIG" ] || printf '%s\n' "$DEFAULTS" > "$CONFIG"

  local cur def_keys cur_keys added removed new k val out
  cur="$(cat "$CONFIG")"
  def_keys="$(leaf_paths <<<"$DEFAULTS")"
  cur_keys="$(leaf_paths <<<"$cur")"
  added="$(jq -cn --argjson a "$def_keys" --argjson b "$cur_keys" '$a - $b')"
  removed="$(jq -cn --argjson a "$cur_keys" --argjson b "$def_keys" '$a - $b')"

  new="$cur"
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    new="$(jq --argjson d "$DEFAULTS" --arg k "$k" \
      'setpath($k | split("."); $d | getpath($k | split(".")))' <<<"$new")"
  done < <(jq -r '.[]' <<<"$added")
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    new="$(jq --arg k "$k" 'delpaths([$k | split(".")])' <<<"$new")"
  done < <(jq -r '.[]' <<<"$removed")
  new="$(jq 'walk(if type == "object" then with_entries(select(.value != {})) else . end)' <<<"$new")"

  if [ "$new" != "$cur" ]; then
    printf '%s\n' "$new" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  fi

  local invalid="[]"
  while IFS= read -r k; do
    val="$(jq -r --arg k "$k" 'getpath($k | split("."))' <<<"$new")"
    if ! out="$(validate "$k" "$val" 2>&1)"; then
      invalid="$(jq -cn --argjson inv "$invalid" --arg k "$k" --arg v "$val" --arg r "$out" \
        '$inv + [{key:$k, value:$v, reason:$r}]')"
    fi
  done < <(jq -r '.[]' <<<"$def_keys")

  jq -n --argjson added "$added" --argjson removed "$removed" --argjson invalid "$invalid" --argjson config "$new" \
    '{added:$added, removed:$removed, invalid:$invalid, config:$config}'
}

config_set() {
  [ $# -gt 0 ] || usage
  local new key val typed ok=1 assign
  new="$(config_get)"
  for assign in "$@"; do
    case "$assign" in *=*) ;; *) echo "expected key=value (got '$assign')" >&2; ok=0; continue ;; esac
    key="${assign%%=*}"; val="${assign#*=}"
    if typed="$(validate "$key" "$val")"; then
      new="$(jq --argjson v "$typed" "setpath(\"$key\" | split(\".\"); \$v)" <<<"$new")"
    else
      ok=0
    fi
  done
  [ "$ok" = 1 ] || { echo "config unchanged" >&2; exit 1; }

  if [ "$(jq -r .reviewer <<<"$new")" = codex ] && [ "$(jq -r .reviewer "$CONFIG")" != codex ]; then
    if [ ! -d "$HOME/.agents/skills/agmsg" ]; then
      local installer
      installer="$(ls "$HOME"/.claude/plugins/cache/fujibee-agmsg/agmsg/*/install.sh 2>/dev/null | head -1 || true)"
      [ -n "$installer" ] && bash "$installer" --cmd agmsg \
        || { echo "agmsg not installed; run: /plugin install agmsg@fujibee-agmsg" >&2; echo "config unchanged" >&2; exit 1; }
    fi
    bash "$SCRIPT_DIR/codex-reviewer.sh" preflight || { echo "config unchanged" >&2; exit 1; }
  fi

  printf '%s\n' "$new" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  printf '%s\n' "$new"
}

case "${1:-}" in
  clean) clean "${2:-}" ;;
  config)
    case "${2:-}" in
      get) config_get ;;
      set) shift 2; config_set "$@" ;;
      sync) config_sync ;;
      *) usage ;;
    esac ;;
  *) usage ;;
esac
