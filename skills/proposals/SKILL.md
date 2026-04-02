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

Initialize progress tracking:

```
TodoWrite([
  {id: "prereqs",  content: "✅ Prerequisites check",         status: "pending"},
  {id: "locate",   content: "🔍 Locate proposal files",       status: "pending"},
  {id: "load",     content: "📋 Load decisions file",         status: "pending"},
  {id: "parse",    content: "🔍 Read and parse proposals",    status: "pending"},
  {id: "classify", content: "📊 Classify by decision status", status: "pending"},
  {id: "action",   content: "🛠️ Execute subcommand",          status: "pending"}
])
```

---

# 1. Prerequisites Check

```bash
test -f autoimprove.yaml || echo "MISSING"
```

If missing, print: `autoimprove is not initialized here. Run /autoimprove init.` and stop.

```
TodoWrite([{id: "prereqs", content: "✅ Prerequisites check", status: "completed"}])
```

---

# 2. 🔍 Locate Proposal Files

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

```
TodoWrite([{id: "locate", content: "🔍 Locate proposal files", status: "completed"}])
```

---

# 3. 📋 Load Decisions File

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

```
TodoWrite([{id: "load", content: "📋 Load decisions file", status: "completed"}])
```

---

# 4. 🔍 Read and Parse Proposals

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

```
TodoWrite([{id: "parse", content: "🔍 Read and parse proposals", status: "completed"}])
```

---

# 5. 📊 Classify by Decision Status

For each proposal, look up its current decision status from `proposals-decisions.json`:
- **pending** — no decision recorded yet
- **approved** — decision is "approve"
- **rejected** — decision is "reject"
- **deferred** — decision is "defer"

```
TodoWrite([
  {id: "classify", content: "📊 Classify by decision status", status: "completed"},
  {id: "action",   content: "🛠️ Execute subcommand",          status: "in_progress"}
])
```

---

# 6. 🛠️ Execute Subcommand

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

```
TodoWrite([{id: "action", content: "📋 Listed <total> proposals — <P> pending, <A> approved, <D> deferred, <R> rejected", status: "completed"}])
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

```
TodoWrite([{id: "action", content: "✅ Proposal #N approved", status: "completed"}])
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

```
TodoWrite([{id: "action", content: "🛠️ Proposal #N rejected", status: "completed"}])
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

```
TodoWrite([{id: "action", content: "💡 Proposal #N deferred", status: "completed"}])
```

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  {id: "prereqs", status: "completed"},
  {id: "locate", status: "completed"},
  {id: "load", status: "completed"},
  {id: "parse", status: "completed"},
  {id: "classify", status: "completed"},
  {id: "action", status: "completed"}
])
```

---

# 7. Notes

- The decisions file is append-style: if a proposal already has a decision and the user issues a new one (e.g., un-rejecting via approve), append the new decision. The `run` skill uses the **most recent** decision entry for each proposal number.
- Proposal files in `experiments/` are never modified by this skill — they are read-only artifacts written by the proposer agent.
- If `experiments/proposals-decisions.json` becomes corrupted (invalid JSON), print an error and stop. Do NOT attempt to repair it automatically.
- The `/autoimprove run` skill reads `proposals-decisions.json` to load approved proposals before the Phase 2 experiment loop begins.

---

# 8. When NOT to Use

- **Starting a grind session** — use `/autoimprove run`. This skill only manages decisions; it does not execute experiments.
- **Generating proposals** — proposals are written by the proposer agent when the grind loop stagnates. You cannot draft proposals through this skill.
- **Viewing the experiment log** — use `/autoimprove history` to browse past experiments and verdicts.

---

# 9. Edge Cases

**Bulk approval**

To approve multiple proposals at once, issue separate `approve` commands for each. There is no `--all` flag — bulk approval bypasses the blocking-dependency check and is intentionally unsupported.

**Re-deciding a previously rejected proposal**

Decisions are append-only. To reverse a rejection, issue `approve <N>` — the new decision is appended and `run` uses the most recent entry. The prior rejection is preserved in the audit trail.

**Proposal file missing after decisions were recorded**

If `proposals-decisions.json` references a proposal file that no longer exists on disk, print a warning but do not fail:
```
Warning: source file for proposal #N not found on disk (experiments/proposals-2026-03-01.md).
Decision is preserved in proposals-decisions.json.
```

**Multiple proposal files with overlapping `#N` identifiers**

Use the most recent file's version (by file mtime or lexicographic sort descending). Print a notice if a conflict was resolved:
```
Note: Proposal #3 found in 2 files — using most recent (proposals-2026-03-25.md).
```

---

# 11. Common Failure Patterns

- **`proposals-decisions.json` rejected proposal prevents approval of a dependent:** The DAG enforcement in `approve` blocks proposals whose dependencies are rejected. If you want to approve a downstream proposal anyway, first un-reject the dependency (re-approve it) before approving the downstream one.
- **Proposal file exists but is not listed by `list`:** The file may not match the `experiments/proposals-*.md` glob pattern. Files with a non-standard prefix (e.g., `proposals_2026-03-01.md`) are silently skipped. Rename to match the expected pattern.
- **`proposals-decisions.json` is corrupted:** If the file contains invalid JSON (e.g., from a partial write), the skill prints an error and stops. Do NOT attempt to auto-repair it — open it in an editor, fix the JSON, and re-run.
- **All proposals are deferred and the run skill keeps generating new ones:** Deferred proposals accumulate without being resolved. Review them with `list` and either approve, reject, or update the deferral condition — otherwise the proposer will keep generating overlapping proposals.

---

# 10. Integration Notes

- **Phase 2 lifecycle**: stagnation detected by `run` → proposer agent writes `experiments/proposals-*.md` → human reviews via this skill → approved proposals are loaded by next `run` session.
- **Blocking graph**: proposals may declare dependencies on each other via the `Blocking:` field. The `approve` subcommand enforces this DAG — resolve dependencies bottom-up.
- **Deferred vs. rejected**: defer when the proposal is valid but the timing is wrong (e.g., blocked by in-flight work). Reject when the proposal direction is wrong or too risky. The `run` skill skips both deferred and rejected proposals.
- **Approved proposals auto-expire**: if an approved proposal is not executed within `budget.max_experiments_per_session` sessions, it is treated as deferred. This prevents stale proposals from blocking future Phase 2 cycles.
- **`/autoimprove run --phase propose`**: Forces the proposer agent to run immediately, even if the stagnation window has not been reached. Use this when you want to manually trigger Phase 2 planning.

---

# Notes

- The `proposals` skill is the human-in-the-loop gate for Phase 2. Phase 1 (grind loop) is fully automated; Phase 2 only proceeds on human approval via this skill.
- Proposal files in `experiments/` are never modified by this skill — they are read-only. The decisions are stored separately in `proposals-decisions.json`.
- Each proposal file contains the proposer agent's reasoning, suggested scope, and expected metric impact. Read the full file (not just the title) before approving large-scope proposals.
