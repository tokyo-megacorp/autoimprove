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

Experiments run **sequentially** — each experiment blocks the next. Only one experiment is ever in_progress at a time.

```
Task: "Autoimprove Session #<N>"          [metadata: {session_id, started_at}]
  |
  +-- Task: "Setup: config + baseline + preflight"  [metadata: {phase: "setup"}]
  |
  +-- Task: "Experiment 001: <theme>"     [blockedBy: setup]      [metadata: {exp_id, theme, phase: "experiment"}]
  +-- Task: "Experiment 002: <theme>"     [blockedBy: exp-001]    [metadata: {exp_id, theme, phase: "experiment"}]
  +-- Task: "Experiment 003: <theme>"     [blockedBy: exp-002]    [metadata: {exp_id, theme, phase: "experiment"}]
  |
  +-- Task: "Session Report"              [blockedBy: exp-N]      [metadata: {phase: "report"}]
```

The report task blocks on the **last** experiment task only (which transitively depends on all prior experiments).

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
   - Tasks with status `pending` where **all** `blockedBy` tasks are `completed`: ready to run (at most one at a time — sequential chain).
   - If no TaskTree exists (fresh session or TaskTree expired): fall through to worktree cleanup.

2. **Worktree cleanup (fallback):** The existing step 2f worktree scan remains as a safety net. It handles cases where the TaskTree is unavailable (e.g., new Claude Code session with no prior TaskTree).

3. **Priority:** TaskTree recovery takes precedence. Only scan worktrees if TaskList returns no experiment tasks.

---

## Constraints

- **Serial execution only.** The sequential chain enforces one experiment in_progress at a time. Never dispatch multiple experiments concurrently.
- **experiments.tsv is always updated before marking a task completed.** The TSV is the durable record; the task metadata is supplementary.
- **Experimenter blindness is preserved.** Task descriptions and metadata visible to the experimenter MUST NOT contain metric names, scores, benchmark definitions, or evaluation config. Only: theme name, file constraints, forbidden paths, test policy, recent history summaries, and focus files.
- **TaskTree is ephemeral.** It exists for the duration of a Claude Code session. Cross-session history lives in experiments.tsv and state.json only.
