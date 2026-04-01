# Changelog

All notable changes to autoimprove are documented here.

## [0.3.0] — 2026-04-01 — AR Smoke Gate

### Added
- `feat(ar)`: ar-effectiveness smoke test gate — validates adversarial-review pipeline end-to-end (#66)

### Fixed
- `fix(adversarial-review)`: run E→A→J inline in foreground, fix agent subagent_type (#65)
- `fix(ar)`: aggregate diff range guidance (#67)

---

## [0.2.0] — 2026-03-31 — Benchmarks + Calibration

### Fixed
- `fix(config)`: remove LLM-based benchmarks that broke Haiku grind loops
- `fix(docs)`: `adversarial-review` SKILL.md — clarify inline-only execution (no background re-dispatch)

### Added
- `feat(benchmark)`: effectiveness benchmarks for adversarial-review + idea-matrix (#59)
- `feat(calibrate)`: cross-model calibration skill for adversarial-review (#58)

### Improved
- Skill quality improvements: `run`, `matrix-draft`, `docs-regenerate`, `prompt-testing`, `init`, `challenge`
- Agent prompt depth: examples, failure patterns, edge-case handling for 3 core agents
- Test coverage: 60+ new assertions across evaluate, compare-mode, shell extractor, and trigger state

---

## [0.1.0] — 2026-03-30 — Inaugural Release

> First release of the autonomous codebase improvement loop.
> 164 commits. 18 skills. 10 agents. 8 commands. ~290 test assertions.

### Core Loop

- **Grind loop** — orchestrator dispatches experimenter agents into isolated git worktrees; changes are evaluated against deterministic benchmarks and kept or discarded automatically
- **autoimprove.yaml** config schema — human-authored improvement strategy (`themes`, `focus_paths`, `gates`, `budget`) drives the loop without code changes
- **Git worktree isolation** — every experiment runs in a clean branch; no main-branch pollution until a benchmark improvement is confirmed
- **evaluate.sh** — deterministic benchmark runner; composite score gates every experiment (exit 0 = improvement kept, exit 1 = discarded)
- **autoimprove-trigger.sh** — signal-driven trigger pipeline; validates YAML signal before writing

### Skills (18)

| Skill | Purpose |
|-------|---------|
| `run` | Start the grind loop — dispatches experimenter with theme + target |
| `status` | Live view of running experiments and recent results |
| `history` | Browse kept/discarded experiment log with filtering |
| `report` | Session summary — experiments run, improvements kept, themes hit |
| `init` | Scaffold `autoimprove.yaml` for a new project |
| `test` | Run the evaluate test suite and benchmark gates |
| `diff` | Inspect code changes from a specific experiment |
| `rollback` | Revert a kept experiment back to pre-merge state |
| `diagnose` | Validate config and debug benchmark failures |
| `decisions` | Browse ADR-style decisions with `--since`, `--verdict`, `--search` |
| `proposals` | View pending improvement proposals before they're run |
| `idea-matrix` | 3×3 Haiku idea exploration matrix on a design decision |
| `idea-archive` | Browse archived ideas from previous sessions |
| `matrix-draft` | Draft the idea matrix without running experiments |
| `adversarial-review` | Run Enthusiast → Adversary → Judge pipeline on a skill or agent |
| `prompt-testing` | Write and run regression tests for skills |
| `docs-regenerate` | Regenerate documentation after code changes (diff-only) |
| `challenge` | Run a single challenge through the full debate pipeline |

### Agents (10)

| Agent | Role |
|-------|------|
| `experimenter` | Implements code changes in worktree based on assigned theme |
| `enthusiast` | AR pipeline — finds strengths, argues for keeping the change |
| `adversary` | AR pipeline — stress-tests the change, finds failure modes |
| `judge` | AR pipeline — weighs evidence, delivers binding verdict |
| `idea-explorer` | Generates improvement ideas across a theme space |
| `proposer` | Structures ideas into ranked, actionable proposals |
| `researcher` | Deep-dives a topic to inform theme strategy |
| `challenge-runner` | Runs full debate pipeline on a single challenge, scores with F1 |
| `convergence-analyst` | Detects when the loop is converging or stagnating |
| `docs-regenerate` | Background doc regeneration from git diff |

### Commands (8)

| Command | Trigger |
|---------|---------|
| `autoimprove-run` | Start or resume a grind loop session |
| `autoimprove-test` | Run test suites (evaluate + benchmark) |
| `autoimprove-report` | Show session summary |
| `autoimprove-init` | Initialize a project for autoimprove |
| `adversarial-review` | Run AR pipeline on any skill or agent |
| `idea-matrix` | Launch idea exploration matrix |
| `prompt-testing` | Run prompt regression tests |
| `docs-regenerate` | Trigger doc regeneration from diff |

### Theme Engine (Phases 1–3)

- **Phase 1 — Harvest:** `harvest.sh` + `harvest-themes.sh` collect improvement signals from LCM, git log, and test results
- **Phase 2 — Focus paths:** `focus_paths` in `autoimprove.yaml` constrains experimenter to high-signal files
- **Phase 3 — Weighted feedback:** `theme-weights.sh` adjusts theme priority dynamically from experiment history (#37)

### Benchmark & Metrics

- **Self-metrics benchmark** (`benchmark/self-metrics.sh`) — measures prompt quality of the plugin itself:
  - `skill_depth` — word count across all skill SKILL.md files
  - `agent_sections` — structured section count across agent prompts
  - `test_count` — total test assertions in evaluate suite
- `score-challenge.sh` — F1 scorer for challenge debates

### Test Suite (~290 assertions)

- `test/evaluate/test-evaluate.sh` — evaluator logic: gate pass/fail, verdict logic, delta_pct, exit codes, reason formatting, metric accumulation, cross-benchmark regression, edge cases (zero-baseline, stagnation, sparse output, mixed metrics)
- `test/evaluate/fixtures/` — 4 fixture configs (basic, gates-only, baseline-basic, mock-benchmark)
- `benchmark/test-trigger-signal-validation.sh` — signal validation guards

### CI & Security

- AR coverage gate CI workflow — adversarial review runs on PRs
- Dependabot — automated dependency updates
- CodeQL scanning — static security analysis
- Signal validation guards — malformed YAML signals are rejected before write (#8, PR #9)

### Bug Fixes

- Python heredoc → env-var passing in `autoimprove-trigger.sh` (#15, PR #16)
- `evaluate.sh` calling convention — `cd` to worktree before running (#41)
- AR background execution reliability pattern (#152)
- Tool parameter validation guard in adversary + judge agents (#147)

---

[0.1.0]: https://github.com/ipedro/autoimprove/releases/tag/v0.1.0
