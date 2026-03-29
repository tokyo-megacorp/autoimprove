---
name: proposals
description: "Use when reviewing, approving, or rejecting autoimprove Phase 2 proposals. Examples:

<example>
Context: User wants to see what proposals the proposer drafted.
user: \"show me pending autoimprove proposals\"
assistant: I'll use the proposals skill to list the current proposal queue.
<commentary>Reviewing pending proposals — proposals skill.</commentary>
</example>

<example>
Context: User wants to approve a specific proposal to run.
user: \"approve proposal 2\"
assistant: I'll use the proposals skill to approve proposal #2 and queue it for the next run.
<commentary>Approving a proposal — proposals skill.</commentary>
</example>

<example>
Context: User wants to reject a proposal.
user: \"reject proposal 1\"
assistant: I'll use the proposals skill to reject proposal #1.
<commentary>Rejecting a proposal — proposals skill.</commentary>
</example>

Do NOT use to start a grind session (use run). Do NOT use to generate proposals (use proposer agent). Do NOT use to view log (use history)."
argument-hint: "[approve <N>] [reject <N> [--reason TEXT]] [defer <N> [--until TEXT]] [list]"
allowed-tools: [Read, Write, Edit, Bash, Glob]
---

<SKILL-GUARD>
You are NOW executing the proposals skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Review and act on autoimprove Phase 2 proposals. This skill reads proposal files from `experiments/`, displays them, and records human decisions (approve/reject/defer) to `experiments/proposals-decisions.json`.

Parse the subcommand passed by the user:
- `list` (default, no subcommand) — show all pending proposals
- `approve <N>` — approve proposal #N and queue it for the next run session
- `reject <N> [--reason TEXT]` — reject proposal #N permanently
- `defer <N> [--until TEXT]` — defer proposal #N without rejecting (optional context)

---

# 1. Prerequisites Check

```bash
test -f autoimprove.yaml || echo "MISSING"
```

If missing, print: `autoimprove is not initialized here. Run /autoimprove init.` and stop.

---

# 2. Locate Proposal Files

```bash
ls experiments/proposals-*.md 2>/dev/null | sort
```

If no proposal files exist, print:

```
No proposals have been drafted yet.

Proposals are generated when the grind loop stagnates (keep rate < 25% for 3 sessions).
You can also trigger Phase 2 manually with: /autoimprove run --phase propose
```

And stop.

---

# 3. Load Decisions File

Read `experiments/proposals-decisions.json` if it exists. If missing, initialize an empty structure:

```json
{
  "decisions": []
}
```

Each decision entry has the shape:
```json
{
  "proposal_file": "experiments/proposals-2026-03-25.md",
  "proposal_number": 1,
  "decision": "approve | reject | defer",
  "reason": "optional human-provided context",
  "decided_at": "ISO timestamp"
}
```

---

# 4. Read and Parse Proposals

Read each proposal file found in step 2. For each file, extract individual proposals using the `PROPOSAL #N:` block format. Each proposal block contains:
- Title (from the `PROPOSAL #N:` header line)
- Scope
- Category
- Rationale
- Risk
- Files
- Steps
- Estimated experiments
- Blocking dependencies

Build a flat list of all proposals across all files, numbered by their `#N` identifier. If the same `#N` appears in multiple files (unlikely but possible), use the most recent file's version.

---

# 5. Classify by Decision Status

For each proposal, look up its current decision status from `proposals-decisions.json`:
- **pending** — no decision recorded yet
- **approved** — decision is "approve"
- **rejected** — decision is "reject"
- **deferred** — decision is "defer"

---

# 6. Execute Subcommand

## 6a. `list` (default)

Display all proposals grouped by status. Show pending proposals first, then approved, deferred, rejected.

Format each proposal as:

```
PROPOSAL #N: <Title>          [PENDING | APPROVED | REJECTED | DEFERRED]
  Category:  <category>
  Risk:      <risk level> — <justification>
  Scope:     <scope>
  Rationale: <rationale>
  Steps:     <numbered steps>
  Files:     <file list>
  Estimated experiments: <N>
  Blocking:  <dependencies or "none">
```

After listing all proposals, print a summary line:

```
Proposals: <total> total — <P> pending, <A> approved, <D> deferred, <R> rejected
```

If there are approved proposals, also print:
```
Next run with /autoimprove run will execute <A> approved proposal(s).
```

## 6b. `approve <N>`

1. Find proposal #N. If not found, print: `Proposal #N not found.` and stop.
2. Check if it already has a decision. If already approved, print: `Proposal #N is already approved.` and stop.
3. Check for blocking dependencies listed in the proposal's `Blocking:` field. If any blocking proposal is still pending or deferred, print:
   ```
   Proposal #N is blocked by: <list of blocking proposal numbers and titles>
   Resolve blocking proposals first, or use --force to override.
   ```
   Unless `--force` was passed, stop here.
4. Record the decision:
   ```json
   {
     "proposal_file": "<source file>",
     "proposal_number": N,
     "decision": "approve",
     "reason": null,
     "decided_at": "<ISO timestamp>"
   }
   ```
5. Write updated `experiments/proposals-decisions.json`.
6. Print:
   ```
   Proposal #N approved: "<Title>"
   It will run in the next /autoimprove run session.
   ```

## 6c. `reject <N> [--reason TEXT]`

1. Find proposal #N. If not found, print: `Proposal #N not found.` and stop.
2. Record the decision with `decision: "reject"` and capture `--reason` if provided.
3. Write updated `experiments/proposals-decisions.json`.
4. Print:
   ```
   Proposal #N rejected: "<Title>"
   Reason: <reason or "(none provided)">
   ```

## 6d. `defer <N> [--until TEXT]`

1. Find proposal #N. If not found, print: `Proposal #N not found.` and stop.
2. Record the decision with `decision: "defer"` and capture `--until` as the `reason` field if provided.
3. Write updated `experiments/proposals-decisions.json`.
4. Print:
   ```
   Proposal #N deferred: "<Title>"
   Until: <until context or "(no deadline specified)">
   ```

---

# 7. Notes

- The decisions file is append-style: if a proposal already has a decision and the user issues a new one (e.g., un-rejecting via approve), append the new decision. The `run` skill uses the **most recent** decision entry for each proposal number.
- Proposal files in `experiments/` are never modified by this skill — they are read-only artifacts written by the proposer agent.
- If `experiments/proposals-decisions.json` becomes corrupted (invalid JSON), print an error and stop. Do NOT attempt to repair it automatically.
- The `/autoimprove run` skill reads `proposals-decisions.json` to load approved proposals before the Phase 2 experiment loop begins.
