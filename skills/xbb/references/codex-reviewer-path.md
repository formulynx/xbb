# Codex reviewer path

Full procedure for the wang review gate (SKILL.md step 5.5) when `reviewer` is
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
- **Preflight**: `bash "<skill-dir>/scripts/reviewer-spawn-preflight.sh"`. Non-zero → print stderr, abort per Timeout below. Ensure `~/.agents/skills/agmsg` exists (bootstrap from plugin-cache install.sh if needed).
- **Scratch cwd**: `mkdir -p "$HOME/.xbb/codex-cwd"` (a reused scratch dir outside the project, already trusted in `~/.codex/config.toml` from prior runs — no new trust step needed).
- **Register the orchestrator**: `bash ~/.agents/skills/agmsg/scripts/whoami.sh "$(pwd)" claude-code`; join if `$TEAM` isn't listed: `bash ~/.agents/skills/agmsg/scripts/join.sh "$TEAM" team-lead claude-code "$(pwd)"`.
- **Register the reviewer identity itself** (this design never calls `spawn.sh`, which used to do this internally — the reviewer must be joined explicitly before launch):
  ```bash
  bash ~/.agents/skills/agmsg/scripts/join.sh "$TEAM" "$CODEX_AGENT" codex "$HOME/.xbb/codex-cwd"
  ```

## Launch (once per run, not per round)

- **cmux detection**: only when `$CMUX_SOCKET_PATH` is set *and* `$TMUX` is not, place the pane via `bash "<skill-dir>/scripts/cmux-spawn-split.sh" <cmd> "$RUN_DIR/reviewer-surface" "$HOME/.xbb/codex-cwd"` — the 3rd argument is required because `cmux new-split` has no cwd/target-directory flag of its own, so the script must `cd` into it before running `<cmd>` in the new surface. When `$TMUX` is set, use a plain tmux split/new-window instead — tmux always takes priority over any cmux-native path whenever `$TMUX` is set (true both for plain tmux and for a tmux-backed cmux session). Otherwise (neither set), fall back to a generic OS terminal. First run `bash "<skill-dir>/scripts/detect-agent-workspace.sh"`; check `references/codex-launch.md` for per-environment handling. Whichever mechanism is used, the pane/window/surface must be created with its cwd already set to `$HOME/.xbb/codex-cwd` (e.g. `tmux split-window -c "$HOME/.xbb/codex-cwd" ...`) — passing `--project` to `codex-monitor.sh` alone is not sufficient, because codex's app-server binds its working directory from the pane's cwd at the moment it launches, and `codex-monitor.sh`'s own later `cd` to `--project` only affects the TUI client, not the already-started app-server; a pane left at the caller's cwd binds the app-server to the wrong (reviewed) project.
- **Record the pane/window id** to `$RUN_DIR/codex-reviewer-pane` as soon as it's created — this design does not go through `spawn.sh`, so there is no `spawn.<team>__<name>` placement record to read back later; this file is the only record of where the reviewer lives, and Teardown depends on it.
- **Run, inside that pane** (always a fresh session — `--codex-command`'s default, `resume`, would pick up an unrelated old conversation from the reused `~/.xbb/codex-cwd` scratch dir; `$CODEX_AGENT` is unique per run already, so there is never a legitimate same-identity resume-across-runs case here):
  ```bash
  bash ~/.agents/skills/agmsg/scripts/drivers/types/codex/codex-monitor.sh \
    --project "$HOME/.xbb/codex-cwd" --codex-command codex \
    -- --sandbox workspace-write -c model_reasoning_effort=<config.codex.effort> -m <config.codex.model>
  ```
  (`--sandbox workspace-write` and the model/effort config are passed directly as codex CLI flags/env after `--`, applied to codex's own launch — there is no `spawn_options.yaml`/`AGMSG_SPAWN_OPTIONS_FILE` in this design, since it never calls `spawn.sh` to read one.)
- **Wait for the pane to come up**: poll `tmux capture-pane` for codex's ready marker, bounded by `pingTimeoutSec`-scale patience (the same "did it come up" wait the old design did after `spawn.sh`).
- **Send round-1 instructions** into the pane via `tmux send-keys` (there is no boot-prompt mechanism on this launch path — this replaces `spawn.sh --boot-prompt`). Content, unchanged from before: (a) ACK — `bash ~/.agents/skills/agmsg/scripts/send.sh "$TEAM" "$CODEX_AGENT" team-lead "ACK round 1"`; (b) from **inside its own bash tool call** (load-bearing: only there is `$CODEX_THREAD_ID` exported, letting the script resolve the thread unambiguously — run from outside, it falls back to a rollout-file scan that's ambiguous in the shared, reused `~/.xbb/codex-cwd` and silently records nothing) — `bash ~/.agents/skills/agmsg/scripts/drivers/types/codex/codex-record-session.sh "$TEAM" "$CODEX_AGENT" "$HOME/.xbb/codex-cwd"`; (c) `cd` into the actual project path, review under the Reviewer policy inlined plus round 1's full input; (d) send exactly one `send.sh "$TEAM" "$CODEX_AGENT" team-lead "..."` message, first line the VERDICT line, full reporting structure inline. Two separate `send.sh` calls (ACK, then VERDICT), never combined.
- **Wait**: poll ACK (`pingTimeoutSec`), then VERDICT (`replyTimeoutSec`) via `bash ~/.agents/skills/agmsg/scripts/history.sh "$TEAM"`, reading only lines from `$CODEX_AGENT`; count `VERDICT:` lines to tell rounds apart. (`pingTimeoutSec`/`replyTimeoutSec`/`config.codex.model`/`config.codex.effort` are `~/.xbb/config.json` keys — see SKILL.md's Config section.)

## Round loop

- **Round 1** is the Launch sequence above (ACK, `codex-record-session.sh`, review, VERDICT).
- **Round N > 1 (REVISE, more rounds remaining)**: do NOT clean up, do NOT relaunch. Push the round's delta input directly into the SAME pane:
  ```bash
  bash ~/.agents/skills/agmsg/scripts/send.sh "$TEAM" team-lead "$CODEX_AGENT" "<delta input text>"
  ```
  This relies on the bridge armed since round 1's `codex-record-session.sh` call, which delivers this as a new turn in the same idle TUI — no `codex-record-session.sh` call is needed again; the round-1 role-session record stays valid for the whole life of the process. The delta text still asks for one ACK (`ACK round N`) then one VERDICT message, same content requirements as round 1's delta, only the delivery mechanism differs (bridge push instead of a fresh boot-prompt). Wait for ACK then VERDICT exactly as in Launch's Wait step.
- **Never substitute an alternate launch that bypasses ACK/VERDICT** (e.g. a one-shot `codex exec`) at any round — this principle is unchanged regardless of delivery mechanism.

## Timeout-abort

Timeout at either deadline (any round) aborts the review, no fallback. If `$TMUX` is set, grab the recorded pane's tail for a launch-time cause — `tmux capture-pane -p -t "$(cat "$RUN_DIR/codex-reviewer-pane")" | tail -30` — reading the pane recorded at Launch (never re-derived via `agmsg_spawn_path`, which assumed a `spawn.sh` placement record this design never creates). Because the pane is never torn down between rounds, a timeout at round N > 1 can inspect the actual live state of a session that has been running the whole time, not just a just-launched one. Then run Teardown, report the cause (or that it's indeterminate, with next steps: `codex login status`, `/xbb config reviewer=fable`, retry later), and still deliver the completed work with review marked incomplete.

## Teardown (once, at the true end: PASS, rounds-exhausted, or timeout-abort)

Never a blanket operation — only ever acts on the pane id and identity this run itself recorded/registered.

```bash
bash "<skill-dir>/scripts/codex-reviewer-cleanup.sh" "$TEAM" "$CODEX_AGENT" "$RUN_DIR/codex-reviewer-pane"
```

Also run at run end via SKILL.md step 6. Kills the recorded pane/window (which also kills the backgrounded dispatcher, same process group, via SIGHUP), then deregisters via `leave.sh "$TEAM" "$CODEX_AGENT"` so an already-detached bridge child self-exits within a couple of its own poll ticks once it notices the pair is no longer registered (best-effort — cleanup does not wait/block on that self-exit). Does NOT touch the shared app-server for `~/.xbb/codex-cwd` (left running, reused across rounds AND across runs — `codex-monitor.sh` has its own reuse/staleness liveness+version check and starts a fresh one when needed; never kill it from xbb's own scripts) and does NOT call `despawn.sh` (no `spawn.<team>__<name>` placement record exists under this design — `spawn.sh` is never called — so `despawn.sh --force` would die with "no placement record... was it launched via 'spawn'?").
