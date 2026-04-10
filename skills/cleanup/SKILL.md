---
name: cleanup
description: |
  Manually sweep stale autoimprove worktrees and branches via `skills/_shared/cleanup-worktrees.sh`. Safe to run at any time — protects live worktrees, tagged keepers, and in-flight experiments. Triggers: '/autoimprove cleanup', 'clean up stale worktrees', 'sweep orphan branches', 'autoimprove hygiene'.

  <example>
  user: "/autoimprove cleanup --dry-run"
  assistant: I'll use the cleanup skill to preview what the sweep would remove.
  <commentary>Dry-run preview — cleanup skill.</commentary>
  </example>

  <example>
  user: "clean up the orphan worktree-agent branches"
  assistant: I'll use the cleanup skill to sweep them.
  <commentary>Explicit cleanup request — cleanup skill.</commentary>
  </example>

  Do NOT use for in-loop per-experiment cleanup → that lives in step 3j of the run skill. This skill is the manual/safety-net sweep only.
argument-hint: "[--dry-run] [--verbose]"
allowed-tools: [Read, Bash, Grep]
---

Run the shared worktree cleanup helper and report results.

Parse arguments:
- `--dry-run` — preview mode, no deletions
- `--verbose` — print per-candidate skip reasons

Default behavior: destructive sweep, quiet output.

---

# 1. Prerequisites

Verify the helper exists:

```bash
test -f "${CLAUDE_SKILL_DIR}/../_shared/cleanup-worktrees.sh" || {
  echo "FATAL: cleanup-worktrees.sh not found — plugin may be misconfigured"
  exit 1
}
chmod +x "${CLAUDE_SKILL_DIR}/../_shared/cleanup-worktrees.sh"
```

---

# 2. Invoke

Pass arguments through:

```bash
bash "${CLAUDE_SKILL_DIR}/../_shared/cleanup-worktrees.sh" $ARGUMENTS
```

Capture stdout. The last line is the summary (`[cleanup] N worktrees, M branches removed`).

---

# 3. Report

Present output to the user as a short markdown block:

```
## Cleanup result

<one-line summary from the script's final output line>

<if any actions taken:>
### Removed
- worktree: <path> (<branch>)
- branch: <name>
...

<if any skipped in verbose mode:>
### Skipped (protected)
- <branch>: <reason>
```

If the output is empty or contains only the summary `[cleanup] 0 worktrees, 0 branches removed`, respond with: "Nothing to clean — repo is tidy."

---

# 4. Safety Guarantees (documentation for the user)

The helper refuses to delete anything that is:

1. **Live-worktree**: branch is currently checked out in a `git worktree list` entry
2. **Tagged `exp-*`**: commit is tagged as a kept experiment
3. **In-flight**: branch name embeds an experiment id whose `experiments/<id>/context.json` has `verdict: null`

These guards apply to both branch namespaces: `autoimprove/*` and `worktree-agent-*`.

If the user reports that the script deleted something it should not have, STOP and inspect the three guards above — one of them failed to match. Never suggest adding `--force` or bypassing the guards. The correct response to an over-eager delete is to fix the guard logic, not to loosen it.

---

# When NOT to Use

- **Inside the run loop** — step 3j already cleans up per experiment. Do not call this skill from within 3j.
- **To delete user branches** — this skill only touches `autoimprove/*` and `worktree-agent-*`. Arbitrary branch cleanup is not in scope.
- **To delete worktrees outside the current repo** — the helper only operates on the cwd's git state.
