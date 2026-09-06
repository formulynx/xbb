#!/usr/bin/env bash
# Fixture-driven assertions for context-left.sh. Plain bash, no framework;
# `set -e` plus an explicit check after each assertion means the first
# failure aborts the run with a non-zero exit.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/../context-left.sh"
tmp_root="${TMPDIR:-${TEMP:-${TMP:-/tmp}}}"

fixture="$(mktemp "$tmp_root/context-left-fixture-XXXXXX")"
trap 'rm -f "$fixture"; rm -rf "${fake_home_single:-}" "${fake_cwd_single:-}" "${fake_home_multi:-}" "${fake_cwd_multi:-}"' EXIT

# Line 1: non-assistant, ignored. Line 2: assistant with all-zero usage,
# ignored (used must be > 0). Line 3: assistant with usage summing to
# 700000 across all three token fields -- exercises the sum, not just one
# field.
cat > "$fixture" <<'EOF'
{"type":"user","message":{"role":"user","content":"hi"}}
{"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
{"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":650000,"cache_creation_input_tokens":30000,"cache_read_input_tokens":20000}}}
EOF

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  [ "$expected" = "$actual" ] || fail "$desc (expected [$expected], got [$actual])"
  echo "ok: $desc"
}

# --- default threshold (0.3) -> CONTINUE, tokenLeft==300000 ---------------
out="$(XBB_TRANSCRIPT="$fixture" bash "$script")"
assert_eq "default result"    "SUCCESS"  "$(jq -r '.result' <<<"$out")"
assert_eq "default action"    "CONTINUE" "$(jq -r '.action' <<<"$out")"
assert_eq "default tokenLeft" "300000"   "$(jq -r '.tokenLeft' <<<"$out")"
assert_eq "default used"      "700000"   "$(jq -r '.used' <<<"$out")"

# --- threshold 0.4 -> HANDOFF ----------------------------------------------
out="$(XBB_TRANSCRIPT="$fixture" bash "$script" 0.4)"
assert_eq "0.4 action" "HANDOFF" "$(jq -r '.action' <<<"$out")"

# --- threshold 0.95 -> ERROR, exit 1 ---------------------------------------
set +e
out="$(XBB_TRANSCRIPT="$fixture" bash "$script" 0.95)"
code=$?
set -e
assert_eq "0.95 exit code" "1"     "$code"
assert_eq "0.95 result"    "ERROR" "$(jq -r '.result' <<<"$out")"

# --- missing transcript file -> ERROR, exit 1 ------------------------------
set +e
out="$(XBB_TRANSCRIPT="$tmp_root/context-left-does-not-exist-$$" bash "$script")"
code=$?
set -e
assert_eq "missing file exit code" "1"     "$code"
assert_eq "missing file result"    "ERROR" "$(jq -r '.result' <<<"$out")"

# --- XBB_CONTEXT_WINDOW override -> windowSize==800000 ---------------------
out="$(XBB_TRANSCRIPT="$fixture" XBB_CONTEXT_WINDOW=800000 bash "$script")"
assert_eq "window override windowSize" "800000" "$(jq -r '.windowSize' <<<"$out")"


# --- glob fallback, exactly one match -> SUCCESS ---------------------------
# Primary path is keyed off $PWD's slug, so a cwd outside the fake project
# tree guarantees the primary lookup misses and the glob fallback runs.
fake_home_single="$(mktemp -d "$tmp_root/context-left-home-single-XXXXXX")"
fake_cwd_single="$(mktemp -d "$tmp_root/context-left-cwd-single-XXXXXX")"
session_single="sess-single-$$"
mkdir -p "$fake_home_single/.claude/projects/proj-a"
cp "$fixture" "$fake_home_single/.claude/projects/proj-a/$session_single.jsonl"

out="$(cd "$fake_cwd_single" && HOME="$fake_home_single" CLAUDE_CODE_SESSION_ID="$session_single" bash "$script")"
assert_eq "single fallback result" "SUCCESS" "$(jq -r '.result' <<<"$out")"
assert_eq "single fallback used"   "700000"  "$(jq -r '.used' <<<"$out")"

# --- glob fallback, two or more matches -> ERROR, exit 1 -------------------
fake_home_multi="$(mktemp -d "$tmp_root/context-left-home-multi-XXXXXX")"
fake_cwd_multi="$(mktemp -d "$tmp_root/context-left-cwd-multi-XXXXXX")"
session_multi="sess-multi-$$"
mkdir -p "$fake_home_multi/.claude/projects/proj-a" "$fake_home_multi/.claude/projects/proj-b"
cp "$fixture" "$fake_home_multi/.claude/projects/proj-a/$session_multi.jsonl"
cp "$fixture" "$fake_home_multi/.claude/projects/proj-b/$session_multi.jsonl"

set +e
out="$(cd "$fake_cwd_multi" && HOME="$fake_home_multi" CLAUDE_CODE_SESSION_ID="$session_multi" bash "$script")"
code=$?
set -e
assert_eq "ambiguous fallback exit code" "1"     "$code"
assert_eq "ambiguous fallback result"    "ERROR" "$(jq -r '.result' <<<"$out")"

echo "All context-left.sh assertions passed."
