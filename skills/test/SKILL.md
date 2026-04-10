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
argument-hint: "[challenge|integration|evaluate|harvest|agents|skills|all] [--quiet] [--test <name>]"
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

Parse additional flags:
- `--quiet` → suppress per-suite output; print only the final summary and failures. Useful for CI or quick pre-run checks.
- `--test <name>` → run only the single test case whose description contains `<name>` (substring match). Applies within the selected suite. If multiple suites are selected, run `<name>` within each.

Initialize progress tracking:

```
TodoWrite([
  { id: "prereqs",   content: "✅ Check prerequisites",       status: "in_progress" },
  { id: "suites",    content: "📋 Build suite list",          status: "todo" },
  { id: "run",       content: "🧪 Run each suite",           status: "todo" },
  { id: "parse",     content: "📊 Parse pass/fail counts",   status: "todo" },
  { id: "summary",   content: "📝 Format summary",           status: "todo" },
  { id: "guidance",  content: "📋 Exit guidance",            status: "todo" }
])
```

---

# 1. ✅ Check Prerequisites

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

After confirming prerequisites pass, update progress:
```
TodoWrite([
  { id: "prereqs",  content: "✅ Check prerequisites",     status: "completed" },
  { id: "suites",   content: "📋 Build suite list",        status: "in_progress" }
])
```

---

# 2. 📋 Build Suite List

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

For `all`, filter out scripts that do not exist on disk — do not fail if a suite hasn't been created yet. Print a note for each missing suite:
```
(skipped: test/harvest/test-harvest.sh — not found)
```

Update progress:
```
TodoWrite([
  { id: "suites",  content: "📋 Build suite list",   status: "completed" },
  { id: "run",     content: "🧪 Run each suite",     status: "in_progress" }
])
```

---

# 3. 🧪 Run Each Suite

For each script in the suite list, run:

```bash
chmod +x <script>
bash <script> 2>&1; EXIT_CODE=$?
```

If `--test <name>` was passed, pipe the script through a filter that only executes tests whose description contains `<name>`. For TAP-compatible scripts, this can be done with:

```bash
bash <script> 2>&1 | grep -A1 "# <name>\|<name>"
```

For scripts that use custom markers like `--- Test: <name> ---`, pass the name as an environment variable:
```bash
TEST_FILTER="<name>" bash <script> 2>&1
```

Capture output, exit code, and suite name. In normal mode, print live output as it arrives. In `--quiet` mode, suppress output and only surface failures after all suites complete.

Print status after each suite:
```
[PASS] test/challenge/test-score-challenge.sh
[FAIL] test/evaluate/test-evaluate.sh  (exit 1)
```

Do not abort on failure — run all suites even if one fails.

Update progress:
```
TodoWrite([
  { id: "run",    content: "🧪 Run each suite",         status: "completed" },
  { id: "parse",  content: "📊 Parse pass/fail counts", status: "in_progress" }
])
```

---

# 4. 📊 Parse Pass/Fail Counts

After all suites complete, parse the output for TAP-style or shell-assertion-style results. Look for patterns like:
- `ok N - description` / `not ok N - description` (TAP)
- `PASS: description` / `FAIL: description` (custom)
- `Tests passed: N` / `Tests failed: N` (summary lines)

For each suite, extract: total tests, passed, failed.

If a suite produced no parseable count, report: `(N/A — check raw output)`.

Update progress:
```
TodoWrite([
  { id: "parse",    content: "📊 Parse pass/fail counts",  status: "completed" },
  { id: "summary",  content: "📝 Format summary",          status: "in_progress" }
])
```

---

# 5. 📝 Format Summary

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

In `--quiet` mode, print only the summary block and the Failures section — omit the per-suite live output. This is identical output, just with the streaming output suppressed.

Update progress:
```
TodoWrite([
  { id: "summary",   content: "📝 Format summary",  status: "completed" },
  { id: "guidance",  content: "📋 Exit guidance",   status: "in_progress" }
])
```

---

# 6. 📋 Exit Guidance

If any suite failed:
- Point the user to the failing script: `Re-run with: bash <script>` for focused output.
- Call out missing dependencies explicitly (e.g., `jq: command not found`).
- Note: hard gates in the run loop execute these suites — a failing suite blocks experiment evaluation.

If all suites passed, print: `All clear — safe to run /autoimprove run.`

```
TodoWrite([
  { id: "guidance",  content: "📋 Exit guidance",  status: "completed" }
])
```

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  { id: "prereqs", status: "completed" },
  { id: "suites", status: "completed" },
  { id: "run", status: "completed" },
  { id: "parse", status: "completed" },
  { id: "summary", status: "completed" },
  { id: "guidance", status: "completed" }
])
```

---

# 7. 📋 Usage Examples

## Example 1 — Full suite run before starting a session

```
user: run autoimprove tests
```

Output:
```
autoimprove test — my-project — 2026-03-29

Suite Results
  [PASS] test/challenge/test-score-challenge.sh   8/8
  [PASS] test/challenge/test-integration.sh       5/5
  [PASS] test/evaluate/test-evaluate.sh           12/12
  (skipped: test/harvest/test-harvest.sh — not found)
  (skipped: tests/agents/run-tests.sh — not found)
  [PASS] tests/skills/run-tests.sh                4/4

Total: 29/29 passed across 4 suites

All clear — safe to run /autoimprove run.
```

## Example 2 — Targeted suite run with a failure

```
user: /autoimprove test evaluate
```

Output:
```
autoimprove test — my-project — 2026-03-29

Suite Results
  [FAIL] test/evaluate/test-evaluate.sh           9/11

Total: 9/11 passed across 1 suite

Failures
  test/evaluate/test-evaluate.sh:
    - not ok 7 - handle empty metrics object gracefully
    - not ok 10 - regression delta is zero when baselines match

Re-run with: bash test/evaluate/test-evaluate.sh
```

## Example 3 — CI pre-push check with --quiet

```
user: /autoimprove test all --quiet
```

Output (only summary, no streaming):
```
autoimprove test — my-project — 2026-03-29

Total: 29/29 passed across 4 suites

All clear — safe to run /autoimprove run.
```

## Example 4 — Isolate a single failing test by name

```
user: /autoimprove test evaluate --test "NaN metric"
```

Runs only tests whose description contains "NaN metric" within `test/evaluate/test-evaluate.sh`. Output:
```
autoimprove test — my-project — 2026-03-29 (filtered: "NaN metric")

  [FAIL] test/evaluate/test-evaluate.sh
    - not ok 5 - regression detection handles NaN metric

Re-run with: bash test/evaluate/test-evaluate.sh
```

## Example 5 — Verify after a skill edit

```
user: test autoimprove skills
```

Good practice after any skill SKILL.md change: confirms the skills test suite still passes before committing or running `/autoimprove run`.

---

# 8. ❌ Edge Cases

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

**`--test <name>` matches no tests**

If the name filter produces no matching tests in any suite, print:
```
No tests found matching "<name>" in the selected suites.
Use /autoimprove test <suite> to list all test names in that suite.
```

---

# 9. 🔄 Integration Points

- **Before `/autoimprove run`** — the `run` skill's hard gates call these same scripts. A passing `test` run confirms the baseline is clean before the experiment loop starts.
- **After a KEEP verdict** — re-run `test` to catch regressions the experimenter introduced that gates did not catch (gate commands are configurable and may be narrower than these suites).
- **CI hook** — add `bash test/challenge/test-score-challenge.sh && bash test/evaluate/test-evaluate.sh` as a pre-push hook to keep the scorer and evaluator in sync. Use `--quiet` for CI-friendly output.
- **After modifying `skills/_shared/evaluate.sh`** — re-run `test evaluate` immediately. The evaluate test suite validates the evaluator's own logic; changes to `evaluate.sh` can silently break the scoring pipeline.
- **After updating `autoimprove.yaml` gates** — a gate change may cause experiments to fail that previously passed. Run `test evaluate` to confirm the gate command works as expected before the next run.
- **After adding new challenges** — run `test challenge` after adding entries to `challenges/manifest.json` to verify the new challenge files are reachable and parseable.

---

# 10. ❌ Common Failure Patterns

- **All suites pass but gate fails during `/autoimprove run`:** The gate command in `autoimprove.yaml` may call a different script path than the one this skill runs. Check the `gates` config to ensure the gate command matches `test/evaluate/test-evaluate.sh`.
- **Test count drops unexpectedly after an experimenter commit:** An experimenter may have accidentally modified a test file despite the `additive_only` constraint. Run `git diff HEAD~1 -- test/` to verify. If tests were removed, roll back the experiment with `/autoimprove rollback`.
- **Suite output is empty but exit code is 0:** The test script may be using `set -e` with a subshell that swallowed an error. Run the script manually with `bash -x test/evaluate/test-evaluate.sh` to trace execution.
- **`harvest` suite not found:** The harvest test suite is not yet implemented in all project setups. This is expected — use `/autoimprove test evaluate` or `/autoimprove test challenge` until the harvest suite is scaffolded.
- **`--test <name>` filter returns no results:** The name must be a substring of the test description as it appears in the script output. Run the suite without `--test` first to see exact test names, then filter.

---

# 11. 🔄 Recommended Test Workflow

Use this sequence when debugging a test regression:

1. **Run all suites** — `/autoimprove test all` — confirm which suite is failing
2. **Run the failing suite manually** — `bash test/<suite>/test-<suite>.sh` — get unfiltered output
3. **Isolate the failing test** — use `--test <name>` or look for `--- Test: <name> ---` markers
4. **Check the gate command** in `autoimprove.yaml` — confirm it calls the same script
5. **Re-run after fix** — confirm the suite passes before the next `/autoimprove run`

---

# 12. 📋 When NOT to Use

- **Investigating a specific failing test** — run the script directly (`bash test/challenge/test-score-challenge.sh`) for unfiltered output. Or use `--test <name>` if the skill's filter is sufficient.
- **Checking code style or formatting** — that is a gate concern; use the `run` skill which invokes gates via `evaluate.sh`.
- **Continuous integration** — CI should call the scripts directly; this skill is for interactive review only. Pass `--quiet` if using interactively in a script context.
