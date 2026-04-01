# autoimprove Documentation

Autonomous codebase improvement loop for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Runs experiments, evaluates against your benchmarks, keeps or discards via git worktrees.

## Getting Started

- [Getting Started](getting-started.md) — Install, configure `autoimprove.yaml`, run your first session
- [Configuration](configuration.md) — Full `autoimprove.yaml` reference (gates, benchmarks, themes, safety, trust ratchet)
- [Usage Guide](usage.md) — Running sessions, reading results, tuning your strategy, benchmark patterns

## Reference

- [Commands](commands.md) — All 8 slash commands
- [Skills](skills.md) — All 8 skills (autoimprove, init, run, report, challenge, adversarial-review, idea-matrix, prompt-testing)
- [Agents](agents.md) — All 6 agents (experimenter, enthusiast, adversary, judge, challenge-runner, idea-explorer)

## Deep Dives

- [Architecture](architecture.md) — Grind loop, scoring (set logic), safety mechanisms, trust ratchet
- [Troubleshooting](troubleshooting.md) — Common issues, experiment failures, orphaned worktrees

## Feature Groups

### Grind Loop (autonomous improvement)

The core feature. Spawns experimenter agents into git worktrees, evaluates changes deterministically, keeps or discards.

Commands: [`/autoimprove`](commands.md#autoimprove), [`/autoimprove-run`](commands.md#autoimprove-run), [`/autoimprove-report`](commands.md#autoimprove-report), [`/autoimprove-init`](commands.md#autoimprove-init) | Skills: [autoimprove](skills.md#autoimprove), [init](skills.md#init), [run](skills.md#run), [report](skills.md#report) | Agents: [experimenter](agents.md#experimenter)

### Adversarial Review (debate-based code review)

Three-agent debate cycle: Enthusiast finds bugs, Adversary challenges them, Judge arbitrates. Multi-round with deterministic convergence detection.

Commands: [`/autoimprove-review`](commands.md#autoimprove-review) | Skills: [adversarial-review](skills.md#adversarial-review) | Agents: [enthusiast](agents.md#enthusiast), [adversary](agents.md#adversary), [judge](agents.md#judge)

### Idea Matrix (design exploration)

3x3 exploration grid: 9 parallel haiku agents score design options (solo, hybrid, composite) on a structured rubric, then the orchestrator synthesizes a convergence report.

Commands: [`/autoimprove-idea-matrix`](commands.md#autoimprove-idea-matrix) | Skills: [idea-matrix](skills.md#idea-matrix) | Agents: [idea-explorer](agents.md#idea-explorer)

### Testing

Commands: [`/autoimprove-test`](commands.md#autoimprove-test), [`/autoimprove-prompt-testing`](commands.md#autoimprove-prompt-testing) | Skills: [challenge](skills.md#challenge), [prompt-testing](skills.md#prompt-testing) | Agents: [challenge-runner](agents.md#challenge-runner)
