---
name: autoimprove-test
description: Run the autoimprove test suites — scoring unit tests, integration tests, and evaluate tests.
argument-hint: "[challenge|integration|evaluate|all]"
---

Run the autoimprove test suites. Arguments: $ARGUMENTS

## Arguments

| Argument | Suite run | Script |
|----------|-----------|--------|
| (none) or `all` | All three suites | All scripts below |
| `challenge` | Scoring unit tests | `test/challenge/test-score-challenge.sh` |
| `integration` | Challenge integration tests | `test/challenge/test-integration.sh` |
| `evaluate` | Evaluate pipeline tests | `test/evaluate/test-evaluate.sh` |

## Usage Examples

```
# Run every suite (safest before a commit)
/autoimprove test

# Quick smoke-check on scoring logic only
/autoimprove test challenge

# Verify the integration harness after changing scripts/evaluate.sh
/autoimprove test integration

# Run only the evaluate pipeline tests
/autoimprove test evaluate
```

## What It Does

Runs the requested shell test scripts and collects pass/fail counts per suite.

- **challenge** — unit-tests the scoring functions in `scripts/evaluate.sh`: metric parsing, delta calculations, gate thresholds, tier transitions, and edge cases (empty output, missing keys).
- **integration** — end-to-end run of the full challenge pipeline in a temporary worktree: baseline capture → experimenter agent → evaluate → verdict. Verifies that kept experiments actually improve metrics and that regressions are discarded.
- **evaluate** — unit-tests `scripts/evaluate.sh` directly: baseline structure, within-tolerance regression detection, missing-file handling, and output JSON schema.

After all suites finish, reports a combined summary:

```
Results: 34 passed, 0 failed (challenge: 12, integration: 10, evaluate: 12)
```

If any test fails, the failing test name and the diff between expected and actual output are shown.

## When to Use

- Before opening a PR that touches `scripts/evaluate.sh`, `autoimprove.yaml` schema, or the experiment loop.
- After rebasing to catch breakage introduced by upstream changes.
- When an experiment produces an unexpected verdict — run `challenge` to verify the scoring logic is correct.

## Related Commands

- `/autoimprove run` — run the experiment loop whose logic these tests cover
- `/autoimprove init` — scaffold `autoimprove.yaml` before the first run
- `/prompt-testing` — write triggering and unit tests for skills and agents
