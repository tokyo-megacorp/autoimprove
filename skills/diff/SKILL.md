---
name: diff
description: "Use when inspecting what code an autoimprove experiment changed. Triggers on: 'what did exp-007 change', 'diff experiment 3', 'compare experiments', '/autoimprove diff'. Examples:

<example>
user: \"show me what the last kept experiment changed\"
assistant: I'll use the diff skill to show the most recent kept experiment's commit diff.
<commentary>Inspecting a kept experiment — diff skill, not history or report.</commentary>
</example>

<example>
user: \"diff experiment 12\"
assistant: I'll use the diff skill to show experiment 12's git commit diff.
<commentary>Targeted experiment inspection — diff skill, not rollback (destructive).</commentary>
</example>

<example>
user: \"show me the total diff from all kept experiments\"
assistant: I'll use the diff skill with --kept to aggregate all kept experiment commits.
<commentary>Cumulative kept-experiments diff — diff skill with --kept flag.</commentary>
</example>

Do NOT use to revert changes (use rollback). Do NOT use to browse score trends (use report)."

argument-hint: "[<id>|last|--kept|--range <from>..<to>] [--files] [--stat] [--since YYYY-MM-DD]"
allowed-tools: [Read, Bash]
---

<SKILL-GUARD>
You are NOW executing the diff skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Show the code-level diff for one or more autoimprove experiments. Read-only — makes no changes to experiment state, baselines, or git history.

## Argument Parsing

Parse the argument string passed by the user:

| Argument | Meaning |
|----------|---------|
| `<id>` | Show diff for experiment N (accepts `5`, `005`, `exp-005`) |
| `last` | Show diff for the most recent experiment (any verdict) |
| `last kept` | Show diff for the most recent kept experiment |
| `--kept` | Aggregate diff across ALL kept experiments |
| `--range <from>..<to>` | Aggregate diff across experiments from ID `<from>` to `<to>` inclusive |
| `--since YYYY-MM-DD` | Show diffs for all experiments on or after this date |
| `--files` | List only affected file paths, no line-level diff |
| `--stat` | Show `--stat` summary (insertions, deletions per file), no full diff |
| Two bare IDs (e.g., `5 9`) | Compare side by side: show diff for each, with a shared file overlap summary |

Default (no arguments): show diff for the most recent experiment.

---

# 1. Prerequisites Check

```bash
test -f autoimprove.yaml || echo "MISSING_CONFIG"
test -f experiments/experiments.tsv || echo "MISSING_TSV"
```

If `autoimprove.yaml` is missing: print the message below and stop.

```
autoimprove is not initialized here. Run /autoimprove init first.
```

If `experiments.tsv` is missing: print the message below and stop.

```
No experiment log found. No experiments have run yet.
```

---

# 2. Read the Experiment Log

Read `experiments/experiments.tsv`.

TSV columns (0-indexed):

| Index | Name | Example |
|-------|------|---------|
| 0 | `id` | `007` |
| 1 | `timestamp` | `2026-03-29T14:22:01Z` |
| 2 | `theme` | `test_coverage` |
| 3 | `verdict` | `keep` |
| 4 | `improved_metrics` | `test_count:+4,coverage_pct:+2.1` |
| 5 | `regressed_metrics` | `` |
| 6 | `tokens` | `12400` |
| 7 | `wall_time` | `87s` |
| 8 | `commit_hash` | `a1b2c3d` |
| 9 | `commit_msg` | `exp-007: add edge-case tests for tokenizer` |

> Note: column 8 (`commit_hash`) may be absent in older TSV files. If missing, derive the commit from
> the experiment ID via the git log strategy in step 3b.

Build a list of experiment records from the TSV. Apply any `--since`, `--kept`, or `--range` filters now.

If the filtered list is empty, print:

```
No experiments match the filter. Use /autoimprove history to browse the full log.
```

and stop.

---

# 3. Resolve Commit Hashes

For each experiment to inspect, find its git commit hash. Use the TSV `commit_hash` column when
available. When absent, fall back to searching git history by the commit message prefix:

```bash
git log --oneline --all | grep "exp-<id>:" | head -1 | awk '{print $1}'
```

If no commit is found for an experiment, skip it and print:

```
[SKIP] exp-<id>: commit not found in git history (experiment may have been discarded without commit)
```

---

# 4. Show Diff(s)

For each resolved commit, run the appropriate git command depending on the active flags.

## 4a. Default — Full diff

```bash
git show <commit_hash> --color=never
```

Print the output preceded by a header line:

```
── exp-<id> · <theme> · <verdict> · <timestamp> ──────────────────────────────
```

Cap output at 300 lines. If the diff exceeds 300 lines, truncate and print:

```
[TRUNCATED — showing first 300 lines of N total. Use --stat for a summary or --files for file list.]
```

## 4b. `--stat` mode

```bash
git show <commit_hash> --stat --color=never
```

No line cap needed — stat output is always compact.

## 4c. `--files` mode

```bash
git show <commit_hash> --name-only --format="" --color=never | grep -v '^$'
```

Print only the file paths, one per line.

## 4d. `--kept` or `--range` — Aggregate mode

When aggregating multiple experiments, generate a combined diff from the oldest selected
experiment commit to the newest selected experiment commit. Take both hashes directly from the
filtered experiment list; do not derive `FIRST_COMMIT` with `git log ... | tail -1`, because on a
linear history that can walk all the way back to the repository's initial commit.

```bash
FIRST_COMMIT=<oldest_selected_hash>
LAST_COMMIT=<newest_selected_hash>
git diff ${FIRST_COMMIT}^..${LAST_COMMIT} --color=never
```

Print an aggregate header before the diff:

```
── Aggregate diff · <N> experiments · <first_id>–<last_id> ──────────────────
Experiments: exp-001 (keep), exp-003 (keep), exp-007 (keep)
Combined range: <FIRST_COMMIT> → <LAST_COMMIT>
```

Apply the same 300-line cap. In `--stat` mode, use `git diff --stat` instead.

---

# 5. Side-by-Side Comparison (two IDs)

When the user passes two bare IDs (e.g., `5 9`), show each experiment's diff sequentially with
headers, then add a file overlap summary at the end:

```
── exp-005 · test_coverage · keep ──────────────────────────────────────────
<diff for exp-005>

── exp-009 · skill_quality · neutral ───────────────────────────────────────
<diff for exp-009>

── File overlap ─────────────────────────────────────────────────────────────
Files touched by BOTH experiments:
  src/tokenizer.ts
  tests/tokenizer.test.ts

Files touched by ONLY exp-005:
  src/lexer.ts

Files touched by ONLY exp-009:
  skills/diff/SKILL.md
```

Compute the overlap by comparing the `--name-only` output of each commit.

---

# 6. Print Metadata Footer

After the diff(s), always print a compact metadata footer:

For a single experiment:
```
──────────────────────────────────────────────────────────────────────────────
exp-<id> metadata
  Theme:    <theme>
  Verdict:  <verdict>
  Metrics:  improved=[<improved_metrics>]  regressed=[<regressed_metrics>]
  Tokens:   <tokens>
  Time:     <wall_time>
  Commit:   <commit_hash>
  Message:  <commit_msg>
```

For aggregate mode, print the count and verdict breakdown:
```
──────────────────────────────────────────────────────────────────────────────
Aggregate: <N> experiments included
  Verdicts: keep=3 neutral=0 regress=0
  Total tokens consumed: <sum>
  Date range: <earliest_timestamp> → <latest_timestamp>
```

---

# 7. Common Use Cases and Examples

## Review before rolling back

The primary use case for this skill is reviewing an experiment's actual changes *before* deciding
to roll it back. The workflow is:

```
user: diff experiment 12
→ inspect the changes
user: rollback experiment 12
→ now execute the revert
```

This prevents accidental rollbacks of unrelated changes.

## Understanding what drove a score improvement

```
user: show me what the last kept experiment changed
```

The diff shows which files were modified. Cross-referencing with the metrics footer (e.g.,
`test_count: +4`) reveals the connection between the code change and the improvement.

## Auditing cumulative drift

```
user: show me the total diff from all kept experiments
```

Useful after a long session: understand the overall shape of accumulated changes before
reviewing them with a human or submitting as a PR.

## Checking what the test_coverage theme touched

```
user: /autoimprove diff --since 2026-03-28 --files
```

Lists every file touched by any experiment since March 28, with one path per line. Useful
for scoping a downstream code review.

---

# 8. When NOT to Use

- **Reverting a kept experiment** → use `/autoimprove rollback` (this skill is read-only)
- **Browsing experiment scores and verdicts** → use `/autoimprove history` or `/autoimprove report`
- **Checking active session state** → use `/autoimprove status`
- **Debugging broken gates or metrics** → use `/autoimprove diagnose`

---

# 9. Integration Points

- **`/autoimprove rollback`** — The natural next step after diff. Inspect what an experiment changed (diff), then decide whether to revert it (rollback).
- **`/autoimprove history`** — Use history to find the experiment ID, then diff to inspect its changes. They are complementary: history gives the score story; diff gives the code story.
- **`/autoimprove report`** — Report shows metric trends across the session; diff shows what code changes drove those trends. Together they give the full picture.
- **`experiments/experiments.tsv`** — The diff skill reads this file to resolve experiment IDs to commit hashes. If the TSV is missing or incomplete, the skill falls back to `git log` search by commit message prefix.
