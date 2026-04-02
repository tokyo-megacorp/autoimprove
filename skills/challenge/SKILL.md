---
name: challenge
description: "Use when testing debate agent bug-finding accuracy against curated code challenges — F1 scoring, 'test debate agents on challenges', 'benchmark agents'. Examples:

<example>
Context: User wants to measure how accurately agents find bugs.
user: \"test debate agents on the challenge suite\"
assistant: I'll use the challenge skill to score agents with F1 metrics.
<commentary>Testing agent accuracy — challenge skill, not prompt-testing.</commentary>
</example>

<example>
Context: User wants F1 scores on a language subset.
user: \"benchmark agents on python challenges\"
assistant: I'll use the challenge skill to score agents on the Python suite.
<commentary>Benchmarking with filter — challenge skill.</commentary>
</example>

Do NOT use for writing tests for skills/agents (use prompt-testing instead)."
argument-hint: "[--suite puzzles|all] [--language python|typescript|go|rust|all] [--difficulty easy|medium|hard|all] [--tags <tag>] [--id <challenge-id>] [--dry-run]"
allowed-tools: [Read, Bash, Glob, Grep, Agent]
---

<SKILL-GUARD>
You are NOW executing the challenge skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Run debate agents against curated challenges and score them with precision-weighted F1.

---

Initialize progress tracking:
```
TodoWrite([
  {id: "1", content: "🔍 Parse arguments", status: "pending"},
  {id: "2", content: "📋 Load & filter manifest", status: "pending"},
  {id: "3", content: "🔄 Run challenges", status: "pending"},
  {id: "4", content: "📊 Aggregate & report", status: "pending"},
  {id: "5", content: "🏷️ Log results", status: "pending"}
])
```

---

# 1. 🔍 Parse Arguments

Mark step in progress: `TodoWrite([{id: "1", status: "in_progress"}])`

- **suite**: "puzzles" (default) or "all"
- **language**: filter to a specific language, or "all" (default)
- **difficulty**: filter to "easy", "medium", or "hard", or "all" (default)
- **tags**: comma-separated tag filter (e.g., `--tags off-by-one,loop`); a challenge matches if ANY of its tags match
- **id**: run a single specific challenge by its manifest ID (e.g., `--id python/off-by-one`); overrides all other filters
- **dry-run**: list which challenges would be run without actually executing them; prints the filtered set and stops

Mark complete: `TodoWrite([{id: "1", status: "completed"}])`

---

# 2. 📋 Load Manifest

Mark step in progress: `TodoWrite([{id: "2", status: "in_progress"}])`

Read `challenges/manifest.json` from the project root.

Apply filters in this order:
1. If `--id` is set: match exactly that one challenge. If not found, print `Challenge '<id>' not found in manifest.` and stop.
2. Filter by `language` (if not "all")
3. Filter by `difficulty` (if not "all")
4. Filter by `tags` (if provided): keep challenges whose `tags` array contains at least one of the requested tags

If the filtered set is empty, print:
```
No challenges match the given filters (language=<x>, difficulty=<y>, tags=<z>).
Run /challenge to see all available challenges.
```
and stop.

If `--dry-run`: print the filtered challenge list and stop:
```
Dry run — would run N challenge(s):
  python/off-by-one  [easy, python]  tags: boundary, loop, off-by-one
  go/goroutine-leak  [medium, go]    tags: goroutine, channel, resource-leak
```

Otherwise, report how many challenges will be run:
```
Running {N} challenges ({languages})...
```

Mark complete: `TodoWrite([{id: "2", status: "completed"}])`

---

# 3. 🔄 Run Each Challenge

Mark step in progress: `TodoWrite([{id: "3", status: "in_progress"}])`

For each challenge in the filtered set, run **sequentially** (not in parallel) to avoid context flooding from concurrent debate pipelines. If the set is large (>5 challenges), note estimated wall time: roughly 2–4 min per challenge.

## 3a. 🔍 Read Challenge Code

Read the challenge file (e.g., `challenges/python/off-by-one/challenge.py`).

The file extension tells you the language:
- `.py` → Python
- `.ts` → TypeScript
- `.go` → Go
- `.rs` → Rust

## 3b. 🛠️ Run Single-Pass Adversarial Review

Spawn the adversarial-review pipeline in **single-pass mode** (1 round, not iterative) against the challenge file. This means:

1. **Enthusiast agent** — reviews the challenge file for bugs; outputs a structured JSON findings list with shape `[{"file": "...", "line": N, "type": "...", "description": "..."}]`
2. **Adversary agent** — challenges each Enthusiast finding; outputs which findings it disputes and why
3. **Judge agent** — renders a final verdict for each finding: `accepted` or `rejected`; outputs structured JSON rulings with shape `[{"finding_id": N, "verdict": "accepted|rejected", "rationale": "..."}]`

Pass the full challenge file content as the code under review. Do NOT pass the answer key — agents must find bugs without hints.

The key outputs needed for scoring are:
- `ENTHUSIAST_FINDINGS` — the raw findings array from the Enthusiast
- `JUDGE_RULINGS` — the verdict array from the Judge

## 3c. ✅ Score Against Answer Key

Prepare a combined JSON file with the Judge's rulings AND the Enthusiast's findings (the scoring script needs both to match file/line/type):

```bash
# Write components via printf to avoid shell injection on embedded quotes (F5)
# Use mktemp to prevent parallel-run collisions (F6)
debate_tmpfile=$(mktemp /tmp/debate-output-XXXXXX.json)
rulings_tmpfile=$(mktemp /tmp/debate-rulings-XXXXXX.json)
findings_tmpfile=$(mktemp /tmp/debate-findings-XXXXXX.json)
printf '%s' "${JUDGE_RULINGS}" > "$rulings_tmpfile"
printf '%s' "${ENTHUSIAST_FINDINGS}" > "$findings_tmpfile"
jq -n \
  --slurpfile rulings "$rulings_tmpfile" \
  --slurpfile findings "$findings_tmpfile" \
  '{rulings: $rulings[0], findings: $findings[0]}' > "$debate_tmpfile"
rm "$rulings_tmpfile" "$findings_tmpfile"

# Use absolute path relative to project root (F7)
SCORE_SCRIPT="$(git rev-parse --show-toplevel)/scripts/score-challenge.sh"
ANSWER_KEY="$(git rev-parse --show-toplevel)/challenges/{id}/answer-key.json"
"$SCORE_SCRIPT" "$ANSWER_KEY" "$debate_tmpfile"
rm "$debate_tmpfile"
```

Parse the F1 score from the output JSON.

## 3d. 📋 Report Result

Print per-challenge result:
```
  {id}: F1={f1} (P={precision} R={recall}) TP={tp} FP={fp} FN={fn} {PASS|FAIL}
```

After each challenge completes, update progress:
`TodoWrite([{id: "3", content: "🔄 Run challenges — {N}/{total} done"}])`

After all challenges complete: `TodoWrite([{id: "3", status: "completed", content: "🔄 Run challenges — {total}/{total} done"}])`

---

# 4. 📊 Aggregate and Report

Mark step in progress: `TodoWrite([{id: "4", status: "in_progress"}])`

After all challenges complete:

```
## Challenge Results

| Challenge | Language | Difficulty | F1 | Precision | Recall | Verdict |
|---|---|---|---|---|---|---|
| python/off-by-one | python | easy | 1.00 | 1.00 | 1.00 | PASS |
| python/null-handling | python | easy | 0.80 | 0.67 | 1.00 | PASS |
| ... | ... | ... | ... | ... | ... | ... |

**Overall: {passed}/{total} passed (avg F1: {avg_f1})**
```

Include a breakdown by language and by difficulty if more than one group is present:
```
By language:    python 2/2 (avg F1: 0.90)  go 1/2 (avg F1: 0.60)
By difficulty:  easy 3/3 (avg F1: 0.93)    medium 0/1 (avg F1: 0.40)
```

Mark complete: `TodoWrite([{id: "4", status: "completed", content: "📊 Aggregate & report — {passed}/{total} passed, avg F1: {avg_f1}"}])`

---

# 5. 🏷️ Log Results

Mark step in progress: `TodoWrite([{id: "5", status: "in_progress"}])`

Append a summary line to `experiments.tsv` (if it exists) with `type: challenge`:

```
{id}	{timestamp}	challenge	-	{total_challenges}	{avg_f1}	-	-	{pass_count}/{total}	{tokens_used}	{wall_time}	Challenge benchmark: {passed}/{total} passed
```

This enables longitudinal tracking of agent accuracy over time.

Mark complete: `TodoWrite([{id: "5", status: "completed"}])`

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  {id: "1", status: "completed"},
  {id: "2", status: "completed"},
  {id: "3", status: "completed"},
  {id: "4", status: "completed"},
  {id: "5", status: "completed"}
])
```

---

# Usage Examples

## Example 1 — Run the full puzzle suite

```
user: /challenge
```

Runs all challenges in `challenges/manifest.json` with the default `puzzles` suite filter, reports per-challenge F1 and an overall pass/fail summary.

## Example 2 — Benchmark a single language

```
user: /challenge --language python
```

Filters to only Python challenges. Useful when iterating on prompts that target Python-specific bug patterns and you want fast feedback without running Go/Rust/TypeScript suites.

## Example 3 — Run the full suite including non-puzzle challenges

```
user: /challenge --suite all --language all
```

Runs every challenge regardless of suite tag. Expect a longer wall time. Use this before a major version bump or trust-tier promotion to get a complete accuracy baseline.

## Example 4 — Run a single challenge by ID

```
user: /challenge --id go/interface-nil
```

Runs exactly the `go/interface-nil` challenge and scores it. Useful for fast iteration when debugging a specific failure — no need to run the full suite for one regression.

## Example 5 — Filter by difficulty

```
user: /challenge --difficulty hard
```

Runs only hard-difficulty challenges. These typically involve subtle language-specific gotchas (e.g., Go nil interfaces, Rust unsafe UB). Use when evaluating whether agents can handle non-obvious bugs.

## Example 6 — Filter by tag

```
user: /challenge --tags race-condition,concurrent-modification
```

Runs challenges tagged with `race-condition` OR `concurrent-modification`. Useful for targeted regression testing after modifying concurrency-focused review prompts.

## Example 7 — Dry run before a long benchmark

```
user: /challenge --suite all --dry-run
```

Lists which challenges would be run without actually executing them. Use before a long full-suite run to confirm filters are set correctly and estimate wall time.

---

# Common Failure Patterns

- **F1 score drops suddenly across all challenges:** Indicates a structural change to the debate pipeline's JSON output — not a regression in agent quality. Check if `adversarial-review` recently changed its output schema and update `score-challenge.sh` to match before interpreting scores.
- **One language consistently scores near zero while others are normal:** The challenge files for that language may have drifted from the manifest (`challenges/manifest.json`). Run `cat challenges/manifest.json | jq '.[] | select(.language=="<lang>")'` to verify each challenge file still exists at the listed path.
- **Score improves on retries without code changes:** Debate pipelines have inherent non-determinism. Run each challenge 2-3 times and average before concluding anything. A single-run score difference of ±0.1 F1 is within normal variance.
- **`score-challenge.sh` exits non-zero with "jq: command not found":** `jq` is a required dependency. Install it with `brew install jq` and retry.
- **Enthusiast returns prose instead of JSON findings:** The adversarial-review pipeline must be invoked in structured-output mode. If the Enthusiast returns a freeform text block, the scoring script cannot parse it — F1 will be 0 for that challenge. Check the adversarial-review skill's output-format instructions.
- **F1 is non-zero but all verdicts are FAIL:** The `score-challenge.sh` pass threshold is configurable. Check if the threshold in the answer key's `scoring` field is stricter than expected (e.g., `match_line_range: 1` vs. `match_line_range: 3`).

---

# Edge Cases and Pitfalls

- **Missing `challenges/manifest.json`**: The skill cannot run without it. If the file is absent, print a clear error and stop. Do not attempt to reconstruct the manifest from the directory structure.
- **Empty filter result**: If `--language python` produces zero challenges (e.g., no Python challenges exist yet), print `No challenges match language=python.` and stop rather than silently reporting 0/0 results.
- **Judge output format drift**: If the debate skill changes its JSON output schema, score-challenge.sh may fail to parse rulings. When `jq` exits non-zero, print the raw error and the path to the temp file for manual inspection before deleting it.
- **Parallel collision risk**: Each challenge uses `mktemp` to produce unique temp file paths. Do NOT reuse a hardcoded `/tmp/debate-output.json` across challenges — parallel runs will corrupt each other's inputs.
- **F1 = 0 on all challenges**: Usually means the debate pipeline returned no structured findings (all text, no JSON). Check that the review skill is running in structured-output mode, not prose mode.
- **`--id` with a path separator mismatch**: Challenge IDs use forward slash (e.g., `python/off-by-one`). On Windows-style paths, backslash lookup will fail. Always use forward slashes in `--id` values.
- **Manifest has a challenge entry but the file is missing on disk**: Print a warning and skip that challenge rather than failing the entire run. A missing file usually means the challenge was removed from the repo but not from the manifest.

---

# Integration Points

- **adversarial-review skill**: The challenge skill calls the review pipeline (Enthusiast → Adversary → Judge) under the hood. Changes to adversarial-review prompts directly affect challenge scores.
- **prompt-testing skill**: Use prompt-testing for iterating on a single agent's behavior in isolation. Use challenge for end-to-end F1 measurement across the full debate pipeline.
- **experiments.tsv log**: Challenge appends to the same log as autoimprove experiments. Filter with `/history --theme challenge` to see only benchmark runs.
- **score-challenge.sh**: Located at `scripts/score-challenge.sh`. Scores by matching (file, line, type) tuples from Judge verdicts against the answer key. Understanding the matching logic is essential for diagnosing low-recall scores.

---

# Recommended Workflow for Prompt Iteration

Use this sequence when improving agent prompts and measuring the effect:

1. **Run a baseline** — `/challenge` — record avg F1 and per-challenge scores
2. **Modify the agent prompt** — change `adversarial-review` Enthusiast or Adversary instructions
3. **Run targeted regression** — `/challenge --language <affected-language>` — fast feedback on the most relevant subset
4. **Run full suite** — `/challenge --suite all` — only after targeted pass looks good; this is the definitive before/after comparison
5. **Archive the delta** — log the F1 change to `experiments.tsv` manually or via `/autoimprove run` with `--theme challenge`

Tip: use `--difficulty hard` to isolate the highest-signal challenges. Hard challenges require the most nuanced reasoning — improvements here generalize to the full suite better than easy wins on easy challenges.

---

# When NOT to Use

- **Do not use** to write or modify test suites — this skill only runs existing challenges against agents. Use prompt-testing for that.
- **Do not use** as a substitute for CI — challenge is an interactive diagnostic tool, not a regression gate. Wire CI to the test script directly.
- **Do not use** when the debate pipeline is in mid-refactor — a structural change to agent output format will produce meaningless F1 scores until score-challenge.sh is updated to match.
- **Do not use** to measure improvements from a single experimenter run — challenge is a macro benchmark. Use it to measure deliberate agent prompt changes, not to evaluate individual autoimprove experiments.
- **Do not use** as a replacement for the evaluate gate — the evaluate gate checks the autoimprove pipeline's correctness; challenge measures agent accuracy on pre-seeded bugs. They measure different things.
- **Do not use** for regression testing during normal autoimprove sessions — it consumes significant tokens (one full debate pipeline per challenge). Reserve challenge runs for before/after comparisons on major agent prompt changes.
- **Do not use** as the sole signal for agent quality — F1 measures finding accuracy on synthetic bugs, not real-world code improvement quality. Use challenge alongside human review of kept experiments.
