# Getting Started with autoimprove

autoimprove is a Claude Code plugin that runs an autonomous improvement loop on your codebase. It spawns experiments, evaluates them against your benchmarks, and keeps only the changes that move your metrics forward — all without human intervention.

## Prerequisites

- **Claude Code** — autoimprove is a Claude Code plugin and runs entirely within it
- **jq** — used by `evaluate.sh` for JSON processing (`brew install jq` or `apt install jq`)
- **bash 4+** — macOS ships bash 3; install bash 5 via Homebrew if needed
- **A project with tests** — gates require a passing test suite as a safety floor
- **git** — worktrees are used to isolate each experiment

## Installation

**From marketplace:**

```bash
claude plugin marketplace add https://github.com/ipedro/autoimprove
claude plugin install autoimprove
```

**Local development:** If you're working inside the autoimprove repo, Claude Code auto-discovers `.claude-plugin/` — no install needed.

After installing, run `/autoimprove init` inside your project. This is an interactive command — it detects your project type, runs your test suite, and writes `autoimprove.yaml` and `benchmark/metrics.sh` for you. You don't need to write anything by hand to get started.

## Quick Start

```
# 1. Scaffold the config (interactive — detects your project automatically)
/autoimprove init

# 2. Review autoimprove.yaml — init wrote it, but you can tune themes and priorities
#    Not required for the first run.

# 3. Run a trial session (3 experiments is a good smoke test)
/autoimprove run --experiments 3

# 4. See what happened
/autoimprove report
```

### What is a benchmark?

A benchmark is a script that measures your codebase and outputs a JSON object:

```bash
#!/usr/bin/env bash
echo '{"test_count": 42, "todo_count": 7}'
```

autoimprove uses these numbers to decide whether to keep or discard each experiment. **If a metric gets worse, the experiment is thrown away.** If at least one improves and none regress, it's merged.

> **Gates protect invariants. Benchmarks measure progress.** Gates are binary — if tests fail, the experiment is discarded. Benchmarks are numeric — if a metric regresses beyond tolerance, the experiment is discarded. Gates catch regressions; benchmarks track improvement.

`/autoimprove init` generates a working benchmark script automatically. The default metrics — `test_count` and `todo_count` — work for any project with a test suite. You can add custom metrics later by editing `benchmark/metrics.sh` and updating the `benchmarks:` section of `autoimprove.yaml`.

**No benchmark = no grind loop.** You need at least one metric for the loop to score experiments.

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

## Beyond the grind loop

autoimprove also includes standalone tools that work without `autoimprove.yaml`:

- **Adversarial review** (`/autoimprove-review`) — run a multi-round debate review on any code file or diff. Three agents (Enthusiast, Adversary, Judge) find and validate bugs through structured debate. See [skills: adversarial-review](skills.md#adversarial-review).

- **Idea matrix** (`/autoimprove-idea-matrix`) — explore design options systematically. 9 parallel haiku agents score individual options, hybrids, and composites on a structured rubric, then a convergence report synthesizes the winner. See [skills: idea-matrix](skills.md#idea-matrix).

- **Challenge benchmarks** (`/autoimprove-test challenge`) — test debate agent accuracy against curated code puzzles with known answer keys. See [skills: challenge](skills.md#challenge).

- **Prompt testing** (`/autoimprove-prompt-testing`) — methodology guide for writing tests for skills and agents. See [skills: prompt-testing](skills.md#prompt-testing).

## Autoimprove-Compatible Development

Every new feature you ship should have a corresponding metric in autoimprove.yaml.
Without a metric, the grind loop cannot improve it.

Checklist for each new feature:
- [ ] Add a metric to autoimprove.yaml (or extend an existing benchmark script)
- [ ] Run `/autoimprove run --experiments 1` to capture the new epoch baseline
- [ ] Verify the metric direction (higher_is_better vs lower_is_better)
- [ ] Add the feature's files to a relevant theme's focus_paths

## Adding Metrics Mid-Sprint

When you add a new feature, add its metric immediately — not at the end of the sprint.

1. Add the metric to `autoimprove.yaml` under the appropriate benchmark
2. Update the benchmark script to compute and output the new field
3. Start a new `/autoimprove run` session — the orchestrator captures a fresh epoch baseline at session start, which includes your new metric
4. The grind loop can now optimize the feature starting from the next experiment
