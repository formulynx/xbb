# Codex reviewer path

Full procedure for the wang review gate (SKILL.md step 7) when `reviewer` is
`codex`, via [agmsg](https://github.com/fujibee/agmsg)'s app-server bridge.
Codex is launched exactly ONCE per run, kept alive across every REVISE round
in the same TUI pane, and torn down exactly once at the true end (PASS,
rounds-exhausted, or timeout-abort). Setup/Launch below run only before round
1; the Round loop covers every round including round 1; Teardown runs only
once, at the end.

## Setup (once per run)

- **Team scope**, computed once: agmsg's lock is keyed on `(team, agent name)` with no project/run dimension.
  ```bash
  PROJECT_ABS="$(cd "$(pwd)" && pwd)"
  TEAM="xbb-$(basename "$PROJECT_ABS")-$(printf '%s' "$PROJECT_ABS" | cksum | cut -d' ' -f1)"
  CODEX_AGENT="xbbrv-$RUN_ID-reviewer"
  ```
- **Bootstrap agmsg**: ensure `~/.agents/skills/agmsg` exists (bootstrap from plugin-cache install.sh if needed) — before preflight, which inspects the install.
- **Preflight**: `bash "${CLAUDE_SKILL_DIR}/scripts/codex-reviewer.sh" preflight`. Non-zero → print stderr, abort per Timeout below. Covers the reviewer toolchain (codex present + logged in + app-server-capable, agmsg bridge-capable, node present), the sandbox spawn path, and a live app-server launch probe — everything checkable before codex's own thread exists. The one thing it cannot cover is the round-2+ bridge arming (role-session record); that is written and verified at runtime by the orchestrator's own record step right after round 1's ACK (Launch's Wait step below).
- **Scratch cwd**: `mkdir -p "$HOME/.xbb/codex-cwd"` (a reused scratch dir outside the project, already trusted in `~/.codex/config.toml` from prior runs — no new trust step needed).
- **Register the orchestrator**: `bash ~/.agents/skills/agmsg/scripts/whoami.sh "$(pwd)" claude-code`; join if `$TEAM` isn't listed: `bash ~/.agents/skills/agmsg/scripts/join.sh "$TEAM" team-lead claude-code "$(pwd)"`.
- **Register the reviewer identity** explicitly before launch (`spawn.sh`, which would otherwise do this, is not used on this path):
  ```bash
  bash ~/.agents/skills/agmsg/scripts/join.sh "$TEAM" "$CODEX_AGENT" codex "$HOME/.xbb/codex-cwd"
  ```

## Launch (once per run, not per round)

- **Write the round-1 instructions file** first, to `$RUN_DIR/codex-round1.md`, so the launch command can point at it (it lives in `$RUN_DIR`, never in the reviewed project; codex reads it from `~/.xbb/codex-cwd` — `--sandbox workspace-write` restricts writes only, so the read works). Content: (a) from **inside its own bash tool call** (load-bearing: only there is `$CODEX_THREAD_ID` exported) — `bash ~/.agents/skills/agmsg/scripts/drivers/types/codex/codex-record-session.sh "$TEAM" "$CODEX_AGENT" "$HOME/.xbb/codex-cwd"` (a backstop only; the orchestrator records the seat itself on ACK, see Wait below); (b) ACK, AFTER the record — `bash ~/.agents/skills/agmsg/scripts/send.sh "$TEAM" "$CODEX_AGENT" team-lead "ACK round 1 thread=${CODEX_THREAD_ID:-unset}"` (the thread field is what the orchestrator's record step consumes; record-session itself is silent and exits 0 even when it records nothing); (c) `cd` into the actual project path, review under the full text of `references/reviewer-policy.md`, appended to the file with `cat` (never retyped; it is the only review criterion codex receives, and no Claude-side rules or CLAUDE.md content is passed or read) plus round 1's full input; (d) send exactly one `send.sh "$TEAM" "$CODEX_AGENT" team-lead "..."` message, first line the VERDICT line per the VERDICT protocol, second line `round: 1`, full reporting structure inline. Two separate `send.sh` calls (ACK, then VERDICT), never combined.
- **Place the pane**: `bash "${CLAUDE_SKILL_DIR}/scripts/codex-reviewer.sh" launch <cmd> "$RUN_DIR/reviewer-surface" "$HOME/.xbb/codex-cwd"`. The script picks the backend: tmux whenever `$TMUX` is set (true both for plain tmux and for a tmux-backed cmux session — tmux always takes priority over any cmux-native path), deterministically `split-window` or `new-window` per `~/.xbb/config.json`'s `codex.tmuxLaunchMode` key (default `split-window` when the file, key, or value is missing/invalid); else cmux when `$CMUX_SOCKET_PATH` is set (the 3rd argument matters here because `cmux new-split` has no cwd flag, so the script `cd`s before running `<cmd>`). Neither set → the script exits non-zero; fall back to a generic OS terminal: first run `bash "${CLAUDE_SKILL_DIR}/scripts/detect-agent-workspace.sh"`, then check `references/codex-launch.md` for per-environment handling. Whichever mechanism is used, the pane/window/surface must be created with its cwd already set to `$HOME/.xbb/codex-cwd` (e.g. `tmux split-window -c "$HOME/.xbb/codex-cwd" ...`) — passing `--project` to `codex-monitor.sh` alone is not sufficient, because codex's app-server binds its working directory from the pane's cwd at the moment it launches, and `codex-monitor.sh`'s own later `cd` to `--project` only affects the TUI client, not the already-started app-server; a pane left at the caller's cwd binds the app-server to the wrong (reviewed) project.
- **Record the pane/window id** to `$RUN_DIR/codex-reviewer-pane` as soon as it's created — this design does not go through `spawn.sh`, so there is no `spawn.<team>__<name>` placement record to read back later; this file is the only record of where the reviewer lives, and Teardown depends on it.
- **Run, inside that pane** (always a fresh session — `--codex-command`'s default, `resume`, would pick up an unrelated old conversation from the reused `~/.xbb/codex-cwd` scratch dir; `$CODEX_AGENT` is unique per run already, so there is never a legitimate same-identity resume-across-runs case here):
  ```bash
  bash ~/.agents/skills/agmsg/scripts/drivers/types/codex/codex-monitor.sh \
    --project "$HOME/.xbb/codex-cwd" --codex-command codex \
    -- --sandbox workspace-write -c model_reasoning_effort=<config.codex.effort> -m <config.codex.model> \
    "Read the file $RUN_DIR/codex-round1.md and follow it exactly."
  ```
  (Sandbox, model, and effort are codex CLI flags after `--`; `spawn_options.yaml`/`AGMSG_SPAWN_OPTIONS_FILE` is not read on this path.) The trailing quoted string is codex's positional `[PROMPT]`: `codex-monitor.sh` hands everything after `--` verbatim to `codex --remote <url> …`, and the TUI submits that prompt as its first turn by itself. This is the boot-prompt mechanism on this launch path — the same positional-prompt shape `spawn.sh --boot-prompt` uses — so nothing is ever typed into the pane after launch. Keep it to that one pointer line: the instructions are 10 KB-class text whose quoting inside `<cmd>` would be fragile.
- **No readiness poll**: the prompt rides on the launch command, so the first event to wait for is the ACK below. `tmux capture-pane` on the recorded pane is only for diagnosing a missing ACK.
- **Wait**: poll ACK (`pingTimeoutSec`), then VERDICT (`replyTimeoutSec`) via `bash ~/.agents/skills/agmsg/scripts/history.sh "$TEAM"`, reading only lines from `$CODEX_AGENT`; round N's VERDICT is the message carrying the `round: N` marker — never count untagged `VERDICT:` lines to tell rounds apart, since bridge delivery is at-least-once and a duplicate wake can make codex resend an old verdict. On round 1's ACK, read the thread field and record the seat yourself: `CODEX_THREAD_ID=<id> bash ~/.agents/skills/agmsg/scripts/drivers/types/codex/codex-record-session.sh "$TEAM" "$CODEX_AGENT" "$HOME/.xbb/codex-cwd"`, then verify `~/.agents/skills/agmsg/run/role-session.${TEAM}__${CODEX_AGENT}` exists and its `session=` line carries that id (the env-var path writes the file without touching the app-server, so it runs inside the Bash sandbox). The bridge launcher that `codex-monitor.sh` started picks the record up on its next poll and arms the bridge (observed within a minute). Never run `codex-record-session.sh` from outside WITHOUT `CODEX_THREAD_ID`: its app-server probe (`thread/loaded/list` minus already-seated threads) needs exactly one candidate, but one TUI launch loads two threads — the real one plus an unnamed `ephemeral` companion — so it silently records nothing. `thread=unset`, or the record file still missing after this step, means the bridge is NOT armed for later rounds — do not abort; deliver every round-N>1 delta via the raw-pane fallback below instead of `send.sh` (everything else in the Round loop unchanged). (`pingTimeoutSec`/`replyTimeoutSec`/`config.codex.model`/`config.codex.effort` are `~/.xbb/config.json` keys — see SKILL.md's Config section.) The Codex reviewer is a plain OS process with no harness idle/termination notification to fall back on.
- **Delivery rule for every text that reaches codex**: the text goes into a file under `$RUN_DIR` (`codex-round1.md`, `codex-round2.md`, …), and the only thing transported to codex is the one-line pointer `Read the file $RUN_DIR/<file> and follow it exactly.` No review content, file path list, identifier, or prose ever rides inside a `send.sh` argument or a `send-keys` string. Reason: backticks inside a double-quoted shell argument are command-substituted and silently deleted; the pointer line contains no backtick by construction.
- **Raw-pane fallback transport** (only when the bridge is not armed): type the same one-line pointer with two calls — `tmux send-keys -t "$(cat "$RUN_DIR/codex-reviewer-pane")" -l "Read the file $RUN_DIR/<file> and follow it exactly."` followed by `tmux send-keys -t "$(cat "$RUN_DIR/codex-reviewer-pane")" Enter`. cmux's tmux compatibility shim implements `send-keys`, `capture-pane`, `display-message`, `kill-pane` and `set-buffer`, but `load-buffer`, `paste-buffer` and `delete-buffer` fail with "Unsupported tmux compatibility command", so buffer-based pasting and multi-line text are never used.

## Round loop

- **Round 1** is the Launch sequence above (codex's backstop record, ACK, the orchestrator's seat record on ACK, review, VERDICT).
- **Round N > 1 (REVISE, more rounds remaining)**: do NOT clean up, do NOT relaunch. Write the round's delta input to `$RUN_DIR/codex-round$N.md`, then push only the pointer into the SAME pane:
  ```bash
  bash ~/.agents/skills/agmsg/scripts/send.sh "$TEAM" team-lead "$CODEX_AGENT" "Read the file $RUN_DIR/codex-round$N.md and follow it exactly."
  ```
  This relies on the bridge armed since round 1's seat record (written by the orchestrator on ACK, or by codex's own backstop call), which delivers this as a new turn in the same idle TUI — no `codex-record-session.sh` call is needed again; the round-1 role-session record stays valid for the whole life of the process. A message that lands while a turn is still running is held by the bridge and delivered when that turn ends, so sending before the TUI is idle is safe. (If the bridge never armed — `thread=unset`, or the record file missing after Launch's Wait step — type the same pointer via Launch's raw-pane fallback transport instead.) The delta file still asks for one ACK (`ACK round N`) then one VERDICT message whose second line is `round: N`, same content requirements as round 1's file, only the pointer transport differs (bridge push instead of a fresh boot-prompt). Wait for ACK then VERDICT exactly as in Launch's Wait step.
- **Never substitute an alternate launch that bypasses ACK/VERDICT** (e.g. a one-shot `codex exec`) at any round — this principle is unchanged regardless of delivery mechanism.

## Timeout-abort

Timeout at either deadline (any round) aborts the review, no fallback. If `$TMUX` is set, grab the recorded pane's tail for a launch-time cause — `tmux capture-pane -p -t "$(cat "$RUN_DIR/codex-reviewer-pane")" | tail -30` — reading the pane recorded at Launch (never re-derived via `agmsg_spawn_path`, which assumed a `spawn.sh` placement record this design never creates). Because the pane is never torn down between rounds, a timeout at round N > 1 can inspect the actual live state of a session that has been running the whole time, not just a just-launched one. Then run Teardown, report the cause (or that it's indeterminate, with next steps: `/xbb config reviewer=fable`, retry later — login/toolchain causes are already ruled out by preflight), and still deliver the completed work with review marked incomplete.

## Teardown (once, at the true end: PASS, rounds-exhausted, or timeout-abort)

Never a blanket operation — only ever acts on the pane id and identity this run itself recorded/registered.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/codex-reviewer.sh" cleanup "$TEAM" "$CODEX_AGENT" "$RUN_DIR/codex-reviewer-pane"
```

Also run at run end via SKILL.md step 8. Kills the recorded pane/window (which also kills the backgrounded dispatcher, same process group, via SIGHUP), then deregisters via `leave.sh "$TEAM" "$CODEX_AGENT"` so an already-detached bridge child self-exits within a couple of its own poll ticks once it notices the pair is no longer registered (best-effort — cleanup does not wait/block on that self-exit). Does NOT touch the shared app-server for `~/.xbb/codex-cwd` (left running, reused across rounds AND across runs — `codex-monitor.sh` has its own reuse/staleness liveness+version check and starts a fresh one when needed; never kill it from xbb's own scripts) and does NOT call `despawn.sh` (no `spawn.<team>__<name>` placement record exists under this design — `spawn.sh` is never called — so `despawn.sh --force` would die with "no placement record... was it launched via 'spawn'?").
