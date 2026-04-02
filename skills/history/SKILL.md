---
name: history
description: "Use when browsing or filtering the autoimprove experiment log — viewing past experiments by verdict, theme, date, or score. Examples:

<example>
Context: User wants to see all experiments that were kept.
user: \"show me all kept experiments\"
assistant: I'll use the history skill to filter the log and show kept experiments.
<commentary>Filtering kept experiments — history skill.</commentary>
</example>

<example>
Context: User wants to review what autoimprove tried in a specific theme.
user: \"what experiments ran for the failing_tests theme?\"
assistant: I'll use the history skill to filter by theme and show matching experiments.
<commentary>Theme-scoped log review — history skill.</commentary>
</example>

Do NOT use for a session summary with metric drift (use the report skill). Do NOT use to start a session (use the run skill)."
argument-hint: "[--verdict kept|neutral|regress|fail] [--theme THEME] [--last N] [--since YYYY-MM-DD]"
allowed-tools: [Read, Bash]
---

<SKILL-GUARD>
You are NOW executing the history skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Browse and filter the autoimprove experiment log. Read-only — makes no changes.

Parse any flags passed by the user:
- `--verdict` — filter by verdict (kept, neutral, regress, fail, crash)
- `--theme` — filter by theme name (substring match)
- `--last N` — show only the N most recent experiments (default: 20)
- `--since YYYY-MM-DD` — show experiments on or after this date

Initialize progress tracking:
```
TodoWrite([
  {id:"prereqs", content:"🔍 Check prerequisites",    status:"in_progress"},
  {id:"read",    content:"📋 Read experiment log",     status:"pending"},
  {id:"filter",  content:"🔍 Apply filters",           status:"pending"},
  {id:"table",   content:"📊 Format results table",    status:"pending"},
  {id:"summary", content:"📋 Print filter summary",    status:"pending"},
  {id:"totals",  content:"📊 Print all-time totals",   status:"pending"}
])
```

---

# 1. 🔍 Check Prerequisites

```bash
test -f autoimprove.yaml || echo "MISSING"
```

If missing, print: `autoimprove is not initialized here. Run /autoimprove init.` and stop.

Mark `prereqs` complete: `TodoWrite([{id:"prereqs", content:"🔍 Check prerequisites", status:"completed"}, {id:"read", content:"📋 Read experiment log", status:"in_progress"}])`

---

# 2. 📋 Read the Experiment Log

Read `experiments/experiments.tsv`.

If the file is missing or contains only the header row, print:
```
No experiments have been run yet. Run /autoimprove run to start.
```
and stop.

The TSV columns are:
```
id  timestamp  theme  verdict  improved_metrics  regressed_metrics  tokens  wall_time  commit_msg
```

Mark `read` complete: `TodoWrite([{id:"read", content:"📋 Read experiment log", status:"completed"}, {id:"filter", content:"🔍 Apply filters", status:"in_progress"}])`

---

# 3. 🔍 Apply Filters

Parse each data row into a structured record. Then apply filters in this order:

1. **`--since YYYY-MM-DD`**: Keep rows where `timestamp >= since_date`.
2. **`--theme THEME`**: Keep rows where `theme` contains `THEME` (case-insensitive substring match).
3. **`--verdict VERDICT`**: Keep rows where `verdict == VERDICT` exactly.
4. **`--last N`**: After all other filters, keep only the last N rows (by `id` order).

If no filters were passed, apply only the default `--last 20` limit.

If filters produce an empty result, print: `No experiments match those filters.` and stop.

Mark `filter` complete: `TodoWrite([{id:"filter", content:"🔍 Apply filters", status:"completed"}, {id:"table", content:"📊 Format results table", status:"in_progress"}])`

---

# 4. 📊 Format the Table

Print each matching experiment as a table row. Use the following layout:

```
#<id>  <timestamp>  <theme>          <verdict>  <commit_msg>
```

Verdict coloring convention (describe with text labels, not ANSI):
- `kept`    → prefix with [KEPT]
- `neutral` → prefix with [SKIP]
- `regress` → prefix with [BACK]
- `fail`    → prefix with [FAIL]
- `crash`   → prefix with [CRAS]

Truncate commit messages to 60 characters, appending `…` if cut.

Example output:
```
autoimprove history — my-project — 2026-03-25

  #001  2026-03-25 22:01  failing_tests    [KEPT]  Fix divide-by-zero in math.divide()
  #002  2026-03-25 22:18  lint_warnings    [SKIP]  Remove unused imports in utils.js
  #003  2026-03-25 22:31  coverage_gaps    [FAIL]  Add branch coverage for error paths
  #004  2026-03-25 22:47  todo_comments    [KEPT]  Implement string.truncate() from TODO…
  #005  2026-03-25 23:02  failing_tests    [BACK]  Optimize FTS5 query — broke test tim…

Showing 5 experiments (filtered: theme=failing_tests excluded, last 20)
```

Mark `table` complete: `TodoWrite([{id:"table", content:"📊 Format results table", status:"completed"}, {id:"summary", content:"📋 Print filter summary", status:"in_progress"}])`

---

# 5. 📋 Print Filter Summary

After the table, print a one-line summary:

```
Showing <N> experiment(s)<filter description>.
```

Build the filter description from active filters, e.g.:
- ` — verdict=kept`
- ` — theme=failing_tests, verdict=kept`
- ` — since 2026-03-20, last 10`
- ` — (no filters, last 20)`

Mark `summary` complete: `TodoWrite([{id:"summary", content:"📋 Print filter summary", status:"completed"}, {id:"totals", content:"📊 Print all-time totals", status:"in_progress"}])`

---

# 6. 📊 Print Verdict Totals

Below the table, always print a totals line across the entire log (unfiltered):

```
All-time:  <total> experiments — <K> kept, <N> neutral, <R> regressed, <F> failed, <C> crashed
```

This gives context for how many the filter excluded.

Mark `totals` complete: `TodoWrite([{id:"totals", content:"📊 🏆 <K> kept, <F> failed all-time", status:"completed"}])`

---

# Notes

- If `experiments.tsv` has rows with missing columns (malformed), skip them and note the count: `N malformed row(s) skipped.` The log is append-only — do not sort, deduplicate, or modify it.
- For large logs (>200 rows), warn the user: `Log has <N> rows. Use --last or --since to narrow results.` before printing the table.

---

# Usage Examples

## Example 1 — Review the last 20 experiments (default)

```
user: /history
```

Shows the 20 most recent experiments across all themes and verdicts. Good starting point for a morning catch-up after an overnight autoimprove session.

## Example 2 — Find all regressions

```
user: /history --verdict regress
```

Lists every experiment that regressed a metric. Useful for auditing what themes or approaches have caused harm so far. Combine with `--theme` to narrow further.

## Example 3 — Investigate a specific theme over time

```
user: /history --theme coverage_gaps --last 10
```

Shows the 10 most recent experiments for `coverage_gaps`. Lets you see whether the theme is making progress (alternating kept/neutral) or stuck (all fail/neutral).

## Example 4 — Review experiments since a specific date

```
user: /history --since 2026-03-25
```

Useful after returning from a break or for a weekly retro: see everything that ran since Monday.

## Example 5 — Combine multiple filters

```
user: /history --theme failing_tests --verdict kept --last 5
```

Shows the 5 most recent kept experiments for `failing_tests`. Use this to understand what kinds of fixes have been successful in a theme before writing a new experiment.

---

# Edge Cases and Pitfalls

- **Filters are applied in order**: `--since` is applied first, then `--theme`, then `--verdict`, then `--last N`. The `--last N` cap applies to the already-filtered subset, not the full log. A query like `--verdict kept --last 5` returns the 5 most recent kept rows, not the last 5 rows that happen to be kept.
- **Substring match on theme**: `--theme test` will match both `failing_tests` and `prompt-testing`. If you want an exact match, use a more specific string like `--theme failing_tests`.
- **Malformed rows**: Each row in `experiments.tsv` must have exactly 9 tab-separated columns. Rows with fewer columns are skipped silently (with a count at the end). This can happen if a commit message contained a literal tab character.
- **Empty log**: If no experiments have run yet, the skill stops immediately with a helpful message. It does not print an empty table.
- **Large logs without filters**: Logs grow without bound; at >200 rows the skill warns before printing. Always pass `--last` or `--since` for logs in active production use.

---

# Integration Points

- **status skill**: `/status` shows only the single most recent experiment. Use `/history` when you need more context or want to filter by verdict/theme.
- **report skill**: `/report` shows metric-level drift (which benchmarks improved/regressed). `/history` shows experiment-level records (themes, verdicts, commit messages). Use both together for a complete picture.
- **run skill**: After reviewing history to understand which themes are stagnating or regressing, use `/run` to kick off the next session with informed expectations.
- **experiments.tsv format**: The TSV is the canonical append-only log. Never edit it manually. The history skill is the intended read interface; direct TSV inspection is a fallback only.

---

# Common Failure Patterns

- **`--since` date returns no results despite recent experiments:** The date format must be `YYYY-MM-DD`. A format like `03-29-2026` or `March 29` will not parse correctly and the filter will silently return nothing.
- **`--theme` filter returns experiments from an unrelated theme:** Theme names are substring-matched. Use the full theme name (e.g., `--theme failing_tests`, not `--theme test`) to avoid cross-contamination.
- **Malformed row count increases after experimenter commits:** Commit messages with embedded tab characters break the TSV format. Prefer commit messages without tabs. If a row is malformed, the experiment is still recorded but cannot be queried by verdict or theme — fix the commit message format for future experiments.

---

# When NOT to Use

- **Do not use** to see metric-level benchmark scores — use the report skill for that.
- **Do not use** to modify or clean up the log — the TSV is append-only and must not be edited. If you need to annotate an experiment, use LCM with a reference to the experiment ID.
- **Do not use** to start or resume a session — that is the run skill's job.
- **Do not use** as a substitute for `/autoimprove diff <exp-id>` when you need to see what code changed — history shows metadata (theme, verdict, commit message); diff shows the actual code diff.
- **Do not use** to retrieve experiment context files — those are in `experiments/<id>/context.json` and are read directly, not via this skill.

---

# Notes

- Experiment IDs in the TSV are sequential integers, not git SHAs. The `/diff` and `/rollback` skills accept these IDs and resolve them to commit SHAs internally.
- The history skill is read-only and stateless — it never modifies `experiments.tsv` or any state file.
