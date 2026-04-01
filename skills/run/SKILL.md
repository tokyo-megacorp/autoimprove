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
```

---

## 2i. Create Experiment Tasks

Pre-create all experiment tasks so the full session plan is visible and crash-recoverable.

Initialize `PREV_TASK_ID = SETUP_TASK_ID`.

For each experiment slot `i` from 1 to `max_experiments_per_session` (or `--experiments N` override):

1. **Select theme:** Run `theme-weights.sh` (step 3c logic). If `--theme THEME` was passed, use it for all slots. Apply stagnation and cooldown filters — skip slots where no eligible theme exists.
2. **Assign experiment ID:** Next available zero-padded ID from experiments.tsv.
3. **Create the task and chain it to the previous one (setup for exp-001, previous experiment for exp-002+):**

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

---

# 3. Experiment Loop

Read `references/loop.md` and `references/tasktree.md`, then execute the full experiment loop (sections 3a–3o) and session end (section 4). Session state lives in TaskTree + experiments.tsv. The orchestrator manages task lifecycle and delegates individual experiments to Agent subagents. See `references/tasktree.md` for the TaskTree protocol.

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
