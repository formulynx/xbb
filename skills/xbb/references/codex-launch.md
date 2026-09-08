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

`detect-agent-workspace.sh` prints one of `cmux-tmux`, `cmux-native`, or `other`.

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

Whenever `$CMUX_CLAUDE_TEAMS_CMUX_BIN` is set, never hand-assemble a raw
`tmux split-window`/`new-window` or `cmux new-split` command in place of the
Launch step's own script — a hand-assembled command still works (the shim
translates it) but skips the surface-file recording `codex-reviewer.sh cleanup`
needs, and its flag shapes drift run to run. Always launch through
`scripts/codex-reviewer.sh launch`, which uses tmux for this `$TMUX`-set case
(both bare tmux and this tmux-backed cmux session) and cmux for the
`cmux-native` case below.

## `cmux-native`

+cmux with `$CMUX_SOCKET_PATH` set but `$TMUX` not set (native pane creation).
+This path uses `cmux new-split`/`cmux send`, which do not touch
+`tmux-compat-store.json`, so the `cmux-tmux` allowlist addition is not
+needed. Launches normally with no setup. Verified at the source level only,
+not yet live end-to-end.