# autoimprove

Autonomous codebase improvement loop for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Inspired by [karpathy/autoresearch](https://github.com/karpathy/autoresearch).

You program the improvement strategy. The system modifies code, evaluates against your benchmarks, and keeps or discards changes via git worktree isolation. You wake up to a log of experiments and a better codebase.

## How it works

```
autoimprove.yaml          evaluate.sh              experimenter agent
(you write this)          (deterministic scoring)   (blind to scoring)
       │                         │                         │
       ▼                         ▼                         ▼
┌─────────────┐  spawn   ┌──────────────┐  evaluate  ┌──────────┐
│ orchestrator │────────▶ │  worktree    │──────────▶ │ verdict  │
│   (loop)    │◀─────────│  experiment  │            │ keep or  │
│             │  commit   │              │            │ discard  │
└─────────────┘          └──────────────┘            └──────────┘
```

The orchestrator picks improvement themes (failing tests, TODOs, coverage gaps), spawns an experimenter agent into an isolated git worktree, then evaluates the result with a deterministic script. The experimenter never sees your metrics or scores — it makes changes it genuinely believes are improvements.

**Scoring uses set logic, not weighted averages.** A change is kept only if no metric regresses and at least one improves. A single regression vetoes the entire experiment.

## Quick start

```bash
# 1. Scaffold config for your project
/autoimprove init

# 2. Run the improvement loop
/autoimprove run

# 3. See what happened
/autoimprove report
```

## The autoresearch mapping

| autoresearch | autoimprove |
|---|---|
| `train.py` (agent edits this) | Your source code |
| `prepare.py` (immutable eval) | `evaluate.sh` |
| `program.md` (human strategy) | `autoimprove.yaml` |
| `val_bpb` (fitness number) | Per-metric set logic |
| `git reset --hard` | `git worktree remove` |

The key insight from autoresearch: **the human doesn't edit the code — they edit the improvement strategy.** You tune `autoimprove.yaml`, not your source files.

## Safety

autoimprove is conservative by default:

- **Hard gates first** — tests and typecheck must pass or the change is immediately discarded
- **No metric can regress** — a single regression vetoes, regardless of other improvements
- **Epoch drift halt** — session stops if cumulative drift exceeds 5% from session start
- **Trust starts small** — tier 0 limits experiments to 3 files, 150 lines. Scope expands only after consecutive successful keeps
- **Fast-forward only** — rebase conflicts = discard. Clean linear history guaranteed
- **Experimenter is blind** — can't game metrics it can't see
- **Evaluation is deterministic** — `evaluate.sh` (bash + jq), no LLM in the scoring loop

## Configuration

`autoimprove.yaml` lives in your project root:

```yaml
gates:
  - name: tests
    command: npm test
  - name: typecheck
    command: npx tsc --noEmit

benchmarks:
  - name: project-metrics
    type: script
    command: bash benchmark/metrics.sh
    metrics:
      - name: test_count
        extract: "json:.test_count"
        direction: higher_is_better
        tolerance: 0.02       # max acceptable regression
        significance: 0.01    # min meaningful improvement

themes:
  auto:
    strategy: weighted_random
    priorities:
      failing_tests: 5
      todo_comments: 3
      coverage_gaps: 2
```

See [docs/configuration.md](docs/configuration.md) for the full schema.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- `jq` (`brew install jq` / `apt install jq`)
- bash 4+
- A project with a test suite

## Documentation

- [Getting Started](docs/getting-started.md) — install, configure, first run
- [Usage Guide](docs/usage.md) — setup walkthrough, running sessions, tuning strategy, benchmark patterns
- [Configuration](docs/configuration.md) — full `autoimprove.yaml` reference
- [How It Works](docs/how-it-works.md) — architecture, scoring, safety mechanisms
- [Commands](docs/commands.md) — `/autoimprove run`, `report`, `init`
- [Troubleshooting](docs/troubleshooting.md) — common issues and how to fix them

## Project structure

```
.claude-plugin/
  plugin.json              # plugin manifest
  skills/
    orchestrator.md        # the main experiment loop
    init.md                # scaffold autoimprove.yaml
    report.md              # morning report
  agents/
    experimenter.md        # runs in worktree, blind to scoring
  commands/
    run.md                 # /autoimprove run
    report.md              # /autoimprove report
    init.md                # /autoimprove init
scripts/
  evaluate.sh              # the prepare.py — deterministic evaluation
```

## Design

The full design spec — including adversarial review, constraint philosophy, and the case for set logic over weighted composites — is in [DESIGN.md](DESIGN.md).

## License

MIT
