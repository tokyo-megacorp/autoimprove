---
name: experiment
description: "Use when the user wants to manually create, list, or remove autoimprove experiments. Triggers: 'create experiment', 'list experiments', 'remove experiment', 'define hypothesis', '/autoimprove experiment'.

<example>
user: \"/autoimprove experiment create\"
assistant: I'll use the experiment skill to walk through the interactive creation wizard.
<commentary>Manual experiment creation — experiment skill.</commentary>
</example>

<example>
user: \"/autoimprove experiment list --status pending\"
assistant: I'll use the experiment skill to show all pending experiments.
<commentary>Listing pending experiments — experiment skill.</commentary>
</example>

<example>
user: \"/autoimprove experiment remove\"
assistant: I'll use the experiment skill to interactively remove experiment records.
<commentary>Cleanup — experiment skill.</commentary>
</example>

Do NOT use to start the grind loop (use run). Do NOT use to view metric trends (use report). Do NOT use to browse the verdict log (use history)."
argument-hint: "<create|list|remove> [options]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

<SKILL-GUARD>
You are NOW executing the experiment skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Interactive CRUD for autoimprove experiments. Parse the subcommand from `$ARGUMENTS`:
- `create` (or no subcommand) — interactive wizard to define a new experiment
- `list` — formatted table view with optional filters
- `remove` — interactive selection and confirmed deletion

Initialize progress tracking:

```
TodoWrite([
  {id: "prereqs",   content: "✅ Prerequisites check",  status: "in_progress"},
  {id: "subcommand", content: "🔀 Route subcommand",    status: "pending"}
])
```

---

# 1. Prerequisites Check

```bash
test -f autoimprove.yaml || echo "MISSING_CONFIG"
test -d experiments || echo "MISSING_EXPERIMENTS_DIR"
```

If `autoimprove.yaml` is missing, print:
```
autoimprove is not initialized here. Run /autoimprove init first.
```
and stop.

If the `experiments/` directory does not exist, create it:
```bash
mkdir -p experiments
```

Mark complete:
```
TodoWrite([
  {id: "prereqs", content: "✅ Prerequisites check", status: "completed"},
  {id: "subcommand", content: "🔀 Route subcommand", status: "in_progress"}
])
```

---

# 2. Route Subcommand

Parse the first word of `$ARGUMENTS`. Route to the matching section:
- `create` → Section 3
- `list` → Section 4
- `remove` → Section 5
- anything else or empty → default to `create` (print a one-line note: "No subcommand given — starting experiment creation wizard.")

Mark complete:
```
TodoWrite([{id: "subcommand", content: "🔀 Route subcommand", status: "completed"}])
```

---

# 3. `create` — Interactive Experiment Wizard

Add todos:

```
TodoWrite([
  {id: "c_theme",    content: "💡 Ask: theme",            status: "in_progress"},
  {id: "c_hypo",     content: "🧪 Ask: hypothesis",       status: "pending"},
  {id: "c_files",    content: "📁 Ask: target files",     status: "pending"},
  {id: "c_constr",   content: "🔒 Ask: constraints",      status: "pending"},
  {id: "c_outcome",  content: "🎯 Ask: expected outcome", status: "pending"},
  {id: "c_write",    content: "💾 Write context.json",    status: "pending"},
  {id: "c_confirm",  content: "✅ Confirm and next steps", status: "pending"}
])
```

## Step 3a — Theme

Read `autoimprove.yaml` to get available themes from `themes.auto.priorities`. Present them as a numbered list:

```
What theme does this experiment address?
Available themes (from autoimprove.yaml):
  1. failing_tests
  2. todo_comments
  3. coverage_gaps
  4. lint_warnings
  5. Other (type a custom theme name)
```

Wait for the user's response. Accept a number or a free-text theme name. If the user types a number, resolve it to the theme name. If they type `5` or "other", prompt for a free-text name.

Mark `c_theme` complete, `c_hypo` in_progress.

## Step 3b — Hypothesis

Ask one question:

```
What is your hypothesis? Describe what you think is wrong (or improvable) and why.

Example: "The off-by-one error in src/filter.ts causes date-range filter tests to fail on leap-year inputs."
```

Wait for the user's response. Accept any non-empty text. Do not validate; the user knows their codebase.

Mark `c_hypo` complete, `c_files` in_progress.

## Step 3c — Target Files

Ask one question:

```
Which files should the experimenter focus on?
List paths (relative to project root), one per line, or press Enter to leave unspecified.

Example:
  src/filter.ts
  tests/filter.test.ts
```

Wait for the user's response. Accept a multi-line list or an empty response (empty = `[]`). Parse the input into an array of file path strings. Trim whitespace from each line; skip blank lines.

Mark `c_files` complete, `c_constr` in_progress.

## Step 3d — Constraints

Ask one question:

```
Any constraints for this experiment? (Press Enter to use trust-tier defaults.)

Options:
  max_files <N>    — maximum source files the experimenter may touch (default: from trust tier)
  max_lines <N>    — maximum lines changed across all files
  forbidden: <path> — additional paths the experimenter must not touch

Example: max_files 2, max_lines 100
```

Wait for the user's response. Parse `max_files` and `max_lines` if provided; default to reading `experiments/state.json` trust tier and looking up defaults from `autoimprove.yaml constraints.trust_ratchet.tier_<N>`. If parsing fails or the user presses Enter, use `{}` (empty = defer to run-time trust tier).

Mark `c_constr` complete, `c_outcome` in_progress.

## Step 3e — Expected Outcome

Ask one question:

```
What does success look like for this experiment?
Describe the observable outcome you expect if the hypothesis is correct.

Example: "All date-range filter tests pass; test_count metric stays the same or increases."
```

Wait for the user's response. Accept any non-empty text.

Mark `c_outcome` complete, `c_write` in_progress.

## Step 3f — Write context.json

Generate the experiment ID using the current timestamp:

```bash
date -u +"%Y%m%d-%H%M%S"
```

Create the experiment directory and write `context.json`:

```bash
mkdir -p experiments/<ID>
```

Write `experiments/<ID>/context.json`:

```json
{
  "id": "<YYYYMMDD-HHMMSS>",
  "theme": "<theme>",
  "hypothesis": "<hypothesis>",
  "target_files": ["<file1>", "<file2>"],
  "constraints": { "max_files": N, "max_lines": N },
  "forbidden_paths": ["<path1>"],
  "expected_outcome": "<expected_outcome>",
  "status": "pending",
  "created_at": "<ISO timestamp>"
}
```

Field notes:
- `id`: timestamp string from `date -u +"%Y%m%d-%H%M%S"` (e.g. `"20260403-143012"`)
- `constraints`: use whatever the user provided; if empty, write `{}` not null
- `target_files`: write `[]` if the user left it blank
- `status`: always `"pending"` on creation
- `created_at`: ISO 8601 UTC timestamp, e.g. `"2026-04-03T14:30:12Z"`

Mark `c_write` complete, `c_confirm` in_progress.

## Step 3g — Confirm and Next Steps

Print a summary:

```
Experiment created: experiments/<ID>/context.json

  Theme:    <theme>
  Status:   pending
  Files:    <file1>, <file2>  (or "unspecified")

Next steps:
  /autoimprove run --experiment <ID>   — run this experiment now
  /autoimprove experiment list --status pending   — see all pending experiments
```

Mark `c_confirm` complete.

## Final Cleanup (create)

```
TodoWrite([
  {id: "c_theme",   status: "completed"},
  {id: "c_hypo",    status: "completed"},
  {id: "c_files",   status: "completed"},
  {id: "c_constr",  status: "completed"},
  {id: "c_outcome", status: "completed"},
  {id: "c_write",   status: "completed"},
  {id: "c_confirm", status: "completed"}
])
```

---

# 4. `list` — Experiment Table View

Add todos:

```
TodoWrite([
  {id: "l_parse",  content: "📋 Parse arguments",   status: "in_progress"},
  {id: "l_read",   content: "📖 Read experiments",   status: "pending"},
  {id: "l_filter", content: "🔍 Apply filters",      status: "pending"},
  {id: "l_table",  content: "📊 Format table",       status: "pending"},
  {id: "l_totals", content: "📊 Print totals",       status: "pending"}
])
```

## Step 4a — Parse Arguments

Parse flags from `$ARGUMENTS` (after stripping the `list` subcommand):
- `--status <status>` — exact match: `pending`, `running`, `completed`, `failed`, `crashed`
- `--theme <name>` — substring match (case-insensitive)
- `--since <YYYY-MM-DD>` — ISO date; keep entries with `created_at` or `timestamp` on or after this date
- `--last N` — keep only the N most recent entries (default: 20)

Mark `l_parse` complete, `l_read` in_progress.

## Step 4b — Read Experiments

Scan two sources:

**Source 1 — `experiments/experiments.tsv`**

Read the TSV. The columns are:
```
id  timestamp  theme  verdict  improved_metrics  regressed_metrics  tokens  wall_time  commit_msg
```
For each data row, build a record with fields: `id`, `timestamp`, `theme`, `verdict`, `commit_msg`.

Map TSV verdicts to status for the `--status` filter:
- `keep` → `completed`
- `neutral` → `completed`
- `regress` → `completed`
- `fail` → `failed`
- `crash` → `crashed`
- `running` → `running`

**Source 2 — `experiments/*/context.json`**

Glob `experiments/*/context.json`. For each file:
- Read `id`, `theme`, `status`, `created_at`, `hypothesis`, `expected_outcome`
- If the ID matches a row in experiments.tsv, the TSV record wins (it has richer outcome data). Skip the context.json record.
- If not in TSV (status is `pending` or `running`), include only the context.json record.

Merge both sources into a unified list sorted by date descending (most recent first).

If the combined list is empty, print:
```
No experiments found. Run /autoimprove experiment create to define one.
```
and stop.

Mark `l_read` complete, `l_filter` in_progress.

## Step 4c — Apply Filters

Apply filters in this order:
1. `--since YYYY-MM-DD` — keep entries where date ≥ since_date
2. `--theme` — substring match on `theme`
3. `--status` — exact match using the mapped status
4. `--last N` — keep only the N most recent (already sorted by date desc)

If the filtered list is empty, print: `No experiments match those filters.` and stop.

Mark `l_filter` complete, `l_table` in_progress.

## Step 4d — Format Table

Print a header and one row per experiment:

```
autoimprove experiments — <project-name> — <today>

  ID                    THEME            STATUS       DATE         SUMMARY
  20260403-143012       failing_tests    [PENDING]    2026-04-03   The off-by-one error in src/…
  041                   refactoring      [KEPT]       2026-03-31   refactor(tests): move helper…
  040                   lint_warnings    [SKIP]       2026-03-31   Remove unused imports in…
  039                   coverage_gaps    [FAIL]       2026-03-30   Add branch coverage for…

Showing 4 experiments (--status pending, --theme failing_tests)
```

Status labels:
- `pending`   → `[PENDING]`
- `running`   → `[RUNNING]`
- `completed` + `keep` verdict   → `[KEPT]`
- `completed` + `neutral` verdict → `[SKIP]`
- `completed` + `regress` verdict → `[BACK]`
- `failed`    → `[FAIL]`
- `crashed`   → `[CRAS]`

For context.json-only records (pending/running), show `hypothesis` truncated to 60 chars in the SUMMARY column.
For TSV records, show `commit_msg` truncated to 60 chars.

For completed TSV records that have a matching `context.json`, append a metrics-delta line below the row:
```
                                                       improved: test_count (+9.5%)  regressed: —
```

Mark `l_table` complete, `l_totals` in_progress.

## Step 4e — Print Totals

Below the table, print all-time totals (unfiltered):

```
All-time: <total> experiments — <P> pending, <R> running, <K> kept, <S> skipped, <B> regressed, <F> failed, <C> crashed
```

Mark `l_totals` complete.

## Final Cleanup (list)

```
TodoWrite([
  {id: "l_parse",  status: "completed"},
  {id: "l_read",   status: "completed"},
  {id: "l_filter", status: "completed"},
  {id: "l_table",  status: "completed"},
  {id: "l_totals", status: "completed"}
])
```

---

# 5. `remove` — Interactive Experiment Removal

Add todos:

```
TodoWrite([
  {id: "r_scan",    content: "🔍 Scan removable experiments", status: "in_progress"},
  {id: "r_select",  content: "🗂️ User selects experiments",   status: "pending"},
  {id: "r_confirm", content: "⚠️ Confirm before deletion",    status: "pending"},
  {id: "r_delete",  content: "🗑️ Delete selected records",    status: "pending"},
  {id: "r_report",  content: "📋 Deletion summary",           status: "pending"}
])
```

## Step 5a — Scan Removable Experiments

Scan both sources (same logic as list Section 4b) to build the candidate list. Exclude any experiments with `status: "running"` — these cannot be removed while in progress.

If the candidate list is empty, print:
```
No experiments available to remove.
(Note: running experiments cannot be removed while in progress.)
```
and stop.

Mark `r_scan` complete, `r_select` in_progress.

## Step 5b — Present Selection

Print a numbered list of all removable experiments:

```
Select experiments to remove (comma-separated numbers, or "all"):

  1.  20260403-143012   failing_tests    [PENDING]   2026-04-03
  2.  041               refactoring      [KEPT]       2026-03-31
  3.  040               lint_warnings    [SKIP]       2026-03-31
  4.  039               coverage_gaps    [FAIL]       2026-03-30

  Enter numbers (e.g. "1,3") or "all" to remove everything:
```

Wait for the user's response. Parse the input:
- Comma-separated numbers → select those entries
- `"all"` → select all entries
- Empty or invalid input → print "No selection made. Aborting." and stop.

Resolve selection to a list of experiment records.

Mark `r_select` complete, `r_confirm` in_progress.

## Step 5c — Confirm Before Deletion

Always confirm — this is a hard requirement. Print a confirmation prompt showing exactly what will be deleted:

```
The following experiments will be permanently deleted:

  - experiments/20260403-143012/  (context.json only)
  - experiments/039/  (directory + experiments.tsv row #039)

This cannot be undone. Type "yes" to confirm, or anything else to cancel:
```

Wait for the user's response. Only proceed if the user types exactly `"yes"` (case-insensitive). Any other response:
```
Deletion cancelled. No changes made.
```
and stop.

Mark `r_confirm` complete, `r_delete` in_progress.

## Step 5d — Delete Selected Records

For each confirmed experiment:

1. **Remove the directory:**
   ```bash
   rm -rf experiments/<id>/
   ```

2. **Remove from experiments.tsv (if present):**

   Read `experiments/experiments.tsv`. Filter out any row where the `id` column matches the experiment ID. Write the filtered content back to `experiments/experiments.tsv`.

   If the experiment only existed as a `context.json` (no TSV row), skip this step.

3. **Check for an active worktree:**
   ```bash
   git worktree list --porcelain | grep "autoimprove/<id>"
   ```
   If a worktree exists for this experiment, remove it:
   ```bash
   git worktree remove --force <worktree_path>
   git branch -D <branch_name>
   ```
   Print a warning if a worktree was cleaned up: `[WARN] Active worktree removed for experiment <id>.`

Track successes and failures separately. If a directory deletion fails, log the error and continue with remaining experiments.

Mark `r_delete` complete, `r_report` in_progress.

## Step 5e — Deletion Summary

Print a brief summary:

```
Removal complete.

  Deleted: 2 experiment(s)
    - 20260403-143012  (pending, no TSV row)
    - 039              (fail, TSV row removed)

  Skipped: 0 error(s)
```

If any deletion failed, list the errors explicitly.

Mark `r_report` complete.

## Final Cleanup (remove)

```
TodoWrite([
  {id: "r_scan",    status: "completed"},
  {id: "r_select",  status: "completed"},
  {id: "r_confirm", status: "completed"},
  {id: "r_delete",  status: "completed"},
  {id: "r_report",  status: "completed"}
])
```

---

# Notes

## ID Format

Timestamp IDs (`YYYYMMDD-HHMMSS`) are used for manually created experiments. Auto-generated experiments from the grind loop use zero-padded numeric IDs (`001`, `002`, …). Both coexist in the `experiments/` directory and the TSV. The list and remove subcommands handle both formats.

## Running Experiments

`remove` never deletes a `running` experiment. Running experiments are excluded from the candidate list entirely (Section 5a). If a run crashes and leaves `status: "running"` stuck, the user must manually edit `context.json` to change the status before removal is possible. This is intentional — automatic removal of in-progress work is too dangerous. The check uses `status: "running"` in `context.json`; if the context file is absent but a worktree exists, treat as running.

## TSV Row Removal

When removing a row from `experiments.tsv`, read the full file, filter the matching row by exact ID match (first column), and write the result back. Preserve the header row. Never sort or reorder other rows.

## Edge Cases

- **Experiment directory exists but no context.json:** Show it in the list with `[UNKNOWN]` status and allow removal of the directory.
- **TSV row exists but no directory:** Show in list with `[TSV_ONLY]` status; removal deletes the TSV row only.
- **`experiments.tsv` missing:** Skip TSV operations silently; only operate on `context.json` files.
- **Large experiment count (>100):** Warn the user before printing the full list in `remove`: "Found <N> experiments. Showing all — use Ctrl+C to abort."

---

# Integration Points

- **`run` skill** — picks up `pending` experiments when `--experiment <id>` is passed.
- **`history` skill** — shows the same TSV data with verdict-focused filtering (no context.json merging).
- **`report` skill** — shows metric-level trends; `experiment list` shows status and hypothesis.
- **`proposals` skill** — manages Phase 2 proposals; `experiment` manages Phase 1 (grind) experiments.

---

# When NOT to Use

- **Starting the grind loop** — use `run`.
- **Viewing metric trends** — use `report`.
- **Approving/rejecting Phase 2 proposals** — use `proposals`.
- **Browsing experiments by verdict** — use `history` (it is faster for verdict-based queries).
