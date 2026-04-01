---
name: autoimprove
description: Start the main autoimprove orchestrator loop directly. Alias for `/autoimprove run`.
argument-hint: "[--theme <name>] [--experiments N]"
---

Invoke the `autoimprove:autoimprove` skill now. Do not do any work before the skill loads.

Arguments: $ARGUMENTS

---

This command is the direct entry point for the autonomous improvement loop. It behaves the same as `/autoimprove run`.

## Arguments

| Argument | Description |
|----------|-------------|
| `--theme <name>` | Run only experiments for this theme (e.g. `failing_tests`, `todo_comments`, `coverage_gaps`, `lint_warnings`). |
| `--experiments N` | Override `max_experiments_per_session` from `autoimprove.yaml` for this run only. |

Both arguments are optional. Omitting them uses the config defaults and picks themes via weighted-random selection.

## Usage Examples

```
# Start a default session
/autoimprove

# Quick trial — run 3 experiments only
/autoimprove --experiments 3

# Focus on a specific theme
/autoimprove --theme failing_tests
```

## Related Commands

- `/autoimprove run` — explicit subcommand form of the same orchestrator entry point
- `/autoimprove report` — review what was kept, discarded, and metric trends after the session
- `/autoimprove init` — scaffold `autoimprove.yaml` before running for the first time
