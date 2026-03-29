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
