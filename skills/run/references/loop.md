# Experiment Loop + Session End

Continue from where SKILL.md left off. All session state (config, baselines, state.json, counters) is already loaded. The TaskTree has been created (session task, setup task completed, experiment tasks pending, report task blocked). See `references/tasktree.md` for the task lifecycle protocol.

---

# 3. Experiment Loop

Initialize: `experiment_count = 0`, `session_keeps = 0`, `session_fails = 0`, `session_regresses = 0`, `session_neutrals = 0`.

Also initialize from config:
```
EXPERIMENTER_MODEL = config.budget.experimenter_model ?? "sonnet"
```

## 3a. Budget Check

```
TaskList() → count experiment tasks by status.
If all experiment tasks are completed (including skipped) → go to Session End.
```

Also maintain `experiment_count` as a local counter for the summary.

## 3b. Stagnation Check

```
active_themes = themes where theme_cooldowns[theme] <= 0 or not in cooldowns
if ALL active_themes have theme_stagnation[theme] >= stagnation_window → go to Session End
```

If a theme becomes stagnated mid-session, mark remaining pending experiment tasks for that theme as completed:
```
TaskUpdate(taskId: <exp_task_id>, status: "completed", metadata: {verdict: "skipped_stagnated"})
```

## 3c. Theme Selection

Theme was pre-selected during task creation (step 2i in SKILL.md). Read the next pending experiment task's `metadata.theme`.

```
next_task = first pending experiment task from TaskList() where all blockedBy tasks are completed
THEME = next_task.metadata.theme
EXP_ID = next_task.metadata.exp_id
```

If `THEME == "user_goal"` and `next_task.metadata.goal_name` is present, treat it as a goal slot. Goal slots bypass theme cooldown/stagnation checks and proceed directly to 3d.

If the theme is now on cooldown or stagnated (state changed during this session), skip it:
```
TaskUpdate(taskId: next_task.id, status: "completed", metadata: {verdict: "skipped_stagnated"})
→ go to 3a
```

**Goodhart boundary (preserved):** theme-weights.sh was used for selection during 2i. Never include weight data in the experimenter prompt.

**Reference:** Theme weight computation details (cold start factors, keep-rate scaling, floor 0.25x base) are in step 2i of SKILL.md where themes are selected.

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

## 3f. Harvest Scan (pre-spawn)

Before spawning the experimenter, run the harvest scan to identify low-hanging-fruit files for the selected theme:

```bash
FOCUS=$(bash scripts/harvest-themes.sh "$THEME" "$PROJECT_ROOT")
```

`FOCUS` is a newline-separated list of JSON objects: `{"path":"...","reason":"..."}`.

If `THEME == "user_goal"`, skip the harvest scan and leave `FOCUS` empty unless the task already carries explicit focus hints. Goal slots are scheduled from user priority, not theme-harvest suggestions.

If `FOCUS` is non-empty, extract the file paths and include them in the experimenter prompt as:
```
Focus on these files (structural reasons provided):
<path> — <reason>
<path> — <reason>
```

**Goodhart constraint (BINDING):** Pass file paths and structural reasons only — NEVER pass metric names, scores, or evaluation details. The experimenter must remain blind to scoring.

If `FOCUS` is empty (unknown theme or no matches), spawn experimenter with full autonomy — no focus hint.

## 3g. Spawn Experimenter

> **KNOWN ISSUE: `isolation:"worktree"` CWD**
> `Agent(isolation: "worktree")` creates the worktree from the SESSION's CWD (`~/.claude`),
> not the target repo. For cross-repo grind loops: use manual `git worktree add` from the
> target repo directory. Do NOT rely on `isolation:"worktree"` when CWD ≠ target repo.

### Claim the task

```
TaskUpdate(taskId: next_task.id, status: "in_progress", owner: "orchestrator")
```

### Build the experimenter prompt

Include:
- Theme name
- Constraints: `max_files`, `max_lines`
- Forbidden paths from `constraints.forbidden_paths`
- Test modification policy from `constraints.test_modification`
- Scope constraint from `focus_paths[THEME]` in `autoimprove.yaml` (if defined): list the paths/globs as "Only modify files matching: <paths>". If `focus_paths` is not defined for the theme, experimenter has full autonomy within `max_files`/`max_lines`.
- If `next_task.metadata.goal_name` is set, include a qualitative goal hint derived from that name, but strip raw metric identifiers, operators, and numeric thresholds before adding it to the prompt.
- Recent experiment summaries (from 3e)
- Focus files from harvest scan (from 3f), if any

Do NOT include: metric names, benchmark definitions, scoring logic, tolerance/significance values, current scores, evaluate-config.json contents, or trust tier number.

### Goodhart Guard (pre-spawn)

Before dispatching, verify the experimenter prompt is clean:

```
If the prompt contains any of: "weight", "score", "metric", "keep_rate",
"COLD_START", "FLOOR", "target_metric", "target_delta", numeric weight values,
or evaluate-config.json contents
→ ABORT: log "GOODHART VIOLATION: prompt contains scoring data" and halt session.
```

This is a hard check — a contaminated prompt means the Goodhart boundary has been breached.

### Dispatch

Experiments always run **one at a time** — the TaskTree chain enforces this (each experiment is blocked by the previous). Spawn one experimenter and wait for it to complete before the loop returns to 3a.

EXPERIMENTER_MODEL is read from autoimprove.yaml `budget.experimenter_model` (default: "sonnet").

```
Agent(
  prompt: "<experimenter prompt>",
  agent: "experimenter",
  isolation: "worktree",
  model: EXPERIMENTER_MODEL
)
```

Record the start time before spawning.

## 3h. Collect Results

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

## 3i. Evaluate

1. Update `evaluate-config.json` with changed files for the coverage gate's `changed_files` array.

2. Run evaluation from the worktree:
   ```bash
   # cd into the worktree so gates/benchmarks run against the candidate code.
   # $PROJECT_ROOT is the MAIN project dir set during prerequisites (step 1) — NOT the worktree.
   # Passing a worktree path as the 2nd arg is a common mistake: it's a directory, not a file,
   # which triggers INIT_MODE and skips baseline comparison entirely.
   cd <worktree_path>
   bash scripts/evaluate.sh "$PROJECT_ROOT/experiments/evaluate-config.json" "$PROJECT_ROOT/experiments/rolling-baseline.json"
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

## 3j. Act on Verdict

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
   cd "$PROJECT_ROOT"
   bash scripts/evaluate.sh experiments/evaluate-config.json experiments/rolling-baseline.json
   ```

5. Update trust ratchet: increment `consecutive_keeps`. Promote tier if threshold reached (Tier 0→1 at 5 keeps, Tier 1→2 at 15 keeps).

6. Reset: `theme_stagnation[THEME] = 0`. Increment `session_keeps`.

7. **Debate annotation (advisory only):** Run the adversarial review on the kept diff. This is post-verdict — the result never influences the decision already made.

   Get the diff that was just merged:
   ```bash
   git diff HEAD~1 HEAD
   ```

   Spawn the review agents using the `review` skill on this diff (pass as `TARGET_CODE` directly — no need to re-parse arguments). Use `--rounds` auto-scaled to the diff size. Store the structured JSON output as `DEBATE_ANNOTATION`.

   If the review fails or times out, set `DEBATE_ANNOTATION = null`. Never let a failed review block the loop.

8. **Goal achievement check (after every `keep` verdict):** If `next_task.metadata.goal_name` is set, treat the keep as a goal-slot result.

   1. Read the candidate value for `next_task.metadata.target_metric` from the current `evaluate.sh` output (`metrics.<target_metric>.candidate`).
   2. Read `experiments/state.json` and find the matching goal by `goal_name`. If the goal is already missing or not active/achieved anymore, log a warning and skip the achievement check.
   3. Read the epoch baseline value for the same metric from `experiments/epoch-baseline.json`. If the metric is missing there, log a warning and skip the achievement check.
   4. Compute achievement against the epoch baseline:
      - `-20%` style deltas are achieved when `(candidate - epoch) / epoch <= -0.20`
      - `+10%` style deltas are achieved when `(candidate - epoch) / epoch >= 0.10`
      - `≥N` or `>=N` goals are achieved when `candidate >= N`
      - `≤N` or `<=N` goals are achieved when `candidate <= N`
   5. If achieved:
      - Set `status: "achieved"` on the goal in `experiments/state.json`
      - Log `[GOAL_ACHIEVED: <goal_name> — <target_metric> reached <target_delta>]`
      - Print `Goal achieved: <goal_name> (<target_metric> → <target_delta>)`
      - Write the updated `experiments/state.json`

Achieved goals are excluded from future slot allocation because step 2i only schedules goals where `status == "active"`.

## 3k. Log Experiment

**First**, append to `experiments/experiments.tsv` (durable record — always before task update):
```
<id>	<ISO timestamp>	<theme>	<verdict>	<improved or ->	<regressed or ->	<tokens or 0>	<wall_time>	<commit_msg or ->
```

**Canonical verdict values for the TSV `verdict` column:**

| Verdict | Source | Meaning |
|---------|--------|---------|
| `keep` | evaluate.sh | All gates passed, at least one metric improved |
| `gate_fail` | evaluate.sh | Hard gate failed (tests broken, typecheck failed) |
| `regress` | evaluate.sh | Benchmark regression beyond tolerance |
| `neutral` | evaluate.sh or orchestrator | No changes made, or evaluate.sh found no delta |
| `rebase_fail` | orchestrator (3j) | Merge conflict during keep rebase — change discarded |
| `skipped_stagnated` | orchestrator (3b/3c) | Theme stagnated; experiment slot skipped |
| `skipped_drift_halt` | orchestrator (3l) | Epoch drift threshold breached; session halted |
| `rollback` | rollback skill | Manual revert of a previously kept experiment |

Any TSV parser must handle all eight values without erroring or misclassifying.

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
  "timestamp": "<ISO>",
  "debate_annotation": {
    "rounds": 2,
    "confirmed": [{"severity": "medium", "file": "src/foo.ts", "line": 42, "resolution": "Add null check"}],
    "debunked": [],
    "summary": "1 medium finding confirmed, 0 debunked."
  }
}
```

**Then**, update the experiment task with structured metadata:
```
TaskUpdate(taskId: <exp_task_id>, status: "completed", metadata: {
  exp_id: "<id>",
  theme: "<theme>",
  verdict: "<keep|gate_fail|regress|neutral|rebase_fail>",
  tokens: <N>,
  wall_time_ms: <N>,
  improved_metrics: [...],
  regressed_metrics: [...],
  commit_sha: "<sha or null>",
  worktree_branch: "autoimprove/<id>-<theme>"
})
```

**Invariant 9 enforced:** experiments.tsv is always written before TaskUpdate. The TSV is the durable record; task metadata is supplementary.

## 3l. Epoch Drift Check

After every experiment, compute drift for each metric:
```
drift_pct = abs(rolling[metric] - epoch[metric]) / epoch[metric]
```

If any metric has drifted beyond `safety.epoch_drift_threshold` (default 5%) in the regressing direction → halt session immediately. Log: `"EPOCH DRIFT HALT: <metric> drifted <drift_pct>%"`.

On drift halt, mark all remaining pending experiment tasks as completed:
```
TaskUpdate(taskId: <exp_task_id>, status: "completed", metadata: {verdict: "skipped_drift_halt"})
```

## 3m. Persist State

Write `experiments/state.json` after every experiment to enable crash recovery.

## 3n. Increment and Continue

```
experiment_count += 1
→ execute 3o (theme fitness check)
→ go to 3a (TaskList will reveal the next pending experiment task)
```

## 3o. Theme Fitness Monitoring (informational)

After each experiment, track keep rate per theme from `experiments.tsv`:

```
keeps_for_theme = count rows where theme == THEME and verdict == "keep"
runs_for_theme  = count rows where theme == THEME (last 5 entries)
```

If a theme has **0 keeps in its last 5 experiments**: log `[THEME_STALE: <theme>]` to LCM.

- Stale themes should have their prompts reviewed or be deprioritized in `autoimprove.yaml`
- **Do NOT auto-remove themes** — this is informational only
- The existing stagnation mechanism (3b) handles loop-level skipping; this signal helps humans improve theme prompts

**Design note — all-time keep rate (by design):** `theme-weights.sh` computes keep_rate from the full experiment history, not a rolling window. This is intentional for v1: all-time history is stable, simple to audit, and avoids overfitting to recent noise. The stagnation mechanism (3b) handles themes that are currently failing without needing recency decay. If a theme has many old successes but recent failures, the stagnation window will catch it. Recency decay is a v2 concern.

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

Mark the report task completed with session summary metadata:
```
TaskUpdate(taskId: REPORT_TASK_ID, status: "completed", metadata: {
  phase: "report",
  total_experiments: <count>,
  keeps: <session_keeps>,
  gate_failures: <session_fails>,
  regressions: <session_regresses>,
  neutrals: <session_neutrals>,
  exit_reason: "<budget_exhausted | all_stagnated | epoch_drift_halt>"
})
```

## 4d. Visual Digest (optional)

After printing the terminal summary, offer a visual digest:

```
Visual digest? [Y/n]
```

If the user says yes (or presses Enter):

**1. Build the DATA object** from files already in memory:

```javascript
const DATA = {
  project:    "<project name from autoimprove.yaml>",
  session:    <session_count>,
  date:       "<YYYY-MM-DD>",
  exit_reason: "<budget_exhausted | all_stagnated | epoch_drift_halt>",
  trust_tier: <trust_tier>,
  consecutive_keeps: <consecutive_keeps>,
  keeps_needed_for_next: <tier_threshold - consecutive_keeps>,
  stagnated_themes: [...],   // from state.json theme_stagnation

  // One entry per experiment in this session (from experiments.tsv + context.json):
  experiments: [
    {
      id:                  "<id>",
      theme:               "<theme>",
      verdict:             "<keep|gate_fail|regress|neutral|...>",
      commit_msg:          "<commit_msg or ->",
      tokens:              <tokens or 0>,
      // From context.json — best single-metric delta for the bar:
      max_delta_pct:       <float or null>,       // largest abs(delta_pct) across improved metrics
      max_delta_direction: "<higher_is_better | lower_is_better>"
    },
    ...
  ],

  // Aggregate metric drift (epoch → rolling):
  metrics: {
    "<metric_name>": {
      baseline:    <epoch baseline value>,
      final:       <rolling baseline value>,
      delta_pct:   <float>,
      direction:   "<higher_is_better | lower_is_better>"
    },
    ...
  }
};
```

For `max_delta_pct`: read each kept experiment's `experiments/<id>/context.json`. Pick the metric with the highest `abs(delta_pct)` from the `improved` list. For non-kept experiments, `max_delta_pct = null`.

For `metrics`: compare `epoch-baseline.json` values to `rolling-baseline.json` values. Compute `delta_pct = (final - baseline) / baseline * 100`. Use `direction` from `evaluate-config.json` metric definitions.

**2. Generate the HTML** by reading `references/digest-template.html` and replacing `__DATA_PLACEHOLDER__` with the JSON-serialized DATA object:

```bash
# Read template, inject data, write digest
DIGEST_PATH="experiments/digest-session-<session_count>.html"
```

Use Read to load the template, substitute `__DATA_PLACEHOLDER__` with `JSON.stringify(DATA)`, then Write the result to `DIGEST_PATH`.

**3. Open in browser:**

```bash
open "<project_path>/experiments/digest-session-<session_count>.html"
```

**4.** Update the TodoWrite report task label:
```
TodoWrite([{id: "report", content: "📋 Session report + visual digest", status: "completed"}])
```

If the user declines the digest, mark the report task completed as-is and skip this step entirely.
