---
name: autoimprove-docs-regenerate
description: Regenerate documentation after code changes — detects changed files, maps to affected docs, and updates them.
argument-hint: "[--range <git-range>] [--dry-run]"
---

Invoke the `docs-regenerate` skill now. Do not do any work before the skill loads.

Arguments: $ARGUMENTS

---

## Arguments

| Argument | Description |
|----------|-------------|
| `--range <git-range>` | Git range to detect changed files (default: `HEAD~1..HEAD`). Examples: `HEAD~5..HEAD`, `main..feature-branch`. |
| `--dry-run` | Print the docs update plan without writing any files. |

## Usage Examples

```
# Update docs for the last commit (default)
/docs-regenerate

# Update docs for the last 5 commits
/docs-regenerate --range HEAD~5..HEAD

# Preview what would change without writing
/docs-regenerate --dry-run

# Update docs after merging a feature branch
/docs-regenerate --range main..HEAD
```

## What It Does

1. Runs `git diff --name-only` for the given range to identify changed source files.
2. Maps each changed file to the doc(s) it affects (skills → `docs/skills.md`, agents → `docs/agents.md`, commands → `docs/commands.md`, hooks → `docs/hooks.md`, config → `docs/configuration.md`).
3. Reads only the affected doc sections — never reads full source files.
4. Delegates patching to subagents (haiku for small updates, sonnet for new entries created from diff context).
5. Writes updated docs using Edit or Write, then commits to git.

## Output

```
Docs update complete (diff-only).

  Patched:  docs/skills.md (updated idea-matrix section)
  Patched:  docs/commands.md (added idea-matrix entry)
  Patched:  docs/README.md (TOC refreshed)
  Skipped:  docs/configuration.md (no config changes)

Commit: <SHA> — "docs: update after HEAD~1 HEAD"
```

With `--dry-run`, only the update plan is printed — no files are written.

## What It Does NOT Do

- Full regeneration (`--all` flag) is intentionally unsupported — it reads every source file and is a token trap.
- It never reads full source files, only git diffs. Subagents also receive only diffs, not full files.

## When to Use

- After any milestone commit to keep docs current.
- After adding, renaming, or removing skills, commands, agents, or hooks.
- Before opening a PR to verify docs reflect the latest changes.

## Related Commands

- `/autoimprove run` — runs experiments that may produce changes requiring a docs update
- `/prompt-testing` — write tests for the skills and agents that docs describe
