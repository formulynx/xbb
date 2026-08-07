# Codex launch handling, by detected environment

This doc is consulted at the **Spawn** step of the Codex reviewer path
(SKILL.md), right after `scripts/detect-agent-workspace.sh` has printed one
identifier for the current shell. Look up that identifier below for any
per-environment handling the upcoming `spawn.sh` call needs.

Every detected environment launches normally with the sandbox on —
agmsg's own `spawn.sh` already picks the right launcher (tmux pane, Herdr
pane, or `open -a <terminal>`) and that launcher works from inside the Bash
sandbox as-is. `cmux-tmux` needs a one-time
`sandbox.filesystem.allowWrite` settings addition (below); every other
environment launches normally with no setup at all.

Non-cmux detection is currently deactivated: `detect-agent-workspace.sh`
prints only `cmux-tmux`, `cmux-native`, or `other`. The per-environment
sections below for other tools are commented out (kept for possible future
reinstatement).

## `other`

Not cmux. No special handling — `spawn.sh` launches normally via its
existing tmux/Herdr/terminal-open logic.

## `cmux-tmux`

Launches normally with the sandbox on, given a one-time settings addition.

Inside a tmux-backed cmux pane (e.g. `cmux claude-teams`), both `$TMUX` and
`$CMUX_CLAUDE_TEAMS_CMUX_BIN` are set. Because `$TMUX` is set, agmsg's
`spawn.sh` takes its tmux-pane path, which execs `cmux __tmux-compat
new-window`/`split-window`. cmux's own tmux-compat layer
(`saveTmuxCompatStore()` in `CLI/cmux.swift`) updates
`~/.cmuxterm/tmux-compat-store.json` via an atomic write, staged first as a
temp file in the per-user temp directory (`getconf DARWIN_USER_TEMP_DIR`)
and then renamed into place — so `~/.claude/settings.json` needs
`sandbox.filesystem.allowWrite` entries for both paths. See README's
"Codex reviewer under the Bash sandbox" section for the full setup
(JSON snippet included).

## `cmux-native`

cmux with `$CMUX_SOCKET_PATH` set but `$TMUX` not set (native pane creation,
not tmux-backed). This goes through a different cmux code path
(`cmux new-split`/`cmux send`) with no reference to
`tmux-compat-store.json` in its source, so it likely does **not** need the
`cmux-tmux` allowlist addition above. This has not been empirically confirmed end-to-end
live (a separate, unrelated PATH-resolution issue blocked that specific test)
— the separation is solid at the source level only. No exception is applied
here currently; if a similar spawn failure is ever observed under
`cmux-native`, re-test and reconsider.

<!-- Deactivated sections below: non-cmux environments are no longer
detected individually (the script prints `other` for all of them). Kept
commented out for possible future reinstatement.

## `tmux`, `herdr`, `conductor`, `superset`, `kitty`, `alacritty`, `wezterm`, `ghostty`, `warp`, `zed`, `iterm2`, `apple-terminal`

No special handling needed. agmsg's `spawn.sh` launches normally via its
existing tmux/Herdr/terminal-open logic in each of these.

## `vscode-family`

No blocking issue. `TERM_PROGRAM=vscode` is shared by VS Code and every fork
(Cursor, Windsurf, Antigravity, ...) — genuinely ambiguous, but that
ambiguity doesn't matter for launch behavior since none of them get special
handling anyway.

Known cosmetic quirk, not a bug to fix here: agmsg's `spawn.sh` only
special-cases `TERM_PROGRAM=iTerm.app` for "reopen the codex pane in the
terminal app the user is already in." Every other `$TERM_PROGRAM` value,
including `vscode`, falls through to the generic macOS default (`open -a
Terminal`, i.e. Apple's Terminal.app) — so under `vscode-family`, codex opens
in a plain Terminal.app window instead of the IDE's own integrated terminal.
Documented here so it isn't mistaken for a new bug later.

## `unknown`

No detection matched. No action beyond what `spawn.sh` already does on its
own — which may itself die with a "headless environment" error on Linux with
no `$DISPLAY`/`$WAYLAND_DISPLAY`, telling the user to set `$AGMSG_TERMINAL`,
or open a generic terminal on macOS. This is a fallback, not a bug.

## Devin (no env-var detection — never printed by the detection script)

No official self-identifying env var was found for Devin after real research
effort. Devin has (at least) three modes: a local "Devin CLI" that runs
inside whatever terminal the user already has open (ordinary terminal-app
detection above applies to whatever's underneath it), a cloud sandbox VM
(headless, no interactive terminal pane at all to attach anything to), and
"Devin Desktop" (local/cloud split not fully documented). Because no reliable
signal exists, Devin cannot get its own branch in
`detect-agent-workspace.sh` — this is a manual judgment call instead:

- If you know you're running under Devin's **cloud-sandbox** mode
  specifically (headless VM, no interactive terminal): skip the
  terminal-spawn step entirely and run the codex process as a plain
  background process instead, relying purely on agmsg's SQLite-only
  messaging (`send.sh`/`history.sh`) for the ACK/VERDICT protocol. agmsg's
  actual cross-agent messaging is 100% socket/terminal-independent — pure
  local SQLite file I/O — only the spawn/pane step needs a terminal at all.
- If running under Devin's local CLI or Desktop mode: whatever real terminal
  is underneath applies instead, per the branches above.

## OpenCode (intentional exclusion — never printed by the detection script)

OpenCode is a peer CLI coding agent (like Claude Code or Codex itself), not a
terminal emulator, IDE, or workspace/session manager. It has no
self-identifying "I am running inside OpenCode's terminal" env var, and
conceptually doesn't need one: if `/xbb` or its spawned codex reviewer is
ever running "under" OpenCode in some sense, whatever *actual* terminal
environment (iTerm2, tmux, cmux, etc.) is hosting that session is what
determines launch behavior, not OpenCode itself. This is why OpenCode has no
branch in `detect-agent-workspace.sh` — an intentional exclusion, not an
oversight.

## Confidence notes

Most identifiers above rely on official docs or direct source inspection
(high confidence). A few rely on weaker signals — flagged here so a future
reader knows what might need a live re-check:

- **Cursor** is not separately detected — its integrated terminal reports
  `TERM_PROGRAM=vscode`, identical to real VS Code (Cursor is a VS Code
  fork), so it falls under `vscode-family` above. A separate signal,
  `CURSOR_AGENT=1` / `CURSOR_TRACE_ID`, is reported by Cursor's own community
  forum (not official docs) to appear specifically when a shell command is
  run by the Cursor agent/CLI — medium confidence only, one forum thread
  reports it's sometimes not set (flaky/version-dependent). Not used in the
  detection script; treat as an optional secondary hint only if `vscode-family`
  handling is ever refined for Cursor specifically.
- **Kitty**: `KITTY_WINDOW_ID` presence is high confidence. That Kitty does
  *not* also set `TERM_PROGRAM` is medium confidence (confirmed via a 2021
  cross-project comparison; not re-verified against current Kitty versions).
- **Alacritty**: `ALACRITTY_SOCKET` presence is high confidence (confirmed
  directly in Alacritty's own source). Whether Alacritty also sets
  `TERM_PROGRAM` is genuinely unresolved (an old GitHub feature request shows
  as closed but resolution unclear) — not relied upon here.

-->

