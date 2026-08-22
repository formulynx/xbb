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
| `--wang <rest>` | Procedure on `<rest>`, review gate (step 5.5) enabled |
| anything else | Procedure, gate disabled unless step 5's upgrade offer turns it on |

## Role

Orchestrator: decomposition, delegation, verification, synthesis. Never investigation or implementation (see Constraints). All investigation to `xbb-researcher`; all implementation to `xbb-coder` (both Sonnet, effort high).

## Config (`~/.xbb/config.json`)

Lazy-created by whichever mode reads it first (`mkdir -p ~/.xbb` + defaults below). Missing keys fall back to defaults.

```json
{
  "reviewer": "fable",
  "codex": { "model": "gpt-5.6-terra", "effort": "medium", "pingTimeoutSec": 180, "replyTimeoutSec": 300 },
  "maxConcurrentAgents": 4,
  "reviewMaxRounds": 8
}
```

`reviewer` ∈ `fable`/`opus`/`sonnet`/`codex`. `maxConcurrentAgents` bounds the Concurrency guard (steps 3/4/5.5). `reviewMaxRounds`/`reviewer` bound the wang gate (5.5).

## Concurrency guard (`maxConcurrentAgents`)

Applies before every spawn in steps 3, 4, 5.5, for a top-level invocation only (skip if this run is itself a spawned teammate). Excludes the codex reviewer (plain OS process, killed by its own cleanup script, never in the team file).

Resolve `<team-file>` with `$RUN_ID` (step 3), reuse through step 6. Path is provisional until the first spawn confirms it: `bash "<skill-dir>/scripts/resolve-team-file.sh" "$CLAUDE_CODE_SESSION_ID"` (PowerShell: `resolve-team-file.ps1 $env:CLAUDE_CODE_SESSION_ID`). First spawn needs no `gate` call (cap the batch at `maxConcurrentAgents`, spawn), then re-resolve from that spawn's `agent_id` (`<name>@session-XXXXXXXX`) and confirm once via `count`. `TEAMFILE-MISSING` is always a path bug, never teammate evidence.

```
bash "<skill-dir>/scripts/team-guard.sh" <mode> <team-file> "$RUN_ID" ...  # PowerShell: team-guard.ps1
```

`isActive` is `true` only mid-turn; `false` covers done, paused, and finished-but-ungraded alike, none freeing the slot except `TaskStop`. `gate` weighs ACTIVE+FINISHED against the max. A FINISHED teammate is a stop candidate, never an instruction: rank already-graded ones first; never stop one you'll re-engage (a coder awaiting a fix, a reviewer holding REVISE).

1. `team-guard.sh count <team-file> <RUN_ID>` → ACTIVE/FINISHED counts and names.
2. `team-guard.sh gate <team-file> <RUN_ID> <maxConcurrentAgents> <N>` before spawning N more → `SPAWN N`; `HOLD need=k candidates=...` (stop the top-ranked confirmed-done one, re-run `gate`, repeat until SPAWN); `SHORTFALL m` (hold, or split the batch if `N` exceeds the max).

## Procedure

### 1. Scope & mode

Classify **research** / **coding** / **mixed** by inferred intent. Research: decide local codebase, web, or both.

Coding/mixed — parallelization: default to **one** coder; split into parallel coders only when each owns a disjoint file set with no shared interface/contract/landing order. Mixed: run research first, then convert verified findings into coder task prompts.

Coding/mixed — plan source: a plan file/section the request names is the canonical plan, used verbatim. Otherwise, if the review gate is (or might become) enabled, a plan must exist before delegating — author one yourself (the simplest design that fully meets the current requirements, built to stay rather than a stopgap meant to be replaced later), optionally preceded by an `xbb-researcher` investigation when the request is too rough to plan from directly.

### 2. Output check

Research: ask via AskUserQuestion (destination, then format) before spawning, only if the request implies a specific output artifact and leaves either unspecified. Skip for a plain question with no artifact ask.

Coding: ask about artifact form (apply to tree / branch+commit / diff-only) only when genuinely ambiguous. Never commit/push unless asked.

### 3. Delegate

Named teammates, run ID in every name: `xbbr-$RUN_ID-01`, … (researchers); `xbbc-$RUN_ID-01`, … (coders); respawns continue the numbering. `$RUN_ID` = first 3 chars of `$RUN_DIR`'s suffix, computed once after creating it: `RUN_ID="${RUN_DIR##*-}"; RUN_ID="${RUN_ID:0:3}"`. SendMessage carries only short signals (`STATUS: DONE/NEEDS-INPUT/BLOCKED`); files carry content.

Create `$RUN_DIR` before any spawn, atomically unique. Temp root: POSIX `${TMPDIR:-${TEMP:-${TMP:-/tmp}}}`; PowerShell `$env:TMPDIR`, else `$env:TEMP`, else `$env:TMP`, else `C:\Temp`.
```
RUN_DIR="$(mktemp -d "${TMPDIR:-${TEMP:-${TMP:-/tmp}}}/xbb-run-XXXXXX")"  # PowerShell: New-Item + [guid]::NewGuid()
```

**Codex sandbox preflight**, here, once, before any spawn, only if the gate is enabled and `reviewer` is `codex`: `bash "<skill-dir>/scripts/reviewer-spawn-preflight.sh"`. Non-zero → print stderr, stop the run, no teammates spawned.

Each teammate gets its own report file in `$RUN_DIR` (`xbbr-$RUN_ID-01.md`, …). Coding/mixed: write `plan.md` here too, before any coder spawn (canonical-plan reference, or the step-1 orchestrator-authored plan), once, at delegation time.

Spawn independent teammates in one message; apply the Concurrency guard first.

- **Researchers** (read-only): independent angles scaled to difficulty. Give: request verbatim, angle, output path, an evidence-citation instruction.
- **Coders** (scoped write): self-contained changes, each an exclusive write scope checked pairwise against every other coder's for overlap/shared interface — merge or sequence those, never parallel. Give: request verbatim (or verified findings, mixed mode), task, write scope, report path, artifact form.
- **Every prompt states**: (a) a one-line `[read-only]`/`[mutating]` completion criterion (coders: a verification command); (b) the SendMessage address for STATUS — `team-lead`, or this invocation's own name if it is itself spawned, never `main`; (c) any earlier report path this stage needs (round-2 reviewer, a fixer). Don't restate what the agent's own file covers.

### 4. Communicating with spawned teammates

Tracking = STATUS signals + harness idle/termination notifications, nothing else. Never `ScheduleWakeup` to poll.

**One outstanding message per recipient.** Do not send a teammate a
second message before its reply arrives. It cannot read new mail
mid-turn. Hold any new information until the reply lands, then send
one message that accounts for both without duplicating either.

**Escalations.** Answer a subagent's judgment question (interpretation, scope, design, out-of-scope fix) promptly with a ruling + one-line rationale. A coder's scope-expansion request: check against every other live coder's scope before granting; hold the coder if it would overlap.

**Notification filter.** Act only on (a) STATUS messages, (b) termination notifications, (c) the no-STATUS fallback in Reading reports.  
Idle notifications are not events. Never narrate, acknowledge, or message a teammate in response to one.  
Also ignore any message/signal/notification whose sender name lacks this run's `-$RUN_ID-` infix.

**Reading reports.** A teammate's own `STATUS: DONE` is the sole trigger to read its file. Fallback: idle/termination notification with no STATUS ever sent → read the file directly; empty/missing → one re-poke via SendMessage before re-spawning.

**Surface before acting.** Tell the user what a report or escalation said and what you decided, before ruling, asking, replying, or re-spawning on it.

**Liveness invariant.** Presumed alive until a termination notification arrives, or it's confirmed absent from a readable team file — not a missing/empty report, "no STATUS yet", `ACTIVE 0`, or silence after a poke. Use `TaskList`/`TaskGet` for an authoritative liveness check if needed. Re-spawn only after a termination notification or a confirmed-absence check.

**`NEEDS-INPUT` resolution**, in order:
1. Decide yourself when the request/context/other subagents' output already favors a reading — record the ruling, re-spawn with it.
2. Escalate to the user (AskUserQuestion, your recommendation first) only when the choice is genuinely theirs. A backward-compatibility break is always this case.
3. Plan divergence is step 5's call: route it there with a fact-only, neutral deviation disclosure, not your own evaluative read.
4. Convergent-reading subagent output → treat as DONE, no ruling needed.

### 5. Verify

**Research.** Reject reports lacking evidence, using "should work" phrasing, or missing confidence tags — re-spawn naming the defect. Resolve contradictions/gaps with targeted follow-ups. Surface unresolved medium/low-confidence load-bearing claims to the user rather than asserting them.

**Code.** Reject reports missing verification output, using "should work" phrasing, or missing a done-check — re-spawn naming the defect. **Grader separation**: the coder never grades itself — the orchestrator itself or a fresh `xbb-researcher` independently confirms the done-check. A `[mutating]` criterion is always run independently by that grader (plus one aggregate run when multiple coders are involved), logged to `$RUN_DIR/verify-logs/<runner>__<criterion-slug>__round<N>.log` — that log is the evidence of record. Fix loop bounded to two failed attempts on the same defect, then stop and report.

Two-strike rule applies to the orchestrator's own follow-up spawns too.

**Wang-upgrade offer** (non-wang coding/mixed runs only): once checks above pass, if the change is non-trivial, ask once (AskUserQuestion) whether to enable the review gate now.

### 5.5. Wang review gate

Only when the gate is enabled. Loop up to `reviewMaxRounds` rounds.

**Round input.** First round (fresh teammate or codex process): full input — canonical plan (or, for research, the report files) + request verbatim + deviation disclosures + prior verdicts + `[mutating]`-criterion grader logs. Same reviewer identity's later round: delta only — what changed, plus (a) re-verify prior findings, (b) fully re-sweep any enumerable defect class, (c) propagation sweep (grep the whole codebase for every reference, old and new form, to any symbol this round's fix renamed/changed). A reclaimed reviewer replaced by a fresh one gets the full input again. Always excluded: coder report files and task prompts to coders (blind review) — not excluded for research runs, where the report files are themselves the artifact.

**Reviewer policy** (given verbatim in the spawn prompt):
- Judge, not director — report defects, never fix/redesign/expand scope. A stopgap or a custom implementation where an established library fits is an implementation-defect finding, not a side finding.
- Read-only: inspect (diff, files, the project's own verification commands) but never mutate the tree. For a `[mutating]` criterion, treat the grader's log as executed evidence, confirmed against the tree with read-only commands.
- No scope creep: review against the request as given; adjacent issues are non-blocking side findings.
- Never silently resolve ambiguity that would change the verdict: escalate live if a channel exists (Claude path: SendMessage, wait for the ruling); else encode it as the round's sole REVISE finding (codex path).
- A REVISE verdict requires the same full sweep a PASS would: exhaustively enumerate any mechanically-enumerable defect class, and run the propagation sweep above for any changed symbol.
- Report structure: VERDICT / Checked (with an explicit not-inspected coverage declaration) / Findings (REVISE: numbered, file-referenced, actionable) / Side findings / Concerns.

**VERDICT protocol.** First line exactly `VERDICT: PASS` or `VERDICT: REVISE`. Each REVISE finding: numbered, file-referenced, actionable, tagged **implementation defect** or **plan defect**, marked `[carried over from round N-1]` if it repeats an unresolved prior finding.

**PASS** → proceed to step 6. **REVISE**:
1. Show the user one status line (round number, finding counts by tag).
2. Plan-defect findings escalate immediately, bypassing re-fanout: apply step 4's escalation criterion, record the ruling as a neutralized plan-amendment disclosure.
3. Implementation-defect findings become normal step-3 follow-up tasks (Concurrency guard applies); verify via step 5; start the next round by re-engaging the same reviewer identity.
4. Keep looping while making progress. Stall = a finding `[carried over]` for a second consecutive round → stop auto-looping, ask the user once (Continue/Stop); re-arm after; a second stall on the same finding stops directly without asking again.

Rounds exhausted on REVISE, or the user chose Stop → stop the loop; report unresolved findings and that review did not pass.

**Claude reviewer path** (`reviewer` ∈ fable/opus/sonnet). Round 1: Concurrency guard, spawn `xbbrv-$RUN_ID-01` as `xbb-reviewer`, model overridden to the configured `reviewer`, with the round input, report path, Reviewer policy, VERDICT protocol, your teammate name. It inspects the working tree itself (git diff, tests, etc.) — you do not hand it a diff. PASS → step 6 like any teammate. REVISE → holds its round; next round's delta goes via SendMessage to the same teammate (guard-protected as re-engage-pending). Reclaimed before its next round → fresh `xbbrv-$RUN_ID-02` with the full first-round input, numbering continues.

**Codex reviewer path** (`reviewer` is `codex`): follow the full setup/launch/
round-loop/teardown protocol in `references/codex-reviewer-path.md` —
team/agent naming (`$TEAM`, `$CODEX_AGENT`), preflight, a one-time launch into
a pane that stays alive for the whole run, round-1 boot instructions,
ACK/verdict wait, REVISE-round bridge-push delivery into the same pane,
timeout-abort handling, and teardown (once only, at PASS, rounds-exhausted,
or timeout-abort — via step 6 at run end).

### 6. Shut down, then answer

Once step 5 (and, if enabled, the 5.5 loop) has fully resolved and every teammate is DONE/abandoned: **re-resolve** `<team-file>`/`RUN_ID` exactly as the Concurrency guard does (never a remembered/cached name list), run `team-guard.sh sweep <team-file> <RUN_ID>` (PowerShell: `team-guard.ps1 sweep <team-file> <RUN_ID>`), and `TaskStop` every printed name. The codex reviewer is killed via its own round-cleanup script instead, and never appears in the sweep.

### 7. Answer

Respond in the request's language.
- **Fresh-eyes pass** before writing: verify the evidence actually supports each claim.
- **Research**: lead with the single best-fitting finding; other valid findings go briefly in a supplementary-notes section. Cite evidence.
- **Coding**: lead with what changed + verification results, then decisions/rulings, then what's open.
- **Wang outcome** (any gated run): state plainly — passed at round N, or incomplete/aborted and why, plus unresolved findings.
- **Factual error found in an input document**, not part of the task: ask (AskUserQuestion) before fixing it.
- Never a bare "done" — cover what changed/was found, what's unconfirmed, and concerns.
- **Artifact writeback**: write confirmed research artifacts yourself; never rewrite code yourself; never commit/push unless asked.

## Constraints

- **Orchestrator is read-only** except: research output files (step 2), the run directory (including creating it), running (not writing) verification commands, `~/.xbb/config.json`, `~/.xbb/codex-cwd`, invoking agmsg/this skill's shipped scripts, and killing the codex reviewer process it spawned.
- Never deletes existing project files or commits/pushes without being asked. The one exception: `clean` mode's user-confirmed `xbb-run-*` deletion.
- Subagent read/write boundaries live in their own agent files; the orchestrator owns scope assignment, overlap checks, and expansion.
- Destructive operations always need explicit user confirmation.
- Report only what evidence/verification actually supports.

## `clean` mode

Opt-in trim of run directories; temp root resolution matches step 3.

1. **Measure.** `bash "<skill-dir>/scripts/xbb-clean.sh" measure` (PowerShell: `xbb-clean.ps1 measure`) — prints per-directory sizes, total, and count for `xbb-run-*` dirs under the resolved temp root, or "nothing to clean" if none found. Nothing found → tell the user, stop.
2. **Present** the count, total size, per-directory list.
3. **Ask** via AskUserQuestion: Delete all vs Keep. Never default to deleting.
4. **Act.** Delete all → `bash "<skill-dir>/scripts/xbb-clean.sh" delete` (PowerShell: `xbb-clean.ps1 delete`) — deletes strictly `xbb-run-*` under the resolved root, reports freed space/count. Keep/anything else → delete nothing.

## `config` mode

1. **No args**: one AskUserQuestion call with Q1 "Reviewer" (`fable`/`opus`/`sonnet`/`codex`, current suffixed) and Q2 "Max agents" (`2`/`4`/`8`, current suffixed; "Other" free-text is automatic — never add your own Other option). If Q1 = `codex`, a second call: Q1 "Codex model" (`gpt-5.6-terra`/`gpt-5.6`), Q2 "Effort" (`low`/`medium`/`high`/`xhigh`).
2. **With `key=value` args**: apply directly, no questions — except `reviewer` must validate against `fable`/`opus`/`sonnet`/`codex` first; an invalid value is rejected (report it, keep the previous `reviewer`) rather than saved.
3. **Codex preflight**, only when the new `reviewer` is `codex`, before saving:
   - `command -v codex` and `codex --version` matches `codex-cli X.Y.Z`.
   - `codex login status` exits 0.
   - agmsg present at `~/.agents/skills/agmsg/`; if absent but the plugin-cache install.sh exists, bootstrap: `bash "$(ls ~/.claude/plugins/cache/fujibee-agmsg/agmsg/*/install.sh | head -1)" --cmd agmsg`. Neither present → fail.

   Any failure → print the specific remediation (`npm install -g @openai/codex`, `codex login`, or `/plugin install agmsg@fujibee-agmsg`) and keep the previous `reviewer`. Success → save and confirm.
