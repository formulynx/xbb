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

Pick the installer for your shell:

- **macOS / Linux / WSL / Git Bash** (any POSIX shell) → `install.sh` (below).
- **Native Windows** (PowerShell or cmd, no POSIX shell) → `install.ps1`
  ([PowerShell install](#powershell-install-native-windows)).

On Git Bash, prefer `install.sh`'s curl | bash method — it *copies* the files,
whereas its git-clone method relies on symlinks (`ln -s`), which Git Bash does
not create reliably. WSL has no such caveat. `install.ps1` always copies.

### Quick install (curl | bash via jsDelivr)

```sh
curl -fsSL https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.1.1/install.sh | bash
```

This fetches `skills/xbb/SKILL.md`, `agents/xbb-researcher.md`, and
`agents/xbb-coder.md` from jsDelivr's GitHub CDN and copies them into
`~/.claude/`. No local clone is created. Restart your Claude Code session
afterwards.

Before piping a remote script into `bash`, it's good practice to inspect it
first: `curl -fsSL <same-url> -o install.sh && less install.sh && bash
install.sh`. The one-liner above is pinned to a released tag (`@v0.1.1`) so
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

### PowerShell install (native Windows)

For native Windows without a POSIX shell, use the PowerShell installer. Quick
install:

```powershell
irm https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.1.1/install.ps1 | iex
```

Or from a git clone:

```powershell
.\xbb\install.ps1
```

`install.ps1` mirrors `install.sh` — same three payload files into
`~\.claude\` — but always **copies** (no symlinks; those need admin/Developer
Mode on Windows). It's idempotent and honours the same `CLAUDE_DIR`, `XBB_REF`,
and `XBB_BASE_URL` environment variables. To inspect before running, download
first: `irm <same-url> -OutFile install.ps1; notepad install.ps1; .\install.ps1`.

If PowerShell blocks the script with an execution-policy error, run it for the
current process only: `powershell -ExecutionPolicy Bypass -File .\install.ps1`.

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

## Update

If you installed via curl | bash, re-running the same pinned one-liner just
reinstalls the same `v0.1.1` copies — it does not fetch newer code. To
upgrade, run the one-liner for the newer release tag (swap `@v0.1.1` for the
new tag), or use `@main` for the latest in-development version:

```sh
curl -fsSL https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.1.1/install.sh | bash
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
https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.1.1/install.sh | bash -s --
--uninstall`). This works for both the symlink and copy install methods.

On native Windows, download `install.ps1` and run it with `-Uninstall`:

```powershell
irm https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.1.1/install.ps1 -OutFile install.ps1
.\install.ps1 -Uninstall
```

Alternatively, remove the three paths manually (`~/.claude/skills/xbb` is a
symlink if you installed via git clone, or a real directory if you
installed via curl | bash, hence `-rf`):

```sh
rm -rf ~/.claude/skills/xbb
rm ~/.claude/agents/xbb-researcher.md
rm ~/.claude/agents/xbb-coder.md
```
