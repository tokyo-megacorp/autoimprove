---
name: run
description: "This skill should be used when the user invokes \"/autoimprove run\", asks to \"start an improvement session\", \"run autoimprove\", \"run the improvement loop\", or \"run experiments\" on a codebase."
argument-hint: "[--experiments N] [--theme THEME]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent]
---

Run the autoimprove experiment loop: read config, manage state, spawn experimenter agents into worktrees, evaluate their changes deterministically, and keep or discard based on the verdict.

Follow this document top to bottom. Every step is explicit. Do not skip steps.

If `--experiments N` was passed, use N as `max_experiments_per_session`. If `--theme THEME` was passed, only run experiments for that theme.

---

# 1. Prerequisites Check

Verify the environment before anything else:

```bash
test -f autoimprove.yaml || { echo "FATAL: autoimprove.yaml not found in project root"; exit 1; }
test -f scripts/evaluate.sh || { echo "FATAL: scripts/evaluate.sh not found"; exit 1; }
command -v jq >/dev/null || { echo "FATAL: jq is required but not installed"; exit 1; }
chmod +x scripts/evaluate.sh
```

If any check fails, stop immediately and tell the user what's missing.

---

# 2. Session Start

## 2a. Read Config

Read `autoimprove.yaml` and parse it. Required sections:
- `project` — name, path
- `budget` — `max_experiments_per_session`
- `gates` — array of `{name, command}`
- `benchmarks` — array of `{name, command, metrics: [{name, extract, direction, tolerance?, significance?}]}`
- `themes` — strategy, priorities (theme→weight map), `cooldown_per_theme`
- `constraints` — `trust_ratchet` (tier definitions), `forbidden_paths`, `test_modification`
- `safety` — `epoch_drift_threshold`, `coverage_gate`, `regression_tolerance`, `significance_threshold`, `stagnation_window`

## 2b. Generate evaluate-config.json

Convert the YAML config into the JSON format that `evaluate.sh` expects. Write to `experiments/evaluate-config.json`.

```json
{
  "gates": [
    { "name": "tests", "command": "npm test" }
  ],
  "benchmarks": [
    {
      "name": "dogfood",
      "command": "bash benchmark/metrics.sh",
      "metrics": [
        {
          "name": "test_count",
          "extract": "json:.test_count",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
```

Mapping rules:
- `gates` comes directly from `autoimprove.yaml` gates section.
- `benchmarks` comes directly from benchmarks section. Per-metric `tolerance` and `significance` override global `safety` defaults.
- `coverage_gate.command` from `safety.coverage_gate.command`, `threshold` from `safety.coverage_gate.threshold`, `changed_files` starts empty.
- If no `coverage_gate` in config, omit it entirely.
- `regression_tolerance` from `safety.regression_tolerance` (default 0.02).
- `significance_threshold` from `safety.significance_threshold` (default 0.01).

```bash
mkdir -p experiments
```
Then write `experiments/evaluate-config.json` with the generated JSON.

## 2c. Capture Baseline

Run evaluate.sh in init mode to capture current metrics:

```bash
cd <project_path>
bash scripts/evaluate.sh experiments/evaluate-config.json /dev/null
```

Output: `{mode: "init", gates: [...], metrics: {...}}`.

Parse it. If any gate failed, stop — the project must be in a passing state before autoimprove can run.

Save metrics as both baselines:

```json
{
  "metrics": { "<name>": <value> },
  "sha": "<current HEAD sha>",
  "timestamp": "<ISO 8601 now>"
}
```

Write to:
- `experiments/epoch-baseline.json` — frozen for this session, never updated
- `experiments/rolling-baseline.json` — updated after each KEEP

```bash
git rev-parse HEAD
```

## 2d. Load or Create State

Read `experiments/state.json` if it exists. Otherwise create:

```json
{
  "trust_tier": 0,
  "consecutive_keeps": 0,
  "theme_cooldowns": {},
  "theme_stagnation": {},
  "session_count": 0,
  "last_session": null
}
```

Increment `session_count` and set `last_session` to current ISO timestamp.

Decrement all `theme_cooldowns` values by 1. Remove any that reach 0 or below.

## 2e. Load Experiment Log

Read `experiments/experiments.tsv` if it exists. If not, create it with the header:

```
id	timestamp	theme	verdict	improved_metrics	regressed_metrics	tokens	wall_time	commit_msg
```

Determine the next experiment ID by counting existing rows (excluding header). IDs are zero-padded to 3 digits: `001`, `002`, etc.

## 2f. Crash Recovery

```bash
git worktree list --porcelain
```

Filter for worktrees whose path contains `autoimprove/`. For each orphan (no verdict in experiments.tsv):
1. Remove the worktree: `git worktree remove --force <path>`
2. Clean up the branch: `git branch -D <branch_name>`
3. If incomplete experiments.tsv entry exists, set its verdict to `crash`.

---

# 3. Experiment Loop

Initialize: `experiment_count = 0`, `session_keeps = 0`, `session_fails = 0`, `session_regresses = 0`, `session_neutrals = 0`.

## 3a. Budget Check

```
if experiment_count >= budget.max_experiments_per_session → go to Session End
```

## 3b. Stagnation Check

```
active_themes = themes where theme_cooldowns[theme] <= 0 or not in cooldowns
if ALL active_themes have theme_stagnation[theme] >= stagnation_window → go to Session End
```

## 3c. Theme Selection

Pick a theme using weighted random from `themes.auto.priorities`. Skip themes on cooldown or stagnated.

Weighted random: `P(T) = priorities[T] / sum(all eligible priorities)`.

If `--theme` was passed, use that theme exclusively (unless it's on cooldown or stagnated, in which case skip).

## 3d. Trust Tier Constraints

Look up `trust_tier` from state.json. Defaults:

| Tier | max_files | max_lines | mode |
|------|-----------|-----------|------|
| 0 | 3 | 150 | auto_merge |
| 1 | 6 | 300 | auto_merge |
| 2 | 10 | 500 | auto_merge |
| 3 | null | null | propose_only |

Read actual values from `constraints.trust_ratchet.tier_<N>`. If mode is `propose_only`, skip — Tier 3 is not in Phase 1.

## 3e. Gather Recent History

Read the last 5 rows from `experiments.tsv`. Format as:
```
- Experiment 005 (test_coverage): Added edge case tests — kept
- Experiment 004 (lint_warnings): Removed dead code — neutral
```

Include theme, commit message, and verdict only. Do NOT include metric values, scores, or evaluation details.

## 3f. Spawn Experimenter

Build the experimenter prompt with:
- Theme name
- Constraints: `max_files`, `max_lines`
- Forbidden paths from `constraints.forbidden_paths`
- Test modification policy from `constraints.test_modification`
- Recent experiment summaries (from 3e)

Do NOT include: metric names, benchmark definitions, scoring logic, tolerance/significance values, current scores, evaluate-config.json contents, or trust tier number.

```
Agent(
  prompt: "<experimenter prompt>",
  agent: "experimenter",
  isolation: "worktree",
  model: "sonnet"
)
```

Record the start time before spawning.

## 3g. Collect Results

When the experimenter returns:

1. Get the worktree path from Agent result.
2. Check for a commit:
   ```bash
   EXPERIMENTER_SHA=$(cd <worktree_path> && git rev-parse HEAD)
   MAIN_SHA=$(git rev-parse main)
   ```
   If equal, experimenter made no changes → verdict `neutral`. Skip evaluation. Go to 3i.

3. Get commit message:
   ```bash
   cd <worktree_path> && git log -1 --format=%s
   ```

4. Get changed files:
   ```bash
   cd <worktree_path> && git diff --name-only main...HEAD
   ```

## 3h. Evaluate

1. Update `evaluate-config.json` with changed files for the coverage gate's `changed_files` array.

2. Run evaluation from the worktree:
   ```bash
   cd <worktree_path>
   bash scripts/evaluate.sh <abs_path>/experiments/evaluate-config.json <abs_path>/experiments/rolling-baseline.json
   ```

3. Parse JSON output:
   ```json
   {
     "verdict": "keep|gate_fail|regress|neutral",
     "reason": "human-readable explanation",
     "gates": [...],
     "metrics": {...},
     "improved": [...],
     "regressed": [...]
   }
   ```

## 3i. Act on Verdict

**gate_fail / regress / neutral:**
```bash
git worktree remove --force <worktree_path>
git branch -D autoimprove/<branch_name>
```
Increment the appropriate counter. For `neutral`: increment `theme_stagnation[THEME]`. For `regress`: apply trust ratchet penalty (decrement `consecutive_keeps` by `regression_penalty`, demote tier if below threshold).

**keep:**
1. Rebase onto main:
   ```bash
   cd <worktree_path> && git rebase main
   ```
   On conflict: `git rebase --abort`, remove worktree, log as `rebase_fail`, increment `session_fails`, skip keep path.

2. Fast-forward merge:
   ```bash
   cd <project_root>
   KEEP_SHA=$(cd <worktree_path> && git rev-parse HEAD)
   git worktree remove <worktree_path>
   git merge --ff-only <branch_name>
   git branch -D <branch_name>
   ```

3. Tag the commit:
   ```bash
   git tag "exp-<experiment_id>" HEAD
   ```

4. Update rolling baseline — run evaluate.sh init mode on the new main and write the output metrics to `experiments/rolling-baseline.json`:
   ```bash
   cd <project_root>
   bash scripts/evaluate.sh experiments/evaluate-config.json /dev/null
   ```

5. Update trust ratchet: increment `consecutive_keeps`. Promote tier if threshold reached (Tier 0→1 at 5 keeps, Tier 1→2 at 15 keeps).

6. Reset: `theme_stagnation[THEME] = 0`. Increment `session_keeps`.

## 3j. Log Experiment

Append to `experiments/experiments.tsv`:
```
<id>	<ISO timestamp>	<theme>	<verdict>	<improved or ->	<regressed or ->	<tokens or 0>	<wall_time>	<commit_msg or ->
```

Write `experiments/<id>/context.json`:
```json
{
  "id": "007",
  "model": "claude-sonnet-4-6",
  "baseline_sha": "<SHA>",
  "result_sha": "<SHA or null>",
  "theme": "test_coverage",
  "constraints": { "max_files": 3, "max_lines": 150 },
  "changed_files": ["src/foo.ts"],
  "metrics": { "test_count": { "baseline": 37, "candidate": 39, "delta_pct": 5.4 } },
  "verdict": "keep",
  "improved": ["test_count"],
  "regressed": [],
  "wall_time_seconds": 270,
  "timestamp": "<ISO>"
}
```

## 3k. Epoch Drift Check

After every experiment, compute drift for each metric:
```
drift_pct = abs(rolling[metric] - epoch[metric]) / epoch[metric]
```

If any metric has drifted beyond `safety.epoch_drift_threshold` (default 5%) in the regressing direction → halt session immediately. Log: `"EPOCH DRIFT HALT: <metric> drifted <drift_pct>%"`.

## 3l. Persist State

Write `experiments/state.json` after every experiment to enable crash recovery.

## 3m. Increment and Continue

```
experiment_count += 1 → go to 3a
```

---

# 4. Session End

## 4a. Set Cooldowns for Stagnated Themes

For each theme where `theme_stagnation[theme] >= stagnation_window`:
```
theme_cooldowns[theme] = themes.auto.cooldown_per_theme
```

## 4b. Persist Final State

Write `experiments/state.json` one final time.

## 4c. Print Summary

```
═══════════════════════════════════════════════════
  autoimprove session complete
═══════════════════════════════════════════════════

  Experiments run:     <count>
  Kept:                <session_keeps>
  Gate failures:       <session_fails>
  Regressions:         <session_regresses>
  Neutral:             <session_neutrals>

  Trust tier:          <tier> (consecutive keeps: <n>)
  Budget used:         <count> / <max>

  Stagnated themes:    <list or "none">
  Epoch drift:         <max drift %> (threshold: <threshold>%)

  Exit reason:         <budget_exhausted | all_stagnated | epoch_drift_halt>
═══════════════════════════════════════════════════
```

List each kept experiment with its commit message and improved metrics.

---

# Key Invariants

1. **Experimenter is blind.** Never include metric names, benchmark definitions, scoring logic, tolerance/significance, current scores, or evaluate-config.json in the experimenter prompt.
2. **evaluate.sh is the single evaluator.** All gate checks, benchmark runs, metric extraction, and verdict computation happen inside it. Only read the JSON output.
3. **Epoch baseline is frozen.** Never modify `experiments/epoch-baseline.json` after creation.
4. **Rolling baseline updates only on KEEP.**
5. **All worktrees are always cleaned up.** Every code path must remove the worktree and its branch.
6. **Rebase failure = discard.** Never force-merge or create merge commits.
7. **State is persisted after every experiment.** Crash recovery depends on it.
8. **Test modification is additive only.** Always include this constraint in the experimenter prompt.
