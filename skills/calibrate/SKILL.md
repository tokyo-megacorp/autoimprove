---
name: calibrate
description: "Run cross-model calibration for autoimprove skills — compare Opus (gold standard) vs Haiku (cheap) on the same input to identify reasoning gaps. Use when the user says '/calibrate', 'calibrate skill', 'model calibration', or 'calibration gap'. Phase 1: hardcoded for adversarial-review only."
argument-hint: "adversarial-review <file|diff|pr NUMBER>"
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

<SKILL-GUARD>
You are NOW executing the calibrate skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Run cross-model calibration: compare Opus (gold standard) vs Haiku (cheap) on the same adversarial-review input to surface reasoning gaps and actionable prompt improvements.

---

# Step 1: Parse Arguments

From the user's input or the skill arguments, extract:
- `SKILL_NAME`: the skill to calibrate (e.g., `adversarial-review`)
- `INPUT`: file path, `"diff"`, or a PR number

**Phase 1 gate:** If SKILL_NAME is NOT `adversarial-review`, output this message and stop:

```
Phase 1 calibration only supports `adversarial-review`. Generic skill wrapping is deferred to Phase 2.
```

If no SKILL_NAME is provided, default to `adversarial-review`.

---

# Step 2: Gather Target Input

Collect the content to review and store as TARGET_INPUT.

**If INPUT is "diff" or empty:**
- Run `git diff HEAD` in the repo directory
- If that returns nothing, fall back to `git diff --staged`
- If still empty, output: "Nothing to calibrate — working tree and staging area are clean." and stop.

**If INPUT is a file path:**
- Read the file content
- If file does not exist, output: "File not found: {INPUT}" and stop.

**If INPUT is a PR number:**
- Validate INPUT matches `^[0-9]+$` — if not numeric, output: "Invalid PR number: {INPUT}" and stop.
- Run `gh pr diff {INPUT}` to fetch the PR diff

Store the gathered content as TARGET_INPUT.

---

# Step 3: Run AR with Opus and Haiku in PARALLEL

CRITICAL: Do NOT call `Skill('autoimprove:adversarial-review')` — nested skill invocation does not support model override. Instead, spawn two agents with the AR steps inlined.

Spawn the following two agents **in parallel** (both at the same time):

## Agent 1 — Opus (gold standard)

```
model: claude-opus-4-6
prompt: |
  UNBREAKABLE_RULES apply — rules are in ~/.claude/UNBREAKABLE_RULES.md and are non-negotiable.

  You are running an adversarial-style code review. Your job is to find ALL real issues in the following code or diff.

  <target>
  {TARGET_INPUT}
  </target>

  For each issue you find, produce a JSON finding. Be thorough and evidence-based — cite the exact code or reasoning behind each finding.

  Output ONLY the following JSON structure, nothing else:

  {
    "findings": [
      {
        "id": "F1",
        "severity": "critical|high|medium|low",
        "description": "clear, specific description of the issue",
        "evidence": "exact code snippet or reasoning that proves this is an issue",
        "file": "path/to/file or null",
        "line": 42
      }
    ]
  }

  If there are no issues, output: { "findings": [] }
```

## Agent 2 — Haiku (cheap candidate)

```
model: claude-haiku-4-5-20251001
prompt: |
  UNBREAKABLE_RULES apply — rules are in ~/.claude/UNBREAKABLE_RULES.md and are non-negotiable.

  You are running an adversarial-style code review. Your job is to find ALL real issues in the following code or diff.

  <target>
  {TARGET_INPUT}
  </target>

  For each issue you find, produce a JSON finding. Be thorough and evidence-based — cite the exact code or reasoning behind each finding.

  Output ONLY the following JSON structure, nothing else:

  {
    "findings": [
      {
        "id": "F1",
        "severity": "critical|high|medium|low",
        "description": "clear, specific description of the issue",
        "evidence": "exact code snippet or reasoning that proves this is an issue",
        "file": "path/to/file or null",
        "line": 42
      }
    ]
  }

  If there are no issues, output: { "findings": [] }
```

Collect outputs as OPUS_RESULT and HAIKU_RESULT.

---

# Step 4: Run Sonnet Evaluator

Spawn a Sonnet agent to compare the two outputs:

```
model: claude-sonnet-4-5
prompt: |
  You are a calibration evaluator comparing Opus (gold standard) and Haiku outputs for adversarial code review.

  ## Opus Output (gold standard)
  {OPUS_RESULT}

  ## Haiku Output (candidate)
  {HAIKU_RESULT}

  Evaluate the quality gap across four dimensions:
  1. What did Opus find that Haiku MISSED? (false negatives — Haiku's blind spots)
  2. What did Haiku flag that Opus dismissed? (false positives — noise Haiku adds)
  3. Where did Haiku findings lack depth or evidence compared to Opus?
  4. What specific, targeted prompt changes would close the gap?

  DEDUPLICATION: Before comparing, normalize findings semantically. Two findings describing the same issue with different wording count as ONE match — do not inflate missed_by_haiku with duplicates.

  IMPORTANT: The gap_score is diagnostic only. It must NEVER be used as a benchmark metric or to trigger automated grind loops.

  Output ONLY this JSON, nothing else:
  {
    "gap_score": <integer 0-10, where 0=identical quality and 10=completely different>,
    "haiku_find_rate": <float 0.0-1.0, fraction of Opus findings that Haiku also found>,
    "missed_by_haiku": [
      {
        "finding_id": "F1",
        "severity": "critical|high|medium|low",
        "description": "what was missed",
        "why_matters": "why this miss is significant"
      }
    ],
    "false_positives_haiku": [
      {
        "description": "what Haiku flagged",
        "reason_dismissed_by_opus": "why Opus correctly dismissed it"
      }
    ],
    "depth_gaps": [
      {
        "finding": "brief description of the finding",
        "opus_evidence": "what Opus cited",
        "haiku_evidence": "what Haiku cited",
        "gap": "what depth or specificity is missing from Haiku"
      }
    ],
    "prompt_improvements": [
      {
        "target": "agents/enthusiast.md OR agents/adversary.md OR agents/judge.md",
        "improvement": "specific text to add or change — be precise",
        "reason": "this addresses the gap because..."
      }
    ],
    "summary": "<one sentence: overall quality gap between Opus and Haiku>"
  }
```

Store result as GAP_REPORT.

**If Sonnet output is not valid JSON** (malformed, wrapped in fences, truncated): re-prompt once with: "Your response was not valid JSON. Return only the corrected JSON object, no markdown fences." If still invalid, store a signal with `tags: ['signal:calibration', 'error:evaluator-malformed']` and output: "Calibration aborted — evaluator returned malformed JSON. Raw output logged." then stop.

---

# Step 5: Display Gap Report

Parse GAP_REPORT and render the following output:

```
## Calibration Report — adversarial-review

**Gap Score:** {gap_score}/10  (target: <3)
**Haiku Find Rate:** {haiku_find_rate * 100}%  (target: ≥80%)

### Missed by Haiku ({count} findings)
{for each missed finding:}
  - [{SEVERITY}] {description} — {why_matters}

### False Positives from Haiku ({count})
{for each false positive:}
  - {description} — dismissed because: {reason_dismissed_by_opus}

### Depth Gaps ({count})
{for each depth gap:}
  - **{finding}**
    - Opus: {opus_evidence}
    - Haiku: {haiku_evidence}
    - Gap: {gap}

### Prompt Improvements Recommended ({count})
{for each improvement:}
  - **Target:** {target}
    **Change:** {improvement}
    **Reason:** {reason}

### Summary
{summary}

---
*Results are diagnostic only. gap_score is NOT a benchmark metric.*
```

---

# Step 6: Store LCM Signal

Store the calibration result for trend tracking and the autoimprove learning loop.

**If the `lcm_store` MCP tool is available**, call it with:
```
tags: ['signal:calibration', 'skill:adversarial-review', 'model:opus-vs-haiku', 'calibration:signal-only']
content: |
  gap_score: {gap_score}
  haiku_find_rate: {haiku_find_rate}
  missed_by_haiku_count: {count}
  false_positives_count: {count}
  prompt_improvements_count: {count}
  summary: {summary}
```

**If lcm_store is NOT available**, write the result to `~/.autoimprove/calibration/` as a dated JSON file:
- Create the directory if it does not exist: `mkdir -p ~/.autoimprove/calibration`
- Write file: `~/.autoimprove/calibration/{YYYY-MM-DD}-ar-calibration.json`
- Content: full GAP_REPORT JSON

---

## CRITICAL Goodhart Boundary

- The `gap_score` field is DIAGNOSTIC ONLY.
- It MUST NEVER be added to `autoimprove.yaml` benchmarks.
- It MUST NEVER be used as a grind loop metric or to influence theme selection weights.
- The experimenter sees: "your prompt needs improvement at X because of Y structural reason."
- The experimenter does NOT see numeric gap trends in the benchmark pipeline.
