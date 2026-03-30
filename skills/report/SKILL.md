---
name: report
description: "Use when reviewing autoimprove experiment results — what was kept, discarded, score trends, session summary. Examples:

<example>
Context: User wants to see what autoimprove did in the last session.
user: \"show me the autoimprove report\"
assistant: I'll use the report skill to summarize recent experiment results.
<commentary>Reviewing session results — report skill.</commentary>
</example>

<example>
Context: User wants to know what improvements were kept.
user: \"what experiments were kept from the last run?\"
assistant: I'll use the report skill to show kept experiments and score improvements.
<commentary>Experiment review — report skill.</commentary>
</example>"
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

---

# Usage Examples

## Example 1: End-of-Session Summary

```
User: show me the autoimprove report
```

Output after a session with 5 experiments (3 kept, 1 neutral, 1 regressed):

```
autoimprove report — my-project — 2026-03-29

Summary
  Experiments:  5 run, 3 kept, 1 neutral, 1 regressed, 0 failed
  Epoch drift:  +8.3% improvement from session start
  Trust tier:   2 (consecutive keeps: 3)
  Budget used:  5 / 15 experiments

Kept Experiments (merged to main)
  #001  failing_tests   "Fix off-by-one in date range filter"
  #003  todo_comments   "Implement missing input sanitizer from TODO"
  #005  coverage_gaps   "Add tests for empty-collection edge case"

Notable Discards
  #002  lint_warnings   neutral  "Remove unused import in helpers.js"
  #004  coverage_gaps   regress  "Add tests for random ID generator"

Metric Trends
  test_count:   42 → 46  (+9.5%)   ↑ improved
  lint_errors:   8 →  7  (-12.5%)  ↑ improved (lower is better)
  coverage:     71 → 74  (+4.2%)   ↑ improved

Full log:              ./experiments/experiments.tsv
Per-experiment detail: ./experiments/*/context.json
```

## Example 2: Post-Regression Review

```
User: what experiments were discarded in the last run?
```

The skill filters for `regressed` and `failed` verdicts in the most recent session and lists them with their theme and description. This helps identify which themes to cool down or which test patterns are fragile.

## Example 3: Trust Tier Progress Check

```
User: how close are we to trust tier 3?
```

The skill reads `state.json` for `consecutive_keeps` and compares to the tier thresholds in `autoimprove.yaml`. It reports current tier, progress toward the next, and which themes have been stagnating (which resets the count).

## Example 4: Metric Drift Alert

After a session where `todo_count` drifted -25% (many TODOs resolved):

```
Metric Trends
  todo_count:  18 →  9  (-50.0%)  ↑ improved (lower is better)  *** EPOCH DRIFT ALERT ***
  test_count:  55 → 57  (+3.6%)   ↑ improved
```

The `EPOCH DRIFT ALERT` flag appears when any metric's drift exceeds the `epoch_drift_threshold` from `autoimprove.yaml` (default 5%). This signals the rolling baseline may need re-anchoring — or that a burst of improvements was just made and the baseline should be updated.

---

# Edge Cases and Pitfalls

- **Missing `experiments/` directory:** If no session has run yet, the skill says so and suggests `/autoimprove run`. It never crashes on missing files.
- **Missing `epoch-baseline.json`:** Drift calculation is skipped for that metric. The skill notes the missing baseline rather than silently skipping drift reporting.
- **`experiments.tsv` with no rows:** The skill reports `0 run` and skips the Kept/Discards sections. This is normal for a freshly initialized project.
- **Stale `state.json`:** If a session was interrupted (e.g., agent crash), `state.json` may reflect a partial run. The skill reads it faithfully and does not attempt to reconstruct state from `.tsv` — report what's there.
- **Metric direction:** Some metrics are "lower is better" (lint errors, todo count, failing tests). When drift is negative for these metrics, it should be flagged as an improvement, not a regression. The report uses `autoimprove.yaml`'s `lower_is_better` flag to determine direction.
- **Multiple sessions in TSV:** `experiments.tsv` may contain rows from many past sessions. "Most recent session" is defined by the `session_id` field — group rows by session ID and show the latest group as current, with aggregate counts for prior sessions.

---

# Common Failure Patterns

- **Drift percentages all show `0.0%`:** The `epoch-baseline.json` was not written at session start (common after a crash or `--resume`). Without an epoch baseline, drift is undefined — the skill notes this explicitly rather than showing misleading zeroes.
- **"kept" count is non-zero but no experiments appear under Kept Experiments:** The session_id grouping may be off if the TSV was manually edited. Check that all rows intended for the "most recent session" share the same `session_id` value.
- **Stagnated Themes section is empty but experiments keep returning neutral:** Check `autoimprove.yaml`'s `stagnation_window` — if it's set to a large value (e.g., 10), the theme won't appear as stagnated until many consecutive non-improvements. The report reflects the state in `state.json`, which only triggers stagnation after the configured window.
- **Epoch drift alert fires immediately after the first run:** This is expected when the very first experiment improves a metric by more than 5%. The threshold is absolute from epoch-baseline — if you start from a poor baseline, early wins can look like "alert-level" improvements.
- **Report shows prior-session experiments as current:** If two sessions ran without writing a fresh `epoch-baseline.json`, all TSV rows may appear in the "most recent session" bucket. Run `/autoimprove run` fresh (not `--resume`) to anchor a new epoch.

---

# Integration Points

- **`/status`** — The live complement to `/report`. Use `/status` to see what's *currently running* (active worktrees, cooldowns); use `/report` to see what *already happened* (kept experiments, metric trends).
- **`/decisions`** — `/report` shows code-level experiment outcomes; `/decisions` shows design-level decisions. Run both for a complete project retrospective.
- **`/run`** — After reviewing a report that shows stagnation in a theme, `/run` picks the next theme. If the report shows consecutive failures, the trust tier will have dropped and `/run` will adjust scope automatically.
- **`/history`** — For per-experiment detail beyond what the report shows, `/history` provides a per-commit view of what was changed in each kept experiment.
- **`autoimprove.yaml`** — The report reads `epoch_drift_threshold` and metric `lower_is_better` flags from this file. If drift alerts seem wrong, check the YAML configuration first.

---

# When NOT to Use This Skill

- To see the *current* session state (active agents, theme queue) → use `/status`
- To browse per-commit diffs → use `/history`
- To start or continue a session → use `/run`
- To inspect *what code changed* in a specific experiment → use `/diff <exp-id>`
- To review design-level decisions (why we chose approach X) → use `/decisions`

---

# Notes

- The report is a *snapshot* — it reads state files as they exist now. If the session was interrupted, report reflects whatever was last flushed to disk.
- "Epoch drift" is relative to the baseline frozen at session start, not the project's all-time history. A +10% epoch drift means 10% improvement within this session, not from the project's inception.
- Verdict counts (kept/neutral/regressed) are per-experiment, not per-metric. An experiment that improves one metric and is neutral on all others still counts as "kept".
