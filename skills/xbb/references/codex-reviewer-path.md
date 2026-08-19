# Codex reviewer path

Full procedure for the wang review gate (SKILL.md step 5.5) when `reviewer` is
`codex`, via [agmsg](https://github.com/fujibee/agmsg). Consulted once per
review round, after `$RUN_DIR`/`$RUN_ID` exist (step 3) and the round's input
(plan/report files, request, deviation disclosures, prior verdicts, Reviewer
policy, VERDICT protocol) is assembled per step 5.5's Round input rule.

- **Team scope**, computed fresh each round: agmsg's lock is keyed on `(team, agent name)` with no project/run dimension.
  ```bash
  PROJECT_ABS="$(cd "$(pwd)" && pwd)"
  TEAM="xbb-$(basename "$PROJECT_ABS")-$(printf '%s' "$PROJECT_ABS" | cksum | cut -d' ' -f1)"
  CODEX_AGENT="xbbrv-$RUN_ID-reviewer"
  ```
- **Preflight**, every round: `bash "<skill-dir>/scripts/reviewer-spawn-preflight.sh"`. Non-zero → print stderr, abort per Timeout below. Ensure `~/.agents/skills/agmsg` exists (bootstrap from plugin-cache install.sh if needed). Register: `bash ~/.agents/skills/agmsg/scripts/whoami.sh "$(pwd)" claude-code`; join if `$TEAM` isn't listed: `bash ~/.agents/skills/agmsg/scripts/join.sh "$TEAM" team-lead claude-code "$(pwd)"`.
- **Spawn options**, regenerated every round to `$RUN_DIR/spawn_options.yaml`. `--cd` targets one reused scratch dir outside the project, `~/.xbb/codex-cwd` (lazy-created):
  ```bash
  mkdir -p "$HOME/.xbb/codex-cwd"
  cat > "$RUN_DIR/spawn_options.yaml" <<EOF
  codex:
    --sandbox: workspace-write
    --cd: $HOME/.xbb/codex-cwd
    --add-dir: $HOME/.agents/skills/agmsg/db
    --add-dir: $HOME/.agents/skills/agmsg/teams
    --add-dir: $HOME/.agents/skills/agmsg/run
    -a: never
    -c: model_reasoning_effort=<config.codex.effort>
  EOF
  ```
  Unquoted heredoc — `$HOME`/`$RUN_DIR` must expand at write time, or codex dies at launch indistinguishably from an ACK timeout.
- **cmux detection**: only when `$CMUX_SOCKET_PATH` is set *and* `$TMUX` is not, pass `--terminal "bash '<skill-dir>/scripts/cmux-spawn-split.sh' {cmd} '$RUN_DIR/reviewer-surface'"`. When `$TMUX` is set, never pass `--terminal`. Verify `cmux new-split`'s output format (`OK surface:N`) and `cmux send`'s newline handling the first time this actually runs against a live cmux.
- **Spawn**, per round, never `--fresh` — `spawn.sh` resumes the recorded session on its own, so `--fresh` would discard round-to-round memory. First run `bash "<skill-dir>/scripts/detect-agent-workspace.sh"`; check `references/codex-launch.md` for per-environment handling.
  ```bash
  AGMSG_SPAWN_OPTIONS_FILE="$RUN_DIR/spawn_options.yaml" bash ~/.agents/skills/agmsg/scripts/spawn.sh codex "$CODEX_AGENT" --team "$TEAM" --model <config.codex.model> [--terminal ...] --boot-prompt "<text>"
  ```
  Boot prompt must instruct codex to: (1) ACK — `bash ~/.agents/skills/agmsg/scripts/send.sh "$TEAM" "$CODEX_AGENT" team-lead "ACK round N"`; (2) record the session every round — `bash ~/.agents/skills/agmsg/scripts/drivers/types/codex/codex-record-session.sh "$TEAM" "$CODEX_AGENT" "$HOME/.xbb/codex-cwd"`; (3) `cd` into the actual project path, review under the Reviewer policy inlined plus round input; (4) send exactly one `send.sh "$TEAM" "$CODEX_AGENT" team-lead "..."` message, first line the VERDICT line, full reporting structure inline.
- **Wait**: poll ACK (`pingTimeoutSec`), then verdict (`replyTimeoutSec`) via `bash ~/.agents/skills/agmsg/scripts/history.sh "$TEAM"`, reading only lines from `$CODEX_AGENT`; count `VERDICT:` lines to tell rounds apart. (`pingTimeoutSec`/`replyTimeoutSec`/`config.codex.model`/`config.codex.effort` are `~/.xbb/config.json` keys — see SKILL.md's Config section.)
- **Timeout at either deadline aborts the review**, no fallback — never substitute an alternate launch (e.g. a one-shot `codex exec`), since that would bypass the ACK/VERDICT messaging protocol above. If `$TMUX` is set, first grab the reviewer's pane (`tmux list-panes -a -F '#{pane_id} #{pane_start_command}'`, the `agmsg-spawn/boot-*` one) and its tail (`tmux capture-pane -p -t <pane_id> | tail -30`) for a launch-time cause. Then run Round cleanup, report the cause (or that it's indeterminate, with next steps: `codex login status`, `/xbb config reviewer=fable`, retry later), and still deliver the completed work with review marked incomplete.
- **Round cleanup** (timeout-abort, before every re-spawn, and at run end via SKILL.md step 6): always all three args, never a blanket `pkill`. Does not erase codex's own resumable session/memory — safe and cheap to run before every re-spawn.
  ```bash
  bash "<skill-dir>/scripts/codex-reviewer-cleanup.sh" "$TEAM" "$CODEX_AGENT" "$RUN_DIR"
  ```
