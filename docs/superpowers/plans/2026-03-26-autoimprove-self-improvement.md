# autoimprove Self-Improvement Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up autoimprove to run on its own codebase — a dogfooding/integration validation loop that also grows the evaluate.sh test suite.

**Architecture:** Three files: `benchmark/self-metrics.sh` (fitness signal), `autoimprove.yaml` (loop config), `.claude/settings.json` (dev hook protecting evaluate.sh). The loop uses one theme (test_coverage) and three metrics (test_count as improvement signal, broken_constraints + broken_refs as safety tripwires). Primary value is integration validation — confirming a full session completes without crashing.

**Tech Stack:** Bash, YAML, JSON, jq (already required by evaluate.sh)

**Spec:** `docs/superpowers/specs/2026-03-26-autoimprove-on-real-projects-design.md`

---

### Task 1: benchmark/self-metrics.sh

**Files:**
- Create: `benchmark/self-metrics.sh`

The script must output valid JSON with three keys: `test_count`, `broken_constraints`, `broken_refs`. It runs from the repo root (autoimprove calls it from the worktree).

- [ ] **Step 1: Create the benchmark directory and script**

```bash
mkdir -p benchmark
```

Write `benchmark/self-metrics.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"

# test_count: number of test cases in the evaluate.sh test suite
# Marker format: echo "--- Test: <name> ---"
test_count=$(grep -c -- "--- Test:" "$DIR/test/evaluate/test-evaluate.sh" 2>/dev/null || echo 0)

# broken_constraints: load-bearing invariant phrases must remain in experimenter agent
broken_constraints=0
for phrase in "forbidden_paths" "additive only" "how your changes are scored" "worktree"; do
  grep -q "$phrase" "$DIR/agents/experimenter.md" 2>/dev/null || broken_constraints=$((broken_constraints + 1)) || true
done
# Line-count floor: catches wholesale file gutting
lines=$(wc -l < "$DIR/agents/experimenter.md" 2>/dev/null || echo 0)
[ "$lines" -lt 20 ] && broken_constraints=$((broken_constraints + 1))

# broken_refs: critical files referenced by the orchestrator must exist
broken_refs=0
for f in \
  "$DIR/skills/run/references/loop.md" \
  "$DIR/agents/experimenter.md" \
  "$DIR/scripts/evaluate.sh"; do
  [ -f "$f" ] || broken_refs=$((broken_refs + 1))
done

echo "{\"test_count\": $test_count, \"broken_constraints\": $broken_constraints, \"broken_refs\": $broken_refs}"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x benchmark/self-metrics.sh
```

- [ ] **Step 3: Run it and verify output**

```bash
bash benchmark/self-metrics.sh
```

Expected output (exact numbers may vary, but all three keys must be present and broken_* must be 0):
```json
{"test_count": 10, "broken_constraints": 0, "broken_refs": 0}
```

If `broken_constraints` > 0, check which phrase is missing:
```bash
for phrase in "forbidden_paths" "additive only" "how your changes are scored" "worktree"; do
  grep -q "$phrase" agents/experimenter.md && echo "ok: $phrase" || echo "MISSING: $phrase"
done
```

- [ ] **Step 4: Run noise check (3x)**

```bash
bash benchmark/self-metrics.sh
bash benchmark/self-metrics.sh
bash benchmark/self-metrics.sh
```

All three runs must produce identical output. If test_count varies, the grep pattern is unstable.

- [ ] **Step 5: Commit**

```bash
git add benchmark/self-metrics.sh
git commit -m "feat: add self-metrics benchmark script for dogfooding loop"
```

---

### Task 2: autoimprove.yaml

**Files:**
- Create: `autoimprove.yaml`

- [ ] **Step 1: Write autoimprove.yaml**

```yaml
project:
  name: autoimprove
  path: .

budget:
  max_experiments_per_session: 10

gates:
  - name: evaluate_tests
    command: bash test/evaluate/test-evaluate.sh

benchmarks:
  - name: self-metrics
    command: bash benchmark/self-metrics.sh
    metrics:
      - name: test_count
        extract: "json:.test_count"
        direction: higher_is_better
        tolerance: 0.0
        significance: 0.01

      - name: broken_constraints
        extract: "json:.broken_constraints"
        direction: lower_is_better
        tolerance: 0.0
        significance: 0.0

      - name: broken_refs
        extract: "json:.broken_refs"
        direction: lower_is_better
        tolerance: 0.0
        significance: 0.0

themes:
  auto:
    strategy: weighted_random
    cooldown_per_theme: 3
    priorities:
      test_coverage: 1

constraints:
  forbidden_paths:
    - autoimprove.yaml
    - scripts/evaluate.sh
    - benchmark/**
    - .claude-plugin/**
  test_modification: additive_only
  trust_ratchet:
    tier_0: { max_files: 3, max_lines: 150, mode: auto_merge }
    tier_1: { max_files: 6, max_lines: 300, mode: auto_merge, after_keeps: 5 }
    tier_2: { max_files: 10, max_lines: 500, mode: auto_merge, after_keeps: 15 }

safety:
  epoch_drift_threshold: 0.05
  regression_tolerance: 0.0
  significance_threshold: 0.01
  stagnation_window: 5
```

- [ ] **Step 2: Verify prerequisites exist**

```bash
test -f autoimprove.yaml && echo "ok: autoimprove.yaml"
test -f scripts/evaluate.sh && echo "ok: evaluate.sh"
command -v jq && echo "ok: jq"
```

All three must print "ok".

- [ ] **Step 3: Run the prerequisite check from the run skill manually**

```bash
test -f autoimprove.yaml || { echo "FATAL: autoimprove.yaml not found"; exit 1; }
test -f scripts/evaluate.sh || { echo "FATAL: scripts/evaluate.sh not found"; exit 1; }
command -v jq >/dev/null || { echo "FATAL: jq required"; exit 1; }
chmod +x scripts/evaluate.sh
echo "All prerequisites ok"
```

Expected: `All prerequisites ok`

- [ ] **Step 4: Run evaluate.sh in init mode to capture baseline**

```bash
mkdir -p experiments
bash scripts/evaluate.sh autoimprove.yaml /dev/null 2>&1 || true
```

Note: This will likely fail because evaluate.sh expects `experiments/evaluate-config.json`, not `autoimprove.yaml` directly — that conversion is done by the orchestrator skill at session start. This step just confirms evaluate.sh and the gate command work:

```bash
bash test/evaluate/test-evaluate.sh
```

Expected: All 10 tests pass, `FAIL: 0`.

- [ ] **Step 5: Commit**

```bash
git add autoimprove.yaml
git commit -m "feat: add autoimprove.yaml for self-improvement dogfooding loop"
```

---

### Task 3: .claude/settings.json — evaluate.sh guard hook

**Files:**
- Create: `.claude/settings.json`

This hook blocks accidental edits to `scripts/evaluate.sh` (the single evaluator — a key design invariant) and auto-runs the test suite after any change to `scripts/`.

- [ ] **Step 1: Create .claude directory and settings.json**

```bash
mkdir -p .claude
```

Write `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"$CLAUDE_TOOL_INPUT\" | python3 -c \"import sys,json; d=json.load(sys.stdin); f=d.get('file_path',''); sys.exit(1 if 'scripts/evaluate.sh' in f else 0)\" && exit 0 || { echo 'BLOCKED: scripts/evaluate.sh is the single evaluator. Edit deliberately — remove this hook temporarily if intentional.'; exit 1; }",
            "blocking": true
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"$CLAUDE_TOOL_INPUT\" | python3 -c \"import sys,json; d=json.load(sys.stdin); f=d.get('file_path',''); sys.exit(0 if 'scripts/' in f else 1)\" && bash test/evaluate/test-evaluate.sh || exit 0"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Verify the JSON is valid**

```bash
python3 -c "import json; json.load(open('.claude/settings.json')); print('valid JSON')"
```

Expected: `valid JSON`

- [ ] **Step 3: Add .claude/settings.json to git (not .gitignore)**

Check it's not ignored:
```bash
git check-ignore -v .claude/settings.json && echo "IGNORED - fix .gitignore" || echo "ok: not ignored"
```

If ignored, add to `.gitignore` an exception:
```bash
# In .gitignore, the .claude/ dir may be excluded. Add:
# !.claude/settings.json
```

- [ ] **Step 4: Commit**

```bash
git add .claude/settings.json
git commit -m "feat: add dev hook to guard scripts/evaluate.sh from accidental edits"
```

---

### Task 4: Push and verify

- [ ] **Step 1: Push to develop**

```bash
git checkout -b feat/self-improvement-setup 2>/dev/null || git checkout feat/self-improvement-setup
git push -u origin feat/self-improvement-setup
```

- [ ] **Step 2: Smoke-test the full setup**

Run the metrics script one final time from repo root:
```bash
bash benchmark/self-metrics.sh
```

Expected: `{"test_count": 10, "broken_constraints": 0, "broken_refs": 0}`

Confirm autoimprove.yaml passes YAML parse:
```bash
python3 -c "import yaml; yaml.safe_load(open('autoimprove.yaml')); print('yaml valid')" 2>/dev/null || echo "install PyYAML to validate: pip install pyyaml"
```

Confirm the gate passes:
```bash
bash test/evaluate/test-evaluate.sh
```

Expected: `FAIL: 0`

- [ ] **Step 3: Create PR to develop**

```bash
gh pr create \
  --base develop \
  --title "feat: autoimprove self-improvement setup (dogfooding loop)" \
  --body "Adds autoimprove.yaml, benchmark/self-metrics.sh, and .claude/settings.json to enable autoimprove to run on its own codebase.

Primary value: integration validation (confirms a full session completes).
Side effect: grows evaluate.sh test coverage via test_coverage theme.

Metrics: test_count (improvement signal), broken_constraints + broken_refs (safety tripwires).
See: docs/superpowers/specs/2026-03-26-autoimprove-on-real-projects-design.md"
```
