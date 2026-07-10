#!/usr/bin/env bash
# Installs the xbb skill + subagents into a Claude Code config dir.
#
# Two modes:
#   - Clone mode: run from a local git clone (./install.sh) -> symlinks the
#     payload files from the repo into $CLAUDE_DIR.
#   - Remote mode: piped via curl|bash with no local clone -> fetches the
#     3 payload files from jsDelivr and copies them into $CLAUDE_DIR.
#
# Re-running is safe (idempotent). Supports --uninstall.
set -euo pipefail

OWNER=formulynx
REPO=xbb
REF="${XBB_REF:-v0.1.1}"
BASE_URL="${XBB_BASE_URL:-https://cdn.jsdelivr.net/gh/$OWNER/$REPO@$REF}"

main() {
  local claude_dir="${CLAUDE_DIR:-$HOME/.claude}"
  local skills_dir="$claude_dir/skills"
  local agents_dir="$claude_dir/agents"
  local skill_link="$skills_dir/xbb"

  # Payload: src-relative-path -> dest-path
  local srcs=(
    "skills/xbb/SKILL.md"
    "agents/xbb-researcher.md"
    "agents/xbb-coder.md"
  )
  local dests=(
    "$skill_link/SKILL.md"
    "$agents_dir/xbb-researcher.md"
    "$agents_dir/xbb-coder.md"
  )

  if [ "${1:-}" = "--uninstall" ]; then
    rm -f "$agents_dir/xbb-researcher.md" "$agents_dir/xbb-coder.md"
    if [ -L "$skill_link" ]; then
      rm -f "$skill_link"
    else
      rm -f "$skill_link/SKILL.md" 2>/dev/null || true
      rmdir "$skill_link" 2>/dev/null || true
    fi
    echo "uninstalled"
    return
  fi

  # Clone mode only when invoked as a real script file. When piped
  # (curl|bash / `bash < install.sh`), BASH_SOURCE is unset — force remote mode
  # rather than letting dirname "" collapse to the current directory.
  local repo_dir=""
  if [ -f "${BASH_SOURCE[0]:-}" ]; then
    repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi

  mkdir -p "$skills_dir" "$agents_dir"

  if [ -n "$repo_dir" ] && [ -f "$repo_dir/skills/xbb/SKILL.md" ]; then
    # Clone mode: symlink from the local repo. Preserve existing guards.
    if [ -e "$skill_link" ] && [ ! -L "$skill_link" ]; then
      echo "Refusing to overwrite existing directory: $skill_link" >&2
      echo "Back it up or remove it, then re-run this installer." >&2
      exit 1
    fi

    for name in xbb-researcher xbb-coder; do
      local agent_link="$agents_dir/$name.md"
      if [ -e "$agent_link" ] && [ ! -L "$agent_link" ]; then
        echo "Refusing to overwrite existing file: $agent_link" >&2
        echo "Back it up or remove it, then re-run this installer." >&2
        exit 1
      fi
    done

    ln -sfn "$repo_dir/skills/xbb" "$skill_link"
    ln -sf "$repo_dir/agents/xbb-researcher.md" "$agents_dir/xbb-researcher.md"
    ln -sf "$repo_dir/agents/xbb-coder.md" "$agents_dir/xbb-coder.md"
  else
    # Remote mode: fetch the payload files and copy them into place.
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
      fetch "$BASE_URL/$src" "$dest"
    done
  fi

  echo "installed — restart your Claude Code session"
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
