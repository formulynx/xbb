#!/usr/bin/env bash
# xbb context-left: mechanical remaining-context check for a teammate to run
# against its own transcript.
#
# Exists because Claude Code's <total_tokens> reminder is a padded
# countdown from a fixed 15,000,000 budget, not from the model's real
# context window -- a teammate reading it can hit "Prompt is too long" at
# ~975K real tokens while the reminder still shows ~14,000,000 left. The
# transcript's own `message.usage` on the last assistant entry is the real
# figure. That figure still lags one API call behind (usage reflects the
# turn that just completed, not whatever tool result the caller is about
# to add to the transcript), so a run right at the threshold is not a hard
# guarantee against one unusually large next tool result.
#
# Usage:
#   context-left.sh [threshold]
#
# threshold: remaining-context ratio below which action is HANDOFF instead
# of CONTINUE; optional, default 0.3, must be in [0.1, 0.9].
#
# Never reads ~/.xbb/config.json -- teammates invoking this script must not
# need that read scope.
set -euo pipefail

error_exit() {
  jq -nc --arg reason "$1" '{result:"ERROR", reason:$reason}'
  exit 1
}

threshold="${1:-0.3}"
awk -v t="$threshold" 'BEGIN {
  if (t !~ /^[0-9]+(\.[0-9]+)?$/) exit 1;
  if (t + 0 < 0.1 || t + 0 > 0.9) exit 1;
  exit 0
}' || error_exit "threshold must be 0.1-0.9"

# --- Resolve transcript path -------------------------------------------
if [ -n "${XBB_TRANSCRIPT:-}" ]; then
  transcript="$XBB_TRANSCRIPT"
  [ -f "$transcript" ] || error_exit "transcript not found: $transcript"
else
  session_id="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$session_id" ] || error_exit "CLAUDE_CODE_SESSION_ID not set"
  slug="$(printf '%s' "$PWD" | sed 's/[^A-Za-z0-9]/-/g')"
  primary="$HOME/.claude/projects/$slug/$session_id.jsonl"
  if [ -f "$primary" ]; then
    transcript="$primary"
  else
    fallback_pattern="$HOME/.claude/projects/*/$session_id.jsonl"
    shopt -s nullglob
    matches=($fallback_pattern)
    shopt -u nullglob
    if [ "${#matches[@]}" -eq 1 ]; then
      transcript="${matches[0]}"
    elif [ "${#matches[@]}" -eq 0 ]; then
      error_exit "transcript not found: $primary (also tried $fallback_pattern)"
    else
      error_exit "ambiguous transcript: ${#matches[@]} matches for $fallback_pattern"
    fi
  fi
fi

# --- Find the last usable usage entry ----------------------------------
match_json="$(jq -c -R -s '
  ( [ split("\n")[] | select(length > 0) | (try fromjson catch empty) ]
    | map(select(.type == "assistant" and (.message.usage? != null)))
    | map(
        ((.message.usage.input_tokens // 0)
         + (.message.usage.cache_creation_input_tokens // 0)
         + (.message.usage.cache_read_input_tokens // 0)) as $sum
        | select($sum > 0)
        | {used: $sum, model: .message.model}
      )
  ) as $matches
  | if ($matches | length) == 0 then null else $matches[-1] end
' "$transcript")"

[ "$match_json" != "null" ] || error_exit "no usage entry in transcript"

used="$(jq -r '.used' <<<"$match_json")"
model="$(jq -r '.model' <<<"$match_json")"

# --- Resolve the context window size ------------------------------------
if [ -n "${XBB_CONTEXT_WINDOW:-}" ]; then
  case "$XBB_CONTEXT_WINDOW" in
    ''|*[!0-9]*) error_exit "XBB_CONTEXT_WINDOW must be a positive integer" ;;
  esac
  [ "$XBB_CONTEXT_WINDOW" -gt 0 ] || error_exit "XBB_CONTEXT_WINDOW must be a positive integer"
  window_size="$XBB_CONTEXT_WINDOW"
else
  case "$model" in
    *'[1m]'*) window_size=1000000 ;;
    *haiku*) window_size=200000 ;;
    *opus-5*|*sonnet-5*|*fable-5*) window_size=1000000 ;;
    *opus-4*|*sonnet-4*) window_size=200000 ;;
    *) error_exit "unknown context window for model $model; set XBB_CONTEXT_WINDOW" ;;
  esac
fi

# --- Compute and emit -----------------------------------------------------
token_left="$(awk -v w="$window_size" -v u="$used" 'BEGIN { tl = w - u; if (tl < 0) tl = 0; printf "%d", tl }')"
left_ratio="$(awk -v tl="$token_left" -v w="$window_size" 'BEGIN { printf "%.3f", tl / w }')"
action="$(awk -v lr="$left_ratio" -v t="$threshold" 'BEGIN { print (lr < t) ? "HANDOFF" : "CONTINUE" }')"

jq -nc \
  --arg action "$action" \
  --argjson used "$used" \
  --argjson windowSize "$window_size" \
  --argjson tokenLeft "$token_left" \
  --argjson leftRatio "$left_ratio" \
  --argjson threshold "$threshold" \
  --arg model "$model" \
  '{result:"SUCCESS", action:$action, used:$used, windowSize:$windowSize, tokenLeft:$tokenLeft, leftRatio:$leftRatio, threshold:$threshold, model:$model}'
