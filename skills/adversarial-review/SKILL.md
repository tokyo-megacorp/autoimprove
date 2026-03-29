---
name: adversarial-review
description: "Run an adversarial Enthusiast→Adversary→Judge debate review on code. Automatically converges — no manual round control needed. Use when the user says 'adversarial review', 'debate review', 'run a review round', 'do a review round', 'review code with debate agents', 'i want an adversarial review', or '/autoimprove review'. Do NOT trigger on generic 'review' requests or PR reviews. Takes a file, diff, or PR as target."
argument-hint: "[file|diff]"
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

<SKILL-GUARD>
You are NOW executing the adversarial-review skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Run the Enthusiast → Adversary → Judge debate cycle on the given target.

---

# 1. Parse Arguments

From the user's input, extract:
- **target**: file path, glob pattern, or "diff" (meaning staged/unstaged git diff)

The skill always runs until deterministic convergence, with an internal safety cap of 10 rounds.
The goal is to surface all issues — stop only when the debate has genuinely stabilized.

---

# 2. Gather Target Code

Read the target code into a variable to pass to agents.

**If target is a file path or glob:**
Read the file(s) using Read tool. Concatenate with file headers.

**If target is "diff":**
```bash
git diff HEAD
```
If empty, try `git diff --staged`. If still empty, tell the user: "Nothing to review — both working tree and staging area are clean. Try: `git diff <branch>`, `git diff HEAD~1`, `/autoimprove review <file>`, or stage some changes first."

Store the result as `TARGET_CODE`.

---

# 2.5. Initialize Telemetry Run

Before the first round, set up a private run folder to capture this debate for the
self-improvement loop.

**Generate a run ID:**
- Format: `YYYYMMDD-HHMMSS-<target-slug>` where `target-slug` is the basename of the
  target (or `"diff"` for diff targets), lowercased, non-alphanumeric chars → `-`, max 40 chars.
- Example: `20260327-103045-retrieve-prefetch-design`

**Create the run folder:**
```bash
mkdir -p ~/.autoimprove/runs/<RUN_ID>
```

**Write initial `meta.json`:**
```json
{
  "run_id": "<RUN_ID>",
  "target": "<target path or diff>",
  "date": "<ISO timestamp>",
  "rounds_planned": 10,
  "rounds_completed": 0,
  "converged_at_round": null,
  "status": "running",
  "model": "claude-sonnet-4-6"
}
```

Store `RUN_ID` and `RUN_DIR=~/.autoimprove/runs/<RUN_ID>` for use in later steps.
If the directory cannot be created (permissions, disk full), log a warning and continue —
telemetry failure must never block the review.

---

# 3. Run Debate Rounds

Loop: run rounds until **deterministic convergence** is reached or `max_rounds` is hit.

- Start at round 1; increment after each complete round.
- Stop early when `converged = true` (deterministic check, section 3d). Record `converged_at_round`.
- Stop when `round > max_rounds`. Log: `"Safety cap reached at round <N> — stopping."` if the safety cap (10) triggered without convergence.
- Never stop just because the Judge self-reports `convergence: true` — the deterministic check is the only valid stop signal.

For each round:

## 3a. Spawn Enthusiast

Use the Agent tool to spawn the `enthusiast` agent:

```
Prompt: Review the following code and find all issues.

<code>
{TARGET_CODE}
</code>

{If round > 1: "Prior round findings and rulings: {PRIOR_ROUND_OUTPUT}. Focus on what was MISSED — do not repeat prior findings."}

Output your findings as a single JSON object matching the schema. Nothing else.
```

**Validate output**: Parse the Enthusiast's response as JSON.
- If valid JSON with a non-empty `findings` array → store as `ENTHUSIAST_OUTPUT` and continue.
- If invalid JSON → re-prompt once: `"Your previous response was not valid JSON. Return only the corrected JSON object — no prose, no markdown fences."` Re-parse. If still invalid → log `enthusiast_malformed_json` for this round, skip to next round (or abort if only round).
- If valid JSON but `findings` is empty → note "Enthusiast found no issues" and skip 3b/3c for this round; proceed to 3e.

## 3b. Spawn Adversary

Use the Agent tool to spawn the `adversary` agent:

```
Prompt: Review the Enthusiast's findings and challenge them.

<code>
{TARGET_CODE}
</code>

<findings>
{ENTHUSIAST_OUTPUT}
</findings>

Output your verdicts as a single JSON object matching the schema. Nothing else.
```

**Validate output**: Parse the Adversary's response as JSON.
- If valid JSON with a `verdicts` array → store as `ADVERSARY_OUTPUT` and continue.
- If invalid JSON → re-prompt once with the same correction instruction. If still invalid → log `adversary_malformed_json`, pass `{"verdicts": []}` as the adversary input to the Judge (all findings treated as uncontested via Judge's missing-verdicts edge case).

## 3c. Spawn Judge

Use the Agent tool to spawn the `judge` agent:

```
Prompt: Arbitrate between the Enthusiast and Adversary.

<code>
{TARGET_CODE}
</code>

<findings>
{ENTHUSIAST_OUTPUT}
</findings>

<verdicts>
{ADVERSARY_OUTPUT}
</verdicts>

{If round > 1: "Your prior round rulings: {PRIOR_JUDGE_OUTPUT}. Set convergence: true if your rulings this round are identical to last round."}

Output your rulings as a single JSON object matching the schema. Nothing else.
```

**Validate output**: Parse the Judge's response as JSON.
- If valid JSON with a `rulings` array → store as `JUDGE_OUTPUT` and continue.
- If invalid JSON → re-prompt once. If still invalid → log `judge_malformed_json`, record all findings as `status: unresolved`, and end the debate loop.

## 3d. Check Convergence

Convergence is only meaningful from round 2 onward.

**Deterministic check (orchestrator-side):** When `round > 1`, compute convergence independently by comparing this round's rulings to the prior round's rulings:
- Extract the set of `(finding_id, winner, final_severity)` tuples from both rounds
- If the sets are identical (same IDs, same winners, same severities in any order) → `converged = true`
- This overrides whatever the Judge reported

**LLM check (supplemental):** Also check what the Judge reported. If Judge says `convergence: true` but the deterministic check says `false`, log: `"Judge reported convergence but rulings differ — continuing."` and continue.

**Round 1 guard:** If `round == 1` and Judge returned `convergence: true` → treat as `false`. Log: `"convergence: true ignored on round 1."` Continue to round 2.

**Stop condition:** Stop the loop early when `converged = true` (deterministic). Record `converged_at_round = round`.

## 3e. Store Round

Accumulate round results into `ROUNDS` array.

Write an incremental round file to the telemetry run folder (if `RUN_DIR` is set):

**`$RUN_DIR/round-<N>.json`:**
```json
{
  "round": <N>,
  "run_id": "<RUN_ID>",
  "enthusiast": <ENTHUSIAST_OUTPUT>,
  "adversary": <ADVERSARY_OUTPUT>,
  "judge": <JUDGE_OUTPUT>,
  "errors": ["enthusiast_malformed_json" | "adversary_malformed_json" | "judge_malformed_json"],
  "converged": <true|false>
}
```

Omit the `errors` key if the array is empty. This file is written after every round so
a partial run is recoverable even if the session is interrupted.

---

# 4. Format Output

After all rounds complete, present results to the user:

```
## Debate Review — {target} ({total_rounds} round(s){if converged: ", converged at round N"})

### Confirmed Findings

{For each finding where judge ruled winner=enthusiast or winner=split:}
- **{severity}** [{file}:{line}] {resolution}

### Debunked Findings

{For each finding where judge ruled winner=adversary:}
- ~~{description}~~ — {adversary reasoning}

### Unresolved Findings

{If any findings have status: unresolved (judge_malformed_json occurred):}
- **{severity}** [{file}:{line}] {description} *(unresolved — judge output was malformed)*

{If no unresolved findings: omit this section entirely}

### Summary

{Judge's final summary}
{If converged: "Debate converged at round {N}."}
{If any malformed_json errors: "Warning: {N} round(s) had agent output errors — results may be incomplete."}
```

Also output the full structured JSON using the `run.json` shape — confirmed and debunked
as flat arrays, each entry tagged with the round it was discovered in:

```json
{
  "total_rounds": 4,
  "converged_at_round": null,
  "confirmed": [
    { "id": "F2", "severity": "critical", "winner": "adversary", "round": 1, "file": "src/example.ts", "line": 42, "source": "enthusiast", "resolution": "..." }
  ],
  "debunked": [
    { "id": "F4", "round": 1, "reason": "..." }
  ],
  "by_severity": { "critical": 1, "high": 5, "medium": 11, "low": 9 }
}
```

---

# 4.5. Write Telemetry

After formatting output, finalize the run folder (if `RUN_DIR` is set).

**Write `$RUN_DIR/run.json`** — the complete structured run for downstream use:
```json
{
  "run_id": "<RUN_ID>",
  "meta": {
    "target": "<path or diff>",
    "date": "<ISO timestamp>",
    "rounds_planned": <N>,
    "rounds_completed": <actual>,
    "converged_at_round": <N or null>,
    "model": "claude-sonnet-4-6",
    "judge_llm_convergence_mismatches": <count of rounds where judge said converged but deterministic check disagreed>
  },
  "rounds": [ <ROUNDS array> ],
  "confirmed": [
    { "id": "F1", "severity": "high", "winner": "adversary", "round": 1, "file": "src/example.ts", "line": 42, "source": "enthusiast", "resolution": "...", "edit_instruction": "..." }
  ],
  "debunked": [
    { "id": "F4", "round": 1, "reason": "..." }
  ],
  "final_summary": "<Judge's last summary string>",
  "total_rounds": <N>,
  "converged_at_round": <N or null>
}
```

**Update `$RUN_DIR/meta.json`** with final stats:
```json
{
  "run_id": "<RUN_ID>",
  "target": "<path or diff>",
  "date": "<ISO timestamp>",
  "rounds_planned": <N>,
  "rounds_completed": <actual>,
  "converged_at_round": <N or null>,
  "status": "complete",
  "model": "claude-sonnet-4-6",
  "total_findings": <confirmed + debunked>,
  "confirmed": <count>,
  "debunked": <count>,
  "by_severity": { "critical": 0, "high": 0, "medium": 0, "low": 0 },
  "judge_llm_convergence_mismatches": <count>
}
```

**Write `$RUN_DIR/report.md`** — human-readable summary of the run:

````markdown
# Adversarial Review Report

**Run:** {RUN_ID}  
**Target:** {target}  
**Date:** {date}  
**Rounds:** {rounds_completed}{if converged: " (converged at round {converged_at_round})"} | **Model:** {model}

## Confirmed Findings

| Sev | ID | File:Line | Finding | Edit Instruction |
|-----|----|-----------|---------|-----------------|
{For each confirmed finding (winner=enthusiast or winner=split):}
| {final_severity} | {finding_id} | {file}:{line} | {resolution} | {edit_instruction} |

{If no confirmed findings: output row: | — | — | — | No confirmed findings. | — |}

## Dismissed / Debunked

| ID | Finding | Reason |
|----|---------|--------|
{For each dismissed finding (winner=adversary):}
| {finding_id} | {description} | {resolution} |

{If no dismissed findings: output row: | — | No dismissed findings. | — |}

## Round Trail

{For each round N:}
### Round {N}
- Enthusiast: {count} findings
- Confirmed: {comma-separated list of "ID (severity)" for enthusiast/split rulings}
- Debunked: {comma-separated list of IDs for adversary rulings}

## Sources

| Agent | Role | Rounds active |
|-------|------|---------------|
| Enthusiast | Finding generation | All rounds |
| Adversary | Challenge / debunk | All rounds |
| Judge | Final arbitration | All rounds |

{List any per-finding source attribution: for each confirmed finding with source != null, note the agent. If all findings come from "enthusiast", a single line suffices: "All confirmed findings were sourced from the Enthusiast agent."}
````

Generate this file from the final `run.json` data. If `RUN_DIR` is not set, skip silently.

---

**Print the run folder path** at the end of the output:
```
📁 Run saved: ~/.autoimprove/runs/<RUN_ID>/
```

This is the last line of output — it should appear after the structured JSON dump and the Self-Assessment section.

**Write Self-Assessment section** immediately before the run folder path line:

```markdown
## Self-Assessment
- Model used: [opus/sonnet/haiku]
- Could cheaper model have done this? [1=definitely haiku, 2=probably haiku, 3=toss-up, 4=probably needed this tier, 5=this tier was essential]
- Reason: [1 sentence]
```

Populate each field honestly:
- **Model used**: the model executing this review (e.g. `sonnet`, `opus`, `haiku`)
- **Could cheaper model have done this?**: score 1–5 based on actual complexity of the target reviewed. Simple config files, small diffs, single-function changes → lean toward 1–2. Complex architectural code, multi-file refactors, security-sensitive logic → lean toward 4–5. Be honest — this data feeds the model-selection calibration loop.
- **Reason**: one sentence explaining the score (e.g. "The target was a 12-line config change with no logic complexity — haiku handles this easily.").

Also persist the self-assessment in `$RUN_DIR/meta.json` under a `self_assessment` key:
```json
"self_assessment": {
  "model_used": "sonnet",
  "cheaper_model_score": 2,
  "reason": "Small config diff with no architectural complexity."
}
```

---

# 5. Notes

- Each agent is spawned with `model: sonnet` for cost efficiency.
- The review skill NEVER influences keep/discard decisions in the autoimprove loop. It is advisory only.
- Total token budget: the orchestrator should track approximate token usage. If approaching session limits, warn the user.
