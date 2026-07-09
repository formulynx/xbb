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

## Why "xbb"?

The name nods to Xu Bingbing, a character in Liu Cixin's sci-fi novel *The
Three-Body Problem*, known for getting through the work of ten people. `xbb`
fans a request out to many subagents in parallel, so it feels like ten
people are on the job at once.

## Install

### Quick install (curl | bash via jsDelivr)

```sh
curl -fsSL https://cdn.jsdelivr.net/gh/formulynx/xbb@main/install.sh | bash
```

This fetches `skills/xbb/SKILL.md`, `agents/xbb-researcher.md`, and
`agents/xbb-coder.md` from jsDelivr's GitHub CDN and copies them into
`~/.claude/`. No local clone is created. Restart your Claude Code session
afterwards.

Before piping a remote script into `bash`, it's good practice to inspect it
first: `curl -fsSL <same-url> -o install.sh && less install.sh && bash
install.sh`. Also consider pinning the ref to a released tag or commit
instead of `@main` (e.g. `@v1.0.0`) for reproducible installs — jsDelivr
caches moving refs like a branch for ~12h, but tags/commits are cached
effectively forever.

### git clone (for development / contributors)

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
error. (This guard only applies to the clone/symlink method; the curl|bash
method copies files and overwrites its own prior copies freely.)

You can install into a different Claude config directory by setting
`CLAUDE_DIR` before running the script, e.g. `CLAUDE_DIR=/path/to/dir
xbb/install.sh`.

## Usage

Inside a Claude Code session, invoke:

```
/xbb [your request]
```

The request can be a research question, a coding task, or both mixed
together — the skill classifies it automatically, fans it out to
`xbb-researcher` / `xbb-coder` subagents, and reports back with verified
findings or diffs. For example:

```
/xbb research the history of the Silk Road and summarize its major trade routes
/xbb build a simple HTML mockup for a personal portfolio landing page
```

## Update

If you installed via curl | bash, just re-run the one-liner — it overwrites
the existing copies:

```sh
curl -fsSL https://cdn.jsdelivr.net/gh/formulynx/xbb@main/install.sh | bash
```

If you installed via git clone, pull the repo instead:

```sh
git -C xbb pull
```

`SKILL.md` changes take effect immediately (next `/xbb` invocation).
Changes to the agent files take effect on your next Claude Code session.

## Uninstall

```sh
xbb/install.sh --uninstall
```

(or, if installed via curl | bash without keeping the script around, fetch
it again first: `curl -fsSL
https://cdn.jsdelivr.net/gh/formulynx/xbb@main/install.sh | bash -s --
--uninstall`). This works for both the symlink and copy install methods.

Alternatively, remove the three paths manually (`~/.claude/skills/xbb` is a
symlink if you installed via git clone, or a real directory if you
installed via curl | bash, hence `-rf`):

```sh
rm -rf ~/.claude/skills/xbb
rm ~/.claude/agents/xbb-researcher.md
rm ~/.claude/agents/xbb-coder.md
```
