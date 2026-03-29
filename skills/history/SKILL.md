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

---

# 1. Check Prerequisites

```bash
test -f autoimprove.yaml || echo "MISSING"
```

If missing, print: `autoimprove is not initialized here. Run /autoimprove init.` and stop.

---

# 2. Read the Experiment Log

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

---

# 3. Apply Filters

Parse each data row into a structured record. Then apply filters in this order:

1. **`--since YYYY-MM-DD`**: Keep rows where `timestamp >= since_date`.
2. **`--theme THEME`**: Keep rows where `theme` contains `THEME` (case-insensitive substring match).
3. **`--verdict VERDICT`**: Keep rows where `verdict == VERDICT` exactly.
4. **`--last N`**: After all other filters, keep only the last N rows (by `id` order).

If no filters were passed, apply only the default `--last 20` limit.

If filters produce an empty result, print: `No experiments match those filters.` and stop.

---

# 4. Format the Table

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

---

# 5. Print Filter Summary

After the table, print a one-line summary:

```
Showing <N> experiment(s)<filter description>.
```

Build the filter description from active filters, e.g.:
- ` — verdict=kept`
- ` — theme=failing_tests, verdict=kept`
- ` — since 2026-03-20, last 10`
- ` — (no filters, last 20)`

---

# 6. Print Verdict Totals

Below the table, always print a totals line across the entire log (unfiltered):

```
All-time:  <total> experiments — <K> kept, <N> neutral, <R> regressed, <F> failed, <C> crashed
```

This gives context for how many the filter excluded.

---

# Notes

- If `experiments.tsv` has rows with missing columns (malformed), skip them and note the count: `N malformed row(s) skipped.` The log is append-only — do not sort, deduplicate, or modify it.
- For large logs (>200 rows), warn the user: `Log has <N> rows. Use --last or --since to narrow results.` before printing the table.
