---
name: run
description: |
  Use when starting, resuming, or running autoimprove sessions. Triggers: 'start autoimprove', 'run the grind loop', 'kick off experiments', 'resume session', '/autoimprove run'.

  <example>
  user: "start an autoimprove session"
  assistant: I'll use the run skill to start the experiment loop.
  <commentary>Starting the grind loop — run skill.</commentary>
  </example>

  <example>
  user: "run autoimprove with the error-handling theme"
  assistant: I'll use the run skill with --theme error-handling.
  <commentary>Themed run — run skill.</commentary>
  </example>

  <example>
  user: "resume the autoimprove session"
  assistant: I'll use the run skill with --resume to recover from the interruption.
  <commentary>Crash recovery — run --resume.</commentary>
  </example>

  Do NOT use to review results → report. Do NOT inspect state → status. Do NOT browse history → history. Do NOT revert → rollback.
argument-hint: "[--experiments N] [--theme THEME] [--resume] [--phase propose]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, TaskCreate, TaskUpdate, TaskList, TaskGet]
---

Run the autoimprove experiment loop: read config, manage state, spawn experimenter agents into worktrees, evaluate their changes deterministically, and keep or discard based on the verdict.

If `--experiments N` was passed, use N as `max_experiments_per_session`. If `--theme THEME` was passed, only run experiments for that theme.

---

Initialize progress tracking at the start of the session:

```
TodoWrite([
  {id: "prereqs",   content: "✅ Prerequisites check",          status: "pending"},
  {id: "config",    content: "📋 Read config + build eval JSON", status: "pending"},
  {id: "baseline",  content: "📊 Capture baseline metrics",      status: "pending"},
  {id: "state",     content: "🔄 Load state + session TaskTree", status: "pending"},
  {id: "harvest",   content: "🔍 Harvest signals",               status: "pending"},
  {id: "preflight", content: "✅ Preflight: validate benchmarks", status: "pending"},
  {id: "tasks",     content: "🎯 Pre-create experiment tasks",   status: "pending"},
  {id: "loop",      content: "⚗️ Experiment loop",               status: "pending"},
  {id: "report",    content: "📋 Session report",                status: "pending"}
])
```

---

# 1. Prerequisites Check

Verify the environment before anything else:

```bash
test -f autoimprove.yaml || { echo "FATAL: autoimprove.yaml not found in project root"; exit 1; }
test -f scripts/evaluate.sh || { echo "FATAL: scripts/evaluate.sh not found"; exit 1; }
test -f scripts/theme-weights.sh || { echo "FATAL: scripts/theme-weights.sh not found"; exit 1; }
command -v jq >/dev/null || { echo "FATAL: jq is required but not installed"; exit 1; }
command -v python3 >/dev/null || { echo "FATAL: python3 is required for theme-weights.sh"; exit 1; }
chmod +x scripts/evaluate.sh scripts/theme-weights.sh
PROJECT_ROOT=$(pwd)   # capture now — used when calling evaluate.sh from inside worktrees
```

If any check fails, stop immediately and tell the user what's missing.

```
TodoWrite([{id: "prereqs", content: "✅ Prerequisites check", status: "completed"}])
```

---

# 2. Session Start

## 2a. Read Config

Read `autoimprove.yaml` and parse it. Required sections:
- `project` — name, path
- `budget` — `max_experiments_per_session`, `experimenter_model` (default: `"sonnet"`)
- `gates` — array of `{name, command}`
- `benchmarks` — array of `{name, command, metrics: [{name, extract, direction, tolerance?, significance?}]}`
- `themes` — strategy, priorities (theme→weight map), `cooldown_per_theme`
- `constraints` — `trust_ratchet` (tier definitions), `forbidden_paths`, `test_modification`
- `safety` — `epoch_drift_threshold`, `coverage_gate`, `regression_tolerance`, `significance_threshold`, `stagnation_window`

## 2b. Generate evaluate-config.json

Convert the YAML config into the JSON format that `evaluate.sh` expects. Write to `experiments/evaluate-config.json`.

```json
{
  "gates": [{ "name": "tests", "command": "npm test" }],
  "benchmarks": [{
    "name": "project-metrics",
    "command": "bash benchmark/metrics.sh",
    "metrics": [{
      "name": "test_count",
      "extract": "json:.test_count",
      "direction": "higher_is_better",
      "tolerance": 0.02,
      "significance": 0.01
    }]
  }],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
```

Mapping rules:
- `gates` and `benchmarks` come directly from `autoimprove.yaml`.
- Per-metric `tolerance` and `significance` override global `safety` defaults.
- `coverage_gate`: if present in `safety`, include with `command`, `threshold`, and `changed_files: []`. Otherwise omit.
- `regression_tolerance` from `safety.regression_tolerance` (default 0.02).
- `significance_threshold` from `safety.significance_threshold` (default 0.01).

```bash
mkdir -p experiments
```
Then write `experiments/evaluate-config.json`.

```
TodoWrite([{id: "config", content: "📋 Read config + build eval JSON", status: "completed"}])
```

## 2c. Capture Baseline

```bash
cd <project_path>
bash scripts/evaluate.sh experiments/evaluate-config.json /dev/null
```

Output: `{mode: "init", gates: [...], metrics: {...}}`.

Parse it. If any gate failed, stop — the project must be in a passing state before autoimprove can run.

Save metrics as both baselines (format: `{metrics: {...}, sha: "<HEAD>", timestamp: "<ISO>"}`):
- `experiments/epoch-baseline.json` — frozen for the session, never updated
- `experiments/rolling-baseline.json` — updated after each KEEP

```
TodoWrite([{id: "baseline", content: "📊 Capture baseline metrics", status: "completed"}])
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

Increment `session_count`, set `last_session` to current ISO timestamp. Decrement all `theme_cooldowns` by 1; remove any that reach 0 or below.

## 2d-ii. Create Session TaskTree

Create the parent task for visual progress tracking:

```
TaskCreate(
  subject: "Autoimprove Session #<session_count>",
  description: "Automated experiment session",
  metadata: {session_id: <session_count>, started_at: "<ISO>"}
)
→ store returned task ID as SESSION_TASK_ID
```

Create the setup task and mark it in-progress immediately:

```
TaskCreate(
  subject: "Setup: config + baseline + preflight",
  description: "Load config, capture baseline, validate benchmarks",
  activeForm: "Setting up session",
  metadata: {phase: "setup"}
)
→ store returned task ID as SETUP_TASK_ID

TaskUpdate(taskId: SETUP_TASK_ID, status: "in_progress")
```

The setup task covers steps 2a through 2h. Mark it completed after preflight (2h) succeeds.

```
TodoWrite([{id: "state", content: "🔄 Load state + session TaskTree", status: "completed"}])
```

## 2e. Load Experiment Log

Read `experiments/experiments.tsv`. If missing, create with header:

```
id	timestamp	theme	verdict	improved_metrics	regressed_metrics	tokens	wall_time	commit_msg
```

Determine the next experiment ID by counting data rows (zero-padded to 3 digits: `001`, `002`, …).

## 2f. Crash Recovery

### 2f-i. TaskTree Recovery (preferred)

If `--resume` was passed, check for incomplete experiment tasks from a prior session:

```
TaskList() → look for tasks with metadata.phase == "experiment"
```

- Tasks with status `in_progress`: agent crashed mid-experiment. Reset: `TaskUpdate(taskId, status: "pending")`.
- Tasks with status `pending` and all `blockedBy` completed: ready to run — leave as-is.
- If TaskList returns no experiment tasks: no prior session to recover — fall through to worktree cleanup.

### 2f-ii. Worktree Cleanup (fallback)

```bash
git worktree list --porcelain
```

Filter for worktrees whose path contains `autoimprove/`. For each orphan (no verdict in experiments.tsv):
1. `git worktree remove --force <path>`
2. `git branch -D <branch_name>`
3. If an incomplete experiments.tsv entry exists, set its verdict to `crash`.

---

# 2g. Step 0 — Harvest Signals (automatic)

Before entering the experiment loop, run the signal harvester to check for anomalies:

```bash
HARVEST_OUTPUT=$(mktemp)
bash scripts/harvest.sh \
  --signal-dir ~/.claude/signals \
  --baseline experiments/signals-baseline.json \
  --output "$HARVEST_OUTPUT"
```

**Theme override logic:**
- If harvest output contains anomalies with severity `high` or `critical`:
  → Use the `suggested_theme` from the highest-severity anomaly (overrides random selection)
- If only `medium` anomalies or no anomalies:
  → Fall back to normal weighted-random theme selection
- If harvest fails (non-zero exit, missing baseline):
  → Proceed with random theme selection (harvester never blocks the loop)

Read the harvest output:
```bash
HIGH_THEME=$(jq -r '.anomalies[] | select(.severity == "critical" or .severity == "high") | .suggested_theme' "$HARVEST_OUTPUT" 2>/dev/null | head -1)
if [ -n "$HIGH_THEME" ]; then
  echo "Anomaly-driven theme: $HIGH_THEME"
  THEME="$HIGH_THEME"
fi
```

```
TodoWrite([{id: "harvest", content: "🔍 Harvest signals", status: "completed"}])
```

---

## 2h. Pre-flight: Validate benchmarks

Before entering the experiment loop, verify all benchmarks produce the expected metrics:

1. Run each benchmark command from `autoimprove.yaml`
2. Verify ALL expected metric names appear in the output
3. If any metric is missing: **STOP** and fix the benchmark before running experiments
4. Log: `[PREFLIGHT: N/N metrics validated]` (e.g. `[PREFLIGHT: 3/3 metrics validated]`)

A benchmark that silently fails (exits 0 but omits metrics) will produce misleading verdicts. Validate now, not after experiments run.

Mark setup complete:

```
TaskUpdate(taskId: SETUP_TASK_ID, status: "completed", metadata: {baseline_sha: "<HEAD>"})
TodoWrite([{id: "preflight", content: "✅ Preflight: validate benchmarks", status: "completed"}])
```

---

## 2i. Create Experiment Tasks

Pre-create all experiment tasks so the full session plan is visible and crash-recoverable.

Initialize `PREV_TASK_ID = SETUP_TASK_ID`.

**Goal slot injection (B+C model):**

Before filling experiment slots with auto-selected themes, inject goal slots:

1. Read `experiments/state.json goals[]`. Filter goals where `status == "active"`.
   - If a goal has `needs_validation: true`, re-run the configured benchmark commands from `autoimprove.yaml`.
   - If the goal's `target_metric` appears in the benchmark output, clear `needs_validation`.
   - If the key is still missing, mark the goal `status: "stale"`, warn the user, and skip it for this session.
2. Compute `floor_slots`: read `autoimprove.yaml goals.floor_slots` (default: 2). Cap at `min(floor_slots, active_goal_count, max_experiments_per_session)`.
3. For each floor slot, pick the next active goal in round-robin order with higher `priority_weight` goals first. Create a goal experiment task:

```
TaskCreate(
  subject: "Experiment <id>: [goal] <target_metric> → <target_delta>",
  description: "Goal experiment. target_metric: <target_metric>, target_delta: <target_delta>.",
  activeForm: "Running goal experiment <id>",
  metadata: {
    exp_id: "<id>",
    theme: "user_goal",
    goal_name: "<name>",
    target_metric: "<target_metric>",
    target_delta: "<target_delta>",
    phase: "experiment"
  }
)
```

4. Remaining slots (`max_experiments_per_session - floor_slots`) fall back to normal theme selection, but inject active goals into the weighted pool with `priority_weight × 3` weight on top of the existing `theme-weights.sh` scores.
5. Persist any goal validation updates (`needs_validation` cleared, `status: "stale"`) back to `experiments/state.json` before entering the loop so crash recovery and later skills see the same state.

After floor-slot tasks are created, fill the remaining experiment slots until the session budget is exhausted:

1. **Select next slot target:** If `--theme THEME` was passed, use it for every non-goal slot. Otherwise run `theme-weights.sh` (step 3c logic), merge the active goals into that pool with their `priority_weight × 3` boost, then apply stagnation and cooldown filters to theme entries only. Goal entries remain eligible unless their own `status` changed away from `active`. Skip slots where no eligible theme or goal remains.
2. **Assign experiment ID:** Next available zero-padded ID from experiments.tsv.
3. **Create the task and chain it to the previous one (setup for exp-001, previous experiment for exp-002+):**

   - If the selected pool entry is a goal, use the goal-task shape from the floor-slot example (`theme: "user_goal"` plus `goal_name`, `target_metric`, and `target_delta` metadata). Weighted-pool goal picks use the same task shape as guaranteed floor slots so later loop steps can detect achievements consistently.
   - Otherwise create the standard theme task:

```
TaskCreate(
  subject: "Experiment <id>: <theme>",
  description: "Theme: <theme>. Constraints: max_files=<N>, max_lines=<N>.",
  activeForm: "Running experiment <id>",
  metadata: {exp_id: "<id>", theme: "<theme>", phase: "experiment"}
)
→ store returned task ID as <exp_task_id>

TaskUpdate(taskId: <exp_task_id>, addBlockedBy: [PREV_TASK_ID])
PREV_TASK_ID = <exp_task_id>
```

4. **Collect** all experiment task IDs into `EXPERIMENT_TASK_IDS` array.

After all experiment tasks are created, create the report task blocked on the **last** experiment only (which transitively depends on all prior experiments):

```
TaskCreate(
  subject: "Session Report",
  description: "Generate session summary after all experiments complete",
  activeForm: "Generating session report",
  metadata: {phase: "report"}
)
→ store returned task ID as REPORT_TASK_ID

TaskUpdate(taskId: REPORT_TASK_ID, addBlockedBy: [PREV_TASK_ID])
```

If zero experiment tasks were created (all themes stagnated/on cooldown), skip directly to Session End.

```
TodoWrite([
  {id: "tasks", content: "🎯 Pre-create experiment tasks", status: "completed"},
  {id: "loop",  content: "⚗️ Experiment loop",             status: "in_progress"}
])
```

---

## 2j. Dynamic Parallel Scaling

Before spawning any experiment agents, determine how many grind loops may run in parallel.

Read `budget.max_parallel` from `autoimprove.yaml` (default: 1 if absent). This is the **user-configured ceiling**.

Then attempt dynamic scaling from the weekly token budget:

```bash
BUDGET_FILE="$HOME/.xgh/budget.yaml"
SNAPSHOT_LOG="$HOME/.xgh/budget-snapshots.log"
CONFIG_MAX_PARALLEL=<budget.max_parallel from autoimprove.yaml>   # e.g. 1

if [ ! -f "$BUDGET_FILE" ]; then
  # No budget data — use config value, no dynamic scaling
  MAX_PARALLEL=$CONFIG_MAX_PARALLEL
  echo "[grind] budget.yaml not found — using config max_parallel=$MAX_PARALLEL (no dynamic scaling)"
else
  # Read current snapshot
  PCT_USED=$(grep 'pct_used:' "$BUDGET_FILE" | awk '{print $2}')
  PCT_REMAINING=$(echo "100 - $PCT_USED" | bc)

  # Compute burn rate if snapshot log exists and has >= 2 entries
  BURN_RATE=""
  if [ -f "$SNAPSHOT_LOG" ] && [ "$(wc -l < "$SNAPSHOT_LOG")" -ge 2 ]; then
    # Log format: "<ISO_TIMESTAMP> <pct_used>" — one entry per line
    FIRST_LINE=$(head -1 "$SNAPSHOT_LOG")
    FIRST_TS=$(echo "$FIRST_LINE" | awk '{print $1}')
    FIRST_PCT=$(echo "$FIRST_LINE" | awk '{print $2}')
    NOW_TS=$(date -u +%s)
    FIRST_EPOCH=$(date -u -d "$FIRST_TS" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$FIRST_TS" +%s 2>/dev/null)
    HOURS_ELAPSED=$(echo "scale=2; ($NOW_TS - $FIRST_EPOCH) / 3600" | bc)
    if [ "$(echo "$HOURS_ELAPSED > 0" | bc)" -eq 1 ]; then
      # burn_rate = pct consumed since first snapshot / hours elapsed
      PCT_CONSUMED=$(echo "scale=2; $PCT_USED - $FIRST_PCT" | bc)
      BURN_RATE=$(echo "scale=2; $PCT_CONSUMED / $HOURS_ELAPSED" | bc)
    fi
  fi

  # Apply scaling table
  # | PCT_REMAINING | BURN_RATE     | PARALLEL |
  # |---------------|---------------|----------|
  # | >60           | any           | 5        |
  # | 40-60         | low (<2/h)    | 3        |
  # | 40-60         | high (>=2/h)  | 2        |
  # | 20-40         | any           | 1        |
  # | <20           | any           | 0 (halt) |
  if [ "$(echo "$PCT_REMAINING > 60" | bc)" -eq 1 ]; then
    DYNAMIC_MAX=5
  elif [ "$(echo "$PCT_REMAINING >= 40" | bc)" -eq 1 ]; then
    if [ -n "$BURN_RATE" ] && [ "$(echo "$BURN_RATE >= 2" | bc)" -eq 1 ]; then
      DYNAMIC_MAX=2
    else
      DYNAMIC_MAX=3
    fi
  elif [ "$(echo "$PCT_REMAINING >= 20" | bc)" -eq 1 ]; then
    DYNAMIC_MAX=1
  else
    DYNAMIC_MAX=0
  fi

  # Take the minimum of dynamic ceiling and user config
  if [ "$DYNAMIC_MAX" -lt "$CONFIG_MAX_PARALLEL" ]; then
    MAX_PARALLEL=$DYNAMIC_MAX
  else
    MAX_PARALLEL=$CONFIG_MAX_PARALLEL
  fi

  BURN_DISPLAY=${BURN_RATE:-"unknown"}
  echo "[grind] budget ${PCT_REMAINING}% remaining, burn ${BURN_DISPLAY}/h → max ${MAX_PARALLEL} parallel"

  if [ "$MAX_PARALLEL" -eq 0 ]; then
    echo "[grind] HALT: weekly budget < 20% remaining. Hotfix mode only — stopping grind loop."
    # Skip to Session End
  fi
fi
```

If `MAX_PARALLEL` is 0, stop the grind loop immediately and skip to Session End (step 4). Log the halt reason in `experiments/state.json` under `"last_halt_reason": "budget_exhausted"`.

The `MAX_PARALLEL` value is the upper bound on concurrent experimenter agents for this session. Pass it to the experiment loop (section 3) so the loop respects it when spawning agents.

> **Hard ceiling:** `MAX_PARALLEL` must never exceed 5 (§3 of UNBREAKABLE_RULES — max 5 concurrent subagents per agent). The scaling table already respects this; if `budget.max_parallel` is set higher than 5, clamp it to 5.

---

# 3. Experiment Loop

Read `references/loop.md` and `references/tasktree.md`, then execute the full experiment loop (sections 3a–3o) and session end (section 4). Session state lives in TaskTree + experiments.tsv. The orchestrator manages task lifecycle and delegates individual experiments to Agent subagents. See `references/tasktree.md` for the TaskTree protocol.

After the loop completes and the session report is generated, update todos with final counts:

```
TodoWrite([
  {id: "loop",   content: "⚗️ Experiment loop — <K> kept, <D> discarded", status: "completed"},
  {id: "report", content: "📋 Session report",                             status: "completed"}
])
```

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  {id: "prereqs", status: "completed"},
  {id: "config", status: "completed"},
  {id: "baseline", status: "completed"},
  {id: "state", status: "completed"},
  {id: "harvest", status: "completed"},
  {id: "preflight", status: "completed"},
  {id: "tasks", status: "completed"},
  {id: "loop", status: "completed"},
  {id: "report", status: "completed"}
])
```

---

# Key Invariants

These must hold throughout execution. If any is violated, halt and report.

1. **Experimenter is blind.** Never include metric names, benchmark definitions, scoring logic, tolerance/significance, current scores, or evaluate-config.json in the experimenter prompt.
2. **evaluate.sh is the single evaluator.** All verdict computation happens inside it. Only read the JSON output.
3. **Epoch baseline is frozen.** Never modify `experiments/epoch-baseline.json` after creation.
4. **Rolling baseline updates only on KEEP.**
5. **All worktrees are always cleaned up.** Every code path must remove the worktree and its branch.
6. **Rebase failure = discard.** Never force-merge or create merge commits.
7. **State is persisted after every experiment.** Crash recovery depends on it.
8. **Test modification is additive only.** Always include this constraint in the experimenter prompt.
9. **TaskTree is orchestration, experiments.tsv is history.** TaskTree tracks live status during a session. experiments.tsv is the durable, append-only record. Both are updated, but experiments.tsv is the source of truth for cross-session analysis.

## Additional Resources

- **`references/loop.md`** — Full experiment loop (steps 3a–3o) and session end (steps 4a–4c)
- **`references/tasktree.md`** — TaskTree orchestration protocol: task lifecycle, metadata schemas, crash recovery, parallel execution
- **`scripts/theme-weights.sh`** — Computes adjusted theme weights from `experiments.tsv` history. Called at theme selection (step 2i). Themes with higher keep rates get boosted weight; themes with no keeps get penalised (min 0.25× base). Experimenter never sees weights.

---

# When NOT to Use

- **Reviewing pending proposals** — use `/autoimprove proposals list` to inspect and approve Phase 2 proposals before they run.
- **Browsing past experiments** — use `/autoimprove history` for filtered log views.
- **Running tests in isolation** — use `/autoimprove test` to verify suites without launching the grind loop.
- **One-off manual code improvement** — this skill drives automated, scored experiments. For a single targeted fix, edit files directly.

---

# Common Failure Patterns

**Baseline fails a gate**

If `evaluate.sh` in init mode reports a gate failure, `run` will stop before the first experiment. Fix the underlying test/lint failure first. Run `/autoimprove test` to locate the issue.

**Stale worktrees from a crashed session**

Step 2f handles crash recovery automatically. First, TaskTree recovery (2f-i) checks for incomplete experiment tasks and resets them to pending. Then, worktree cleanup (2f-ii) removes orphaned worktrees. Re-running `run --resume` will recover from both. Do not manually delete worktrees with `git worktree remove` — let the skill do it so the TSV is updated correctly.

**Experiment loop runs 0 experiments**

Causes: all themes are on cooldown, `max_experiments_per_session` is 0, or `--theme THEME` was passed for a theme on cooldown. Check `experiments/state.json` for `theme_cooldowns`. Reduce `cooldown_per_theme` in `autoimprove.yaml` or run without `--theme` to use weighted-random selection.

**Rebase conflict on KEEP**

If the experimenter's branch can't rebase cleanly onto `main`, the experiment is discarded (invariant 6). This is expected when concurrent changes landed. The next experiment gets a fresh worktree from the updated base.

---

# Integration Notes

- **Full pipeline order**: `/autoimprove init` → `/autoimprove test` → `/autoimprove run` → `/autoimprove report`.
- **Phase 2 (proposals)**: when the keep rate drops below 25% for 3 consecutive sessions, `run` triggers the proposer agent. Review the output with `/autoimprove proposals` before the next `run` session picks them up.
- **evaluate-config.json is regenerated every session** (step 2b) — changes to `autoimprove.yaml` take effect immediately on the next `run` call.
- **Token budget**: each experiment spawns an Agent; for N experiments, expect roughly N × (experimenter tokens + evaluate.sh overhead). Start with `--experiments 3` on a new project to calibrate cost before raising the budget.
