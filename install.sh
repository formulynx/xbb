#!/usr/bin/env bash
# Installs the xbb skill + subagents into a Claude Code config dir by
# symlinking them from this repo. Re-running is safe (idempotent).
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
claude_dir="${CLAUDE_DIR:-$HOME/.claude}"

skills_dir="$claude_dir/skills"
agents_dir="$claude_dir/agents"
skill_link="$skills_dir/xbb"

mkdir -p "$skills_dir" "$agents_dir"

if [ -e "$skill_link" ] && [ ! -L "$skill_link" ]; then
  echo "Refusing to overwrite existing directory: $skill_link" >&2
  echo "Back it up or remove it, then re-run this installer." >&2
  exit 1
fi

for name in xbb-researcher xbb-coder; do
  agent_link="$agents_dir/$name.md"
  if [ -e "$agent_link" ] && [ ! -L "$agent_link" ]; then
    echo "Refusing to overwrite existing file: $agent_link" >&2
    echo "Back it up or remove it, then re-run this installer." >&2
    exit 1
  fi
done

ln -sfn "$repo_dir/skills/xbb" "$skill_link"
ln -sf "$repo_dir/agents/xbb-researcher.md" "$agents_dir/xbb-researcher.md"
ln -sf "$repo_dir/agents/xbb-coder.md" "$agents_dir/xbb-coder.md"

echo "installed — restart your Claude Code session"
