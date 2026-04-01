---
name: adversarial-review
description: Run the adversarial Enthusiast→Adversary→Judge debate review on the current diff, a file, or a PR. Runs in foreground with sequential E→A→J agents.
argument-hint: "[file|diff|pr <number>|<url>]"
---

Invoke the `autoimprove:adversarial-review` skill with `$ARGUMENTS`.

The skill runs the Enthusiast → Adversary → Judge chain inline, sequentially, in foreground. Do NOT wrap it in a background agent.

## Arguments

| Argument | What is reviewed |
|----------|-----------------|
| (none) | Staged + unstaged diff (`git diff HEAD`) |
| `diff` | Same as no argument — current working-tree diff |
| `<file-path>` | A single file (e.g., `scripts/evaluate.sh`) |
| `pr <number>` | A GitHub PR by number (e.g., `pr 42`) — fetches the PR diff via `gh` |
| `<github-issue-url>` | A GitHub issue URL — fetches the issue body and comments via `gh` |

## Usage Examples

```
# Review the current uncommitted changes
/adversarial-review

# Review a specific file
/adversarial-review scripts/evaluate.sh

# Review a GitHub PR
/adversarial-review pr 42

# Review a GitHub issue
/adversarial-review https://github.com/org/repo/issues/225
```

## Output

Results appear after the full debate completes:

- Confirmed findings count vs debunked count
- Top confirmed findings at critical/high severity (title + one-line rationale)
- Path to the full run folder

Example:

```
Adversarial review complete.
  Confirmed: 3 findings (1 critical, 2 high)
  Debunked:  5 findings

Top confirmed:
  [CRITICAL] evaluate.sh exits 0 on missing jq — gates never fire
  [HIGH]     Rolling baseline updated before gate check — allows ratchet bypass
  [HIGH]     Theme cooldown not persisted across sessions

Run folder: ~/.autoimprove/runs/YYYYMMDD-HHMMSS-<target-slug>/
```

## Notes

- **Runs in foreground.** The E→A→J chain is sequential and blocking — results appear when the full debate completes.
- **Sequential internals are mandatory.** Enthusiast → Adversary → Judge must run in strict order with outputs passed forward between agents.
- Requires `gh` CLI for `pr <number>` and issue URL modes.

## Related Commands

- `/idea-matrix` — explore design options before implementing (avoids needing a post-hoc review)
- `/autoimprove run` — experiment loop whose outputs are typical review targets
