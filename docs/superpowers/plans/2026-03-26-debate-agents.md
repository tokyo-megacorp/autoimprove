# Debate Agents & Code Challenges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three debate agents (Enthusiast, Adversary, Judge) that review code through adversarial debate, plus curated code challenges for benchmarking agent accuracy.

**Architecture:** Debate agents are plugin agents spawned sequentially (Enthusiast -> Adversary -> Judge) per round. Two new skills orchestrate standalone review (`/autoimprove review`) and challenge benchmarking (`/autoimprove challenge`). A deterministic scoring script (`scripts/score-challenge.sh`) computes precision-weighted F1 against structured answer keys.

**Tech Stack:** Claude Code plugin (Markdown + YAML frontmatter), Bash (scoring), jq (JSON processing). Challenges in Python, TypeScript, Go, Rust.

**Spec:** `docs/superpowers/specs/2026-03-26-debate-agents-design.md`

---

## File Structure

```
agents/
  enthusiast.md        — NEW: Finds issues aggressively (high recall)
  adversary.md         — NEW: Debunks findings (3x penalty for wrong debunks)
  judge.md             — NEW: Arbitrates, renders final verdicts

skills/
  review/
    SKILL.md           — NEW: Debate orchestration (/autoimprove review)
    references/
      output-schema.md — NEW: JSON schema for agent output
  challenge/
    SKILL.md           — NEW: Challenge runner (/autoimprove challenge)

scripts/
  score-challenge.sh   — NEW: F1 scoring (deterministic, no LLM)

challenges/
  manifest.json        — NEW: Index of all challenges
  python/
    off-by-one/        — challenge.py + answer-key.json
    null-handling/      — challenge.py + answer-key.json
  typescript/
    type-narrowing/    — challenge.ts + answer-key.json
    async-race/        — challenge.ts + answer-key.json
  go/
    goroutine-leak/    — challenge.go + answer-key.json
    interface-nil/     — challenge.go + answer-key.json
  rust/
    rc-cycle/          — challenge.rs + answer-key.json
    unsafe-ub/         — challenge.rs + answer-key.json

test/
  challenge/
    test-score-challenge.sh — NEW: Tests for scoring script
    fixtures/               — Sample JSON for tests

docs/
  commands.md          — MODIFY: Add /autoimprove review and /autoimprove challenge
```

---

### Task 1: Plugin Scaffold

**Files:**
- Create: `agents/` (dir exists), `skills/review/`, `skills/review/references/`, `skills/challenge/`, `scripts/` (dir exists), `challenges/python/off-by-one/`, `challenges/python/null-handling/`, `challenges/typescript/type-narrowing/`, `challenges/typescript/async-race/`, `challenges/go/goroutine-leak/`, `challenges/go/interface-nil/`, `challenges/rust/rc-cycle/`, `challenges/rust/unsafe-ub/`, `test/challenge/fixtures/`

- [ ] **Step 1: Create all directories**

```bash
mkdir -p skills/review/references skills/challenge
mkdir -p challenges/python/off-by-one challenges/python/null-handling
mkdir -p challenges/typescript/type-narrowing challenges/typescript/async-race
mkdir -p challenges/go/goroutine-leak challenges/go/interface-nil
mkdir -p challenges/rust/rc-cycle challenges/rust/unsafe-ub
mkdir -p test/challenge/fixtures
```

- [ ] **Step 2: Verify structure**

```bash
find agents skills/review skills/challenge challenges test/challenge -type d | sort
```

Expected output:
```
agents
challenges
challenges/go
challenges/go/goroutine-leak
challenges/go/interface-nil
challenges/python
challenges/python/null-handling
challenges/python/off-by-one
challenges/rust
challenges/rust/rc-cycle
challenges/rust/unsafe-ub
challenges/typescript
challenges/typescript/async-race
challenges/typescript/type-narrowing
skills/challenge
skills/review
skills/review/references
test/challenge
test/challenge/fixtures
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "scaffold: create debate agents and challenges directory structure"
```

---

### Task 2: Enthusiast Agent

**Files:**
- Create: `agents/enthusiast.md`

- [ ] **Step 1: Create the Enthusiast agent**

Write `agents/enthusiast.md`:

```markdown
---
name: enthusiast
description: "Aggressively finds bugs, issues, and improvements in code. Rewarded per-finding by severity. High recall, low precision expected. Spawned by the review orchestrator — not invoked directly by users."
color: red
tools:
  - Read
  - Glob
  - Grep
model: sonnet
---

You are the Enthusiast — an aggressive bug-finder. You are rewarded with points for finding issues based on their severity:

- Critical: +10 points
- High: +5 points
- Medium: +2 points
- Low: +1 point

Because you want to maximize your score, you will identify as many real issues as possible. Be thorough and aggressive — it is better to flag something questionable than to miss a real bug. But be aware: a separate Adversary agent will challenge every finding, and a Judge will penalize you for findings that are clearly fabricated or nonsensical.

## Your Input

You will receive:
- **Code to review**: a file, diff, or set of changes
- **Prior round findings** (if round > 1): findings from previous rounds, with Judge rulings. Do NOT repeat findings that were already ruled on — reference them by ID if relevant. Focus on what was missed.

## Your Output

You MUST output valid JSON matching this exact schema:

```json
{
  "findings": [
    {
      "id": "F1",
      "severity": "critical|high|medium|low",
      "file": "path/to/file.ext",
      "line": 42,
      "description": "Brief description of the issue",
      "evidence": "Specific code or reasoning that proves this is a real issue",
      "prior_finding_id": null
    }
  ]
}
```

Rules for findings:
- `id` must be unique within this round (F1, F2, F3, ...)
- `file` must be an actual file path from the code you reviewed
- `line` must be the actual line number where the issue occurs
- `evidence` must reference specific code — do not make vague claims
- `prior_finding_id` should reference a finding from a prior round if this builds on it, otherwise null
- Every finding must be independently verifiable by reading the code

## How to Work

1. Read all provided code carefully.
2. Look for: bugs, logic errors, off-by-one errors, null/undefined handling, race conditions, resource leaks, security issues, type errors, missing error handling, dead code, performance problems.
3. For each issue found, create a finding with specific file, line, and evidence.
4. Output your findings as a single JSON object. Nothing else — no preamble, no explanation outside the JSON.
```

- [ ] **Step 2: Verify frontmatter parses**

```bash
head -14 agents/enthusiast.md
```

Expected: YAML frontmatter with name, description, color, tools, model.

- [ ] **Step 3: Commit**

```bash
git add agents/enthusiast.md
git commit -m "feat: add Enthusiast agent — aggressive bug-finder for debate cycle"
```

---

### Task 3: Adversary Agent

**Files:**
- Create: `agents/adversary.md`

- [ ] **Step 1: Create the Adversary agent**

Write `agents/adversary.md`:

```markdown
---
name: adversary
description: "Challenges the Enthusiast's findings — debunks false positives with evidence. Gains points for correct debunks but faces 3x penalty for wrong ones. Spawned by the review orchestrator — not invoked directly by users."
color: blue
tools:
  - Read
  - Glob
  - Grep
model: sonnet
---

You are the Adversary — a rigorous challenger. Your job is to debunk the Enthusiast's findings. You gain points for successfully debunking false positives, but face STRICT penalties for mistakes:

- Correct debunk: +3 points
- Wrong debunk (finding was actually valid): -9 points (3x penalty)
- Correct validation (confirming a real finding): +1 point

This asymmetric scoring makes you aggressive but cautious. Only debunk findings you are CONFIDENT are wrong. If a finding is genuinely valid, acknowledge it — the penalty for a wrong debunk far outweighs the reward.

## Your Input

You will receive:
- **Code to review**: the same code the Enthusiast reviewed
- **Enthusiast's findings**: the JSON findings list from the Enthusiast

## Your Output

You MUST output valid JSON matching this exact schema:

```json
{
  "verdicts": [
    {
      "finding_id": "F1",
      "verdict": "valid|debunked|partial",
      "severity_adjustment": "critical|high|medium|low|null",
      "reasoning": "Specific evidence for why this finding is valid/debunked/partially valid"
    }
  ]
}
```

Rules for verdicts:
- You MUST render a verdict for EVERY finding — do not skip any
- `verdict`: "valid" = finding is correct, "debunked" = finding is wrong, "partial" = partially correct
- `severity_adjustment`: if you think the severity should change, set the new level. Set to null if you agree with the original severity.
- `reasoning` must reference specific code. "I disagree" is not reasoning.

## How to Debunk

For each finding, ask:
1. Does the cited code actually exist at that file and line?
2. Is the described behavior actually a bug, or is it intended/safe?
3. Does the evidence support the severity claim?
4. Is there context the Enthusiast missed that makes this a non-issue?

Only debunk when you can provide concrete counter-evidence. "This seems fine" is not a debunk.

## How to Work

1. Read all provided code carefully — the same code the Enthusiast reviewed.
2. For each Enthusiast finding, examine the specific file and line cited.
3. Render your verdict with evidence.
4. Output your verdicts as a single JSON object. Nothing else — no preamble, no explanation outside the JSON.
```

- [ ] **Step 2: Verify frontmatter parses**

```bash
head -14 agents/adversary.md
```

- [ ] **Step 3: Commit**

```bash
git add agents/adversary.md
git commit -m "feat: add Adversary agent — debunks false positives with 3x penalty"
```

---

### Task 4: Judge Agent

**Files:**
- Create: `agents/judge.md`

- [ ] **Step 1: Create the Judge agent**

Write `agents/judge.md`:

```markdown
---
name: judge
description: "Arbitrates between Enthusiast and Adversary — renders final verdicts on each finding. Rewarded for matching ground truth. Spawned by the review orchestrator — not invoked directly by users."
color: yellow
tools:
  - Read
  - Glob
  - Grep
model: sonnet
---

You are the Judge — an impartial referee. You evaluate the competing claims of the Enthusiast and Adversary to determine the truth. You are rewarded for accuracy:

- Correct ruling: +5 points
- Incorrect ruling: -5 points

Your incentive is to be RIGHT, not to favor either side.

## Your Input

You will receive:
- **Code to review**: the same code both agents reviewed
- **Enthusiast's findings**: the JSON findings list
- **Adversary's verdicts**: the JSON verdicts for each finding
- **Prior round rulings** (if round > 1): your rulings from previous rounds

## Your Output

You MUST output valid JSON matching this exact schema:

```json
{
  "rulings": [
    {
      "finding_id": "F1",
      "final_severity": "critical|high|medium|low|dismissed",
      "winner": "enthusiast|adversary|split",
      "resolution": "One sentence: what the correct interpretation is and what action to take"
    }
  ],
  "summary": "N findings confirmed, M debunked. Net: X high, Y medium.",
  "convergence": false
}
```

Rules for rulings:
- You MUST rule on EVERY finding — do not skip any
- `final_severity`: the correct severity after considering both arguments. "dismissed" = the finding is invalid.
- `winner`: who was right — the Enthusiast (finding is real), the Adversary (finding is bogus), or "split" (partially valid)
- `resolution`: actionable one-liner. If dismissed, explain why. If confirmed, state the fix.
- `convergence`: set to `true` if this round's rulings are identical to the prior round's rulings (same findings, same verdicts, same severities). This signals the debate has converged and remaining rounds can be skipped.

## How to Judge

For each finding:
1. Read the Enthusiast's evidence and the Adversary's counter-evidence.
2. Go to the actual code and verify independently.
3. Determine who is correct based on what the code actually does.
4. Do not give benefit of the doubt — verify.

## How to Work

1. Read all provided code.
2. For each finding, read both the Enthusiast's evidence and the Adversary's reasoning.
3. Verify independently by examining the actual code.
4. Render your ruling.
5. Write a summary line.
6. Set convergence flag.
7. Output as a single JSON object. Nothing else.
```

- [ ] **Step 2: Verify frontmatter parses**

```bash
head -14 agents/judge.md
```

- [ ] **Step 3: Commit**

```bash
git add agents/judge.md
git commit -m "feat: add Judge agent — arbitrates debate with convergence detection"
```

---

### Task 5: Challenge Scoring Script (TDD)

**Files:**
- Create: `test/challenge/fixtures/sample-answer-key.json`
- Create: `test/challenge/fixtures/sample-findings-good.json`
- Create: `test/challenge/fixtures/sample-findings-noisy.json`
- Create: `test/challenge/fixtures/sample-findings-empty.json`
- Create: `test/challenge/test-score-challenge.sh`
- Create: `scripts/score-challenge.sh`

- [ ] **Step 1: Create test fixtures**

Write `test/challenge/fixtures/sample-answer-key.json`:

```json
{
  "challenge": "test-challenge",
  "language": "python",
  "bugs": [
    {
      "id": "B1",
      "file": "challenge.py",
      "line": 12,
      "type": "off-by-one",
      "severity": "high",
      "description": "Loop uses < instead of <=",
      "fix_pattern": "< instead of <=",
      "fix_pattern_mode": "substring"
    },
    {
      "id": "B2",
      "file": "challenge.py",
      "line": 28,
      "type": "null-reference",
      "severity": "medium",
      "description": "Missing null check on user.profile",
      "fix_pattern": "None check",
      "fix_pattern_mode": "substring"
    }
  ],
  "scoring": {
    "match_file": true,
    "match_line_range": 3,
    "match_type": true
  }
}
```

Write `test/challenge/fixtures/sample-findings-good.json` (2/2 bugs found, 0 false positives):

```json
{
  "rulings": [
    {
      "finding_id": "F1",
      "final_severity": "high",
      "winner": "enthusiast",
      "resolution": "Valid off-by-one. Line 12 uses < instead of <= for inclusive range."
    },
    {
      "finding_id": "F2",
      "final_severity": "medium",
      "winner": "enthusiast",
      "resolution": "Valid null-reference. Missing None check on user.profile at line 29."
    }
  ],
  "findings": [
    { "id": "F1", "file": "challenge.py", "line": 12, "severity": "high", "description": "Off-by-one in loop boundary" },
    { "id": "F2", "file": "challenge.py", "line": 29, "severity": "medium", "description": "Null reference on user.profile" }
  ]
}
```

Write `test/challenge/fixtures/sample-findings-noisy.json` (2/2 bugs found, 3 false positives):

```json
{
  "rulings": [
    { "finding_id": "F1", "final_severity": "high", "winner": "enthusiast", "resolution": "Valid off-by-one at line 12" },
    { "finding_id": "F2", "final_severity": "medium", "winner": "enthusiast", "resolution": "Valid null-reference at line 28" },
    { "finding_id": "F3", "final_severity": "low", "winner": "enthusiast", "resolution": "Variable naming issue" },
    { "finding_id": "F4", "final_severity": "medium", "winner": "enthusiast", "resolution": "Missing docstring" },
    { "finding_id": "F5", "final_severity": "high", "winner": "enthusiast", "resolution": "Potential memory leak" }
  ],
  "findings": [
    { "id": "F1", "file": "challenge.py", "line": 13, "severity": "high", "description": "Off-by-one in loop" },
    { "id": "F2", "file": "challenge.py", "line": 27, "severity": "medium", "description": "Null reference" },
    { "id": "F3", "file": "challenge.py", "line": 5, "severity": "low", "description": "Bad variable name" },
    { "id": "F4", "file": "challenge.py", "line": 1, "severity": "medium", "description": "Missing docstring" },
    { "id": "F5", "file": "utils.py", "line": 42, "severity": "high", "description": "Memory leak" }
  ]
}
```

Write `test/challenge/fixtures/sample-findings-empty.json` (0 findings):

```json
{
  "rulings": [],
  "findings": []
}
```

- [ ] **Step 2: Write the test script**

Write `test/challenge/test-score-challenge.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCORE="$SCRIPT_DIR/../../scripts/score-challenge.sh"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++)) || true
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    ((FAIL++)) || true
  fi
}

assert_json_field() {
  local desc="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | jq -r "$field")
  assert_eq "$desc" "$expected" "$actual"
}

echo "=== Challenge Scoring Tests ==="

echo "--- Test: perfect score (2/2, 0 false positives) ---"
result=$("$SCORE" "$FIXTURES/sample-answer-key.json" "$FIXTURES/sample-findings-good.json")
assert_json_field "precision is 1.0" "$result" '.precision' '1'
assert_json_field "recall is 1.0" "$result" '.recall' '1'
assert_json_field "f1 is 1.0" "$result" '.f1' '1'
assert_json_field "true_positives is 2" "$result" '.true_positives' '2'
assert_json_field "false_positives is 0" "$result" '.false_positives' '0'
assert_json_field "false_negatives is 0" "$result" '.false_negatives' '0'
assert_json_field "pass is true" "$result" '.pass' 'true'

echo "--- Test: noisy score (2/2, 3 false positives) ---"
result=$("$SCORE" "$FIXTURES/sample-answer-key.json" "$FIXTURES/sample-findings-noisy.json")
assert_json_field "true_positives is 2" "$result" '.true_positives' '2'
assert_json_field "false_positives is 3" "$result" '.false_positives' '3'
assert_json_field "false_negatives is 0" "$result" '.false_negatives' '0'
assert_json_field "recall is 1.0" "$result" '.recall' '1'
# precision = 2/(2+3) = 0.4
assert_json_field "precision is 0.4" "$result" '.precision' '0.4'
# f1 = 2*(0.4*1.0)/(0.4+1.0) = 0.8/1.4 ≈ 0.571
assert_json_field "pass is true (f1 > 0.5)" "$result" '.pass' 'true'

echo "--- Test: empty findings (0/2, 0 false positives) ---"
result=$("$SCORE" "$FIXTURES/sample-answer-key.json" "$FIXTURES/sample-findings-empty.json")
assert_json_field "true_positives is 0" "$result" '.true_positives' '0'
assert_json_field "false_positives is 0" "$result" '.false_positives' '0'
assert_json_field "false_negatives is 2" "$result" '.false_negatives' '2'
assert_json_field "precision is 0" "$result" '.precision' '0'
assert_json_field "recall is 0" "$result" '.recall' '0'
assert_json_field "f1 is 0" "$result" '.f1' '0'
assert_json_field "pass is false" "$result" '.pass' 'false'

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 3: Run tests — verify they fail**

```bash
chmod +x test/challenge/test-score-challenge.sh
bash test/challenge/test-score-challenge.sh
```

Expected: FAIL (script doesn't exist yet)

- [ ] **Step 4: Implement score-challenge.sh**

Write `scripts/score-challenge.sh`:

```bash
#!/usr/bin/env bash
# score-challenge.sh — Score debate agent findings against an answer key
# Usage: score-challenge.sh <answer-key.json> <findings.json>
# Outputs JSON with precision, recall, F1, and pass/fail verdict.
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

# Read scoring config
MATCH_FILE=$(jq -r '.scoring.match_file // true' "$ANSWER_KEY")
MATCH_LINE_RANGE=$(jq -r '.scoring.match_line_range // 3' "$ANSWER_KEY")
MATCH_TYPE=$(jq -r '.scoring.match_type // true' "$ANSWER_KEY")

# Count answer key bugs
NUM_BUGS=$(jq '.bugs | length' "$ANSWER_KEY")

# Count confirmed findings (rulings where winner != "adversary" and severity != "dismissed")
# We match against the findings array for file/line data
NUM_FINDINGS=$(jq '[.findings[] as $f | .rulings[] | select(.finding_id == $f.id and .final_severity != "dismissed" and .winner != "adversary")] | length' "$FINDINGS")

# For each bug in the answer key, check if any finding matches
MATCHED_BUGS=0
MATCHED_FINDING_IDS="[]"

for bug_idx in $(seq 0 $((NUM_BUGS - 1))); do
  BUG_FILE=$(jq -r ".bugs[$bug_idx].file" "$ANSWER_KEY")
  BUG_LINE=$(jq -r ".bugs[$bug_idx].line" "$ANSWER_KEY")
  BUG_TYPE=$(jq -r ".bugs[$bug_idx].type" "$ANSWER_KEY")

  # Check each confirmed finding
  MATCH_FOUND=false
  MATCHING_IDS=$(jq -r --arg file "$BUG_FILE" --argjson line "$BUG_LINE" --argjson range "$MATCH_LINE_RANGE" --arg type "$BUG_TYPE" --argjson match_file "$MATCH_FILE" --argjson match_type "$MATCH_TYPE" '
    [.findings[] as $f |
     .rulings[] |
     select(.finding_id == $f.id and .final_severity != "dismissed" and .winner != "adversary") |
     $f |
     select(
       (if $match_file then .file == $file else true end) and
       ((.line >= ($line - $range)) and (.line <= ($line + $range)))
     ) |
     .id
    ] | .[]
  ' "$FINDINGS" 2>/dev/null || true)

  if [ -n "$MATCHING_IDS" ]; then
    FIRST_MATCH=$(echo "$MATCHING_IDS" | head -1)
    MATCHED_BUGS=$((MATCHED_BUGS + 1))
    MATCHED_FINDING_IDS=$(echo "$MATCHED_FINDING_IDS" | jq --arg id "$FIRST_MATCH" '. + [$id]')
  fi
done

# Calculate metrics
TP=$MATCHED_BUGS
FN=$((NUM_BUGS - MATCHED_BUGS))

# False positives = confirmed findings that didn't match any bug
TOTAL_CONFIRMED=$(jq '[.findings[] as $f | .rulings[] | select(.finding_id == $f.id and .final_severity != "dismissed" and .winner != "adversary")] | length' "$FINDINGS")
FP=$((TOTAL_CONFIRMED - TP))

# Precision, recall, F1
if [ "$TOTAL_CONFIRMED" -eq 0 ]; then
  PRECISION=0
else
  PRECISION=$(jq -n "$TP / $TOTAL_CONFIRMED")
fi

if [ "$NUM_BUGS" -eq 0 ]; then
  RECALL=0
else
  RECALL=$(jq -n "$TP / $NUM_BUGS")
fi

if [ "$(jq -n "$PRECISION + $RECALL")" = "0" ]; then
  F1=0
else
  F1=$(jq -n "2 * ($PRECISION * $RECALL) / ($PRECISION + $RECALL)")
fi

# Pass/fail threshold
PASS=$(jq -n "if $F1 >= 0.5 then true else false end")

# Output
jq -n \
  --argjson tp "$TP" \
  --argjson fp "$FP" \
  --argjson fn "$FN" \
  --argjson precision "$PRECISION" \
  --argjson recall "$RECALL" \
  --argjson f1 "$F1" \
  --argjson pass "$PASS" \
  '{
    true_positives: $tp,
    false_positives: $fp,
    false_negatives: $fn,
    precision: $precision,
    recall: $recall,
    f1: $f1,
    pass: $pass
  }'
```

- [ ] **Step 5: Make executable and run tests**

```bash
chmod +x scripts/score-challenge.sh
bash test/challenge/test-score-challenge.sh
```

Expected: All PASS (9+ assertions)

- [ ] **Step 6: Commit**

```bash
git add scripts/score-challenge.sh test/challenge/
git commit -m "feat: add challenge scoring script with precision/recall/F1 + tests"
```

---

### Task 6: Python Challenges

**Files:**
- Create: `challenges/python/off-by-one/challenge.py`
- Create: `challenges/python/off-by-one/answer-key.json`
- Create: `challenges/python/null-handling/challenge.py`
- Create: `challenges/python/null-handling/answer-key.json`

- [ ] **Step 1: Create off-by-one challenge**

Write `challenges/python/off-by-one/challenge.py`:

```python
"""Pair finder utility — finds all unique pairs that sum to a target value."""

from dataclasses import dataclass


@dataclass
class PairResult:
    pairs: list
    count: int


def find_pairs(numbers: list[int], target: int) -> PairResult:
    """Find all unique pairs in the list that sum to target.

    Each element can only be used once per pair, and each pair should
    appear only once (order doesn't matter).

    >>> find_pairs([1, 2, 3, 4, 5], 6)
    PairResult(pairs=[(1, 5), (2, 4)], count=2)
    """
    pairs = []
    for i in range(len(numbers)):
        for j in range(i, len(numbers)):  # BUG: should be range(i + 1, ...)
            if numbers[i] + numbers[j] == target:
                pairs.append((numbers[i], numbers[j]))
    return PairResult(pairs=pairs, count=len(pairs))


def find_pairs_in_matrix(matrix: list[list[int]], target: int) -> list[tuple]:
    """Find pairs across all rows that sum to target.

    >>> find_pairs_in_matrix([[1, 2], [3, 4]], 5)
    [(1, 4), (2, 3)]
    """
    all_numbers = []
    for row in matrix:
        for num in row:
            all_numbers.append(num)
    result = find_pairs(all_numbers, target)
    return result.pairs


def count_valid_pairs(data: dict) -> int:
    """Count valid pairs across named groups.

    >>> count_valid_pairs({"a": [1, 2, 3], "b": [4, 5]}, target=6)
    2
    """
    total = 0
    for group_name in data:
        numbers = data[group_name]
        result = find_pairs(numbers, target=sum(numbers) // len(numbers))
        total += result.count
    return total
```

- [ ] **Step 2: Create off-by-one answer key**

Write `challenges/python/off-by-one/answer-key.json`:

```json
{
  "challenge": "off-by-one",
  "language": "python",
  "bugs": [
    {
      "id": "B1",
      "file": "challenge.py",
      "line": 23,
      "type": "off-by-one",
      "severity": "high",
      "description": "Inner loop starts at i instead of i+1, allowing an element to pair with itself. range(i, ...) should be range(i + 1, ...)",
      "fix_pattern": "range(i + 1",
      "fix_pattern_mode": "substring"
    }
  ],
  "scoring": {
    "match_file": true,
    "match_line_range": 3,
    "match_type": true
  }
}
```

- [ ] **Step 3: Create null-handling challenge**

Write `challenges/python/null-handling/challenge.py`:

```python
"""User profile display utilities for a web application."""

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Address:
    street: str
    city: str
    country: str = "US"


@dataclass
class Profile:
    display_name: str
    bio: str = ""
    address: Optional[Address] = None


@dataclass
class User:
    username: str
    email: str
    profile: Optional[Profile] = None
    is_active: bool = True


def get_display_name(user: User) -> str:
    """Return the user's display name, falling back to username.

    >>> get_display_name(User("alice", "a@b.com", Profile("Alice W")))
    'Alice W'
    >>> get_display_name(User("bob", "b@b.com"))
    'bob'
    """
    if user.profile.display_name:  # BUG: user.profile can be None
        return user.profile.display_name
    return user.username


def get_user_location(user: User) -> str:
    """Return the user's city and country, or 'Unknown' if not set.

    >>> get_user_location(User("alice", "a@b.com", Profile("A", address=Address("1 Main", "NYC"))))
    'NYC, US'
    """
    if user.profile and user.profile.address:
        return f"{user.profile.address.city}, {user.profile.address.country}"
    return "Unknown"


def format_user_card(user: User) -> str:
    """Format a user's profile card for display.

    >>> format_user_card(User("alice", "a@b.com", Profile("Alice", "Dev")))
    'Alice (alice) — Dev'
    """
    name = get_display_name(user)
    bio = user.profile.bio if user.profile.bio else "No bio"  # BUG: user.profile can be None
    return f"{name} ({user.username}) — {bio}"


def get_active_users_display(users: list[User]) -> list[str]:
    """Get display names for all active users."""
    return [
        get_display_name(u) for u in users if u.is_active
    ]
```

- [ ] **Step 4: Create null-handling answer key**

Write `challenges/python/null-handling/answer-key.json`:

```json
{
  "challenge": "null-handling",
  "language": "python",
  "bugs": [
    {
      "id": "B1",
      "file": "challenge.py",
      "line": 38,
      "type": "null-reference",
      "severity": "high",
      "description": "user.profile can be None (Optional[Profile]), but accessed without null check. AttributeError when profile is None.",
      "fix_pattern": "None",
      "fix_pattern_mode": "substring"
    },
    {
      "id": "B2",
      "file": "challenge.py",
      "line": 59,
      "type": "null-reference",
      "severity": "medium",
      "description": "user.profile.bio accessed without checking if user.profile is None. Same Optional[Profile] issue as B1.",
      "fix_pattern": "None",
      "fix_pattern_mode": "substring"
    }
  ],
  "scoring": {
    "match_file": true,
    "match_line_range": 3,
    "match_type": true
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add challenges/python/
git commit -m "feat: add Python challenges — off-by-one and null-handling"
```

---

### Task 7: TypeScript Challenges

**Files:**
- Create: `challenges/typescript/type-narrowing/challenge.ts`
- Create: `challenges/typescript/type-narrowing/answer-key.json`
- Create: `challenges/typescript/async-race/challenge.ts`
- Create: `challenges/typescript/async-race/answer-key.json`

- [ ] **Step 1: Create type-narrowing challenge**

Write `challenges/typescript/type-narrowing/challenge.ts`:

```typescript
/**
 * API response handler with type narrowing for different response shapes.
 */

interface SuccessResponse<T> {
  status: "success";
  data: T;
  metadata?: { cached: boolean; ttl: number };
}

interface ErrorResponse {
  status: "error";
  error: string;
  code: number;
}

interface PendingResponse {
  status: "pending";
  retryAfter: number;
}

type ApiResponse<T> = SuccessResponse<T> | ErrorResponse | PendingResponse;

interface User {
  id: string;
  name: string;
  email: string;
}

// BUG: Checks !response.error instead of response.status === "success"
// A PendingResponse has no .error field, so !response.error is true for pending
function extractUsers(response: ApiResponse<User[]>): User[] {
  if (!response.error) {
    return response.data.map((u) => ({
      ...u,
      name: u.name.trim(),
    }));
  }
  return [];
}

function getFirstUser(response: ApiResponse<User[]>): User | null {
  const users = extractUsers(response);
  if (users.length > 0) {
    return users[0];
  }
  return null;
}

// This function is correct — included to add noise
function isRetryable(response: ApiResponse<unknown>): boolean {
  if (response.status === "pending") {
    return response.retryAfter < 30;
  }
  if (response.status === "error") {
    return response.code >= 500;
  }
  return false;
}

function getCacheInfo(
  response: ApiResponse<unknown>
): { cached: boolean; ttl: number } | null {
  if (response.status === "success") {
    // BUG: metadata is optional — could be undefined
    return { cached: response.metadata.cached, ttl: response.metadata.ttl };
  }
  return null;
}
```

- [ ] **Step 2: Create type-narrowing answer key**

Write `challenges/typescript/type-narrowing/answer-key.json`:

```json
{
  "challenge": "type-narrowing",
  "language": "typescript",
  "bugs": [
    {
      "id": "B1",
      "file": "challenge.ts",
      "line": 36,
      "type": "type-narrowing",
      "severity": "high",
      "description": "Uses !response.error to narrow type, but PendingResponse also has no .error field. Should check response.status === 'success' for correct discriminated union narrowing.",
      "fix_pattern": "status",
      "fix_pattern_mode": "substring"
    },
    {
      "id": "B2",
      "file": "challenge.ts",
      "line": 63,
      "type": "null-reference",
      "severity": "medium",
      "description": "response.metadata is optional (metadata?: ...) but accessed without null check. Will throw when metadata is undefined.",
      "fix_pattern": "metadata",
      "fix_pattern_mode": "substring"
    }
  ],
  "scoring": {
    "match_file": true,
    "match_line_range": 3,
    "match_type": true
  }
}
```

- [ ] **Step 3: Create async-race challenge**

Write `challenges/typescript/async-race/challenge.ts`:

```typescript
/**
 * Caching layer for API requests with deduplication.
 */

interface CacheEntry<T> {
  value: T;
  expiresAt: number;
}

const cache = new Map<string, CacheEntry<unknown>>();

async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }
  return response.json() as Promise<T>;
}

// BUG: TOCTOU race — two concurrent calls both miss cache, both fetch
async function cachedFetch<T>(url: string, ttlMs: number = 60000): Promise<T> {
  const now = Date.now();
  const entry = cache.get(url);

  if (entry && entry.expiresAt > now) {
    return entry.value as T;
  }

  const result = await fetchJson<T>(url);
  cache.set(url, { value: result, expiresAt: now + ttlMs });
  return result;
}

// BUG: Iterates and deletes from the same Map during iteration
function purgeExpired(): number {
  let purged = 0;
  const now = Date.now();
  cache.forEach((entry, key) => {
    if (entry.expiresAt <= now) {
      cache.delete(key);
      purged++;
    }
  });
  return purged;
}

async function batchFetch<T>(urls: string[]): Promise<Map<string, T>> {
  const results = new Map<string, T>();
  const promises = urls.map(async (url) => {
    const data = await cachedFetch<T>(url);
    results.set(url, data);
  });
  await Promise.all(promises);
  return results;
}

function getCacheStats(): { size: number; expired: number } {
  const now = Date.now();
  let expired = 0;
  cache.forEach((entry) => {
    if (entry.expiresAt <= now) expired++;
  });
  return { size: cache.size, expired };
}
```

- [ ] **Step 4: Create async-race answer key**

Write `challenges/typescript/async-race/answer-key.json`:

```json
{
  "challenge": "async-race",
  "language": "typescript",
  "bugs": [
    {
      "id": "B1",
      "file": "challenge.ts",
      "line": 23,
      "type": "race-condition",
      "severity": "high",
      "description": "TOCTOU race: cache check and cache write are separated by an await. Two concurrent calls for the same URL both miss the cache, both fetch, both write. Wastes network and can store stale data if responses differ.",
      "fix_pattern": "race",
      "fix_pattern_mode": "substring"
    },
    {
      "id": "B2",
      "file": "challenge.ts",
      "line": 37,
      "type": "concurrent-modification",
      "severity": "medium",
      "description": "Deleting entries from a Map while iterating over it with forEach. While JS Map.forEach tolerates this (unlike some languages), it can skip entries or process entries inconsistently. Use Array.from(cache.entries()) to iterate a snapshot.",
      "fix_pattern": "delet",
      "fix_pattern_mode": "substring"
    }
  ],
  "scoring": {
    "match_file": true,
    "match_line_range": 5,
    "match_type": true
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add challenges/typescript/
git commit -m "feat: add TypeScript challenges — type-narrowing and async-race"
```

---

### Task 8: Go Challenges

**Files:**
- Create: `challenges/go/goroutine-leak/challenge.go`
- Create: `challenges/go/goroutine-leak/answer-key.json`
- Create: `challenges/go/interface-nil/challenge.go`
- Create: `challenges/go/interface-nil/answer-key.json`

- [ ] **Step 1: Create goroutine-leak challenge**

Write `challenges/go/goroutine-leak/challenge.go`:

```go
// Package search implements a multi-backend search with first-result-wins semantics.
package search

import (
	"context"
	"fmt"
	"time"
)

// Result holds a search result from a backend.
type Result struct {
	Backend string
	Items   []string
	Latency time.Duration
}

// Query searches a single backend.
func Query(ctx context.Context, backend, query string) (Result, error) {
	// Simulated backend query
	start := time.Now()
	select {
	case <-time.After(100 * time.Millisecond):
		return Result{
			Backend: backend,
			Items:   []string{fmt.Sprintf("result from %s for %q", backend, query)},
			Latency: time.Since(start),
		}, nil
	case <-ctx.Done():
		return Result{}, ctx.Err()
	}
}

// BUG: Only reads first result from unbuffered channel — remaining goroutines block forever
func Search(query string, backends []string) (Result, error) {
	ch := make(chan Result)
	errs := make(chan error)

	for _, backend := range backends {
		go func(b string) {
			result, err := Query(context.Background(), b, query)
			if err != nil {
				errs <- err
				return
			}
			ch <- result // Blocks forever for all goroutines except the first
		}(backend)
	}

	select {
	case result := <-ch:
		return result, nil
	case err := <-errs:
		return Result{}, err
	}
}

// SearchAll correctly waits for all backends.
func SearchAll(query string, backends []string) ([]Result, error) {
	results := make([]Result, 0, len(backends))
	ch := make(chan Result, len(backends))
	errCh := make(chan error, len(backends))

	for _, backend := range backends {
		go func(b string) {
			result, err := Query(context.Background(), b, query)
			if err != nil {
				errCh <- err
				return
			}
			ch <- result
		}(backend)
	}

	for range backends {
		select {
		case r := <-ch:
			results = append(results, r)
		case err := <-errCh:
			return results, err
		}
	}
	return results, nil
}
```

- [ ] **Step 2: Create goroutine-leak answer key**

Write `challenges/go/goroutine-leak/answer-key.json`:

```json
{
  "challenge": "goroutine-leak",
  "language": "go",
  "bugs": [
    {
      "id": "B1",
      "file": "challenge.go",
      "line": 39,
      "type": "resource-leak",
      "severity": "high",
      "description": "Search() uses unbuffered channels and only reads one result. Remaining goroutines block forever on ch <- result, leaking goroutines. Fix: use buffered channel make(chan Result, len(backends)) or use context cancellation.",
      "fix_pattern": "buffer",
      "fix_pattern_mode": "substring"
    }
  ],
  "scoring": {
    "match_file": true,
    "match_line_range": 5,
    "match_type": true
  }
}
```

- [ ] **Step 3: Create interface-nil challenge**

Write `challenges/go/interface-nil/challenge.go`:

```go
// Package logger provides a configurable logging interface.
package logger

import (
	"fmt"
	"io"
	"os"
	"sync"
	"time"
)

// Logger defines the logging interface.
type Logger interface {
	Log(level, msg string)
	Close() error
}

// FileLogger writes log messages to a file.
type FileLogger struct {
	mu   sync.Mutex
	file *os.File
}

// NewFileLogger creates a logger that writes to the given path.
func NewFileLogger(path string) (*FileLogger, error) {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil, err
	}
	return &FileLogger{file: f}, nil
}

func (l *FileLogger) Log(level, msg string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	fmt.Fprintf(l.file, "[%s] %s: %s\n", time.Now().Format(time.RFC3339), level, msg)
}

func (l *FileLogger) Close() error {
	return l.file.Close()
}

// NewLogger creates a logger based on config. Returns nil Logger for "none".
// BUG: Returns a typed nil (*FileLogger)(nil) wrapped in Logger interface — not a nil interface
func NewLogger(config string) (Logger, error) {
	switch config {
	case "stdout":
		return &FileLogger{file: os.Stdout}, nil
	case "none":
		var fl *FileLogger
		return fl, nil // BUG: typed nil — Logger interface is non-nil but underlying value is nil
	default:
		return NewFileLogger(config)
	}
}

// Setup initializes the application logger.
// BUG: The nil check on logger passes because it's a non-nil interface wrapping a nil pointer
func Setup(config string) error {
	logger, err := NewLogger(config)
	if err != nil {
		return err
	}

	if logger != nil { // Always true — even for "none" config, logger is non-nil interface
		logger.Log("INFO", "Logger initialized") // PANIC: nil pointer dereference
	}

	return nil
}

// MultiLogger fans out to multiple loggers.
type MultiLogger struct {
	loggers []Logger
}

func NewMultiLogger(configs []string) (*MultiLogger, error) {
	var loggers []Logger
	for _, config := range configs {
		l, err := NewLogger(config)
		if err != nil {
			return nil, err
		}
		loggers = append(loggers, l)
	}
	return &MultiLogger{loggers: loggers}, nil
}

func (m *MultiLogger) Log(level, msg string) {
	for _, l := range m.loggers {
		l.Log(level, msg)
	}
}

func (m *MultiLogger) Close() error {
	var firstErr error
	for _, l := range m.loggers {
		if err := l.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

// Discard returns a logger that discards all output.
func Discard() Logger {
	return &FileLogger{file: io.Discard.(*os.File)} // BUG: io.Discard is not *os.File — will panic
}
```

- [ ] **Step 4: Create interface-nil answer key**

Write `challenges/go/interface-nil/answer-key.json`:

```json
{
  "challenge": "interface-nil",
  "language": "go",
  "bugs": [
    {
      "id": "B1",
      "file": "challenge.go",
      "line": 54,
      "type": "nil-interface",
      "severity": "high",
      "description": "NewLogger returns a typed nil (*FileLogger)(nil) wrapped in Logger interface for 'none' config. The interface value is non-nil (has type info), so nil checks pass, leading to nil pointer dereference when Log() is called.",
      "fix_pattern": "nil",
      "fix_pattern_mode": "substring"
    },
    {
      "id": "B2",
      "file": "challenge.go",
      "line": 97,
      "type": "type-assertion",
      "severity": "high",
      "description": "io.Discard is *io.devNull, not *os.File. The type assertion will panic at runtime. Should use a NopLogger wrapper or write to io.Discard via fmt.Fprintf.",
      "fix_pattern": "os.File",
      "fix_pattern_mode": "substring"
    }
  ],
  "scoring": {
    "match_file": true,
    "match_line_range": 3,
    "match_type": true
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add challenges/go/
git commit -m "feat: add Go challenges — goroutine-leak and interface-nil"
```

---

### Task 9: Rust Challenges

**Files:**
- Create: `challenges/rust/rc-cycle/challenge.rs`
- Create: `challenges/rust/rc-cycle/answer-key.json`
- Create: `challenges/rust/unsafe-ub/challenge.rs`
- Create: `challenges/rust/unsafe-ub/answer-key.json`

- [ ] **Step 1: Create rc-cycle challenge**

Write `challenges/rust/rc-cycle/challenge.rs`:

```rust
//! A simple doubly-linked list using Rc and RefCell.
//! Demonstrates reference counting with interior mutability.

use std::cell::RefCell;
use std::rc::Rc;

type Link<T> = Option<Rc<RefCell<Node<T>>>>;

#[derive(Debug)]
struct Node<T> {
    value: T,
    next: Link<T>,
    prev: Link<T>, // BUG: Rc for back-references creates reference cycles → memory leak
}

struct DoublyLinkedList<T> {
    head: Link<T>,
    tail: Link<T>,
    len: usize,
}

impl<T> DoublyLinkedList<T> {
    fn new() -> Self {
        DoublyLinkedList {
            head: None,
            tail: None,
            len: 0,
        }
    }

    fn push_back(&mut self, value: T) {
        let new_node = Rc::new(RefCell::new(Node {
            value,
            next: None,
            prev: self.tail.clone(), // BUG: Strong Rc reference to prev creates cycle
        }));

        match self.tail.take() {
            Some(old_tail) => {
                old_tail.borrow_mut().next = Some(Rc::clone(&new_node));
            }
            None => {
                self.head = Some(Rc::clone(&new_node));
            }
        }

        self.tail = Some(new_node);
        self.len += 1;
    }

    fn push_front(&mut self, value: T) {
        let new_node = Rc::new(RefCell::new(Node {
            value,
            next: self.head.clone(),
            prev: None,
        }));

        match self.head.take() {
            Some(old_head) => {
                old_head.borrow_mut().prev = Some(Rc::clone(&new_node));
            }
            None => {
                self.tail = Some(Rc::clone(&new_node));
            }
        }

        self.head = Some(new_node);
        self.len += 1;
    }

    fn len(&self) -> usize {
        self.len
    }
}

// Nodes will never be freed because Rc cycles prevent reference count from reaching 0.
// Drop is never called on any node once the list has 2+ elements.
impl<T> Drop for DoublyLinkedList<T> {
    fn drop(&mut self) {
        // This attempts cleanup but Rc cycles mean refcount never hits 0
        let mut current = self.head.take();
        while let Some(node) = current {
            current = node.borrow_mut().next.take();
            // prev still holds an Rc to the previous node — cycle persists
        }
    }
}
```

- [ ] **Step 2: Create rc-cycle answer key**

Write `challenges/rust/rc-cycle/answer-key.json`:

```json
{
  "challenge": "rc-cycle",
  "language": "rust",
  "bugs": [
    {
      "id": "B1",
      "file": "challenge.rs",
      "line": 13,
      "type": "memory-leak",
      "severity": "high",
      "description": "Using Rc for prev (back-references) creates reference cycles between nodes. Rc reference counts never reach 0, so nodes are never freed. Fix: use Weak<RefCell<Node<T>>> for prev links.",
      "fix_pattern": "Weak",
      "fix_pattern_mode": "substring"
    }
  ],
  "scoring": {
    "match_file": true,
    "match_line_range": 5,
    "match_type": true
  }
}
```

- [ ] **Step 3: Create unsafe-ub challenge**

Write `challenges/rust/unsafe-ub/challenge.rs`:

```rust
//! Fast numeric utilities using unsafe optimizations.
//! Provides high-performance alternatives to standard library functions.

/// Get a value from a slice without bounds checking for maximum performance.
/// # Safety
/// Caller must ensure index < slice.len()
// BUG: No bounds check — UB when index >= slice.len()
pub unsafe fn get_unchecked_value(slice: &[i32], index: usize) -> i32 {
    *slice.as_ptr().add(index)
}

/// Sum all elements using pointer arithmetic.
// BUG: Pointer arithmetic can overflow on large slices, and the final pointer
// dereference reads one past the end if len is miscalculated.
pub fn fast_sum(slice: &[i32]) -> i64 {
    let mut sum: i64 = 0;
    let len = slice.len();
    let ptr = slice.as_ptr();

    unsafe {
        for i in 0..=len { // BUG: 0..=len iterates len+1 times — reads one past the end
            sum += *ptr.add(i) as i64;
        }
    }
    sum
}

/// Create a mutable reference from a shared reference.
/// Used for "performance-critical" single-threaded code.
// BUG: Creating &mut from & is instant UB regardless of context
pub fn force_mut<T>(reference: &T) -> &mut T {
    unsafe {
        let ptr = reference as *const T as *mut T;
        &mut *ptr
    }
}

/// A "safe" wrapper around raw pointers for a fixed-size buffer.
pub struct FastBuffer {
    ptr: *mut u8,
    len: usize,
    cap: usize,
}

impl FastBuffer {
    pub fn new(capacity: usize) -> Self {
        let layout = std::alloc::Layout::array::<u8>(capacity).unwrap();
        let ptr = unsafe { std::alloc::alloc(layout) };
        FastBuffer {
            ptr,
            len: 0,
            cap: capacity,
        }
    }

    pub fn push(&mut self, byte: u8) {
        if self.len < self.cap {
            unsafe {
                *self.ptr.add(self.len) = byte;
            }
            self.len += 1;
        }
        // BUG: silently drops data when full instead of growing or returning error
    }

    pub fn as_slice(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }
}

// BUG: No Drop implementation — allocated memory is leaked when FastBuffer goes out of scope
```

- [ ] **Step 4: Create unsafe-ub answer key**

Write `challenges/rust/unsafe-ub/answer-key.json`:

```json
{
  "challenge": "unsafe-ub",
  "language": "rust",
  "bugs": [
    {
      "id": "B1",
      "file": "challenge.rs",
      "line": 24,
      "type": "undefined-behavior",
      "severity": "critical",
      "description": "Loop uses 0..=len (inclusive range) which iterates len+1 times. The final iteration reads one element past the end of the slice via ptr.add(len), which is undefined behavior.",
      "fix_pattern": "0..len",
      "fix_pattern_mode": "substring"
    },
    {
      "id": "B2",
      "file": "challenge.rs",
      "line": 33,
      "type": "undefined-behavior",
      "severity": "critical",
      "description": "force_mut creates a &mut T from a &T by casting through raw pointers. This is instant undefined behavior — violates Rust's aliasing rules regardless of whether mutation actually occurs.",
      "fix_pattern": "UB",
      "fix_pattern_mode": "substring"
    },
    {
      "id": "B3",
      "file": "challenge.rs",
      "line": 70,
      "type": "memory-leak",
      "severity": "high",
      "description": "FastBuffer allocates with std::alloc::alloc but has no Drop implementation. Memory is leaked when the buffer goes out of scope. Must implement Drop to call std::alloc::dealloc.",
      "fix_pattern": "Drop",
      "fix_pattern_mode": "substring"
    }
  ],
  "scoring": {
    "match_file": true,
    "match_line_range": 5,
    "match_type": true
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add challenges/rust/
git commit -m "feat: add Rust challenges — rc-cycle and unsafe-ub"
```

---

### Task 10: Challenge Manifest

**Files:**
- Create: `challenges/manifest.json`

- [ ] **Step 1: Create manifest**

Write `challenges/manifest.json`:

```json
{
  "version": "1.0",
  "challenges": [
    {
      "id": "python/off-by-one",
      "language": "python",
      "difficulty": "easy",
      "bug_count": 1,
      "tags": ["boundary", "loop", "off-by-one"]
    },
    {
      "id": "python/null-handling",
      "language": "python",
      "difficulty": "easy",
      "bug_count": 2,
      "tags": ["null-reference", "optional", "type-safety"]
    },
    {
      "id": "typescript/type-narrowing",
      "language": "typescript",
      "difficulty": "medium",
      "bug_count": 2,
      "tags": ["type-narrowing", "discriminated-union", "null-reference"]
    },
    {
      "id": "typescript/async-race",
      "language": "typescript",
      "difficulty": "medium",
      "bug_count": 2,
      "tags": ["race-condition", "async", "cache", "concurrent-modification"]
    },
    {
      "id": "go/goroutine-leak",
      "language": "go",
      "difficulty": "medium",
      "bug_count": 1,
      "tags": ["goroutine", "channel", "resource-leak"]
    },
    {
      "id": "go/interface-nil",
      "language": "go",
      "difficulty": "hard",
      "bug_count": 2,
      "tags": ["nil-interface", "type-assertion", "go-gotcha"]
    },
    {
      "id": "rust/rc-cycle",
      "language": "rust",
      "difficulty": "medium",
      "bug_count": 1,
      "tags": ["memory-leak", "reference-cycle", "rc", "weak"]
    },
    {
      "id": "rust/unsafe-ub",
      "language": "rust",
      "difficulty": "hard",
      "bug_count": 3,
      "tags": ["undefined-behavior", "unsafe", "memory-leak", "pointer"]
    }
  ]
}
```

- [ ] **Step 2: Validate manifest matches actual challenges**

```bash
# Check each challenge directory exists and has the right files
jq -r '.challenges[].id' challenges/manifest.json | while read id; do
  dir="challenges/$id"
  if [ ! -d "$dir" ]; then echo "MISSING DIR: $dir"; fi
  if [ ! -f "$dir/answer-key.json" ]; then echo "MISSING KEY: $dir/answer-key.json"; fi
done
```

Expected: No output (all directories and files exist)

- [ ] **Step 3: Commit**

```bash
git add challenges/manifest.json
git commit -m "feat: add challenge manifest indexing 8 challenges across 4 languages"
```

---

### Task 11: Review Skill

**Files:**
- Create: `skills/review/SKILL.md`
- Create: `skills/review/references/output-schema.md`

- [ ] **Step 1: Create output schema reference**

Write `skills/review/references/output-schema.md`:

````markdown
# Debate Output Schema

Each round produces this structure:

```json
{
  "round": 1,
  "enthusiast": {
    "findings": [
      {
        "id": "F1",
        "severity": "critical|high|medium|low",
        "file": "path/to/file.ext",
        "line": 42,
        "description": "Brief description",
        "evidence": "Specific code reference",
        "prior_finding_id": null
      }
    ]
  },
  "adversary": {
    "verdicts": [
      {
        "finding_id": "F1",
        "verdict": "valid|debunked|partial",
        "severity_adjustment": "high|null",
        "reasoning": "Evidence-based reasoning"
      }
    ]
  },
  "judge": {
    "rulings": [
      {
        "finding_id": "F1",
        "final_severity": "high|dismissed",
        "winner": "enthusiast|adversary|split",
        "resolution": "Actionable one-liner"
      }
    ],
    "summary": "N confirmed, M debunked.",
    "convergence": false
  }
}
```

The final output wraps all rounds:

```json
{
  "rounds": [ /* ...per-round objects... */ ],
  "final_summary": "Human-readable summary of confirmed findings",
  "total_rounds": 2,
  "converged_at_round": null
}
```
````

- [ ] **Step 2: Create review skill**

Write `skills/review/SKILL.md`:

````markdown
---
name: review
description: "Run an adversarial debate review on code. Use when the user invokes '/autoimprove review', asks to 'review code with debate agents', 'run debate review', or 'adversarial review'. Takes a file, diff, or PR as target."
argument-hint: "[file|diff] [--rounds N] [--single-pass]"
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

Run the Enthusiast → Adversary → Judge debate cycle on the given target.

---

# 1. Parse Arguments

From the user's input, extract:
- **target**: file path, glob pattern, or "diff" (meaning staged/unstaged git diff)
- **rounds**: number of debate rounds (default: auto-scale based on target size)
- **single_pass**: if true, set rounds to 1

If `--single-pass` was passed, set rounds to 1.

If no explicit `--rounds N`, auto-scale:
- Target < 50 lines → 1 round
- Target < 200 lines or ≤ 5 files → 2 rounds
- Target > 200 lines or > 5 files → 3 rounds

---

# 2. Gather Target Code

Read the target code into a variable to pass to agents.

**If target is a file path or glob:**
Read the file(s) using Read tool. Concatenate with file headers.

**If target is "diff":**
```bash
git diff HEAD
```
If empty, try `git diff --staged`. If still empty, tell the user there's nothing to review.

Store the result as `TARGET_CODE`.

---

# 3. Run Debate Rounds

For each round (1 to N):

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

Parse the Enthusiast's JSON output. Store as `ENTHUSIAST_OUTPUT`.

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

Parse the Adversary's JSON output. Store as `ADVERSARY_OUTPUT`.

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

Parse the Judge's JSON output. Store as `JUDGE_OUTPUT`.

## 3d. Check Convergence

If the Judge set `convergence: true`, stop the loop early. Record `converged_at_round`.

## 3e. Store Round

Accumulate round results into `ROUNDS` array.

---

# 4. Format Output

After all rounds complete, present results to the user:

```
## Debate Review — {target} ({total_rounds} round(s))

### Confirmed Findings

{For each finding where judge ruled winner=enthusiast or winner=split:}
- **{severity}** [{file}:{line}] {resolution}

### Debunked Findings

{For each finding where judge ruled winner=adversary:}
- ~~{description}~~ — {adversary reasoning}

### Summary

{Judge's final summary}
{If converged: "Debate converged at round {N}."}
```

Also output the full structured JSON so it can be consumed programmatically.

---

# 5. Notes

- Each agent is spawned with `model: sonnet` for cost efficiency.
- The review skill NEVER influences keep/discard decisions in the autoimprove loop. It is advisory only.
- Total token budget: the orchestrator should track approximate token usage. If approaching session limits, warn the user.
````

- [ ] **Step 3: Commit**

```bash
git add skills/review/
git commit -m "feat: add review skill — debate orchestration with auto-scaling rounds"
```

---

### Task 12: Challenge Skill

**Files:**
- Create: `skills/challenge/SKILL.md`

- [ ] **Step 1: Create challenge skill**

Write `skills/challenge/SKILL.md`:

````markdown
---
name: challenge
description: "Benchmark debate agents against curated code challenges with known bugs. Use when the user invokes '/autoimprove challenge', asks to 'run challenges', 'benchmark debate agents', or 'test review agents'."
argument-hint: "[--suite puzzles|all] [--language python|typescript|go|rust|all]"
allowed-tools: [Read, Bash, Glob, Grep, Agent]
---

Run debate agents against curated challenges and score them with precision-weighted F1.

---

# 1. Parse Arguments

- **suite**: "puzzles" (default) or "all"
- **language**: filter to a specific language, or "all" (default)

---

# 2. Load Manifest

Read `challenges/manifest.json` from the project root.

Filter challenges by the `language` argument if specified.

Report how many challenges will be run:
```
Running {N} challenges ({languages})...
```

---

# 3. Run Each Challenge

For each challenge in the filtered manifest:

## 3a. Read Challenge Code

Read the challenge file (e.g., `challenges/python/off-by-one/challenge.py`).

The file extension tells you the language:
- `.py` → Python
- `.ts` → TypeScript
- `.go` → Go
- `.rs` → Rust

## 3b. Run Single-Pass Review

Run the review skill in single-pass mode (1 round) on the challenge file. This spawns:
1. Enthusiast agent → finds issues
2. Adversary agent → challenges findings
3. Judge agent → renders verdicts

Capture the structured JSON output from the debate.

## 3c. Score Against Answer Key

Prepare a combined JSON file with the Judge's rulings AND the Enthusiast's findings (the scoring script needs both to match file/line/type):

```bash
# Combine rulings and findings into format score-challenge.sh expects
jq -n --argjson rulings "$JUDGE_RULINGS" --argjson findings "$ENTHUSIAST_FINDINGS" \
  '{rulings: $rulings, findings: $findings}' > /tmp/debate-output.json

# Score
scripts/score-challenge.sh challenges/{id}/answer-key.json /tmp/debate-output.json
```

Parse the F1 score from the output JSON.

## 3d. Report Result

Print per-challenge result:
```
  {id}: F1={f1} (P={precision} R={recall}) TP={tp} FP={fp} FN={fn} {PASS|FAIL}
```

---

# 4. Aggregate and Report

After all challenges complete:

```
## Challenge Results

| Challenge | Language | F1 | Precision | Recall | Verdict |
|---|---|---|---|---|---|
| python/off-by-one | python | 1.00 | 1.00 | 1.00 | PASS |
| python/null-handling | python | 0.80 | 0.67 | 1.00 | PASS |
| ... | ... | ... | ... | ... | ... |

**Overall: {passed}/{total} passed (avg F1: {avg_f1})**
```

---

# 5. Log Results

Append a summary line to `experiments.tsv` (if it exists) with `type: challenge`:

```
{id}	{timestamp}	challenge	-	{total_challenges}	{avg_f1}	-	-	{pass_count}/{total}	{tokens_used}	{wall_time}	Challenge benchmark: {passed}/{total} passed
```

This enables longitudinal tracking of agent accuracy over time.
````

- [ ] **Step 2: Commit**

```bash
git add skills/challenge/
git commit -m "feat: add challenge skill — benchmark debate agents with F1 scoring"
```

---

### Task 13: Documentation Update

**Files:**
- Modify: `docs/commands.md`

- [ ] **Step 1: Add review and challenge commands to docs**

Append to `docs/commands.md`:

```markdown

---

## `/autoimprove review`

Runs an adversarial debate review (Enthusiast → Adversary → Judge) on code.

```
/autoimprove review [file|diff] [--rounds N] [--single-pass]
```

**Options:**

| Option | Description |
|---|---|
| `file` | Path to a file or glob pattern to review. Use `diff` to review staged/unstaged changes. |
| `--rounds N` | Number of debate rounds (default: auto-scaled by target size). |
| `--single-pass` | Sugar for `--rounds 1`. Fast, cheaper, less thorough. |

**What it does:**

1. Reads the target code (file or diff).
2. Auto-scales round count: 1 for <50 lines, 2 for normal, 3 for >5 files.
3. For each round: Enthusiast finds issues → Adversary debunks → Judge arbitrates.
4. Checks for convergence between rounds (skips remaining if debate has converged).
5. Presents confirmed findings, debunked findings, and summary.

**Output:** Human-readable summary + structured JSON.

---

## `/autoimprove challenge`

Benchmarks debate agent accuracy against curated code challenges with known bugs.

```
/autoimprove challenge [--suite puzzles|all] [--language python|typescript|go|rust|all]
```

**Options:**

| Option | Description |
|---|---|
| `--suite` | Which challenge suite to run. Default: `puzzles`. |
| `--language` | Filter to a specific language. Default: `all`. |

**What it does:**

1. Loads the challenge manifest (`challenges/manifest.json`).
2. For each challenge: runs a single-pass debate review, then scores findings against the answer key.
3. Scoring uses precision-weighted F1: rewards finding real bugs, penalizes false positives.
4. Reports per-challenge and aggregate results.
5. Logs results to `experiments.tsv` for longitudinal tracking.

**Requirements:**
- `challenges/` directory with manifest and challenge files (included with the plugin).
- `scripts/score-challenge.sh` (included with the plugin).
- `jq` installed.
```

- [ ] **Step 2: Commit**

```bash
git add docs/commands.md
git commit -m "docs: add /autoimprove review and /autoimprove challenge commands"
```

---

### Task 14: Integration Test

**Files:**
- Create: `test/challenge/test-integration.sh`

- [ ] **Step 1: Write integration test**

Write `test/challenge/test-integration.sh`:

```bash
#!/usr/bin/env bash
# Integration test: verify score-challenge.sh works end-to-end with a real challenge.
# This tests the scoring pipeline, not the debate agents (which require Claude).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
SCORE="$ROOT/scripts/score-challenge.sh"
PASS=0
FAIL=0

assert_json_field() {
  local desc="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | jq -r "$field")
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++)) || true
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    ((FAIL++)) || true
  fi
}

echo "=== Integration Tests ==="

echo "--- Test: manifest is valid JSON ---"
if jq empty "$ROOT/challenges/manifest.json" 2>/dev/null; then
  echo "  PASS: manifest.json is valid JSON"
  ((PASS++)) || true
else
  echo "  FAIL: manifest.json is invalid JSON"
  ((FAIL++)) || true
fi

echo "--- Test: all answer keys are valid JSON ---"
ALL_VALID=true
for key in $(find "$ROOT/challenges" -name "answer-key.json"); do
  if ! jq empty "$key" 2>/dev/null; then
    echo "  FAIL: invalid JSON: $key"
    ALL_VALID=false
    ((FAIL++)) || true
  fi
done
if $ALL_VALID; then
  echo "  PASS: all answer-key.json files are valid JSON"
  ((PASS++)) || true
fi

echo "--- Test: all manifested challenges have files ---"
ALL_EXIST=true
while IFS= read -r id; do
  dir="$ROOT/challenges/$id"
  if [ ! -d "$dir" ]; then
    echo "  FAIL: directory missing: $dir"
    ALL_EXIST=false
    ((FAIL++)) || true
  fi
  if [ ! -f "$dir/answer-key.json" ]; then
    echo "  FAIL: answer-key.json missing: $dir"
    ALL_EXIST=false
    ((FAIL++)) || true
  fi
done < <(jq -r '.challenges[].id' "$ROOT/challenges/manifest.json")
if $ALL_EXIST; then
  echo "  PASS: all manifested challenges have files"
  ((PASS++)) || true
fi

echo "--- Test: scoring script handles each real answer key ---"
for key in $(find "$ROOT/challenges" -name "answer-key.json"); do
  # Score with empty findings (should get F1=0, pass=false)
  EMPTY='{"rulings":[],"findings":[]}'
  tmpfile=$(mktemp)
  echo "$EMPTY" > "$tmpfile"
  result=$("$SCORE" "$key" "$tmpfile" 2>/dev/null)
  rm "$tmpfile"

  challenge=$(jq -r '.challenge' "$key")
  f1=$(echo "$result" | jq -r '.f1')
  pass=$(echo "$result" | jq -r '.pass')
  assert_json_field "empty findings on $challenge: f1=0" "$result" '.f1' '0'
  assert_json_field "empty findings on $challenge: pass=false" "$result" '.pass' 'false'
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run integration test**

```bash
chmod +x test/challenge/test-integration.sh
bash test/challenge/test-integration.sh
```

Expected: All PASS

- [ ] **Step 3: Run the scoring unit tests too**

```bash
bash test/challenge/test-score-challenge.sh
```

Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add test/challenge/test-integration.sh
git commit -m "test: add integration tests for challenge pipeline"
```

---

## Summary

| Task | Description | Files |
|---|---|---|
| 1 | Plugin scaffold | directories only |
| 2 | Enthusiast agent | `agents/enthusiast.md` |
| 3 | Adversary agent | `agents/adversary.md` |
| 4 | Judge agent | `agents/judge.md` |
| 5 | Scoring script (TDD) | `scripts/score-challenge.sh`, `test/challenge/` |
| 6 | Python challenges | `challenges/python/` (2 challenges) |
| 7 | TypeScript challenges | `challenges/typescript/` (2 challenges) |
| 8 | Go challenges | `challenges/go/` (2 challenges) |
| 9 | Rust challenges | `challenges/rust/` (2 challenges) |
| 10 | Challenge manifest | `challenges/manifest.json` |
| 11 | Review skill | `skills/review/` |
| 12 | Challenge skill | `skills/challenge/` |
| 13 | Documentation | `docs/commands.md` |
| 14 | Integration test | `test/challenge/test-integration.sh` |

**Independent tasks (can parallelize):** 2, 3, 4 (agents); 6, 7, 8, 9 (challenges); 5 (scoring)
**Sequential dependencies:** 10 after 6-9; 11 after 2-4; 12 after 5, 10, 11; 13 after 11, 12; 14 after all
