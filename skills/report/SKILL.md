---
name: report
description: "This skill should be used when the user invokes \"/autoimprove report\", asks for a \"session summary\", \"morning report\", \"what did autoimprove do\", \"experiment results\", \"what was kept\", or wants to review recent autoimprove activity."
allowed-tools: [Read, Bash]
---

Generate a summary report of recent autoimprove experiment activity. Read session state, compute metric drift, and format a human-readable report.

If no experiments have been run, say so and suggest `/autoimprove run`.

---

## 1. Read State

Read these files (report what's missing):
- `experiments/experiments.tsv` — the full experiment log
- `experiments/state.json` — trust tier, stagnation counters, session info
- `experiments/epoch-baseline.json` — frozen baseline from session start
- `experiments/rolling-baseline.json` — current baseline (updated on each keep)

## 2. Compute Summary

From `experiments.tsv`:
- Total experiments across all sessions and in the most recent session
- Verdict breakdown: kept, neutral, regressed, failed (gate_fail), crashed
- Stagnated themes (from `state.json`)
- Current trust tier and consecutive keep count

## 3. Compute Metric Drift

For each metric, compare rolling vs. epoch baseline:
```
drift = (rolling - epoch) / epoch * 100
```

Flag any metric where `abs(drift)` exceeds the `epoch_drift_threshold` from `autoimprove.yaml` (default 5%). Indicate whether drift is positive (improvement) or negative (regression).

## 4. Format Report

Output the report in this format:

```
autoimprove report — <project name> — <date>

Summary
  Experiments:  N run, K kept, D neutral, R regressed, F failed
  Epoch drift:  +X.X% improvement from session start
  Trust tier:   N (consecutive keeps: M)
  Budget used:  N / M experiments

Kept Experiments (merged to main)
  #001  failing_tests   "Fix divide-by-zero in math.divide()"
  #003  todo_comments   "Implement string.truncate() from TODO"

Notable Discards
  #002  lint_warnings  neutral  "Clean up unused imports"
  #004  coverage_gaps  regress  "Add tests for wordCount"

Stagnated Themes
  lint_warnings (5 consecutive non-improvements)

Metric Trends
  test_count:   37 → 39  (+5.4%)  ↑ improved
  todo_count:   12 → 10  (-16.7%) ↑ improved (lower is better)

Full log:              ./experiments/experiments.tsv
Per-experiment detail: ./experiments/*/context.json
```

Adapt the output to what's actually present — skip sections if there's no data (e.g., no stagnated themes, no discards worth noting).
