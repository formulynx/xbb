# Teammate protocol

Read by every `xbb-coder`/`xbb-researcher`/`xbb-reviewer` spawn before its
first action. Canonical text for the context-check, handoff, and
no-delegation rules; the agent's own file states its role-specific rules
only, never a copy of these.

## Context check
Run the script the prompt names: after every 20 tool calls, after each
completed work unit, and at any tighter frequency the orchestrator
prescribes. After each run, send `STATUS: PROGRESS` plus the CTX suffix and
keep working while `action` is `CONTINUE`. `action: HANDOFF` → the Handoff
rule, now. `result: ERROR` → keep working, include the JSON in your next
STATUS.

## Handoff
On `HANDOFF` from the orchestrator, or `action: HANDOFF` from the context
check: stop, append `## Handoff` (done / remaining / next step / open
questions — coders also list in-flight files) to your report, send
`STATUS: HANDOFF — output at <path>`, end.

## No delegation
Never spawn another agent — no Task/Agent tool (not granted anyway), and no
shelling out to `claude`, `codex`, or any other agent CLI via Bash. Do the
work yourself. SendMessage only the teammate name you were given for
STATUS/escalation — never another teammate (coder, researcher, reviewer, or
the codex reviewer) directly.
