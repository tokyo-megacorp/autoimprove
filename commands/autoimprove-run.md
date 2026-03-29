---
name: autoimprove-run
description: Start the autoimprove grind loop — runs experiments, scores them, and keeps or discards via git worktrees.
argument-hint: "[--theme <name>] [--max-experiments N]"
---

Invoke the `autoimprove:run` skill now. Do not do any work before the skill loads.

Arguments: $ARGUMENTS

---

## Arguments

| Argument | Description |
|----------|-------------|
| `--theme <name>` | Run only experiments for this theme (e.g. `failing_tests`, `todo_comments`, `coverage_gaps`, `lint_warnings`). Skips weighted-random selection. |
| `--experiments N` | Override `max_experiments_per_session` from `autoimprove.yaml` for this run only. |

Both arguments are optional. Omitting them uses the config defaults and picks themes via weighted-random selection.

## Usage Examples

```
# Start a default session (reads budget from autoimprove.yaml)
/autoimprove run

# Quick trial — run 3 experiments only
/autoimprove run --experiments 3

# Focus on a specific theme
/autoimprove run --theme failing_tests

# Combine: 5 experiments, lint theme only
/autoimprove run --theme lint_warnings --experiments 5
```

## What It Does

1. Reads `autoimprove.yaml` and `scripts/evaluate.sh` — stops if either is missing.
2. Captures a baseline by running the benchmarks before any change.
3. Picks a theme (weighted-random or `--theme` override), spawns an experimenter agent in an isolated git worktree.
4. Evaluates the experiment's changes with `evaluate.sh` — keeps the commit if metrics improved, discards otherwise.
5. Repeats until the experiment budget is exhausted or stagnation is detected.
6. Cleans up all worktrees and writes a session summary to `experiments/experiments.tsv`.

## Output

- `experiments/experiments.tsv` — log of every experiment (id, theme, verdict, metrics delta)
- `experiments/state.json` — trust tier, consecutive keep count, theme cooldowns
- `experiments/epoch-baseline.json` — frozen baseline for the session (never updated mid-session)
- `experiments/rolling-baseline.json` — updated after each KEEP

## Prerequisites

- `autoimprove.yaml` must exist in the project root.
- `scripts/evaluate.sh` must be executable.
- `jq` must be installed.
- All gates in `autoimprove.yaml` must pass before the loop can start.
- Run `/autoimprove init` first if you have not set up the project yet.

## Related Commands

- `/autoimprove init` — scaffold `autoimprove.yaml` before running for the first time
- `/autoimprove report` — review what was kept, discarded, and metric trends after the session
