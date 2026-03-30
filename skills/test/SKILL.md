---
name: test
description: "Use when running the autoimprove test suites — scoring unit tests, integration tests, evaluate tests, or agent/skill behavior tests. Examples:

<example>
Context: User wants to verify all tests pass before running experiments.
user: \"run autoimprove tests\"
assistant: I'll use the test skill to run all test suites and report pass/fail counts.
<commentary>Full test suite run — test skill.</commentary>
</example>

<example>
Context: User wants to run only the evaluate pipeline tests.
user: \"run autoimprove evaluate tests\"
assistant: I'll use the test skill with the evaluate argument to run only those tests.
<commentary>Targeted suite run — test skill.</commentary>
</example>

<example>
Context: User wants to confirm nothing is broken after a skill change.
user: \"test autoimprove skills\"
assistant: I'll use the test skill with the skills argument to run behavior tests for skills.
<commentary>Skill regression check — test skill.</commentary>
</example>"
argument-hint: "[challenge|integration|evaluate|harvest|agents|skills|all]"
allowed-tools: [Read, Bash]
---

<SKILL-GUARD>
You are NOW executing the test skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Run the autoimprove test suites, report pass/fail counts per suite, and surface any failures with enough context to fix them.

Parse the argument:
- `challenge` → run `test/challenge/test-score-challenge.sh` only
- `integration` → run `test/challenge/test-integration.sh` only
- `evaluate` → run `test/evaluate/test-evaluate.sh` only
- `harvest` → run `test/harvest/test-harvest.sh` only
- `agents` → run `tests/agents/run-tests.sh` only
- `skills` → run `tests/skills/run-tests.sh` only
- `all` or no argument → run every suite listed above

---

# 1. Check Prerequisites

Verify you are in a project with the autoimprove test infrastructure:

```bash
test -f autoimprove.yaml || echo "MISSING_CONFIG"
test -d test || echo "MISSING_TEST_DIR"
```

If `autoimprove.yaml` is missing, print:
```
autoimprove is not initialized here. Run /autoimprove init.
```
and stop.

If the `test/` directory is missing, print:
```
No test suites found. Expected test/ directory in project root.
```
and stop.

---

# 2. Build Suite List

Map the argument to the set of scripts to run:

| Argument | Scripts |
|----------|---------|
| `challenge` | `test/challenge/test-score-challenge.sh` |
| `integration` | `test/challenge/test-integration.sh` |
| `evaluate` | `test/evaluate/test-evaluate.sh` |
| `harvest` | `test/harvest/test-harvest.sh` |
| `agents` | `tests/agents/run-tests.sh` |
| `skills` | `tests/skills/run-tests.sh` |
| `all` / none | all of the above that exist |

For `all`, filter out scripts that do not exist on disk — do not fail if a suite hasn't been created yet.

---

# 3. Run Each Suite

For each script in the suite list, run:

```bash
chmod +x <script>
bash <script> 2>&1; EXIT_CODE=$?
```

Capture output, exit code, and suite name. Print status after each suite:
```
[PASS] test/challenge/test-score-challenge.sh
[FAIL] test/evaluate/test-evaluate.sh  (exit 1)
```

Do not abort on failure — run all suites even if one fails.

# 4. Parse Pass/Fail Counts

After all suites complete, parse the output for TAP-style or shell-assertion-style results. Look for patterns like:
- `ok N - description` / `not ok N - description` (TAP)
- `PASS: description` / `FAIL: description` (custom)
- `Tests passed: N` / `Tests failed: N` (summary lines)

For each suite, extract: total tests, passed, failed.

If a suite produced no parseable count, report: `(N/A — check raw output)`.

---

# 5. Format Summary

```
autoimprove test — <project name> — <date>

Suite Results
  [PASS] test/challenge/test-score-challenge.sh   5/5
  [PASS] test/challenge/test-integration.sh       3/3
  [FAIL] test/evaluate/test-evaluate.sh           4/6
  [PASS] test/harvest/test-harvest.sh             7/7

Total: 19/21 passed across 4 suites

Failures
  test/evaluate/test-evaluate.sh:
    - not ok 3 - extract json:.missing_key returns empty string
    - not ok 5 - regression detection handles NaN metric
```

If all suites pass:
```
All tests passed (N/N across M suites).
```

---

# 6. Exit Guidance

If any suite failed:
- Point the user to the failing script: `Re-run with: bash <script>` for focused output.
- Call out missing dependencies explicitly (e.g., `jq: command not found`).
- Note: hard gates in the run loop execute these suites — a failing suite blocks experiment evaluation.

If all suites passed, print: `All clear — safe to run /autoimprove run.`

---

# 7. When NOT to Use

- **Investigating a specific failing test** — run the script directly (`bash test/challenge/test-score-challenge.sh`) for unfiltered output.
- **Checking code style or formatting** — that is a gate concern; use the `run` skill which invokes gates via `evaluate.sh`.
- **Continuous integration** — CI should call the scripts directly; this skill is for interactive review only.

---

# 8. Edge Cases

**Missing script for a requested suite**

If the user asks for a specific suite (e.g., `harvest`) but its script does not exist, print:
```
Suite 'harvest' not found: expected test/harvest/test-harvest.sh
Run /autoimprove test all to see which suites are available.
```
Do not fall through silently.

**Missing binary dependency**

If a suite exits non-zero with `command not found` in its output, surface the dependency name explicitly:
```
[FAIL] test/evaluate/test-evaluate.sh — missing dependency: jq
Install with: brew install jq
```

**Suite hangs (no output for > 30 s)**

Report the suite as timed-out rather than waiting indefinitely:
```
[TIMEOUT] test/challenge/test-integration.sh — no output after 30s
Re-run manually: bash test/challenge/test-integration.sh
```

---

# 10. Common Failure Patterns

- **All suites pass but gate fails during `/autoimprove run`:** The gate command in `autoimprove.yaml` may call a different script path than the one this skill runs. Check the `gates` config to ensure the gate command matches `test/evaluate/test-evaluate.sh`.
- **Test count drops unexpectedly after an experimenter commit:** An experimenter may have accidentally modified a test file despite the `additive_only` constraint. Run `git diff HEAD~1 -- test/` to verify. If tests were removed, roll back the experiment with `/autoimprove rollback`.
- **Suite output is empty but exit code is 0:** The test script may be using `set -e` with a subshell that swallowed an error. Run the script manually with `bash -x test/evaluate/test-evaluate.sh` to trace execution.
- **`harvest` suite not found:** The harvest test suite is not yet implemented in all project setups. This is expected — use `/autoimprove test evaluate` or `/autoimprove test challenge` until the harvest suite is scaffolded.

---

# 9. Integration Notes

- **Before `/autoimprove run`** — the `run` skill's hard gates call these same scripts. A passing `test` run confirms the baseline is clean before the experiment loop starts.
- **After a KEEP verdict** — re-run `test` to catch regressions the experimenter introduced that gates did not catch (gate commands are configurable and may be narrower than these suites).
- **CI hook** — add `bash test/challenge/test-score-challenge.sh && bash test/evaluate/test-evaluate.sh` as a pre-push hook to keep the scorer and evaluator in sync.
- **After modifying `scripts/evaluate.sh`** — re-run `test evaluate` immediately. The evaluate test suite validates the evaluator's own logic; changes to `evaluate.sh` can silently break the scoring pipeline.
- **After updating `autoimprove.yaml` gates** — a gate change may cause experiments to fail that previously passed. Run `test evaluate` to confirm the gate command works as expected before the next run.
- **After adding new challenges** — run `test challenge` after adding entries to `challenges/manifest.json` to verify the new challenge files are reachable and parseable.

---

# 11. Recommended Test Workflow

Use this sequence when debugging a test regression:

1. **Run all suites** — `/autoimprove test all` — confirm which suite is failing
2. **Run the failing suite manually** — `bash test/<suite>/test-<suite>.sh` — get unfiltered output
3. **Isolate the failing test** — look for `--- Test: <name> ---` markers around the failure
4. **Check the gate command** in `autoimprove.yaml` — confirm it calls the same script
5. **Re-run after fix** — confirm the suite passes before the next `/autoimprove run`
