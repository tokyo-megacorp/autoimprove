---
name: adversarial-review
description: Run the adversarial Enthusiast→Adversary→Judge debate review on the current diff, a file, or a PR. Always runs in background.
argument-hint: "[file|diff|pr <number>]"
---

This review MUST run in the background so the user is not blocked.

## Arguments

| Argument | What is reviewed |
|----------|-----------------|
| (none) | Staged + unstaged diff (`git diff HEAD`) |
| `diff` | Same as no argument — current working-tree diff |
| `<file-path>` | A single file (e.g., `scripts/evaluate.sh`) |
| `pr <number>` | A GitHub PR by number (e.g., `pr 42`) — fetches the PR diff via `gh` |

## Usage Examples

```
# Review the current uncommitted changes
/adversarial-review

# Review a specific file
/adversarial-review scripts/evaluate.sh

# Review a GitHub PR
/adversarial-review pr 42
```

## What It Does

1. Spawns a **background Agent** (using `run_in_background: true`) with the `adversarial-review` skill.
2. Inside that background run, the skill executes three agents **sequentially, never in parallel** — Enthusiast, Adversary, Judge:
    - **Enthusiast** surfaces strengths and best-case interpretations.
    - **Adversary** waits for the Enthusiast's full output, then challenges those specific claims.
    - **Judge** waits for both prior outputs, then emits confirmed vs debunked findings with severity ratings.
3. Results are written to a timestamped run folder under `experiments/ar-runs/`.

## Output

When the background agent completes, the summary includes:

- Confirmed findings count vs debunked count
- Top confirmed findings at critical/high severity (title + one-line rationale)
- Path to the full run folder for detailed output

Example summary:

```
Adversarial review complete.
  Confirmed: 3 findings (1 critical, 2 high)
  Debunked:  5 findings

Top confirmed:
  [CRITICAL] evaluate.sh exits 0 on missing jq — gates never fire
  [HIGH]     Rolling baseline updated before gate check — allows ratchet bypass
  [HIGH]     Theme cooldown not persisted across sessions

Run folder: experiments/ar-runs/2026-03-29T14-22-00/
```

## Notes

- **Always non-blocking.** The review is dispatched in the background — the orchestrator session remains available immediately.
- **Sequential internals are mandatory.** The top-level review may run in the background, but the Enthusiast → Adversary → Judge chain must run in order with outputs passed forward between agents.
- Requires `gh` CLI for `pr <number>` mode.
- The Enthusiast→Adversary→Judge pattern is fixed; individual agents cannot be run standalone via this command.

## Related Commands

- `/idea-matrix` — explore design options before implementing (avoids needing a post-hoc review)
- `/autoimprove run` — experiment loop whose outputs are typical review targets
