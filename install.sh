#!/usr/bin/env bash
# Installs the xbb skill + subagents into a Claude Code config dir.
#
# Two modes:
#   - Clone mode: run from a local git clone (./install.sh) -> symlinks the
#     payload files from the repo into $CLAUDE_DIR.
#   - Remote mode: piped via curl|bash with no local clone -> fetches the
#     payload files from jsDelivr and copies them into $CLAUDE_DIR.
#
# Re-running is safe (idempotent). Supports --uninstall.
set -euo pipefail

OWNER=formulynx
REPO=xbb
REF="${XBB_REF:-v0.1.10}"
BASE_URL="${XBB_BASE_URL:-https://cdn.jsdelivr.net/gh/$OWNER/$REPO@$REF}"

say() { echo "==> $*"; }

main() {
  local claude_dir="${CLAUDE_DIR:-$HOME/.claude}"
  local skills_dir="$claude_dir/skills"
  local agents_dir="$claude_dir/agents"
  local skill_link="$skills_dir/xbb"
  local ref_file="$skill_link/.xbb-ref"

  # Payload: src-relative-path -> dest-path
  local srcs=(
    "skills/xbb/SKILL.md"
    "skills/xbb/scripts/codex-reviewer-cleanup.sh"
    "skills/xbb/scripts/cmux-spawn-split.sh"
    "skills/xbb/scripts/team-guard.sh"
    "agents/xbb-researcher.md"
    "agents/xbb-coder.md"
    "agents/xbb-reviewer.md"
  )
  local dests=(
    "$skill_link/SKILL.md"
    "$skill_link/scripts/codex-reviewer-cleanup.sh"
    "$skill_link/scripts/cmux-spawn-split.sh"
    "$skill_link/scripts/team-guard.sh"
    "$agents_dir/xbb-researcher.md"
    "$agents_dir/xbb-coder.md"
    "$agents_dir/xbb-reviewer.md"
  )

  if [ "${1:-}" = "--uninstall" ]; then
    say "Removing $skill_link"
    rm -f "$agents_dir/xbb-researcher.md" "$agents_dir/xbb-coder.md" "$agents_dir/xbb-reviewer.md"
    if [ -L "$skill_link" ]; then
      rm -f "$skill_link"
    else
      rm -rf "$skill_link/scripts" 2>/dev/null || true
      rm -f "$skill_link/SKILL.md" "$ref_file" 2>/dev/null || true
      rmdir "$skill_link" 2>/dev/null || true
    fi
    echo "xbb uninstalled."
    return
  fi

  # Clone mode only when invoked as a real script file. When piped
  # (curl|bash / `bash < install.sh`), BASH_SOURCE is unset — force remote mode
  # rather than letting dirname "" collapse to the current directory.
  local repo_dir=""
  if [ -f "${BASH_SOURCE[0]:-}" ]; then
    repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi

  say "Target: $skill_link"
  mkdir -p "$skills_dir" "$agents_dir"

  if [ -n "$repo_dir" ] && [ -f "$repo_dir/skills/xbb/SKILL.md" ]; then
    # Clone mode: symlink from the local repo. Preserve existing guards.
    say "Installing xbb $REF"
    say "Mode: local clone ($repo_dir) — symlinking"
    if [ -e "$skill_link" ] && [ ! -L "$skill_link" ]; then
      # A prior remote-mode install leaves a real dir containing our own
      # SKILL.md (plus scripts/, once shipped). Recognize and replace it;
      # refuse anything else.
      if [ -f "$skill_link/SKILL.md" ] \
        && grep -q '^name: xbb$' "$skill_link/SKILL.md" 2>/dev/null; then
        rm -rf "$skill_link"
      else
        echo "Refusing to overwrite existing directory: $skill_link" >&2
        echo "Back it up or remove it, then re-run this installer." >&2
        exit 1
      fi
    fi

    for name in xbb-researcher xbb-coder xbb-reviewer; do
      local agent_link="$agents_dir/$name.md"
      if [ -e "$agent_link" ] && [ ! -L "$agent_link" ]; then
        # Same recognize-and-replace for a prior remote-mode agent file.
        if grep -q "^name: $name$" "$agent_link" 2>/dev/null; then
          rm -f "$agent_link"
        else
          echo "Refusing to overwrite existing file: $agent_link" >&2
          echo "Back it up or remove it, then re-run this installer." >&2
          exit 1
        fi
      fi
    done

    ln -sfn "$repo_dir/skills/xbb" "$skill_link"
    ln -sf "$repo_dir/agents/xbb-researcher.md" "$agents_dir/xbb-researcher.md"
    ln -sf "$repo_dir/agents/xbb-coder.md" "$agents_dir/xbb-coder.md"
    ln -sf "$repo_dir/agents/xbb-reviewer.md" "$agents_dir/xbb-reviewer.md"
  else
    # Remote mode: fetch the payload files and copy them into place.
    # A .xbb-ref marker records the installed ref; skip if already current.
    # (Not written in clone mode — a symlink tracks the repo, no fixed version.)
    local current=""
    if [ ! -L "$skill_link" ] && [ -f "$ref_file" ]; then
      current="$(cat "$ref_file")"
    fi
    if [ "$current" = "$REF" ]; then
      say "xbb $REF is already installed — nothing to do."
      return
    fi
    if [ -n "$current" ]; then
      say "Updating xbb from $current to $REF"
    else
      say "Installing xbb $REF"
    fi
    say "Mode: remote — downloading from $BASE_URL"
    if ! command -v curl >/dev/null 2>&1; then
      echo "curl is required to install xbb but was not found." >&2
      exit 1
    fi

    # A prior clone install may have left skill_link as a symlink; remove it
    # so we can create a real directory.
    if [ -L "$skill_link" ]; then
      rm -f "$skill_link"
    fi
    mkdir -p "$skill_link"

    local i
    for i in "${!srcs[@]}"; do
      local src="${srcs[$i]}"
      local dest="${dests[$i]}"
      # Switching from a prior symlinked install: drop the symlink first.
      if [ -L "$dest" ]; then
        rm -f "$dest"
      fi
      mkdir -p "$(dirname "$dest")"
      say "Fetching $src"
      fetch "$BASE_URL/$src" "$dest"
    done
    echo "$REF" > "$ref_file"
  fi

  echo "xbb $REF installed successfully. Restart Claude Code (or start a new session) to pick it up."
}

fetch() {
  local url="$1"
  local dest="$2"
  case "$url" in
    https://*)
      curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$dest"
      ;;
    *)
      curl -fsSL "$url" -o "$dest"
      ;;
  esac
}

main "$@"
