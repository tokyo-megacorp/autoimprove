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
</example>

<example>
Context: User wants to review the results of a specific earlier session.
user: \"show report for session 3\"
assistant: I'll use the report skill with --session 3 to pull that session's results.
<commentary>Historical session review — report skill.</commentary>
</example>"
argument-hint: "[--session N] [--full]"
allowed-tools: [Read, Bash]
---

<SKILL-GUARD>
You are NOW executing the report skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Generate a summary report of recent autoimprove experiment activity. Read session state, compute metric drift, and format a human-readable report.

Parse flags:
- `--session N` — show results for session number N only (not just the most recent)
- `--full` — include all experiments in the Kept/Discards lists, not just the current session

If no experiments have been run, say so and suggest `/autoimprove run`.

Initialize progress tracking:
```
TodoWrite([
  {id:"prereqs",   content:"🔍 Check prerequisites",        status:"in_progress"},
  {id:"read",      content:"📋 Read state files",            status:"pending"},
  {id:"parse",     content:"📊 Parse experiment log",        status:"pending"},
  {id:"drift",     content:"📅 Compute metric drift",        status:"pending"},
  {id:"trust",     content:"🏆 Compute trust tier progress", status:"pending"},
  {id:"format",    content:"📝 Format report",               status:"pending"},
  {id:"stagnation",content:"📋 Check stagnated themes",      status:"pending"}
])
```

---

# 1. 🔍 Prerequisites Check

```bash
test -f autoimprove.yaml || echo "MISSING"
```

If missing, print: `autoimprove is not initialized here. Run /autoimprove init.` and stop.

Mark `prereqs` complete: `TodoWrite([{id:"prereqs", content:"🔍 Check prerequisites", status:"completed"}, {id:"read", content:"📋 Read state files", status:"in_progress"}])`

---

# 2. 📋 Read State Files

Read these files (note which are absent — do not stop on missing files, report what's available):

```bash
# Confirm which files exist before reading
test -f experiments/experiments.tsv    && echo "TSV:present"    || echo "TSV:missing"
test -f experiments/state.json         && echo "STATE:present"  || echo "STATE:missing"
test -f experiments/epoch-baseline.json  && echo "EPOCH:present"  || echo "EPOCH:missing"
test -f experiments/rolling-baseline.json && echo "ROLLING:present" || echo "ROLLING:missing"
```

Read each present file:
- `experiments/experiments.tsv` — the full experiment log
- `experiments/state.json` — trust tier, consecutive keeps, session count, stagnation counters
- `experiments/epoch-baseline.json` — frozen baseline from session start (`{metrics: {...}, sha: "...", timestamp: "..."}`)
- `experiments/rolling-baseline.json` — current baseline, updated on every KEEP (`{metrics: {...}, sha: "...", timestamp: "..."}`)

If `experiments.tsv` is missing or contains only the header row, print:
```
No experiments have been run yet. Run /autoimprove run to start.
```
and stop.

Mark `read` complete: `TodoWrite([{id:"read", content:"📋 Read state files", status:"completed"}, {id:"parse", content:"📊 Parse experiment log", status:"in_progress"}])`

---

# 3. 📊 Parse the Experiment Log

The TSV columns are:
```
id  timestamp  theme  verdict  improved_metrics  regressed_metrics  tokens  wall_time  commit_msg
```

Parse each data row. If `--session N` was passed, filter to rows whose session_id matches N. Otherwise, identify the most recent session by grouping all rows by session_id (last chunk of rows with the same session_id) and use that group as "current session".

Count per-session verdicts: kept, neutral, regress, fail, crash.

For the "current session" group, also capture:
- List of kept experiments (id, theme, commit_msg)
- List of discarded experiments with notable verdicts: regress or fail (id, theme, verdict, commit_msg)

If `--full` was passed, include ALL sessions in kept/discards lists, not just the current one.

Mark `parse` complete: `TodoWrite([{id:"parse", content:"📊 Parse experiment log", status:"completed"}, {id:"drift", content:"📅 Compute metric drift", status:"in_progress"}])`

---

# 4. 📅 Compute Metric Drift

For each metric in `rolling-baseline.json.metrics`, compare to `epoch-baseline.json.metrics`:

```
drift_pct = (rolling_value - epoch_value) / epoch_value * 100
```

Determine improvement direction from `autoimprove.yaml` metric config:
- `direction: higher_is_better` → positive drift = improvement
- `direction: lower_is_better` → negative drift = improvement

Flag any metric where `abs(drift_pct)` exceeds `safety.epoch_drift_threshold` from `autoimprove.yaml` (default 5%) with `*** EPOCH DRIFT ALERT ***`.

If either baseline file is missing, print: `(drift unavailable — baseline file missing)` for that metric.

Mark `drift` complete: `TodoWrite([{id:"drift", content:"📅 Compute metric drift", status:"completed"}, {id:"trust", content:"🏆 Compute trust tier progress", status:"in_progress"}])`

---

# 5. 🏆 Compute Trust Tier Progress

From `state.json`, read `trust_tier` and `consecutive_keeps`.

From `autoimprove.yaml`, read `constraints.trust_ratchet` tier definitions. Find the next tier after the current one and compute:
```
keeps_needed = next_tier.after_keeps - state.consecutive_keeps
```

If at the maximum tier (no higher tier defined), print "maximum tier reached."

Mark `trust` complete: `TodoWrite([{id:"trust", content:"🏆 Compute trust tier progress", status:"completed"}, {id:"format", content:"📝 Format report", status:"in_progress"}])`

---

# 6. 📝 Format Report

```
autoimprove report — <project name> — <date>

Summary
  Experiments:  N run, K kept, D neutral, R regressed, F failed, C crashed
  Epoch drift:  +X.X% net improvement from session start  (or "N/A — baselines missing")
  Trust tier:   N (consecutive keeps: M / needs P more for tier N+1)
  Budget used:  N / M experiments (from autoimprove.yaml max_experiments_per_session)

Kept Experiments (merged to main)
  #001  failing_tests   "Fix divide-by-zero in math.divide()"
  #003  todo_comments   "Implement string.truncate() from TODO"

Notable Discards
  #002  lint_warnings  neutral  "Clean up unused imports"
  #004  coverage_gaps  regress  "Add tests for wordCount"

Stagnated Themes                      ← omit section if none stagnated
  lint_warnings (5 consecutive non-improvements)

Metric Trends
  test_count:   37 → 39  (+5.4%)  ↑ improved
  todo_count:   12 → 10  (-16.7%) ↑ improved (lower is better)

Full log:              ./experiments/experiments.tsv
Per-experiment detail: ./experiments/*/context.json
```

Adapt the output to what's present — skip sections that have no data (e.g., no stagnated themes, no discards). Never print an empty section header.

For "epoch drift" in the Summary line, summarize net direction: if most metrics improved, print positive; if mixed, print "mixed — see Metric Trends".

For the "Notable Discards" list, only include experiments with `regress` or `fail` verdicts — omit `neutral` unless there are zero regressed/failed experiments to show, in which case include the most recent neutral as context.

Mark `format` complete: `TodoWrite([{id:"format", content:"📝 Format report", status:"completed"}, {id:"stagnation", content:"📋 Check stagnated themes", status:"in_progress"}])`

---

# 7. 📋 Stagnated Themes

From `state.json`, read `theme_stagnation`. A theme is stagnated if its count is >= `safety.stagnation_window` from `autoimprove.yaml` (default 5).

List each stagnated theme with its count. If none stagnated, omit the section entirely.

Mark `stagnation` complete: `TodoWrite([{id:"stagnation", content:"📋 Check stagnated themes", status:"completed"}])`

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  {id:"prereqs", status:"completed"},
  {id:"read", status:"completed"},
  {id:"parse", status:"completed"},
  {id:"drift", status:"completed"},
  {id:"trust", status:"completed"},
  {id:"format", status:"completed"},
  {id:"stagnation", status:"completed"}
])
```

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
  Epoch drift:  +8.3% net improvement from session start
  Trust tier:   2 (consecutive keeps: 3 / needs 12 more for tier 3)
  Budget used:  5 / 15 experiments

Kept Experiments (merged to main)
  #001  failing_tests   "Fix off-by-one in date range filter"
  #003  todo_comments   "Implement missing input sanitizer from TODO"
  #005  coverage_gaps   "Add tests for empty-collection edge case"

Notable Discards
  #004  coverage_gaps   regress  "Add tests for random ID generator"

Metric Trends
  test_count:   42 → 46  (+9.5%)   ↑ improved
  lint_errors:   8 →  7  (-12.5%)  ↑ improved (lower is better)
  coverage:     71 → 74  (+4.2%)   ↑ improved

Full log:              ./experiments/experiments.tsv
Per-experiment detail: ./experiments/*/context.json
```

## Example 2: Review a Specific Earlier Session

```
User: show report for session 2
```

The skill filters `experiments.tsv` to rows from session 2, reports those verdicts and kept experiments only. Drift is still computed against epoch-baseline (frozen at session 2 start if available; otherwise falls back to current epoch-baseline.json).

## Example 3: Full History View

```
User: autoimprove report --full
```

Kept Experiments includes all KEEP verdicts across all sessions. Notable Discards includes all regress/fail across all sessions. Metric Trends still shows epoch → rolling (session-scoped). Useful for a weekly retrospective.

## Example 4: Metric Drift Alert

After a session where `todo_count` improved by 50%:

```
Metric Trends
  todo_count:  18 →  9  (-50.0%)  ↑ improved (lower is better)  *** EPOCH DRIFT ALERT ***
  test_count:  55 → 57  (+3.6%)   ↑ improved
```

The `EPOCH DRIFT ALERT` fires when any metric's drift exceeds `epoch_drift_threshold` (default 5%). This signals the rolling baseline may need re-anchoring after a burst of improvements.

---

# Edge Cases and Pitfalls

- **Missing `experiments/` directory:** If no session has run yet, stop after step 2 with the "no experiments yet" message. Never crash on a missing file.
- **Missing `epoch-baseline.json`:** Drift calculation is skipped. Print `(drift unavailable — epoch baseline not found)` in the Metric Trends section.
- **`experiments.tsv` with no data rows (only header):** Report `0 run` and omit all kept/discards sections. Suggest running `/autoimprove run`.
- **`--session N` with no matching rows:** Print `No experiments found for session N.` and stop.
- **Metric direction:** Some metrics are `lower_is_better` (lint errors, todo count, failing tests). Negative drift on these is an improvement. Always label direction correctly — a user reading `-16.7%` on `todo_count` must see `↑ improved (lower is better)`, not `↓ regressed`.
- **`state.json` stale after interrupted session:** Report reflects whatever was last written to disk. Note if `state.json` timestamps are more than 2 hours older than the latest TSV row — this signals an interrupted session.
- **Multiple sessions in TSV without a session_id column:** If the TSV predates session_id tracking, treat the entire log as one session. Print a note: `(session_id not present — showing full log as single session)`.

---

# Common Failure Patterns

- **Drift percentages all show `0.0%`:** The `epoch-baseline.json` was written at the same moment as `rolling-baseline.json` (e.g., session crashed before any KEEP). Without diverged baselines, drift is 0. The skill notes this explicitly rather than showing misleading results.
- **"kept" count is non-zero but no experiments appear under Kept Experiments:** The session_id grouping may be off if the TSV was manually edited. Check that all rows for the current session share the same session_id field.
- **Stagnated Themes section is empty but experiments keep returning neutral:** Check `autoimprove.yaml`'s `stagnation_window`. If it is set large (e.g., 10), the theme won't appear as stagnated until many consecutive non-improvements. The report reflects the state in `state.json`.
- **Epoch drift alert fires immediately after the first run:** Expected when the very first experiment improves a metric by more than 5%. The threshold is relative to epoch-baseline — early wins on a poor baseline can look like "alert-level" improvements.
- **Report shows prior-session experiments as "current":** If two sessions ran without a fresh `epoch-baseline.json`, all TSV rows may land in the same session bucket. Run `/autoimprove run` fresh (not `--resume`) to anchor a new epoch.
- **`Notable Discards` section lists neutral experiments:** This only happens when there are zero regressed/failed experiments in the session. One neutral is shown as context. If the user finds this confusing, they can suppress it by passing `--full` and reading the full verdict distribution.

---

# Integration Points

- **`/status`** — The live complement to `/report`. Use `/status` to see what's *currently running* (active worktrees, cooldowns, trust tier in real time); use `/report` to see what *already happened* (kept experiments, metric trends).
- **`/decisions`** — `/report` shows code-level experiment outcomes; `/decisions` shows design-level decisions. Run both for a complete project retrospective.
- **`/run`** — After reviewing a report that shows stagnation in a theme, `/run` picks the next theme. If the report shows consecutive failures, the trust tier will have dropped and `/run` will adjust scope automatically.
- **`/history`** — For per-experiment metadata beyond what the report shows (filters by verdict/theme/date). The report is session-scoped; `/history` spans all sessions with filtering.
- **`/diff <exp-id>`** — When the report shows a kept experiment, use `/diff <id>` to inspect the exact code change. The report shows commit message only; diff shows the full patch.
- **`autoimprove.yaml`** — The report reads `epoch_drift_threshold`, metric `direction`, and `stagnation_window` from this file. If drift alerts or stagnation counts seem wrong, check the YAML config first.

---

# When NOT to Use This Skill

- To see the *current* session state (active agents, theme queue, orphan worktrees) → use `/status`
- To browse per-commit diffs of kept experiments → use `/diff <exp-id>`
- To start or continue a session → use `/run`
- To filter the raw experiment log by verdict/theme/date → use `/history`
- To review design-level decisions (why we chose approach X) → use `/decisions`

---

# Notes

- The report is a *snapshot* — it reads state files as they exist now. If the session was interrupted, the report reflects whatever was last flushed to disk.
- "Epoch drift" is relative to the baseline frozen at session start, not the project's all-time history. A +10% epoch drift means 10% improvement *within this session*.
- Verdict counts (kept/neutral/regressed) are per-experiment, not per-metric. An experiment that improves one metric and is neutral on all others still counts as "kept".
- The report does not re-run benchmarks — it reads pre-computed baseline files. For live metric values, run the benchmark command directly from `autoimprove.yaml`.
