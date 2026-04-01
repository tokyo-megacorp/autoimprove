# TaskTree Orchestration Protocol

Reference for the TaskTree-backed experiment loop. Read by the orchestrator during steps 2d-ii, 2f, 2i, and throughout section 3.

---

## Tool API Summary

| Tool | Purpose | Key Parameters |
|------|---------|---------------|
| `TaskCreate` | Create a task | `subject`, `description`, `activeForm?`, `metadata?` |
| `TaskUpdate` | Update a task | `taskId`, `status?`, `owner?`, `metadata?`, `addBlocks?`, `addBlockedBy?` |
| `TaskList` | List all tasks | (none) |
| `TaskGet` | Get task details | `taskId` |

**Status values:** `pending` | `in_progress` | `completed`

---

## Task Lifecycle

```
TaskCreate  -->  pending
                   |
         TaskUpdate(status: in_progress, owner: "orchestrator")
                   |
               in_progress
                   |
         TaskUpdate(status: completed, metadata: {verdict, ...})
                   |
               completed
```

Tasks with `addBlockedBy` remain blocked until all blocking tasks are completed.

---

## Session Task Structure

```
Task: "Autoimprove Session #<N>"          [metadata: {session_id, started_at}]
  |
  +-- Task: "Setup: config + baseline + preflight"  [metadata: {phase: "setup"}]
  |
  +-- Task: "Experiment 001: <theme>"     [blockedBy: setup] [metadata: {exp_id, theme, phase: "experiment"}]
  +-- Task: "Experiment 002: <theme>"     [blockedBy: setup] [metadata: {exp_id, theme, phase: "experiment"}]
  +-- Task: "Experiment 003: <theme>"     [blockedBy: setup] [metadata: {exp_id, theme, phase: "experiment"}]
  |
  +-- Task: "Session Report"              [blockedBy: all experiments] [metadata: {phase: "report"}]
```

---

## Metadata Schemas

### Setup Task

```json
{
  "phase": "setup",
  "baseline_sha": "<HEAD at session start>"
}
```

### Experiment Task (at creation)

```json
{
  "exp_id": "007",
  "theme": "error-handling",
  "phase": "experiment"
}
```

### Experiment Task (after completion)

```json
{
  "exp_id": "007",
  "theme": "error-handling",
  "phase": "experiment",
  "worktree_branch": "autoimprove/007-error-handling",
  "verdict": "keep",
  "tokens": 12450,
  "wall_time_ms": 45000,
  "improved_metrics": ["test_count"],
  "regressed_metrics": [],
  "commit_sha": "abc1234"
}
```

### Experiment Task (skipped)

When an experiment is skipped due to stagnation or drift halt:

```json
{
  "exp_id": "008",
  "theme": "refactoring",
  "phase": "experiment",
  "verdict": "skipped_stagnated"
}
```

or `"verdict": "skipped_drift_halt"`.

### Report Task (after completion)

```json
{
  "phase": "report",
  "total_experiments": 10,
  "keeps": 4,
  "gate_failures": 2,
  "regressions": 1,
  "neutrals": 3,
  "exit_reason": "budget_exhausted"
}
```

---

## Crash Recovery Protocol

On `--resume` or when starting a new session after a crash:

1. **TaskList check:** Call `TaskList()`. Look for tasks with `metadata.phase == "experiment"`.
   - Tasks with status `in_progress`: the agent crashed mid-experiment. Reset to `pending` with `TaskUpdate(status: "pending")`.
   - Tasks with status `pending` and all `blockedBy` completed: ready to run.
   - If no TaskTree exists (fresh session or TaskTree expired): fall through to worktree cleanup.

2. **Worktree cleanup (fallback):** The existing step 2f worktree scan remains as a safety net. It handles cases where the TaskTree is unavailable (e.g., new Claude Code session with no prior TaskTree).

3. **Priority:** TaskTree recovery takes precedence. Only scan worktrees if TaskList returns no experiment tasks.

---

## Parallel Execution Protocol

When `budget.parallel_experiments > 1`:

1. Read `parallel_experiments` from `autoimprove.yaml` (under `budget`). Default: `1`.
2. Cap at `min(parallel_experiments, 5)` per UNBREAKABLE_RULES S3 (max 5 concurrent subagents).
3. From `TaskList()`, collect up to `parallel_limit` pending experiment tasks with empty `blockedBy`.
4. For each, `TaskUpdate(status: "in_progress", owner: "orchestrator")`.
5. Spawn all Agent calls concurrently (each with its own worktree).
6. As results return, process them one-at-a-time for evaluation and verdict:
   - Evaluation MUST be serial (rolling baseline updates on KEEP).
   - `TaskUpdate(status: "completed", metadata: {...})` after each verdict.
   - Update `experiments.tsv` after each verdict.
7. After the batch completes, check for more pending tasks. Repeat until none remain.

**Critical constraint:** Even with parallel spawning, evaluation and merging are always serial. Two KEEPs cannot merge simultaneously -- the second must rebase onto the first.

---

## Constraints

- **Max 5 concurrent subagents** per UNBREAKABLE_RULES S3.
- **experiments.tsv is always updated before marking a task completed.** The TSV is the durable record; the task metadata is supplementary.
- **Experimenter blindness is preserved.** Task descriptions and metadata visible to the experimenter MUST NOT contain metric names, scores, benchmark definitions, or evaluation config. Only: theme name, file constraints, forbidden paths, test policy, recent history summaries, and focus files.
- **TaskTree is ephemeral.** It exists for the duration of a Claude Code session. Cross-session history lives in experiments.tsv and state.json only.
