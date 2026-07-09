# xbb

`xbb` is a delegated research & coding orchestrator skill for
[Claude Code](https://claude.com/product/claude-code). The `/xbb` command
keeps the main agent as a pure orchestrator: it decomposes a request,
delegates all investigation to `xbb-researcher` subagents and all
implementation to `xbb-coder` subagents, verifies their output, and returns
a single synthesized answer.

This repo is distributed as a plain skill + agent files, installed via
symlinks — there is no plugin manifest, so the command stays available as
the bare `/xbb` and the subagent types stay unscoped as `xbb-researcher` /
`xbb-coder`.

## Install

```sh
git clone <repo-url> xbb
xbb/install.sh
```

This symlinks `skills/xbb` and `agents/xbb-researcher.md` /
`agents/xbb-coder.md` from the clone into `~/.claude/`. Restart your Claude
Code session afterwards.

If `~/.claude/skills/xbb` or `~/.claude/agents/xbb-researcher.md` /
`xbb-coder.md` already exist as real files (not symlinks) — e.g. from a
previous manual install — back them up or remove them before running
`install.sh`; it will refuse to overwrite real files and exit with an
error.

You can install into a different Claude config directory by setting
`CLAUDE_DIR` before running the script, e.g. `CLAUDE_DIR=/path/to/dir
xbb/install.sh`.

## Update

```sh
git -C xbb pull
```

`SKILL.md` changes take effect immediately (next `/xbb` invocation).
Changes to the agent files take effect on your next Claude Code session.

## Uninstall

Remove the three symlinks:

```sh
rm ~/.claude/skills/xbb
rm ~/.claude/agents/xbb-researcher.md
rm ~/.claude/agents/xbb-coder.md
```
