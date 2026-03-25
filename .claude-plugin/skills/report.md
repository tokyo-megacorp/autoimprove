---
name: report
description: "Generate the morning report — summarizes recent autoimprove experiment sessions with kept/discarded experiments, drift, and stagnation."
---

You are generating an autoimprove morning report.

## Steps

### 1. Read State

Read these files (report what's missing):
- `experiments/experiments.tsv` — the experiment log
- `experiments/state.json` — trust tier, stagnation counters
- `experiments/epoch-baseline.json` — session start baseline
- `experiments/rolling-baseline.json` — current baseline

### 2. Compute Summary

From `experiments.tsv`, compute:
- Total experiments run (across all sessions, and in the most recent session)
- Verdicts breakdown: kept, neutral, regressed, failed, crashed
- Stagnated themes (from state.json)
- Current trust tier and consecutive keeps

### 3. Compute Drift

For each metric, compare `rolling-baseline.json` to `epoch-baseline.json`:
```
drift = (rolling - epoch) / epoch * 100
```

Flag any metric with drift > epoch_drift_threshold.

### 4. Format Report

Output the report in this format:

```
autoimprove report — <project name> — <date>

Summary
  Experiments: N run, K kept, D neutral, R regressed, F failed
  Epoch drift:  +X.X% improvement from session start
  Trust tier:   N (consecutive keeps: M)
  Budget used:  N / M experiments

Kept Experiments (merged to main)
  #001  theme   "commit message"
  #003  theme   "commit message"

Notable Discards
  #002  theme   verdict  "commit message"

Stagnated Themes
  performance (5 consecutive non-improvements)

Full log: ./experiments/experiments.tsv
Per-experiment context: ./experiments/*/context.json
```

If no experiments have been run, say so and suggest `/autoimprove run`.
