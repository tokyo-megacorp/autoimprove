---
name: autoimprove-report
description: Show a session summary — experiments run, kept vs discarded, score trends, and confirmed findings.
argument-hint: "[--since <date>] [--experiment <id>]"
---

Invoke the `autoimprove:report` skill now. Do not do any work before the skill loads.

Arguments: $ARGUMENTS

---

## Arguments

| Argument | Description |
|----------|-------------|
| `--since <date>` | Filter the experiment log to entries on or after this date (ISO format: `2026-03-01`). |
| `--experiment <id>` | Show detail for a single experiment by its zero-padded ID (e.g., `--experiment 007`). |

Both arguments are optional. Without them, the full experiment log is summarized.

## Usage Examples

```
# Full session summary
/autoimprove report

# Show only experiments from this week
/autoimprove report --since 2026-03-25

# Inspect one specific experiment
/autoimprove report --experiment 004
```

## What It Does

Reads `experiments/experiments.tsv`, `experiments/state.json`, `experiments/epoch-baseline.json`, and `experiments/rolling-baseline.json`, then produces a human-readable summary covering:

- Total experiments run with verdict breakdown (kept / neutral / regressed / failed / crashed)
- Epoch drift: how much metrics changed from the session start baseline to the current rolling baseline
- Current trust tier and consecutive keep count
- List of kept experiments (merged to main) with their theme and commit message
- Notable discards (regressions and failures) with their theme
- Stagnated themes (themes that hit consecutive non-improvements and are on cooldown)
- Per-metric trend table with direction indicators

If no experiments have been run yet, the skill says so and suggests `/autoimprove run`.

## Sample Output

```
autoimprove report — my-project — 2026-03-29

Summary
  Experiments:  5 run, 3 kept, 1 neutral, 1 regressed, 0 failed
  Epoch drift:  +8.3% improvement from session start
  Trust tier:   2 (consecutive keeps: 3)
  Budget used:  5 / 10 experiments

Kept Experiments (merged to main)
  #001  failing_tests   "Fix off-by-one in date range filter"
  #003  todo_comments   "Implement missing input sanitizer from TODO"
  #005  coverage_gaps   "Add tests for empty-collection edge case"

Metric Trends
  test_count:   42 → 46  (+9.5%)   ↑ improved
  lint_errors:   8 →  7  (-12.5%)  ↑ improved (lower is better)
```

## When to Use

- After `/autoimprove run` completes, to review what was kept and what changed.
- Mid-session to check progress before the budget is exhausted.
- To identify stagnated themes (themes to deprioritize or change strategy on).
- To verify metric trends before anchoring a new baseline.

## Related Commands

- `/autoimprove run` — start or continue the experiment loop
- `/autoimprove init` — set up the project before the first run
