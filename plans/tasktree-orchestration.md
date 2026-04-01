# Plan: TaskTree Orchestration for autoimprove run loop

**Issue:** ipedro/autoimprove#71
**Date:** 2026-04-01
**Status:** DRAFT -- awaiting Co-CEO approval

---

## Objective

Replace the linear, invisible experiment loop with TaskTree-backed orchestration. Each experiment becomes a visible, trackable task with structured metadata. Crash recovery shifts from worktree scanning to TaskList status inspection. Optionally, experiments can run in parallel via Agent subagents.

---

## Files to Modify

### 1. `skills/run/SKILL.md`

**What changes:**

- **Line 26 (`allowed-tools`):** Add `TaskCreate, TaskUpdate, TaskList, TaskGet` to the list.

  ```
  # Before
  allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent]
  # After
  allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, TaskCreate, TaskUpdate, TaskList, TaskGet]
  ```

- **Line 202 (the "do not delegate" constraint):** Replace with TaskTree + delegation instruction.

  ```
  # Before (line 202)
  Read `references/loop.md` and execute the full experiment loop (sections 3a-3m) and session end (section 4). Maintain all session state (counters, config, baselines) in this same context throughout -- do not delegate to a subagent.

  # After
  Read `references/loop.md` and execute the full experiment loop (sections 3a-3m) and session end (section 4). Session state lives in TaskTree + experiments.tsv. The orchestrator manages task lifecycle and delegates individual experiments to Agent subagents. See references/tasktree.md for the TaskTree protocol.
  ```

- **Section 2d (Load or Create State):** After loading state.json, add a step:

  ```
  ## 2d-ii. Create Session TaskTree

  Create the parent task for this session:
  TaskCreate(subject: "Autoimprove Session #<session_count>", description: "...", metadata: {session_id: <session_count>, started_at: <ISO>})
  Store returned task ID as SESSION_TASK_ID.

  Create the setup task:
  TaskCreate(subject: "Setup: config + baseline + preflight", description: "...", metadata: {phase: "setup"})
  TaskUpdate(taskId: <setup_task_id>, addBlockedBy: []) -- no blockers, runs immediately
  TaskUpdate(taskId: <setup_task_id>, status: "in_progress")
  ```

- **Section 2h (after preflight completes):** Mark setup task completed:

  ```
  TaskUpdate(taskId: <setup_task_id>, status: "completed")
  ```

- **New section 2i: Create Experiment Tasks (between preflight and loop):**

  ```
  ## 2i. Create Experiment Tasks

  For each experiment slot (1..max_experiments_per_session):
    1. Select theme (3c logic -- weighted random or --theme override)
    2. TaskCreate(
         subject: "Experiment <id>: <theme>",
         description: "<constraints, forbidden paths, test policy>",
         metadata: {exp_id: "<id>", theme: "<theme>", phase: "experiment"}
       )
    3. TaskUpdate(taskId: <exp_task_id>, addBlockedBy: [<setup_task_id>])
    4. Store exp_task_id in EXPERIMENT_TASK_IDS array

  Create report task:
    TaskCreate(subject: "Session Report", description: "...", metadata: {phase: "report"})
    TaskUpdate(taskId: <report_task_id>, addBlockedBy: EXPERIMENT_TASK_IDS)
  ```

  **IMPORTANT CHANGE:** Theme selection moves UP from inside the loop to this pre-loop planning phase. This is necessary because TaskTree needs all experiment tasks created upfront so dependencies are correct. The stagnation check (3b) and budget check (3a) still apply -- if all themes are stagnated, fewer tasks get created. If a theme becomes stagnated mid-session, remaining experiments for that theme are marked `completed` with metadata `{verdict: "skipped_stagnated"}`.

- **Section 2f (Crash Recovery):** Add TaskTree-based recovery path:

  ```
  ## 2f. Crash Recovery

  ### 2f-i. TaskTree Recovery (preferred)
  TaskList() -- check for incomplete session tasks.
  If any tasks have status "in_progress" or "pending" with metadata.phase == "experiment":
    - For "in_progress" tasks: the agent crashed mid-experiment.
      Reset to "pending" so they re-enter the queue.
    - For "pending" tasks with blockedBy all completed: ready to run.

  ### 2f-ii. Worktree Cleanup (unchanged)
  [existing worktree cleanup logic remains as fallback]
  ```

- **Key Invariants section:** Add new invariant:

  ```
  9. **TaskTree is orchestration, experiments.tsv is history.** TaskTree tracks live status during a session. experiments.tsv is the durable, append-only record. Both are updated, but experiments.tsv is the source of truth for cross-session analysis.
  ```

### 2. `skills/run/references/loop.md`

**What changes:**

- **Section 3 preamble:** Add instruction to read tasktree.md for the task-driven loop protocol.

- **Section 3a (Budget Check):** Change from counter-based to task-based:

  ```
  # Before
  if experiment_count >= budget.max_experiments_per_session -> go to Session End

  # After
  TaskList() -- count completed + in_progress experiment tasks.
  If all experiment tasks are completed or skipped -> go to Session End
  ```

- **Section 3b (Stagnation Check):** Now operates on remaining pending tasks. If a pending task's theme is newly stagnated, mark it completed with `{verdict: "skipped_stagnated"}`.

- **Section 3c (Theme Selection):** Simplified -- theme was already selected during task creation (2i). The task's metadata.theme is used. Skip if on cooldown or stagnated (mark completed + skip).

- **Section 3g (Spawn Experimenter):** Modified to be task-driven:

  ```
  # Before: linear spawn
  Agent(prompt: "...", agent: "experimenter", isolation: "worktree", model: "sonnet")

  # After: claim task, then spawn
  next_task = first pending experiment task from TaskList() with empty blockedBy
  TaskUpdate(taskId: next_task.id, status: "in_progress", owner: "orchestrator")

  parallel_limit = budget.parallel_experiments or 1  # default serial
  parallel_limit = min(parallel_limit, 5)            # enforce S3 max 5

  If parallel_limit == 1:
    Agent(prompt: "...", agent: "experimenter", isolation: "worktree", model: "sonnet")
  Else:
    Spawn up to parallel_limit Agent calls concurrently for pending experiment tasks.
    Each agent gets its own worktree. Collect results as they return.
  ```

- **Section 3h-3k (Collect/Evaluate/Verdict/Log):** After each experiment completes:

  ```
  TaskUpdate(taskId: <exp_task_id>, status: "completed", metadata: {
    exp_id: "<id>",
    theme: "<theme>",
    verdict: "<keep|gate_fail|regress|neutral>",
    tokens: <N>,
    wall_time_ms: <N>,
    improved_metrics: [...],
    regressed_metrics: [...],
    commit_sha: "<sha or null>",
    worktree_branch: "autoimprove/<id>-<theme>"
  })
  ```

  Then update experiments.tsv as before (unchanged format).

- **Section 3l (Epoch Drift):** Unchanged logic. If drift halt triggered, mark all remaining pending experiment tasks as completed with `{verdict: "skipped_drift_halt"}`.

- **Section 3n (Increment and Continue):** Change from counter increment to:

  ```
  Go to 3a (TaskList will show next pending task)
  ```

- **Section 4c (Print Summary):** After printing summary, mark report task completed:

  ```
  TaskUpdate(taskId: <report_task_id>, status: "completed", metadata: {
    total_experiments: <N>,
    keeps: <N>,
    gate_failures: <N>,
    regressions: <N>,
    neutrals: <N>,
    exit_reason: "<reason>"
  })
  ```

### 3. `skills/run/references/tasktree.md` (NEW FILE)

**Purpose:** Dedicated reference for the TaskTree protocol, kept separate from loop.md to avoid bloating the main loop reference. Contains:

- TaskTree tool API summary (create, update, list, get)
- Task lifecycle diagram (pending -> in_progress -> completed)
- Metadata schema for each task phase (setup, experiment, report)
- Crash recovery protocol (TaskList-based)
- Parallel execution protocol (when parallel_experiments > 1)
- Constraints: max 5 concurrent agents (S3), experiments.tsv is always updated before task metadata

### 4. `autoimprove.yaml`

**What changes:** Add optional `parallel_experiments` key under `budget`:

```yaml
budget:
  max_experiments_per_session: 10
  parallel_experiments: 1  # optional, default 1 (serial). Max 5 per S3.
```

No other config changes. The key is optional and defaults to 1 (serial execution, identical to current behavior).

---

## What Stays the Same (backwards compat guarantees)

| Component | Guarantee |
|-----------|-----------|
| `experiments.tsv` | Format unchanged. Append-only. Remains source of truth for history. |
| `experiments/<id>/context.json` | Format unchanged. Still written per experiment. |
| `experiments/state.json` | Format unchanged. Still persisted after every experiment. |
| `experiments/epoch-baseline.json` | Frozen per session, never modified. |
| `experiments/rolling-baseline.json` | Updated on KEEP only. |
| `evaluate.sh` | Contract unchanged. No modifications. |
| `scripts/theme-weights.sh` | Contract unchanged. Still called for weight computation. |
| `scripts/harvest.sh` | Contract unchanged. |
| `scripts/harvest-themes.sh` | Contract unchanged. |
| `--experiments N` flag | Still respected -- creates N experiment tasks. |
| `--theme THEME` flag | Still works -- all N tasks get that theme. |
| `--resume` flag | Enhanced -- now checks TaskList first, then falls back to worktree scan. |
| Key Invariants 1-8 | All preserved. Invariant 9 added (TaskTree vs TSV roles). |
| Experimenter blindness | Fully preserved. No metric data in task descriptions. |

---

## Design Decisions

### D1: Pre-create all experiment tasks vs create on-the-fly

**Decision:** Pre-create all experiment tasks in step 2i.

**Why:** Enables the report task to have correct `blockedBy` from the start. Enables parallel dispatch (the orchestrator can see the full queue). Enables crash recovery (all planned work is visible even if the orchestrator crashes mid-session).

**Trade-off:** Theme selection happens earlier (before experiments run). This means stagnation detected mid-session can't prevent already-created tasks from existing. Mitigation: mid-session stagnated tasks are marked `completed` with `verdict: "skipped_stagnated"` instead of running.

### D2: TaskTree is orchestration, TSV is history

**Decision:** TaskTree is ephemeral per-session orchestration. experiments.tsv is durable history.

**Why:** TaskTree does not persist across sessions (it's tied to the Claude Code session). experiments.tsv and state.json persist across sessions on disk. Both are updated, but the TSV is what matters for cross-session analysis (theme-weights, stagnation, reports).

### D3: Serial by default, parallel opt-in

**Decision:** `parallel_experiments` defaults to 1 (serial).

**Why:** Parallel execution changes the token budget profile significantly. Serial is the safe default. Users opt into parallel after understanding the cost implications.

### D4: Agent (subagent) not TeamCreate

**Decision:** Use `Agent()` tool for experiment delegation, not `TeamCreate`.

**Why:** Agent subagents run within the same session context. TeamCreate spawns separate sessions that can't easily share worktree state. The experimenter needs isolation (worktree) but not a separate session. Also, per Pedro's feedback, TeamCreate always spawns in `~/.claude` and the pre-edit-repo-guard blocks Dev repo writes.

### D5: No new scripts

**Decision:** All TaskTree operations happen in the skill's instruction flow (SKILL.md + loop.md). No new bash scripts.

**Why:** TaskTree tools are Claude Code built-in tools, not CLI commands. They can only be invoked by the agent, not by shell scripts. The orchestration logic belongs in the skill instructions.

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| TaskTree tools not available in the model's toolset | Low | High (plan unworkable) | Verify tools exist in allowed-tools before merge. Fallback: the loop still works without TaskTree if tools are missing (existing linear flow). |
| Pre-created tasks become stale (e.g., baseline changes mid-session from a KEEP) | Medium | Low | The worktree is always created from current HEAD. The task metadata is just a label. The actual experiment always runs against latest main. |
| Parallel experiments cause rebase conflicts | Medium | Low | Already handled: rebase failure = discard (invariant 6). With parallel experiments, more conflicts expected. Each KEEP rebases and fast-forwards, so the next experiment starts from updated main. |
| Token overhead from TaskTree tool calls | Low | Low | ~6 tool calls per experiment (create, update to in_progress, update to completed). Negligible vs the Agent spawn cost. |
| Crash mid-session with partial TaskTree state | Medium | Low | Recovery protocol: TaskList -> reset in_progress to pending -> resume. Plus existing worktree cleanup as fallback. |
| Stagnation/cooldown logic mismatch with pre-created tasks | Medium | Medium | Explicit handling: tasks for stagnated themes are marked completed+skipped. Theme weights are computed at task creation time. |

---

## Implementation Order

1. Write `skills/run/references/tasktree.md` (new reference file)
2. Modify `skills/run/SKILL.md` (add tools, replace constraint, add 2d-ii and 2i sections, update 2f)
3. Modify `skills/run/references/loop.md` (task-driven loop changes)
4. Modify `autoimprove.yaml` (add optional parallel_experiments key)
5. Manual testing with `--experiments 1` to validate single-experiment TaskTree flow

---

## Scope Boundaries

**In scope:**
- TaskTree creation and lifecycle management
- Experiment metadata on tasks
- Crash recovery via TaskList
- Optional parallel_experiments config key
- All skill instruction changes

**Out of scope (separate issues):**
- Teammate-based experimenters (TeamCreate instead of Agent) -- requires resolving CWD issues first
- Task-based reporting (reading TaskTree for report generation) -- separate skill
- Persistent cross-session task history (TaskTree is ephemeral) -- experiments.tsv handles this
- UI/visualization of task progress -- Claude Code's built-in task list handles this
