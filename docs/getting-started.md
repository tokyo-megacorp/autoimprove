# Getting Started with autoimprove

autoimprove is a Claude Code plugin that runs an autonomous improvement loop on your codebase. It spawns experiments, evaluates them against your benchmarks, and keeps only the changes that move your metrics forward — all without human intervention.

## Prerequisites

- **Claude Code** — autoimprove is a Claude Code plugin and runs entirely within it
- **jq** — used by `evaluate.sh` for JSON processing (`brew install jq` or `apt install jq`)
- **bash 4+** — macOS ships bash 3; install bash 5 via Homebrew if needed
- **A project with tests** — gates require a passing test suite as a safety floor
- **git** — worktrees are used to isolate each experiment

## Installation

1. Clone or copy the plugin into your Claude Code plugins directory (or reference it from your project):

   ```
   .claude-plugin/
   ```

2. Run `/autoimprove init` in your project directory. This scaffolds an `autoimprove.yaml` config file with sensible defaults.

3. Edit `autoimprove.yaml` to wire up your gates, benchmarks, and themes. See [configuration.md](configuration.md) for the full schema.

## Quick Start

```
# 1. Scaffold the config
/autoimprove init

# 2. Edit autoimprove.yaml — add your gates and at least one benchmark

# 3. Run the improvement loop (default: 20 experiments)
/autoimprove run

# 4. See what happened
/autoimprove report
```

### What happens during `/autoimprove run`

1. The orchestrator reads your `autoimprove.yaml` and measures your project's current state as the **epoch baseline** — a frozen snapshot of all your metrics at session start.
2. For each experiment (up to `max_experiments_per_session`), a theme is picked (e.g. `failing_tests`, `lint_warnings`) and an **experimenter agent** is spawned into an isolated git worktree.
3. The experimenter makes changes and commits them. It never sees your metric names or scores — it only knows the theme and scope constraints.
4. `evaluate.sh` runs your gates and benchmarks in the worktree and applies set logic: if any metric regresses, the change is discarded; if at least one metric improves and none regress, it is merged back to main.
5. After the session, trust tier may escalate (allowing larger future experiments) and a summary is written.

## Safety Model

autoimprove is conservative by design:

- **Hard gates first**: your test suite and typecheck must pass or the change is immediately discarded.
- **Set logic, not averages**: a single metric regression vetoes the entire experiment, regardless of improvements elsewhere.
- **Epoch drift check**: if your rolling metrics drift more than 5% from session-start values, the session halts automatically.
- **Fast-forward only merges**: experiments are rebased onto main; rebase conflicts = discard.
- **Trust starts small**: tier 0 limits experiments to 3 files and 150 lines. Scope expands only after 5 consecutive successful keeps.
- **Forbidden paths**: `autoimprove.yaml`, benchmark scripts, and test fixtures are never touched.
- **Test modifications are additive only**: the experimenter can add tests but cannot delete or weaken assertions.

The first session is intentionally cautious. After a track record of clean keeps, the system earns broader scope automatically.
