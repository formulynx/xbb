# xbb

`/xbb` is a delegated research & coding orchestrator skill.

## Why "xbb"?

The name originates from Xu Bingbing, a character from Liu Cixin's *The Three-Body
Problem*, known for doing the work of ten people.  
`/xbb` fans a request out to many subagents at once, evoking that same effect.

## Install

xbb ships as a Claude Code plugin. Add the marketplace once, then install:

```sh
claude plugin marketplace add formulynx/xbb
claude plugin install xbb@xbb
```

- Uninstall with `claude plugin uninstall xbb@xbb`
- For dev, `claude plugin marketplace add /path/to/clone` and install from
  there, or run `claude --plugin-dir /path/to/clone`

### Requirements

- Claude Code
- `bash` and `jq` on `PATH`
- On native Windows
  - [Git for Windows](https://gitforwindows.org/) (provides
  Git Bash; Claude Code treats it as optional, xbb requires it)
  - `jq` binary (e.g. `winget install jqlang.jq`)
- The `--wang` codex reviewer and its tmux/cmux pane handling are POSIX-only

## Usage

The request can be a research question, a coding task, or both mixed together.

```sh
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

```sh
/xbb config
/xbb config [args]
```

No args for an interactive settings menu. With args, `key=value` pairs are
validated and saved directly (`/xbb config reviewer=opus codex.effort=high`);
an invalid value rejects the whole call and keeps the previous settings.
- Stored in `~/.xbb/config.json`, created on first use and preserved across reinstalls
- `maxConcurrentAgents` for parallelizations control
- `handoffLeftRatio` (default 0.3, range 0.1–0.9): the remaining-context ratio
  below which a subagent hands off (measured from the subagent's own
  transcript by `scripts/context-left.sh`), and a fresh one continues from
  its handoff report. The reading lags one API call, so a very low value
  (e.g. 0.1) leaves little margin against a single large tool result —
  set it deliberately
- Settings include which reviewer judges `--wang` rounds
  - `fable` by default, or `opus`/`sonnet`/`codex`
  - the `model` / `effort` / `timeouts` for the `codex` reviewer
  - `reviewMaxRounds`
- Using `reviewer=codex` requires
  - Codex CLI: `npm install -g @openai/codex`, then `codex login`
  - agmsg: the messaging bridge to it, already set up

### Housekeeping

```sh
/xbb clean
```

Review and optionally delete subagent hand-off files under `$TMPDIR/xbb-run-<id>/`.

## Migrating from the install.sh / install.ps1 era

Versions up to v0.3.4 copied files into `~/.claude/skills/xbb` and
`~/.claude/agents/`. Those copies take precedence over the plugin and will
never update, so remove them first:

```sh
# macOS / Linux / WSL / Git Bash
curl -fsSL https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.3.4/install.sh | bash -s -- --uninstall

# Native Windows (PowerShell)
irm https://cdn.jsdelivr.net/gh/formulynx/xbb@v0.3.4/install.ps1 -OutFile install.ps1
.\install.ps1 -Uninstall
```

`~/.xbb/config.json` is untouched by either path.

## License

MIT. See [LICENSE](LICENSE).
