# Debate Agent Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 21 confirmed issues from the adversarial code review of the debate agent system — shell injection, silent false negatives, race conditions, and spec inconsistencies.

**Architecture:** Six independent fix batches, ordered by impact. Tasks 1–3 fix executable code (testable with bash). Tasks 4–7 fix LLM instruction files (verified by reading). All fixes are backward-compatible — no schema changes.

**Tech Stack:** Bash, jq, Markdown (Claude Code plugin agent/skill files).

**Source review:** `docs/superpowers/reviews/2026-03-27-debate-review-round1.md` (findings F1–F31)

---

## File Structure

```
scripts/score-challenge.sh          — MODIFY: F1 (jq error checks), F2 (line type guard), F17 (FP guard + dedup)
test/challenge/test-score-challenge.sh — MODIFY: add regression tests for F2 and F17
test/challenge/test-integration.sh  — MODIFY: F24 (find antipattern), F27 (bug_count validation)
agents/challenge-runner.md          — MODIFY: F4 (shell injection fix), F26 (extraction step)
skills/challenge/SKILL.md           — MODIFY: F5 (double-quote injection), F6 (mktemp), F7 (relative path)
skills/review/SKILL.md              — MODIFY: F9 (deterministic convergence), F14 (auto-scale tie-break)
agents/judge.md                     — MODIFY: F12 (ID-based convergence), F18 (split → TP pool)
agents/adversary.md                 — MODIFY: F19 (inaccessible file policy alignment)
agents/enthusiast.md                — MODIFY: F21 (false "carried forward" promise)
```

---

## Task 1: Fix score-challenge.sh — Scoring Correctness (F1, F2, F17)

**Files:**
- Modify: `scripts/score-challenge.sh`
- Modify: `test/challenge/test-score-challenge.sh` (add regression tests first)

### F2: Silent false negative when `.line` is null/string
### F17: FP can go negative from duplicate finding IDs
### F1: jq pipeline errors produce empty `--argjson` inputs silently

- [ ] **Step 1: Add regression tests for F2 and F17**

Append to `test/challenge/test-score-challenge.sh` before the final `Results` echo:

```bash
echo ""
echo "--- Test: null line in finding (F2 regression) ---"
NULL_LINE_FINDINGS='{
  "rulings": [
    {"finding_id": "F1", "final_severity": "high", "winner": "enthusiast", "resolution": "Valid"}
  ],
  "findings": [
    {"id": "F1", "file": "challenge.py", "line": null, "severity": "high", "description": "Bug"}
  ]
}'
tmpfile=$(mktemp)
echo "$NULL_LINE_FINDINGS" > "$tmpfile"
result=$("$SCORE" "$FIXTURES/sample-answer-key.json" "$tmpfile" 2>/dev/null)
rm "$tmpfile"
assert_json_field "null line: true_positives=0 (not a crash)" "$result" '.true_positives' '0'
assert_json_field "null line: false_positives=1 (confirmed but no match)" "$result" '.false_positives' '1'
assert_json_field "null line: pass=false" "$result" '.pass' 'false'

echo ""
echo "--- Test: duplicate finding IDs (F17 regression) ---"
DUPE_FINDINGS='{
  "rulings": [
    {"finding_id": "F1", "final_severity": "high", "winner": "enthusiast", "resolution": "Valid"},
    {"finding_id": "F1", "final_severity": "high", "winner": "enthusiast", "resolution": "Valid dupe"}
  ],
  "findings": [
    {"id": "F1", "file": "challenge.py", "line": 12, "severity": "high", "description": "Bug"},
    {"id": "F1", "file": "challenge.py", "line": 12, "severity": "high", "description": "Bug dupe"}
  ]
}'
tmpfile=$(mktemp)
echo "$DUPE_FINDINGS" > "$tmpfile"
result=$("$SCORE" "$FIXTURES/sample-answer-key.json" "$tmpfile" 2>/dev/null)
rm "$tmpfile"
# After dedup: 1 confirmed finding, matches B1 → TP=1, FP=0, precision=1
assert_json_field "dupe IDs: false_positives=0 (not negative)" "$result" '.false_positives' '0'
assert_json_field "dupe IDs: true_positives=1" "$result" '.true_positives' '1'
fp_val=$(echo "$result" | jq -r '.false_positives')
if [ "$fp_val" -ge 0 ] 2>/dev/null; then
  echo "  PASS: false_positives is non-negative ($fp_val)"
  ((PASS++)) || true
else
  echo "  FAIL: false_positives is negative ($fp_val)"
  ((FAIL++)) || true
fi
```

- [ ] **Step 2: Run tests — verify new ones fail**

```bash
bash test/challenge/test-score-challenge.sh
```

Expected: The null-line test and dupe-IDs test FAIL (current code crashes or produces wrong output).

- [ ] **Step 3: Fix score-challenge.sh**

Replace the match loop's jq filter (lines 80–89) and the CONFIRMED_FINDINGS block (lines 47–58). The full new file content for `scripts/score-challenge.sh`:

```bash
#!/usr/bin/env bash
# score-challenge.sh — Score a challenge findings file against an answer key
# Usage: score-challenge.sh <answer-key.json> <findings.json>
# Outputs a JSON score object to stdout. Exit code is always 0.
# Requires: bash 4+, jq

set -uo pipefail

ANSWER_KEY="${1:-}"
FINDINGS="${2:-}"

if [ -z "$ANSWER_KEY" ] || [ -z "$FINDINGS" ]; then
  echo '{"error":"usage: score-challenge.sh <answer-key.json> <findings.json>"}' >&2
  exit 1
fi

if [ ! -f "$ANSWER_KEY" ]; then
  echo "{\"error\":\"answer key not found: $ANSWER_KEY\"}" >&2
  exit 1
fi

if [ ! -f "$FINDINGS" ]; then
  echo "{\"error\":\"findings not found: $FINDINGS\"}" >&2
  exit 1
fi

# ── Read scoring config ────────────────────────────────────────────────────────

MATCH_FILE=$(jq -r '.scoring.match_file // true' "$ANSWER_KEY")
MATCH_LINE_RANGE=$(jq -r '.scoring.match_line_range // 3' "$ANSWER_KEY")

# ── Count answer key bugs ──────────────────────────────────────────────────────

NUM_BUGS=$(jq '.bugs | length' "$ANSWER_KEY")

# ── Identify confirmed findings ────────────────────────────────────────────────
# Confirmed = winner != "adversary" AND final_severity != "dismissed"

# Build confirmed IDs array (F1)
CONFIRMED_IDS_JSON=$(jq '
  [
    .rulings
    | map(select(.winner != "adversary" and .final_severity != "dismissed"))
    | .[].finding_id
  ]' "$FINDINGS" 2>/dev/null) || CONFIRMED_IDS_JSON='[]'

# Build confirmed findings with deduplication on ID (F17: prevents TP inflation from dupe IDs)
CONFIRMED_FINDINGS=$(jq --argjson confirmed_ids "${CONFIRMED_IDS_JSON}" '
  .findings
  | map(select(.id as $id | $confirmed_ids | contains([$id])))
  | unique_by(.id)
' "$FINDINGS" 2>/dev/null) || CONFIRMED_FINDINGS='[]'

[ -z "$CONFIRMED_FINDINGS" ] && CONFIRMED_FINDINGS='[]'

TOTAL_CONFIRMED=$(echo "$CONFIRMED_FINDINGS" | jq 'length')

# ── Match bugs to confirmed findings ──────────────────────────────────────────
# For each bug in answer key, find a confirmed finding that matches:
#   same file (if match_file=true) AND line within match_line_range
# F2: findings with non-numeric .line are skipped (type guard in jq)

TP=0
MATCHED_FINDING_IDS='[]'

BUG_COUNT=$(jq '.bugs | length' "$ANSWER_KEY")

for (( i=0; i<BUG_COUNT; i++ )); do
  BUG_FILE=$(jq -r ".bugs[$i].file" "$ANSWER_KEY")
  BUG_LINE=$(jq -r ".bugs[$i].line" "$ANSWER_KEY")

  # Find a confirmed finding that matches this bug (not already matched)
  MATCH_ID=$(echo "$CONFIRMED_FINDINGS" | jq -r \
    --arg file "$BUG_FILE" \
    --argjson line "$BUG_LINE" \
    --argjson range "$MATCH_LINE_RANGE" \
    --argjson match_file "$MATCH_FILE" \
    --argjson already_matched "$MATCHED_FINDING_IDS" \
    '
    map(
      select(
        (.id as $id | $already_matched | contains([$id]) | not)
        and (if $match_file then .file == $file else true end)
        and ((.line | type) == "number")
        and ((.line - $line) | if . < 0 then . * -1 else . end) <= $range
      )
    )
    | first
    | .id // empty
    ' 2>/dev/null || true)

  if [ -n "$MATCH_ID" ]; then
    ((TP++)) || true
    MATCHED_FINDING_IDS=$(echo "$MATCHED_FINDING_IDS" | jq --arg id "$MATCH_ID" '. + [$id]')
  fi
done

FN=$(( NUM_BUGS - TP ))
FP=$(( TOTAL_CONFIRMED - TP ))
[ "$FP" -lt 0 ] && FP=0  # F17: guard against negative FP from dedup edge cases

# ── Calculate precision, recall, F1 ───────────────────────────────────────────

PRECISION=$(jq -n \
  --argjson tp "$TP" \
  --argjson fp "$FP" \
  'if ($tp + $fp) == 0 then 0 else $tp / ($tp + $fp) end')

RECALL=$(jq -n \
  --argjson tp "$TP" \
  --argjson num_bugs "$NUM_BUGS" \
  'if $num_bugs == 0 then 0 else $tp / $num_bugs end')

F1=$(jq -n \
  --argjson precision "$PRECISION" \
  --argjson recall "$RECALL" \
  'if ($precision + $recall) == 0 then 0 else 2 * $precision * $recall / ($precision + $recall) end')

PASS=$(jq -n --argjson f1 "$F1" 'if $f1 >= 0.5 then true else false end')

# ── Output ─────────────────────────────────────────────────────────────────────

jq -n \
  --argjson true_positives "$TP" \
  --argjson false_positives "$FP" \
  --argjson false_negatives "$FN" \
  --argjson precision "$PRECISION" \
  --argjson recall "$RECALL" \
  --argjson f1 "$F1" \
  --argjson pass "$PASS" \
  '{
    true_positives: $true_positives,
    false_positives: $false_positives,
    false_negatives: $false_negatives,
    precision: $precision,
    recall: $recall,
    f1: $f1,
    pass: $pass
  }'
```

- [ ] **Step 4: Run all tests — verify they pass**

```bash
bash test/challenge/test-score-challenge.sh
```

Expected: All PASS including the two new regression tests.

- [ ] **Step 5: Run integration tests too**

```bash
bash test/challenge/test-integration.sh
```

Expected: All PASS (no regressions).

- [ ] **Step 6: Commit**

```bash
git add scripts/score-challenge.sh test/challenge/test-score-challenge.sh
git commit -m "fix: score-challenge.sh — null line guard (F2), dedup findings (F17), safe jq pipeline (F1)"
```

---

## Task 2: Fix test-integration.sh — Test Robustness (F24, F27)

**Files:**
- Modify: `test/challenge/test-integration.sh`

### F24: `for key in $(find ...)` word-splits on paths with spaces
### F27: manifest `bug_count` field never validated against answer-key length

- [ ] **Step 1: Replace the two `for key in $(find ...)` antipatterns**

Replace lines 40–46 (the "all answer keys are valid JSON" loop) with:

```bash
echo "--- Test: all answer keys are valid JSON ---"
ALL_VALID=true
while IFS= read -r key; do
  if ! jq empty "$key" 2>/dev/null; then
    echo "  FAIL: invalid JSON: $key"
    ALL_VALID=false
    ((FAIL++)) || true
  fi
done < <(find "$ROOT/challenges" -name "answer-key.json")
if $ALL_VALID; then
  echo "  PASS: all answer-key.json files are valid JSON"
  ((PASS++)) || true
fi
```

Replace lines 73–84 (the "scoring script handles each real answer key" loop) with:

```bash
echo "--- Test: scoring script handles each real answer key ---"
while IFS= read -r key; do
  EMPTY='{"rulings":[],"findings":[]}'
  tmpfile=$(mktemp)
  echo "$EMPTY" > "$tmpfile"
  result=$("$SCORE" "$key" "$tmpfile" 2>/dev/null)
  rm "$tmpfile"

  challenge=$(jq -r '.challenge' "$key")
  assert_json_field "empty findings on $challenge: f1=0" "$result" '.f1' '0'
  assert_json_field "empty findings on $challenge: pass=false" "$result" '.pass' 'false'
done < <(find "$ROOT/challenges" -name "answer-key.json")
```

- [ ] **Step 2: Add bug_count validation test**

Append before the final `Results` echo:

```bash
echo "--- Test: manifest bug_count matches answer-key bug array length ---"
ALL_MATCH=true
while IFS= read -r id; do
  manifest_count=$(jq -r --arg id "$id" '.challenges[] | select(.id == $id) | .bug_count' "$ROOT/challenges/manifest.json")
  key="$ROOT/challenges/$id/answer-key.json"
  if [ ! -f "$key" ]; then continue; fi
  actual_count=$(jq '.bugs | length' "$key")
  if [ "$manifest_count" != "$actual_count" ]; then
    echo "  FAIL: $id — manifest says bug_count=$manifest_count but answer-key has $actual_count bugs"
    ALL_MATCH=false
    ((FAIL++)) || true
  fi
done < <(jq -r '.challenges[].id' "$ROOT/challenges/manifest.json")
if $ALL_MATCH; then
  echo "  PASS: all manifest bug_counts match answer-key bug array lengths"
  ((PASS++)) || true
fi
```

- [ ] **Step 3: Run integration tests**

```bash
bash test/challenge/test-integration.sh
```

Expected: All PASS including the new bug_count validation test.

- [ ] **Step 4: Commit**

```bash
git add test/challenge/test-integration.sh
git commit -m "fix: test-integration.sh — safe find loops (F24), manifest bug_count validation (F27)"
```

---

## Task 3: Fix agents/challenge-runner.md — Shell Injection + Extraction Step (F4, F26)

**Files:**
- Modify: `agents/challenge-runner.md`

### F4: Shell injection — `echo '...' ${JUDGE_RULINGS} ...'` breaks on single quotes in LLM output
### F26: No explicit extraction step from JUDGE_OUTPUT to JUDGE_RULINGS/ENTHUSIAST_FINDINGS

- [ ] **Step 1: Add explicit extraction step after Step 2 Judge spawn**

Find the paragraph "Parse the Judge's output. Store as `JUDGE_OUTPUT`." and replace it with:

```markdown
Parse the Judge's output. Store as `JUDGE_OUTPUT`.

Extract the components needed for scoring:

```bash
JUDGE_RULINGS=$(printf '%s' "${JUDGE_OUTPUT}" | jq '.rulings')
ENTHUSIAST_FINDINGS=$(printf '%s' "${ENTHUSIAST_OUTPUT}" | jq '.findings')
```

If either extraction fails (jq error), output `{"error": "failed to extract debate components"}` and exit.
```

- [ ] **Step 2: Replace the shell injection pattern in Step 3**

Find the "Write a combined findings file to a temp path" block and replace:

```bash
tmpfile=$(mktemp /tmp/debate-output-XXXXXX.json)
echo '{
  "rulings": '"${JUDGE_RULINGS}"',
  "findings": '"${ENTHUSIAST_FINDINGS}"'
}' > "$tmpfile"
```

With the safe pattern using temp files (avoids shell injection via single-quote break):

```bash
tmpfile=$(mktemp /tmp/debate-output-XXXXXX.json)
tmprulings=$(mktemp /tmp/debate-rulings-XXXXXX.json)
tmpfindings=$(mktemp /tmp/debate-findings-XXXXXX.json)
printf '%s' "${JUDGE_RULINGS}" > "$tmprulings"
printf '%s' "${ENTHUSIAST_FINDINGS}" > "$tmpfindings"
jq -n \
  --slurpfile rulings "$tmprulings" \
  --slurpfile findings "$tmpfindings" \
  '{rulings: $rulings[0], findings: $findings[0]}' > "$tmpfile"
rm "$tmprulings" "$tmpfindings"
```

Also update the cleanup line to match (it is unchanged: `rm "$tmpfile"`).

- [ ] **Step 3: Verify the fix by reading the modified sections**

Read `agents/challenge-runner.md` and confirm:
1. After "Store as `JUDGE_OUTPUT`", there is now an explicit extraction block for `JUDGE_RULINGS` and `ENTHUSIAST_FINDINGS`
2. The Step 3 scoring block uses `printf` + temp files + `jq --slurpfile`, not `echo '...' ${VAR} ...'`

- [ ] **Step 4: Commit**

```bash
git add agents/challenge-runner.md
git commit -m "fix: challenge-runner — safe JSON assembly via slurpfile (F4), explicit extraction step (F26)"
```

---

## Task 4: Fix skills/challenge/SKILL.md — Shell Injection, Race Condition, Relative Path (F5, F6, F7)

**Files:**
- Modify: `skills/challenge/SKILL.md`

### F5: Double-quoted jq `--argjson` breaks on unescaped `"` in LLM output
### F6: Hardcoded `/tmp/debate-output.json` races with parallel runs
### F7: Relative path `scripts/score-challenge.sh` breaks outside project root

- [ ] **Step 1: Replace the Step 3c scoring block**

Find the Step 3c block:

```bash
# Combine rulings and findings into format score-challenge.sh expects
jq -n --argjson rulings "$JUDGE_RULINGS" --argjson findings "$ENTHUSIAST_FINDINGS" \
  '{rulings: $rulings, findings: $findings}' > /tmp/debate-output.json

# Score
scripts/score-challenge.sh challenges/{id}/answer-key.json /tmp/debate-output.json
```

Replace with:

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

- [ ] **Step 2: Verify the fix by reading the modified section**

Read `skills/challenge/SKILL.md` Step 3c and confirm:
1. Uses `mktemp` — no `/tmp/debate-output.json` hardcoded path
2. Uses `printf '%s'` + temp files for JSON assembly — no `--argjson "$VAR"` with double-quoted variables
3. Uses `$(git rev-parse --show-toplevel)/scripts/...` for the script path

- [ ] **Step 3: Commit**

```bash
git add skills/challenge/SKILL.md
git commit -m "fix: challenge skill — safe JSON assembly (F5), mktemp (F6), absolute script path (F7)"
```

---

## Task 5: Fix skills/review/SKILL.md — Convergence + Auto-Scale (F9, F14)

**Files:**
- Modify: `skills/review/SKILL.md`

### F9: Convergence fully delegated to LLM Judge — add deterministic supplement
### F14: Auto-scale rules conflict for e.g. 60 lines / 6 files — no precedence

- [ ] **Step 1: Fix the auto-scale rules (F14)**

Find the auto-scale block:

```
If no explicit `--rounds N`, auto-scale based on target size:
- 1–49 lines → 1 round
- 50–199 lines or ≤ 5 files → 2 rounds
- 200+ lines or > 5 files → 3 rounds
```

Replace with (mutual exclusion via if/elif):

```
If no explicit `--rounds N`, auto-scale based on target size:
- More than 5 files OR 200+ lines → 3 rounds
- 50–199 lines (and ≤ 5 files) → 2 rounds
- Fewer than 50 lines (and ≤ 5 files) → 1 round

(File count takes precedence over line count when both thresholds trigger.)
```

- [ ] **Step 2: Add deterministic convergence supplement (F9)**

Find step 3d "Check Convergence" and replace:

```markdown
## 3d. Check Convergence

Convergence is only meaningful from round 2 onward. Apply these rules:

- If `round == 1` and Judge returned `convergence: true` → treat as `false`. Log: `"convergence: true ignored on round 1 — no prior rulings to compare against."` Continue to round 2.
- If `round > 1` and Judge set `convergence: true` → stop the loop early. Record `converged_at_round = round`.
- Otherwise → continue to next round.
```

With:

```markdown
## 3d. Check Convergence

Convergence is only meaningful from round 2 onward.

**Deterministic check (orchestrator-side):** When `round > 1`, compute convergence independently by comparing this round's rulings to the prior round's rulings:
- Extract the set of `(finding_id, winner, final_severity)` tuples from both rounds
- If the sets are identical (same IDs, same winners, same severities in any order) → `converged = true`
- This overrides whatever the Judge reported

**LLM check (supplemental):** Also check what the Judge reported. If Judge says `convergence: true` but the deterministic check says `false`, log: `"Judge reported convergence but rulings differ — continuing."` and continue.

**Round 1 guard:** If `round == 1` and Judge returned `convergence: true` → treat as `false`. Log: `"convergence: true ignored on round 1."` Continue to round 2.

**Stop condition:** Stop the loop early when `converged = true` (deterministic). Record `converged_at_round = round`.
```

- [ ] **Step 3: Verify fixes by reading the file**

Read `skills/review/SKILL.md` and confirm:
1. Auto-scale rules use if/elif precedence — file count wins over line count
2. Step 3d has both deterministic and LLM convergence checks, with deterministic taking precedence

- [ ] **Step 4: Commit**

```bash
git add skills/review/SKILL.md
git commit -m "fix: review skill — deterministic convergence check (F9), auto-scale tie-break (F14)"
```

---

## Task 6: Fix Agent Spec Consistency (F12, F18, F19, F21)

**Files:**
- Modify: `agents/judge.md`
- Modify: `agents/adversary.md`
- Modify: `agents/enthusiast.md`

### F12: "corresponding ruling from prior round" — ambiguous whether index-based or ID-based
### F18: Inaccessible file → "split" ruling → enters TP pool, rewarding hallucinated paths
### F19: Adversary says "valid", Judge says "split" for inaccessible files — always disagree
### F21: Enthusiast claims "prior findings carried forward by orchestrator" — false on empty round

- [ ] **Step 1: Fix judge.md — convergence wording (F12) and inaccessible file (F18, F19)**

In `agents/judge.md`, find the convergence rule:

```
`convergence`: **always `false` in round 1** — there are no prior rulings to compare against. In round 2+, set `true` only if every ruling in `rulings[]` is identical in `winner` and `final_severity` to the corresponding ruling from the prior round.
```

Replace with:

```
`convergence`: **always `false` in round 1** — there are no prior rulings to compare against. In round 2+, set `true` only if, for every `finding_id` that appears in BOTH the current and prior round's `rulings[]`, the `winner` and `final_severity` are identical. Match by `finding_id`, not by array index — finding order may differ between rounds.
```

In `agents/judge.md`, find the edge case:

```
- **Cannot read a cited file**: If neither agent's claim can be verified, rule "split" with resolution noting the file was inaccessible.
```

Replace with:

```
- **Cannot read a cited file**: If neither agent's claim can be verified, rule `winner: "adversary"` with `final_severity: "dismissed"` and resolution: "File inaccessible — finding cannot be verified." This prevents unverifiable file references from entering the TP pool.
```

- [ ] **Step 2: Fix adversary.md — inaccessible file policy (F19)**

In `agents/adversary.md`, find:

```
- **Cannot read a cited file**: Call "valid" — you cannot debunk what you cannot verify. Never fabricate a rebuttal.
```

Replace with:

```
- **Cannot read a cited file**: Call "debunked" — cite that the file does not exist or is inaccessible as your reasoning. A finding citing a nonexistent file is not verifiable and should be dismissed.
```

- [ ] **Step 3: Fix enthusiast.md — false "carried forward" promise (F21)**

In `agents/enthusiast.md`, find:

```
- **Round > 1 with no new issues**: Output `{"findings": []}`. Prior findings will be carried forward by the orchestrator.
```

Replace with:

```
- **Round > 1 with no new issues**: Output `{"findings": []}`. Note: prior round findings are available in the context provided to you as `PRIOR_ROUND_OUTPUT` — they are not automatically re-confirmed. If you found nothing new, output empty findings and let prior rounds stand on their own.
```

- [ ] **Step 4: Verify fixes by reading the three files**

Read `agents/judge.md`, `agents/adversary.md`, `agents/enthusiast.md` and confirm:
1. judge.md: convergence uses ID-based matching, inaccessible file → dismissed
2. adversary.md: inaccessible file → debunked (aligned with judge.md)
3. enthusiast.md: no longer promises "carried forward"

- [ ] **Step 5: Commit**

```bash
git add agents/judge.md agents/adversary.md agents/enthusiast.md
git commit -m "fix: agent specs — ID-based convergence (F12), align inaccessible-file policy (F18+F19), fix false promise (F21)"
```

---

## Summary

| Task | Findings Fixed | Files Changed |
|------|----------------|---------------|
| 1 | F1, F2, F17 | `scripts/score-challenge.sh`, `test/challenge/test-score-challenge.sh` |
| 2 | F24, F27 | `test/challenge/test-integration.sh` |
| 3 | F4, F26 | `agents/challenge-runner.md` |
| 4 | F5, F6, F7 | `skills/challenge/SKILL.md` |
| 5 | F9, F14 | `skills/review/SKILL.md` |
| 6 | F12, F18, F19, F21 | `agents/judge.md`, `agents/adversary.md`, `agents/enthusiast.md` |

**Independent tasks:** All 6 tasks can be dispatched in parallel — no shared state between them. Tasks 1–2 are executable (have tests). Tasks 3–6 are instruction documents (verified by reading).
