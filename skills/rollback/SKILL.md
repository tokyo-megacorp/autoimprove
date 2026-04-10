---
name: rollback
description: "Use when reverting a kept autoimprove experiment that caused downstream problems. Triggers on: 'rollback experiment', 'revert exp-005', 'undo last keep', 'roll back experiment 3', '/autoimprove rollback'. Lists kept experiments by ID and reverts the target via git revert, then refreshes the rolling baseline and updates state.json.

<example>
Context: User notices a kept experiment introduced a bug.
user: \"rollback experiment 5\"
assistant: I'll use the rollback skill to revert exp-005 and refresh the rolling baseline.
<commentary>Reverting a kept experiment — rollback skill.</commentary>
</example>

<example>
Context: User wants to see what can be rolled back.
user: \"show me kept experiments\"
assistant: I'll use the rollback skill in list mode to show rollback candidates.
<commentary>Listing candidates — rollback skill, not history skill.</commentary>
</example>

Do NOT use to discard an in-progress experiment (run skill handles that)."
argument-hint: "[<id>|last] [--list] [--dry-run]"
allowed-tools: [Read, Write, Edit, Bash]
---

<SKILL-GUARD>
You are NOW executing the rollback skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Revert a specific kept experiment by its ID, using `git revert` to preserve history. Updates the rolling baseline and state after revert.

Parse arguments:
- `<id>` — experiment ID to roll back (e.g., `5`, `005`, `exp-005`)
- `last` — roll back the most recent kept experiment
- `--list` — list all kept experiments and stop (no rollback)
- `--dry-run` — show what would happen without making changes

Initialize progress tracking:

```javascript
TodoWrite([
  { id: "1", content: "✅ Prerequisites check", status: "pending" },
  { id: "2", content: "📋 Load kept experiments", status: "pending" },
  { id: "3", content: "📋 List mode (if --list)", status: "pending" },
  { id: "4", content: "🔍 Resolve target ID", status: "pending" },
  { id: "5", content: "🔍 Find the commit", status: "pending" },
  { id: "6", content: "✅ Check revertibility", status: "pending" },
  { id: "7", content: "⚠️ Dry run (if --dry-run)", status: "pending" },
  { id: "8", content: "⚠️ Confirm with user", status: "pending" },
  { id: "9", content: "⏮️ Execute revert", status: "pending" },
  { id: "10", content: "📋 Update rolling baseline", status: "pending" },
  { id: "11", content: "🗂️ Update state.json", status: "pending" },
  { id: "12", content: "🗂️ Log rollback to TSV", status: "pending" },
  { id: "13", content: "✅ Confirm completion", status: "pending" }
])
```

---

# 1. ✅ Prerequisites Check

```bash
test -f autoimprove.yaml || echo "MISSING_CONFIG"
test -f experiments/experiments.tsv || echo "MISSING_TSV"
```

If `autoimprove.yaml` is missing: print `autoimprove is not initialized here. Run /autoimprove init.` and stop.

If `experiments.tsv` is missing: print `No experiment log found. No experiments have run yet.` and stop.

---

# 2. 📋 Load Kept Experiments

Read `experiments/experiments.tsv`. Filter to rows where `verdict == "keep"`.

TSV columns (0-indexed): `id`, `timestamp`, `theme`, `verdict`, `improved_metrics`, `regressed_metrics`, `tokens`, `wall_time`, `commit_msg`

Build a list of kept experiments, newest first (sort by id descending).

If no kept rows exist: print `No kept experiments found. Nothing to roll back.` and stop.

---

# 3. 📋 Handle `--list` Mode

If `--list` was passed (or no ID was given and the user said something like "show kept experiments"):

Print a table of all kept experiments:

```
Kept experiments (rollback candidates):

  ID   Date        Theme            Commit
  001  2026-03-15  test_coverage    Fix off-by-one in date range filter
  003  2026-03-16  skill_quality    Add usage examples to idea-matrix SKILL.md
  005  2026-03-17  agent_prompts    Improve judge convergence instructions

3 kept experiment(s) — use /autoimprove rollback <id> to revert one.
```

For each entry, also check whether the git tag `exp-<id>` exists:
```bash
git tag -l "exp-<id>"
```
If the tag is missing, append `[no git tag]` to that row — it may have been created before tagging was added.

Stop after printing the table.

---

# 4. 🔍 Resolve Target ID

If user passed `last`: use the highest numeric ID from the kept rows.

Otherwise, normalize the user's input to a 3-digit zero-padded ID:
- `5` → `005`
- `05` → `005`
- `exp-005` → `005`

Find the matching row in the kept experiments list. If not found: print `Experiment <id> not found or was not kept. Use --list to see rollback candidates.` and stop.

Store as `TARGET_ID`, `TARGET_THEME`, `TARGET_MSG`.

---

# 5. 🔍 Find the Commit

**5a. Try git tag first:**
```bash
TAG_SHA=$(git rev-list -n 1 "exp-${TARGET_ID}" 2>/dev/null)
```

**5b. Fall back to context.json:**
If the tag doesn't exist, read `experiments/${TARGET_ID}/context.json` and extract `result_sha`.

**5c. Fall back to commit message search:**
If neither worked, search git log for the commit message:
```bash
git log --oneline --all | grep "${TARGET_MSG}"
```
Extract the SHA from the first match.

If no SHA was found after all three attempts, print:
```
Cannot locate commit for experiment <TARGET_ID>.
The commit may have already been reverted or the tag was not created.
Use git log to find the commit manually.
```
and stop.

Store as `TARGET_SHA`.

---

# 6. ✅ Check Revertibility

**6a. Verify the commit is still in history:**
```bash
git merge-base --is-ancestor "${TARGET_SHA}" HEAD && echo "IN_HISTORY" || echo "NOT_IN_HISTORY"
```

If `NOT_IN_HISTORY`: print `Commit ${TARGET_SHA} is not in the current branch history. It may have already been reverted.` and stop.

**6b. Check for a prior revert:**
```bash
git log --oneline | grep "Revert.*exp-${TARGET_ID}"
```
If a revert commit already exists, print:
```
Experiment <TARGET_ID> appears to have already been reverted (found revert commit in history).
Use git log to inspect.
```
and stop.

---

# 7. ⚠️ Dry Run

If `--dry-run` was passed, print:

```
Dry run — no changes will be made.

Would revert:
  Experiment: <TARGET_ID>
  Theme:      <TARGET_THEME>
  Commit:     <TARGET_SHA>
  Message:    <TARGET_MSG>

Steps that would run:
  1. git revert --no-edit <TARGET_SHA>
  2. Update experiments/rolling-baseline.json
  3. Update experiments/state.json (decrement consecutive_keeps, re-evaluate trust_tier)
  4. Append rollback record to experiments/experiments.tsv

No changes made. Remove --dry-run to proceed.
```

Stop after the dry run output.

---

# 8. ⚠️ Confirm with User

Before reverting, print a confirmation prompt:

```
About to revert experiment <TARGET_ID>:
  Theme:   <TARGET_THEME>
  Commit:  <TARGET_SHA>
  Message: <TARGET_MSG>

This will create a revert commit on the current branch.
Proceed? [y/N]
```

Wait for user confirmation. If the user does not explicitly confirm (`y`, `yes`, `Y`): print `Rollback cancelled.` and stop.

---

# 9. ⏮️ Execute Revert

```bash
git revert --no-edit "${TARGET_SHA}"
```

On success: capture the new revert commit SHA:
```bash
REVERT_SHA=$(git rev-parse HEAD)
```

On failure (merge conflict or non-fast-forward): print the git error, then:
```
Revert failed — the commit may conflict with later changes.
Options:
  1. Resolve conflicts manually, then run: git revert --continue
  2. Abort: git revert --abort
The rolling baseline and state.json have NOT been updated.
```
Stop — do not update state on failure.

---

# 10. 📋 Update Rolling Baseline

After a successful revert, re-run the benchmark to refresh the rolling baseline:

```bash
bash "${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh" experiments/evaluate-config.json experiments/rolling-baseline.json
```

If this fails (non-zero exit), print a warning but do NOT treat it as a fatal error:
```
Warning: could not refresh rolling baseline (evaluate.sh failed).
Baseline may be stale — run /autoimprove run to re-anchor it.
```

---

# 11. 🗂️ Update State

Read `experiments/state.json`. Decrement `consecutive_keeps` by 1 (floor at 0).

Then re-evaluate `trust_tier` based on the new `consecutive_keeps` value:

```
if trust_tier == 2 and consecutive_keeps < 15 → trust_tier = 1
if trust_tier == 1 and consecutive_keeps < 5  → trust_tier = 0
```

A rollback voids the keep that earned the tier slot. If the new consecutive count no longer satisfies the tier's threshold, demote immediately — otherwise the next session will grant larger scope than the system has earned.

Write the updated `experiments/state.json`.

---

# 12. 🗂️ Log the Rollback

Append a rollback record to `experiments/experiments.tsv`:

```
<next_id>	<ISO timestamp>	<TARGET_THEME>	rollback	-	-	0	0	Rollback of exp-<TARGET_ID>: <TARGET_MSG>
```

Where `<next_id>` is the next sequential experiment ID (padded to 3 digits).

---

# 13. ✅ Confirm

Print:

```
Rolled back experiment <TARGET_ID>.

  Reverted:  <TARGET_SHA>
  New HEAD:  <REVERT_SHA>
  Theme:     <TARGET_THEME>
  Message:   <TARGET_MSG>

Rolling baseline refreshed.
State updated (consecutive_keeps: <new_value>, trust_tier: <new_tier>).

Run /autoimprove status to review the current state.
```

---

# Usage Examples

## Example 1 — List rollback candidates

```
user: show me kept experiments
```

Output:
```
Kept experiments (rollback candidates):

  ID   Date        Theme            Commit
  001  2026-03-15  test_coverage    Fix off-by-one in date range filter
  003  2026-03-16  skill_quality    Add examples to idea-matrix SKILL.md
  005  2026-03-17  agent_prompts    Improve judge convergence instructions

3 kept experiment(s) — use /autoimprove rollback <id> to revert one.
```

## Example 2 — Revert a specific experiment

```
user: rollback experiment 3
```

The skill resolves `3` → `003`, finds the commit via `exp-003` tag, confirms with the user, reverts, refreshes the baseline, and logs the rollback.

## Example 3 — Undo the most recent keep

```
user: roll back the last keep
```

The skill finds the highest-ID kept row, shows the confirmation prompt, and proceeds as above.

## Example 4 — Preview without committing

```
user: rollback experiment 5 --dry-run
```

Shows what would be reverted without touching git, state, or the TSV.

---

# Edge Cases and Pitfalls

- **Tag missing on older experiments**: The `exp-<id>` tag was introduced after the first few experiments. The skill falls back to `context.json` then git log search. If all three fail, it gives a manual recovery path.
- **Revert conflicts**: If later experiments modified the same files, `git revert` may conflict. The skill stops on conflict and tells the user how to resolve it manually. It never force-reverts.
- **Rolling baseline stale after evaluate.sh failure**: If the benchmark fails post-revert (e.g., tests are broken), the skill warns and does NOT block. The baseline will be refreshed by the next `/autoimprove run` session start.
- **Reverting out of order**: Rolling back experiment 003 when experiments 004 and 005 were also kept may cause conflicts — later experiments built on top of 003's changes. The dry run will show the target commit, but conflict detection only happens at `git revert` time.
- **Double revert**: The skill checks for an existing `Revert.*exp-<id>` commit in log before proceeding. This prevents accidentally reverting a revert.

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  { id: "1", status: "completed" },
  { id: "2", status: "completed" },
  { id: "3", status: "completed" },
  { id: "4", status: "completed" },
  { id: "5", status: "completed" },
  { id: "6", status: "completed" },
  { id: "7", status: "completed" },
  { id: "8", status: "completed" },
  { id: "9", status: "completed" },
  { id: "10", status: "completed" },
  { id: "11", status: "completed" },
  { id: "12", status: "completed" },
  { id: "13", status: "completed" }
])
```

---

# Integration Points

- **`/autoimprove history`** — Use `/history --verdict kept` to browse kept experiments with full metric detail before deciding which to roll back.
- **`/autoimprove status`** — After rollback, check status to confirm `consecutive_keeps` and trust tier reflect the updated state.
- **`/autoimprove run`** — A rollback does not re-run the experiment. If you want to retry the same theme with different constraints, start a new session with `/autoimprove run --theme <theme>`.
- **`git tag -l "exp-*"`** — Lists all experiment tags directly. Useful for manual verification that the tag exists before rollback.

---

# When NOT to Use

- **To undo an in-progress experiment** — worktrees are auto-cleaned by the run skill; no rollback needed.
- **To reset all state** — delete `experiments/state.json` manually and re-run `/autoimprove init`. Rollback targets one commit.
- **To revert a non-experiment commit** — use `git revert <sha>` directly. This skill is scoped to autoimprove experiment commits only.
