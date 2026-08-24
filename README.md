# xbb

`/xbb` is a delegated research & coding orchestrator skill.

## Why "xbb"?

The name originates from Xu Bingbing, a character from Liu Cixin's *The Three-Body
Problem*, known for doing the work of ten people.  
`/xbb` fans a request out to many subagents at once, evoking that same effect.

## Install

```
# macOS / Linux / WSL / Git Bash — quick install (curl | bash)
curl -fsSL https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.3.0-beta8/install.sh | bash

# Native Windows (PowerShell) — quick install
irm https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.3.0-beta8/install.ps1 | iex
```

- Use `@main` for latest dev code
- Update by re-running the one-liner with a newer tag (or @main)
- Uninstall with `--uninstall` ( `-Uninstall` on the .ps1)
- For dev, git clone and run `xbb/install.sh` (symlinks instead of copies)

## Usage

The request can be a research question, a coding task, or both mixed together.

```
/xbb <your request>              # plain run
/xbb --wang <your request>       # adds an external review gate
```

- `xbb` classifies it automatically, fans it out to `xbb-researcher` /
  `xbb-coder` subagents, and reports back with verified findings or diffs.
- `--wang` adds a blind external review: a reviewer re-verifies the work
  against the plan and returns `VERDICT: PASS` or `VERDICT: REVISE`, looping
  (up to `reviewMaxRounds`, see [Configuration](#configuration)) until it
  passes or stalls, then reports the review outcome alongside the results.

### Configuration

```
/xbb config
/xbb config [args]
```

No args for an interactive settings menu
- Stored in `~/.xbb/config.json`, created on first use and preserved across reinstalls
- `maxConcurrentAgents` for parallelizations control
- Settings include which reviewer judges `--wang` rounds
  - `fable` by default, or `opus`/`sonnet`/`codex`
  - the `model` / `effort` / `timeouts` for the `codex` reviewer
  - `reviewMaxRounds`
- Using `reviewer=codex` requires
  - Codex CLI: `npm install -g @openai/codex`, then `codex login`
  - agmsg: the messaging bridge to it, already set up

### Housekeeping

```
/xbb clean
```

Review and optionally delete subagent hand-off files under `$TMPDIR/xbb-run-<id>/`.

## License

MIT. See [LICENSE](LICENSE).
