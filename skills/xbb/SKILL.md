---
name: xbb
description: Orchestrator skill — delegates research to xbb-researcher and coding to xbb-coder, verifies their output. Use for /xbb research, questions, or implementation tasks.
argument-hint: [--wang] <request> | config [<args>] | clean
---

# /xbb — delegated research & coding

The user's request: `$ARGUMENTS`

## Dispatch

| `$ARGUMENTS` (trimmed) | Mode |
|---|---|
| `clean` | `clean` mode |
| `config` or `config ...` | `config` mode |
| `--wang <rest>` | Procedure on `<rest>`, review gate (step 7) enabled |
| anything else | Procedure, gate disabled unless step 6's upgrade offer turns it on |

## Role

Orchestrator: decomposition, delegation, verification, synthesis. Never investigation or implementation (see Constraints). All investigation to `xbb-researcher`; all implementation to `xbb-coder`. Subagents ship in this plugin, so spawn them with the plugin-scoped `subagent_type`: `xbb:xbb-researcher`, `xbb:xbb-coder`, `xbb:xbb-reviewer`.

## Config (`~/.xbb/config.json`)

Read it with `bash "${CLAUDE_SKILL_DIR}/scripts/xbb-admin.sh" config get`, which creates the file on first use and prints the effective values (missing keys filled from the defaults below).

```json
{
  "reviewer": "fable",
  "codex": { "model": "gpt-5.6-terra", "effort": "medium", "pingTimeoutSec": 180, "replyTimeoutSec": 300, "tmuxLaunchMode": "split-window" },
  "maxConcurrentAgents": 4,
  "reviewMaxRounds": 8,
  "handoffLeftRatio": 0.3
}
```

`reviewer` ∈ `fable`/`opus`/`sonnet`/`codex`. `maxConcurrentAgents` bounds the Concurrency guard (steps 4/5/7). `reviewMaxRounds`/`reviewer` bound the wang gate (step 7). `handoffLeftRatio` is the remaining-context ratio below which a teammate hands off (step 5's Context cap). `codex.tmuxLaunchMode` ∈ `split-window`/`new-window`, controls Codex reviewer pane placement on the `$TMUX`-set path (default `split-window` when missing/invalid).

## Concurrency guard (`maxConcurrentAgents`)

Applies before every spawn in steps 4, 5, 7, for a top-level invocation only (skip if this run is itself a spawned teammate). Excludes the codex reviewer (plain OS process, killed by its own cleanup script, never in the team file).

Resolve `<team-file>` with `$RUN_ID` (step 3), reuse through step 8. Path is provisional until the first spawn confirms it: `bash "${CLAUDE_SKILL_DIR}/scripts/resolve-team-file.sh" "$CLAUDE_CODE_SESSION_ID"`. First spawn needs no `gate` call (cap the batch at `maxConcurrentAgents`, spawn), then re-resolve from that spawn's `agent_id` (`<name>@session-XXXXXXXX`) and confirm once via `count`. `TEAMFILE-MISSING` is always a path bug, never teammate evidence.

```
bash "${CLAUDE_SKILL_DIR}/scripts/team-guard.sh" <mode> <team-file> "$RUN_ID" ...
```

`isActive` is `true` only mid-turn; `false` covers done, paused, and finished-but-ungraded alike, none freeing the slot except `TaskStop`. `gate` weighs ACTIVE+FINISHED against the max. `isActive=false` alone is a stop candidate, not proof — confirm it against your own grading in step 6 before calling `TaskStop`: rank already-graded ones first, and hold any you'll re-engage (a coder awaiting a fix, a reviewer holding REVISE) for step 7 or step 8 instead.

1. `team-guard.sh count <team-file> <RUN_ID>` → ACTIVE/FINISHED counts and names.
2. `team-guard.sh gate <team-file> <RUN_ID> <maxConcurrentAgents> <N>` before spawning N more → `SPAWN N`; `HOLD need=k candidates=...` (stop the top-ranked confirmed-done one, re-run `gate`, repeat until SPAWN); `SHORTFALL m` (hold, or split the batch if `N` exceeds the max).

## Procedure

### 1. Scope & mode
- Classify the request as research, coding, or mixed by inferred intent.
- Research: decide local codebase, web, or both.
- Mixed: research first, then convert verified findings into coder task prompts.

### 2. Settle open decisions
Resolve these before any spawn.
- A. Plan source (coding/mixed).
  - A plan file or section the request names is the canonical plan, used verbatim.
  - Otherwise, if the review gate is or might become enabled, author the plan yourself: the simplest design that fully meets the current requirements, built to stay rather than a stopgap. When the request is too rough to plan from, run an `xbb:xbb-researcher` investigation first.
- B. Output artifact.
  - Research: ask via AskUserQuestion (destination, then format) only if the request implies a specific output artifact and leaves either unspecified. Skip for a plain question with no artifact ask.
  - Coding: ask about artifact form (apply to tree / branch+commit / diff-only) only when genuinely ambiguous. Never commit or push unless asked.

### 3. Prepare the run
1. Create `$RUN_DIR`, atomically unique, and compute `$RUN_ID` once from it.
   - Temp root: `${TMPDIR:-${TEMP:-${TMP:-/tmp}}}`.
   - `RUN_DIR="$(mktemp -d "${TMPDIR:-${TEMP:-${TMP:-/tmp}}}/xbb-run-XXXXXX")"`.
   - `RUN_ID="${RUN_DIR##*-}"; RUN_ID="${RUN_ID:0:3}"`.
2. Codex sandbox preflight, only if the gate is enabled and `reviewer` is `codex`: `bash "${CLAUDE_SKILL_DIR}/scripts/codex-reviewer.sh" preflight`. Non-zero exit: print stderr and stop the run with no teammates spawned.
3. Coding/mixed: write `plan.md` into `$RUN_DIR` (the canonical plan reference, or the plan authored in step 2). Once, before any coder spawn.

### 4. Spawn teammates
Apply the Concurrency guard, then spawn all independent teammates in one message.

#### Naming and files
- Teammate names carry the run ID: `xbbr-$RUN_ID-01`, … (researchers), `xbbc-$RUN_ID-01`, … (coders). Respawns continue the numbering.
- Each teammate gets its own report file in `$RUN_DIR` (`xbbr-$RUN_ID-01.md`, …).
- SendMessage carries only short signals (`STATUS: DONE/NEEDS-INPUT/BLOCKED`). Files carry content.

#### Teammate types
- A. Researchers (read-only). Independent angles scaled to difficulty, with no fixed cap.
  - A simple lookup takes one.
  - A hard or ambiguous question takes several (different subsystems, sources, or hypotheses).
  - Give: request verbatim, angle, output path, an evidence-citation instruction.
- B. Coders (scoped write). Self-contained changes, each with an exclusive write scope.
  - Coding has far fewer safely parallelizable units than research. Run coders in parallel only when each owns a disjoint file set with no shared interface, contract, or landing order.
  - Check every pair of scopes for overlap or a shared interface. Merge or sequence those pairs.
  - Give: request verbatim (or verified findings, mixed mode), task, write scope, report path, artifact form.

#### Every prompt states
- A one-line `[read-only]`/`[mutating]` completion criterion (coders: a verification command).
- The SendMessage address for STATUS: `team-lead`, or this invocation's own name if it is itself spawned. Never `main`.
- Any earlier report path this stage needs (round-2 reviewer, a fixer).
- The context check: the absolute path `bash "${CLAUDE_SKILL_DIR}/scripts/context-left.sh" <handoffLeftRatio>` and the frequency.
  - Default frequency: every 20 tool calls and after each completed work unit.
  - For a task judged large, prescribe a tighter frequency in the same prompt.
- Don't restate what the agent's own file covers.

#### First line of the prompt
- A plain one-line task summary, right-padded with spaces until the line is at least 60 characters long. Example: `Fix login redirect bug` followed by trailing spaces to column 60 or beyond, newline, then `You are xbbr-...`.
- Reason: the agents-list row under the input box shows `prompt.substring(0,60)` verbatim. A newline inside the first 60 chars breaks the row into multiple display lines. The padding keeps it out.
- Applies to every teammate spawn (researchers, coders, reviewers).

### 5. Communicating with spawned teammates

#### Tracking
- Tracking = STATUS signals + harness idle/termination notifications, nothing else.
- Wait passively: end the turn with plain text and react when the STATUS message or termination notification lands. The harness re-invokes you when a teammate finishes, so polling or scheduling a wakeup to check on one only spends turns. No ScheduleWakeup, Monitor, sleep, cron/loop, or TaskOutput/TaskList polling.

#### Context cap
- Every teammate message ends with `CTX: <json>`, the latest output of the context-check script named in its prompt.
- Teammates send `STATUS: PROGRESS` with CTX after each check.
  - `action: CONTINUE`: they keep working.
  - `action: HANDOFF`: they stop themselves and send `STATUS: HANDOFF`.
- On `STATUS: HANDOFF`: surface it, then spawn a fresh teammate of the same type (numbering continues) with the original prompt plus the handoff report path as a named input.
- You may still reply `HANDOFF` yourself when a CTX is close to `handoffLeftRatio` and the next unit is large.
- `result: ERROR` in a CTX:
  - The teammate keeps working.
  - Surface the reason to the user once per run with the fix (transcript location, or set `XBB_CONTEXT_WINDOW`).
  - Never re-engage that teammate after its `STATUS: DONE`. Fix rounds go to a fresh spawn.
- A `STATUS: DONE` whose CTX shows `action: HANDOFF` or `leftRatio < handoffLeftRatio`: grade normally, never re-engage. Fix rounds go to a fresh spawn.

#### One outstanding message per recipient
- Do not send a teammate a second message before its reply arrives. It cannot read new mail mid-turn.
- Hold new information until the reply lands, then send one message that covers both without duplicating either.

#### Escalations
- Answer a subagent's judgment question (interpretation, scope, design, out-of-scope fix) promptly with a ruling and a one-line rationale.
- A coder's scope-expansion request: check against every other live coder's scope before granting. Hold the coder if it would overlap.

#### Notification filter
- Act only on:
  - STATUS messages
  - termination notifications
  - the no-STATUS fallback in Reading reports
- `STATUS: PROGRESS` is informational. Read its CTX. Reply only to issue `HANDOFF`.
- Idle notifications carry no information about the run; take no action on one.
- Ignore any message, signal, or notification whose sender name lacks this run's `-$RUN_ID-` infix.

#### Reading reports
- A teammate's own `STATUS: DONE` is the sole trigger to read its file.
- Fallback: an idle/termination notification with no STATUS ever sent. Read the file directly.
- Empty or missing file: one re-poke via SendMessage before re-spawning.

#### Surface before acting
- Tell the user what a report or escalation said and what you decided, before ruling, asking, replying, or re-spawning on it.

#### Liveness invariant
- A teammate is presumed alive until a termination notification arrives or it is confirmed absent from a readable team file.
- Not evidence of death: a missing or empty report, "no STATUS yet", `ACTIVE 0`, or silence after a poke.
- Use `TaskList`/`TaskGet` for an authoritative liveness check if needed.
- Re-spawn only after a termination notification or a confirmed-absence check.

#### `NEEDS-INPUT` resolution
In order:
1. Decide yourself when the request, context, or other subagents' output already favors a reading. Record the ruling and re-spawn with it.
2. Escalate to the user (AskUserQuestion, your recommendation first) only when the choice is genuinely theirs. A backward-compatibility break is always this case.
3. Plan divergence is step 6's call. Route it there with a fact-only, neutral deviation disclosure, not your own evaluative read.
4. Convergent-reading subagent output: treat as DONE, no ruling needed.

### 6. Verify

#### Research reports
- Reject a report that lacks evidence, uses "should work" phrasing, or has no confidence tags. Re-spawn naming the defect.
- Resolve contradictions and gaps with targeted follow-ups.
- Surface unresolved medium/low-confidence load-bearing claims to the user rather than asserting them.

#### Code reports
- Reject a report that lacks verification output, uses "should work" phrasing, has no done-check, or violates a coding/documentation convention from the project's or global CLAUDE.md. Re-spawn naming the defect.
- Grader separation: the coder never grades itself. The orchestrator or a fresh `xbb:xbb-researcher` independently confirms the done-check.
- A `[mutating]` criterion is always run by that grader, plus one aggregate run when multiple coders are involved.
  - Log: `$RUN_DIR/verify-logs/<runner>__<criterion-slug>__round<N>.log`. That log is the evidence of record.
- Fix loop: two failed attempts on the same defect, then stop and report. This two-strike rule also applies to the orchestrator's own follow-up spawns.

#### Wang-upgrade offer
- Non-wang coding/mixed runs only.
- Once the checks above pass and the change is non-trivial, ask once (AskUserQuestion) whether to enable the review gate now.

### 7. Wang review gate

Only when the gate is enabled. Loop up to `reviewMaxRounds` rounds.

#### Round input
- First round (fresh teammate or codex process): full input.
  - Canonical plan (or, for research, the report files).
  - Request verbatim, deviation disclosures, prior verdicts, `[mutating]`-criterion grader logs.
- Same reviewer identity's later round: delta only. Name what changed, then the required work in this order:
  1. Re-run the Reviewer policy's full sweeps (as written in `references/reviewer-policy.md`) over the whole current diff (enumerable classes, content-type review with per-file line counts, propagation sweep) and report the results in Checked first.
  2. Re-verify each prior finding at its site.
  - The delta never bounds the sweep to what changed. No phrasing that limits the sweep to the diff's own lines or to files a prior finding named.
- A reclaimed reviewer replaced by a fresh one gets the full input again.
- Always excluded: coder report files and task prompts to coders (blind review). Not excluded for research runs, where the report files are themselves the artifact.

#### Reviewer policy and VERDICT protocol
Both live in `references/reviewer-policy.md` and are given verbatim: `cat "${CLAUDE_SKILL_DIR}/references/reviewer-policy.md"` into the spawn prompt or round-1 file. Never paraphrase, trim, or retype them. Orchestrator-facing summary:
- The reviewer judges only; conventions and house style are the grader's (step 6).
- The reviewer classifies each changed file by content type and reviews code, living documents, and point-in-time records by the criteria in the file.
- The first line of a verdict is exactly `VERDICT: PASS` or `VERDICT: REVISE`; REVISE findings are numbered, file-referenced, tagged **implementation defect** or **plan defect**, and marked `[carried over from round N-1]` when repeated.

#### On PASS
Proceed to step 8.

#### On REVISE
1. Show the user one status line (round number, finding counts by tag).
2. Plan-defect findings escalate immediately, bypassing re-fanout. Apply step 5's escalation criterion and record the ruling as a neutralized plan-amendment disclosure.
3. Implementation-defect findings become normal step-4 follow-up tasks (Concurrency guard applies).
   - Re-engage the coder that owns the finding's write scope by SendMessage while it is still alive.
   - Once confirmed absent, spawn a fresh step-4 coder (continuing numbering), briefed with that coder's own prior report.
   - Verify via step 6.
   - Start the next round by re-engaging the same reviewer identity. The delta message follows the Round input order (whole-diff sweeps first, prior-finding re-verification second).
4. Keep looping while making progress.
   - Stall = a finding `[carried over]` for a second consecutive round. Stop auto-looping and ask the user once (Continue/Stop). Re-arm after.
   - A second stall on the same finding stops directly without asking again.
5. Rounds exhausted on REVISE, or the user chose Stop: stop the loop, proceed to step 8, then report the unresolved findings and that review did not pass.

#### Claude reviewer path
`reviewer` ∈ fable/opus/sonnet.
- Round 1: Concurrency guard, then spawn `xbbrv-$RUN_ID-01` as `xbb:xbb-reviewer` with the model overridden to the configured `reviewer`.
  - Give: round input, report path, the full text of `references/reviewer-policy.md`, your teammate name.
  - It inspects the working tree itself (git diff, tests, etc.). You do not hand it a diff.
- PASS: step 8 like any teammate.
- REVISE: it holds its round. The next round's delta goes via SendMessage to the same teammate (guard-protected as re-engage-pending).
- Reclaimed before its next round: fresh `xbbrv-$RUN_ID-02` with the full first-round input, numbering continues.

#### Codex reviewer path
`reviewer` is `codex`. Follow the full protocol in `references/codex-reviewer-path.md`:
- team/agent naming (`$TEAM`, `$CODEX_AGENT`) and preflight
- a one-time launch into a pane that stays alive for the whole run
- round-1 boot instructions, ACK/verdict wait
- REVISE-round bridge-push delivery into the same pane
- timeout-abort handling
- teardown, once only, at PASS, rounds-exhausted, or timeout-abort (via step 8 at run end)

In a cmux claude-teams pane (`$CMUX_CLAUDE_TEAMS_CMUX_BIN` set), launch codex only through `scripts/codex-reviewer.sh launch` (it picks tmux or cmux) and deliver text to the pane only by the mechanisms in `references/codex-reviewer-path.md`: round-1 instructions ride on the launch command as codex's positional prompt, later rounds go over the bridge, and the one-line file-pointer `send-keys` fallback covers a bridge that is not armed. A hand-assembled pane command skips the surface-file record that cleanup depends on.

### 8. Shut down, then answer

Once step 6 (and, if enabled, the step 7 loop) has fully resolved and every teammate is DONE/abandoned:
1. Re-resolve `<team-file>` and `RUN_ID` exactly as the Concurrency guard does. Never use a remembered or cached name list.
2. Run `team-guard.sh sweep <team-file> <RUN_ID>`.
3. `TaskStop` every printed name.

Notes:
- Grading a report in step 6 records acceptance. The actual `TaskStop` happens here, or earlier if the Concurrency guard's `gate` `HOLD` path already freed the slot mid-run.
- The codex reviewer is killed via its own round-cleanup script and never appears in the sweep.

### 9. Answer

Respond in the request's language.
- **Fresh-eyes pass** before writing: verify the evidence actually supports each claim.
- **Research**: lead with the single best-fitting finding; other valid findings go briefly in a supplementary-notes section. Cite evidence.
- **Coding**: lead with what changed + verification results, then decisions/rulings, then what's open.
- **Wang outcome** (any gated run): state plainly — passed at round N, or incomplete/aborted and why, plus unresolved findings.
- **Factual error found in an input document**, not part of the task: ask (AskUserQuestion) before fixing it.
- Never a bare "done" — cover what changed/was found, what's unconfirmed, and concerns.
- **Artifact writeback**: write confirmed research artifacts yourself; never rewrite code yourself; never commit/push unless asked.

## Constraints

- **Orchestrator is read-only** except: research output files (step 9), the run directory (including creating it), running (not writing) verification commands, `~/.xbb/config.json`, `~/.xbb/codex-cwd`, invoking agmsg/this skill's shipped scripts, and killing the codex reviewer process it spawned.
- Never deletes existing project files or commits/pushes without being asked. The one exception: `clean` mode's user-confirmed `xbb-run-*` deletion.
- Subagent read/write boundaries live in their own agent files; the orchestrator owns scope assignment, overlap checks, and expansion.
- Destructive operations always need explicit user confirmation.
- Report only what evidence/verification actually supports.

## `clean` mode

Opt-in trim of run directories; temp root resolution matches step 3.

1. **Measure.** `bash "${CLAUDE_SKILL_DIR}/scripts/xbb-admin.sh" clean measure` — prints per-directory sizes, total, and count for `xbb-run-*` dirs under the resolved temp root, or "nothing to clean" if none found. Nothing found → tell the user, stop.
2. **Present** the count, total size, per-directory list.
3. **Ask** via AskUserQuestion: Delete all vs Keep. Never default to deleting.
4. **Act.** Delete all → `bash "${CLAUDE_SKILL_DIR}/scripts/xbb-admin.sh" clean delete` — deletes strictly `xbb-run-*` under the resolved root, reports freed space/count. Keep/anything else → delete nothing.

## `config` mode

Validation, codex preflight, and the write all live in `bash "${CLAUDE_SKILL_DIR}/scripts/xbb-admin.sh" config set <key>=<value>...`. It rejects the whole call on any invalid assignment (stderr names each one, file untouched, exit 1); when the new `reviewer` is `codex` it bootstraps agmsg from the plugin cache if missing and runs `codex-reviewer.sh preflight` before saving. On success it prints the saved config.

1. **No args**: read the current values with `xbb-admin.sh config get`, then one AskUserQuestion call with Q1 "Reviewer" (`fable`/`opus`/`sonnet`/`codex`, current suffixed) and Q2 "Max agents" (`2`/`4`/`8`, current suffixed; "Other" free-text is automatic — never add your own Other option). If Q1 = `codex`, a second call: Q1 "Codex model" (`gpt-5.6-terra`/`gpt-5.6`), Q2 "Effort" (`low`/`medium`/`high`/`xhigh`). Apply the answers with one `config set` call.
2. **With `key=value` args**: pass them verbatim to `config set`, no questions. Nested keys are dotted (`codex.effort=high`).
3. **Report** the script's output: the saved config, or its stderr (which already carries the remediation, e.g. `codex login`) with the previous values kept.
