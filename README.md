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
`xbb-coder` / `xbb-reviewer`.

## Why "xbb"?

The name nods to Xu Bingbing, a character in Liu Cixin's sci-fi novel *The
Three-Body Problem*, known for getting through the work of ten people. `xbb`
fans a request out to many subagents in parallel, so it feels like ten
people are on the job at once.

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

### External review: `/xbb --wang <request>`

```
/xbb --wang [your request]
```

Runs the same orchestrated flow as a plain `/xbb` request, then adds an
external review gate: once the teammates finish, a reviewer judges the
resulting working tree against the **plan** — a plan file named in your
request (e.g. "follow the plan in PLAN.md §3"), or, when none exists, a plan
xbb writes down before delegating — plus your original request, and returns
either `VERDICT: PASS` or `VERDICT: REVISE` with findings. It never sees the
implementers' self-reports: this is blind review by design, so an inflated
or hallucinated "done" claim can't sway the verdict, and the reviewer
re-runs verification itself rather than trusting anyone else's. On
`REVISE`, the orchestrator re-delegates fixes to teammates and loops back
through review, up to `reviewMaxRounds` (default `8`, see `/xbb config`
below). The loop keeps going automatically only while rounds make progress;
if the same finding survives two consecutive rounds unresolved, xbb pauses
and asks whether to continue, stop, or adjust course with guidance for the
next round. Findings that turn out to be plan problems rather than
implementation problems are escalated to you directly instead of burning
rounds on re-fanout that can't fix them. The final answer reports the review
outcome alongside the normal results.

### Configuration: `/xbb config`

```
/xbb config
```

Opens an interactive settings menu (arrow-key selection). You can also set
values directly on the command line:

```
/xbb config reviewer=codex codex.model=gpt-5.6-terra codex.effort=medium
```

Settings live in `~/.xbb/config.json`, created on first use with the
defaults below, and survive reinstalling or updating xbb:

```json
{
  "reviewer": "fable",
  "codex": { "model": "gpt-5.6-terra", "effort": "medium", "pingTimeoutSec": 180, "replyTimeoutSec": 300 },
  "maxConcurrentAgents": 4,
  "reviewMaxRounds": 8
}
```

- `reviewer` — who judges `/xbb --wang` rounds. `fable` (default), `opus`,
  or `sonnet` spawn a Claude reviewer subagent (`agents/xbb-reviewer.md`),
  with the model chosen at spawn time. `codex` instead spawns an external
  OpenAI Codex CLI session reached over agmsg — see prerequisites below.
- `codex.model` / `codex.effort` — model and reasoning effort passed to the
  Codex CLI session when `reviewer=codex`.
- `codex.pingTimeoutSec` / `codex.replyTimeoutSec` — how long to wait for
  the Codex session to acknowledge a round, or return a verdict, before
  treating it as unresponsive.
- `maxConcurrentAgents` — cap on subagents running in parallel.
- `reviewMaxRounds` — cap on `/xbb --wang` review/fix loops before giving up
  and reporting the review as incomplete.

#### Codex reviewer prerequisites

Selecting `reviewer=codex` in `/xbb config` checks, once, that both of these
are in place, refusing the config change with setup instructions if either
is missing:

- The Codex CLI: `npm install -g @openai/codex`, then `codex login`. (This
  is the **scoped** `@openai/codex` package — the unscoped `codex` package
  on npm is an unrelated project.)
- agmsg, the messaging bridge to the Codex session: `/plugin marketplace add
  fujibee/agmsg` + `/plugin install agmsg@fujibee-agmsg`, or agmsg's own
  `install.sh`.

At review time, the Codex reviewer is spawned per round with `--sandbox
workspace-write` (scoped to a fixed scratch directory reused across every
run, never the reviewed project — `read-only` would also block its own
`send.sh` call back to agmsg) and the configured model/effort; its replies
travel over agmsg messages. If it stops answering partway through (rate
limit, API error — the two are indistinguishable from outside), the run
aborts the review loop, keeps all work completed so far, and reports the
review as incomplete with next steps, rather than retrying indefinitely.

Because that scratch directory is fixed and reused, the very first time
`reviewer=codex` actually spawns a review, the Codex CLI itself shows a
one-time "Do you trust the contents of this directory?" prompt in its pane
— answer it once; every later round and run reuses the same, by-then-
trusted directory and never shows it again.

**Terminal behavior for the codex reviewer**: inside cmux, it opens as a
split surface in the current workspace (auto-detected via
`CMUX_SOCKET_PATH`, via a helper script that ships with the skill install,
`scripts/cmux-spawn-split.sh`); inside tmux, a new pane; otherwise a new OS
terminal window per review round. Outside cmux/tmux, these windows are not
auto-closed — a known limitation.

#### Files created at runtime

xbb writes a couple of things under `~/.xbb/` as needed, not part of the
installer payload or touched by `--uninstall`:

- `config.json` — settings, see [Configuration](#configuration-xbb-config).
- `codex-cwd/` — the Codex reviewer's fixed scratch working directory (see
  above); empty, reused across every run, never the reviewed project.

The codex reviewer's per-round spawn options and surface marker live under
that run's own `$TMPDIR/xbb-run-<id>/` directory instead (see
[Housekeeping](#housekeeping-xbb-clean)) — scoped per run so concurrent
`/xbb --wang` runs never share, and therefore never race on, the same file.

To remove `~/.xbb` (settings included), run `rm -rf ~/.xbb`.

### Housekeeping: `/xbb clean`

Each run writes its subagent hand-off files to a per-run temp directory
(`$TMPDIR/xbb-run-<id>/`, or the equivalent temp root on Linux/Windows) and
never deletes them — they're a small audit trail of what past runs
investigated, and normal runs do no cleanup (zero overhead). Your OS's temp
reaper clears them eventually, so you can ignore this entirely if you don't
mind the disk use.

To trim them yourself, run:

```
/xbb clean
```

It lists the leftover run directories with their sizes and total, then asks
before deleting anything — pick **Delete all** to reclaim the space or
**Keep** to leave them to the OS. It only ever touches `xbb-run-*`
directories. Works on macOS/Linux (and Windows Git Bash) as well as native
Windows PowerShell.

## Install

Pick the installer for your shell:

- **macOS / Linux / WSL / Git Bash** (any POSIX shell) → `install.sh` (below).
- **Native Windows** (PowerShell or cmd, no POSIX shell) → `install.ps1`
  ([PowerShell install](#powershell-install-native-windows)).

On Git Bash, prefer `install.sh`'s curl | bash method — it *copies* the files,
whereas its git-clone method relies on symlinks (`ln -s`), which Git Bash does
not create reliably. WSL has no such caveat. `install.ps1` always copies.

### Quick install (curl | bash via jsDelivr)

```sh
curl -fsSL https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.1.9/install.sh | bash
```

This fetches `skills/xbb/SKILL.md`, its `scripts/` helpers, and the three
`agents/xbb-*.md` files from jsDelivr's GitHub CDN and copies them into
`~/.claude/`. No local clone is created. Restart your Claude Code session
afterwards.

Before piping a remote script into `bash`, it's good practice to inspect it
first: `curl -fsSL <same-url> -o install.sh && less install.sh && bash
install.sh`. The one-liner above is pinned to a released tag (`@v0.1.9`) so
installs stay reproducible — jsDelivr caches tags/commits effectively
forever. Each release updates this README to point at the new tag; if you
want the latest in-development code instead, substitute `@main` (a moving
ref, cached by jsDelivr for ~12h).

### git clone (for development / contributors)

```sh
git clone <repo-url> xbb
xbb/install.sh
```

This symlinks `skills/xbb` and `agents/xbb-researcher.md` /
`agents/xbb-coder.md` / `agents/xbb-reviewer.md` from the clone into
`~/.claude/`. Restart your Claude Code session afterwards.

If `~/.claude/skills/xbb` or `~/.claude/agents/xbb-researcher.md` /
`xbb-coder.md` / `xbb-reviewer.md` already exist as real files (not
symlinks) — e.g. from a previous manual install — back them up or remove
them before running
`install.sh`; it will refuse to overwrite real files and exit with an
error. (This guard only applies to the clone/symlink method; the curl|bash
method copies files and overwrites its own prior copies freely.)

You can install into a different Claude config directory by setting
`CLAUDE_DIR` before running the script, e.g. `CLAUDE_DIR=/path/to/dir
xbb/install.sh`.

### PowerShell install (native Windows)

For native Windows without a POSIX shell, use the PowerShell installer. Quick
install:

```powershell
irm https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.1.9/install.ps1 | iex
```

Or from a git clone:

```powershell
.\xbb\install.ps1
```

`install.ps1` mirrors `install.sh`'s payload into `~\.claude\` — `SKILL.md`,
the three agent files, and `team-guard.ps1` in place of `install.sh`'s
POSIX-only scripts (the codex reviewer and cmux support they back don't
apply on native Windows) — but always **copies** (no symlinks; those need
admin/Developer Mode on Windows). It's idempotent and honours the same `CLAUDE_DIR`, `XBB_REF`,
and `XBB_BASE_URL` environment variables. To inspect before running, download
first: `irm <same-url> -OutFile install.ps1; notepad install.ps1; .\install.ps1`.

If PowerShell blocks the script with an execution-policy error, run it for the
current process only: `powershell -ExecutionPolicy Bypass -File .\install.ps1`.

## Update

If you installed via curl | bash, re-running the same pinned one-liner just
reinstalls the same `v0.1.9` copies — it does not fetch newer code. To
upgrade, run the one-liner for the newer release tag (swap `@v0.1.9` for the
new tag), or use `@main` for the latest in-development version:

```sh
curl -fsSL https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.1.9/install.sh | bash
```

If you installed via git clone, pull the repo instead:

```sh
git -C xbb pull
```

`SKILL.md` changes take effect immediately (next `/xbb` invocation). New or
changed agent files (e.g. `xbb-reviewer.md`) are loaded at session start, so
start a new Claude Code session after installing or updating to pick them
up.

## Uninstall

```sh
xbb/install.sh --uninstall
```

(or, if installed via curl | bash without keeping the script around, fetch
it again first: `curl -fsSL
https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.1.9/install.sh | bash -s --
--uninstall`). This works for both the symlink and copy install methods.

On native Windows, download `install.ps1` and run it with `-Uninstall`:

```powershell
irm https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.1.9/install.ps1 -OutFile install.ps1
.\install.ps1 -Uninstall
```

Alternatively, remove the four paths manually (`~/.claude/skills/xbb` is a
symlink if you installed via git clone, or a real directory if you
installed via curl | bash, hence `-rf`):

```sh
rm -rf ~/.claude/skills/xbb
rm ~/.claude/agents/xbb-researcher.md
rm ~/.claude/agents/xbb-coder.md
rm ~/.claude/agents/xbb-reviewer.md
```

None of the above touches `~/.xbb/` (config and the codex scratch cwd — see
[Files created at runtime](#files-created-at-runtime)); the uninstaller
intentionally leaves it so your settings survive reinstalls. To remove
settings too: `rm -rf ~/.xbb`.
