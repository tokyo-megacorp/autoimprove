---
name: adversarial-review
description: "Run an adversarial Enthusiast→Adversary→Judge debate review on code. Automatically converges — no manual round control needed. Use when the user says 'adversarial review', 'debate review', 'run a review round', 'do a review round', 'review code with debate agents', 'i want an adversarial review', or '/autoimprove review'. Do NOT trigger on generic 'review' requests or PR reviews. Takes a file, diff, or PR as target."
argument-hint: "[file|diff]"
allowed-tools: [Read, Glob, Grep, Bash, Agent, TodoWrite]
---

<SKILL-GUARD>
You are NOW executing the adversarial-review skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

# MANDATORY CHAIN: E → A → J

**This chain is not interpretable. Follow each numbered step exactly. No step may be skipped, reordered, or improvised.**

Agents are loaded via `subagent_type` — do NOT inline their prompts or improvise their logic.

---

# STEP 0 — ADAPTIVE MODE DETECTION

Measure target size first. Mode gates max rounds and prompt depth.

- Diff target: `git diff HEAD | wc -l` (or `--staged`).
- File/glob target: count lines via Read/Glob.

| Condition | MODE | MAX_ROUNDS |
|-----------|------|------------|
| Single file OR diff ≤ 150 lines | `LIGHTWEIGHT` | 3 |
| Multi-file OR diff > 150 lines | `FULL` | 10 |

Log: `"[AR] Mode: {MODE} ({N} lines, max_rounds: {MAX_ROUNDS})"`

---

# STEP 1 — GATHER TARGET CODE

Target is: file path, glob, or `"diff"`.

- File/glob: use Read/Glob, concatenate with `=== {filepath} ===` headers.
- Diff: `git diff HEAD` (fallback: `git diff --staged`). If empty: stop and inform user.

Store as `TARGET_CODE`. If empty: stop — nothing to review.

---

# STEP 2 — INITIALIZE RUN

**Generate run ID:** `YYYYMMDD-HHMMSS-<target-slug>` (basename, lowercased, non-alnum → `-`, max 40 chars).

```bash
mkdir -p ~/.autoimprove/runs/<RUN_ID>
```

Store: `RUN_ID`, `RUN_DIR=~/.autoimprove/runs/<RUN_ID>`.

**Write `$RUN_DIR/meta.json`:**
```json
{ "run_id": "<RUN_ID>", "target": "<target>", "date": "<ISO>", "mode": "<MODE>", "max_rounds": <N>, "rounds_completed": 0, "status": "running" }
```

**Initialize state:**
```
ROUND = 1
ROUNDS = []
CONFIRMED_LOCATIONS = []   # (file, line) tuples from enthusiast/split rulings
PRIOR_JUDGE_OUTPUT = null
PRIOR_JUDGE_SUMMARY = null
ROUND_YIELDS = []
ROUND_MODEL = "haiku"
MODEL_LADDER = ["haiku", "sonnet", "opus"]
converged = false
```

**Init todos:**
```
TodoWrite([
  {id: "enthusiast", content: "🔍 Enthusiast — surface findings", status: "pending"},
  {id: "adversary",  content: "⚔️ Adversary — challenge findings", status: "pending"},
  {id: "judge",      content: "⚖️ Judge — rule on debate",         status: "pending"}
])
```

---

# STEP 3 — DEBATE LOOP

Repeat STEP 3A → 3B → 3C → 3D until `converged = true` or `ROUND > MAX_ROUNDS`.

**ORDERING RULE (non-negotiable):** 3A must fully complete before 3B starts. 3B must fully complete before 3C starts. No parallel dispatch. No skipping.

---

## STEP 3A — ENTHUSIAST (MANDATORY)

**Compliance pre-check:** If `ROUND > MAX_ROUNDS`, exit loop immediately.

Mark todo: `{id: "enthusiast", status: "in_progress"}`.

**Build CONFIRMED_LOCATIONS list** (round > 1 only):
Extract `(file, line)` from all prior rulings where `winner` = `"enthusiast"` or `"split"`. Format: `"src/foo.ts:42, src/bar.ts:17"`.

**Dispatch — use EXACTLY this Agent call:**
```
Agent(
  subagent_type: "autoimprove:enthusiast",
  model: ROUND_MODEL,
  prompt: "[AR Round {ROUND} — {MODE}] Review the code below. Output ONLY valid JSON per your schema.
<code>{TARGET_CODE}</code>
{IF round>1: "BLOCKLIST (do not re-raise): {CONFIRMED_LOCATIONS}\nPrior summary: {PRIOR_JUDGE_SUMMARY}\nFind issues NOT in the blocklist only."}"
)
```

**Validate output (MANDATORY — do not skip):**
1. Parse response as JSON.
2. If invalid JSON → re-prompt once: `"Return only the corrected JSON object — no prose, no fences."` Re-parse.
3. If still invalid → log `enthusiast_malformed_json`, skip 3B and 3C, go to 3D with `findings: []`.
4. If round == 1 and response ≤ 50 chars → re-prompt once: `"Response appears truncated. Return full JSON."` If still ≤ 50 chars → log `enthusiast_sparse_output`, treat as `findings: []`.
5. Store as `ENTHUSIAST_OUTPUT`.

**Pre-adversary dedup:**
- Extract `(file, line)` from each new finding.
- Match against `CONFIRMED_LOCATIONS` where same file AND `|new_line - confirmed_line| <= 5`.
- Split into `NOVEL_FINDINGS` (no match) and `DUPLICATE_FINDINGS` (matched).
- If duplicates exist: log `"Auto-dismissed {N} duplicate(s): {locations}"`.
- Replace `ENTHUSIAST_OUTPUT.findings` with `NOVEL_FINDINGS`.
- If `NOVEL_FINDINGS` is empty: skip 3B and 3C, go to 3D (convergence path).

Mark todo complete: `{id: "enthusiast", content: "🔍 AR Round {ROUND}: Enthusiast — {NOVEL_FINDINGS.length} findings", status: "completed"}`.

---

## STEP 3B — ADVERSARY (MANDATORY after 3A produces findings)

**Compliance pre-check:** `ENTHUSIAST_OUTPUT` must exist and `NOVEL_FINDINGS.length > 0`. If not, skip to 3D.

Mark todo: `{id: "adversary", content: "⚔️ AR Round {ROUND}: Adversary — challenging {NOVEL_FINDINGS.length} findings", status: "in_progress"}`.

**Dispatch — use EXACTLY this Agent call:**
```
Agent(
  subagent_type: "autoimprove:adversary",
  model: ROUND_MODEL,
  prompt: "[AR Round {ROUND} — {MODE}] Challenge the findings. Output ONLY valid JSON per your schema.
<code>{TARGET_CODE}</code>
<findings>{ENTHUSIAST_OUTPUT with NOVEL_FINDINGS only}</findings>
Healthy challenge rate: 15–25%. Validating 100% without pushback = insufficient scrutiny."
)
```

**Validate output (MANDATORY):**
1. Parse response as JSON.
2. If invalid → re-prompt once. If still invalid → log `adversary_malformed_json`, use `{"verdicts": []}` (all findings uncontested).
3. Store as `ADVERSARY_OUTPUT`.

**Compliance check:** `ADVERSARY_OUTPUT.verdicts` must contain one entry per finding in `NOVEL_FINDINGS`. If count mismatches: log `"adversary_verdict_count_mismatch: expected {N}, got {M}"` — proceed anyway.

Mark todo: `{id: "adversary", content: "⚔️ AR Round {ROUND}: Adversary — {challenged_count} challenged", status: "completed"}` where `challenged_count` = verdicts where verdict != "valid".

---

## STEP 3C — JUDGE (MANDATORY after 3B)

**Compliance pre-check:** Both `ENTHUSIAST_OUTPUT` and `ADVERSARY_OUTPUT` must exist. If not, log `judge_skipped_missing_inputs` and go to 3D.

Mark todo: `{id: "judge", content: "⚖️ AR Round {ROUND}: Judge — ruling on debate", status: "in_progress"}`.

**Dispatch — use EXACTLY this Agent call:**
```
Agent(
  subagent_type: "autoimprove:judge",
  model: ROUND_MODEL,
  prompt: "[AR Round {ROUND} — {MODE}] Arbitrate. Output ONLY valid JSON per your schema.
<code>{TARGET_CODE}</code>
<findings>{ENTHUSIAST_OUTPUT}</findings>
<verdicts>{ADVERSARY_OUTPUT}</verdicts>
{IF round>1: "Prior rulings: {PRIOR_JUDGE_OUTPUT}\nSet convergence:true only if ALL (file,line,winner,final_severity) tuples match prior round."}
{IF MODE==FULL: "Set next_round_model='sonnet' if: security findings, critical/high multi-file, 0% debunk rate, or strong E/A disagreement. Otherwise 'haiku'."}"
)
```

**Validate output (MANDATORY):**
1. Parse response as JSON.
2. If invalid → re-prompt once. If still invalid → log `judge_malformed_json`, mark all findings as `status: unresolved`, exit loop.
3. Store as `JUDGE_OUTPUT`.

**Compliance check:** `JUDGE_OUTPUT.rulings` must have one entry per `NOVEL_FINDINGS`. If count mismatches: log `"judge_ruling_count_mismatch: expected {N}, got {M}"`.

**Count results:** `confirmed_count` = rulings where winner ∈ {enthusiast, split}; `debunked_count` = rulings where winner = adversary.

Mark todo: `{id: "judge", content: "⚖️ AR Round {ROUND}: Judge — {confirmed_count} confirmed, {debunked_count} debunked", status: "completed"}`.

**Update state:**
- Append confirmed `(file, line)` tuples to `CONFIRMED_LOCATIONS`.
- Store `PRIOR_JUDGE_OUTPUT = JUDGE_OUTPUT`.
- Store `PRIOR_JUDGE_SUMMARY = JUDGE_OUTPUT.summary`.

**Model escalation (FULL mode only):**
- Path A (anomaly): if any `*_malformed_json` logged this round → `ROUND_MODEL = "sonnet"`.
- Path B (judge recommendation): use `JUDGE_OUTPUT.next_round_model` (default `"haiku"`).
- Path A takes priority over Path B.
- If `ROUND_MODEL == "sonnet"` for 3+ consecutive rounds: log `"[COST WARNING] Sonnet active 3 consecutive rounds."`

**Write `$RUN_DIR/round-{ROUND}.json`:** `{round, run_id, model, enthusiast, adversary, judge, errors, converged}` — omit `errors` if empty.

---

## STEP 3D — CONVERGENCE CHECK

**Append** `NOVEL_FINDINGS.length` to `ROUND_YIELDS`.

**Empty-findings shortcut:** If `NOVEL_FINDINGS.length == 0` this round → `converged = true`.

**Deterministic check (round > 1, when findings exist):**
- Extract `(file, line, winner, final_severity)` tuples from this round's rulings AND prior round's rulings.
- Apply ±5-line tolerance: normalize each tuple to its cluster's lowest line.
- For `file: null` findings: use `(null, first-60-chars-of-resolution, winner, final_severity)`.
- If normalized sets are identical → `converged = true`.
- If Judge reported `convergence: true` but deterministic check says false: log `"Judge convergence overridden by deterministic check."` and continue.
- Round 1 guard: if `ROUND == 1` and Judge returned `convergence: true` → override to `false`. Log: `"convergence: true ignored on round 1."`.

**Near-convergence escalation (FULL mode only):**
```
current_yield = ROUND_YIELDS[-1]
prev_yield = ROUND_YIELDS[-2] if len >= 2 else null

near_convergence = current_yield <= 2 AND prev_yield != null AND current_yield < prev_yield * 0.4

if converged OR near_convergence:
  if ROUND_MODEL == "opus": converged = true (final stop)
  else:
    next_model = MODEL_LADDER[MODEL_LADDER.index(ROUND_MODEL) + 1]
    ROUND_MODEL = next_model
    converged = false
    Log: "Round {N}: escalating to {next_model} (yield={current_yield})"
    Re-emit todos as pending for round {N+1}
```

**Increment:** `ROUND += 1`.

**Loop decision:** If `converged = true` OR `ROUND > MAX_ROUNDS` → exit loop. Otherwise → go to STEP 3A.

---

# STEP 4 — FORMAT OUTPUT

```
## Debate Review — {target} ({total_rounds} rounds{if converged: ", converged at round N"})
### Confirmed Findings
{For each winner ∈ {enthusiast, split}: - **{severity}** [{file}:{line}] {resolution}}
### Debunked Findings
{For each winner=adversary: - ~~{description}~~ — {adversary reasoning}}
### Unresolved Findings (if judge_malformed_json occurred)
### Summary
{JUDGE_OUTPUT.summary} | {if converged: "Converged at round N."} | {if errors: "Warning: N round(s) had agent errors."}
```

Structured JSON: `{"total_rounds": N, "converged_at_round": null, "confirmed": [...], "debunked": [...], "by_severity": {"critical": 0, "high": 0, "medium": 0, "low": 0}}`

**Self-Assessment:**
```
## Self-Assessment
- Mode: [LIGHTWEIGHT|FULL] | Model: [haiku|sonnet|opus]
- Could cheaper model have done this? [1=definitely haiku … 5=this tier essential]
- Reason: [1 sentence]
```

---

# STEP 5 — WRITE TELEMETRY

Non-fatal — skip silently if `RUN_DIR` is unset or any write fails.

- `$RUN_DIR/run.json` — full structured run (all rounds + confirmed + debunked + meta)
- `$RUN_DIR/meta.json` — update with final stats (`status: "complete"`, counts, `by_severity`)
- `$RUN_DIR/report.md` — markdown table of confirmed findings

Print last: `📁 Run saved: ~/.autoimprove/runs/<RUN_ID>/`

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  {id: "enthusiast", status: "completed"},
  {id: "adversary", status: "completed"},
  {id: "judge", status: "completed"}
])
```

---

# COMPLIANCE RULES

| Rule | Violation action |
|------|-----------------|
| 3A before 3B | Adversary dispatched without ENTHUSIAST_OUTPUT → abort, re-run from 3A |
| 3B before 3C | Judge dispatched without ADVERSARY_OUTPUT → log error, use `{"verdicts": []}` |
| Each agent uses exact subagent_type | `autoimprove:enthusiast` / `autoimprove:adversary` / `autoimprove:judge` |
| Output validated before passing forward | Invalid → one re-prompt → fallback (never skip validation) |
| Convergence = deterministic check only | Judge self-report overridden when it disagrees |
| Round 1 convergence = always false | No exception |

**Background execution:** This skill executes E→A→J inline — never re-dispatches itself. Caller wanting non-blocking AR: `Agent(run_in_background: true, prompt: "Invoke Skill('autoimprove:adversarial-review', args: '...')")` — no `subagent_type`.
