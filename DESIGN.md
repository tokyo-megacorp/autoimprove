# autoimprove — Autonomous Codebase Improvement Loop

**Date:** 2026-03-25
**Status:** Draft
**Author:** Pedro + Claude
**Inspired by:** [karpathy/autoresearch](https://github.com/karpathy/autoresearch)

## Overview

A Claude Code plugin that adapts autoresearch's autonomous experiment loop to any software project. The human programs the improvement strategy (`autoimprove.yaml`), the system modifies code, evaluates against deterministic benchmarks, and keeps or discards changes via git worktree isolation. You wake up to a log of experiments and (hopefully) a better codebase.

## Core Mental Model

| autoresearch | autoimprove |
|---|---|
| `train.py` (agent-editable code) | Any project's source code |
| `prepare.py` (immutable evaluation) | Project's test suite + benchmark tasks |
| `program.md` (human-written strategy) | `autoimprove.yaml` (human-written improvement strategy) |
| `val_bpb` (single fitness number) | Composite score from deterministic benchmarks |
| `git commit` / `git reset --hard` | git worktree create / merge or delete |
| 5-minute training budget | Configurable token + time cap per iteration |

The key insight from autoresearch: the human doesn't edit `train.py` — they edit `program.md`. Here, you don't hand-tune your code — you tune the improvement instructions and let the loop do the work.

## Architecture

### Two-Agent Design

**Orchestrator** (runs in the main session):
- Reads `autoimprove.yaml`
- Picks themes (auto or manual)
- Creates/manages git worktrees
- Runs hard gates and benchmarks (deterministic, no LLM needed)
- Compares scores, decides keep/discard
- Merges or deletes worktrees
- Logs to `experiments.tsv`
- Manages budget, cooldowns, stagnation detection

**Experimenter** (spawned per-experiment into an isolated worktree):
- Receives: theme, scope, constraints, recent experiment history, project context
- Does NOT receive: benchmark definitions, metric names, scoring weights, current scores, composite formula
- Makes changes within constraints
- Commits with descriptive message explaining what it tried and why
- Returns control to orchestrator

**Why two agents?** Separation of concerns prevents Goodhart's Law. The experimenter can't game a metric it can't observe. Combined with the coverage gate and forbidden_paths, this creates defense in depth — two independent defenses against metric gaming.

**On LLM "blindness":** The experimenter will reason about what "good" means from domain knowledge. This is fine — desirable, even. The point isn't perfect blindness; it's removing the direct numerical optimization gradient. autoresearch's agent also knows val_bpb is the metric. The goal: make changes the agent genuinely believes are improvements, not changes that game a specific number.

### Loop Flow

```
SESSION START
  Load autoimprove.yaml
  Load experiments.tsv (history)
  Run & freeze epoch baseline (written to disk)

LOOP:
  Check budget (tokens, time, cost) → exhausted? STOP
  Pick theme (auto: weighted random with cooldown, or manual)
  Create worktree: autoimprove/<theme>-<timestamp>

  EXPERIMENT:
    Spawn experimenter agent into worktree
    Agent makes changes within constraints
    Agent commits with descriptive message

  HARD GATES (fast-fail):
    Run tests → fail? DISCARD, log "fail", skip benchmarks
    Run typecheck → fail? DISCARD, log "fail", skip benchmarks
    Check coverage on changed files ≥80% → fail? DISCARD

  BENCHMARKS:
    Run benchmark suite on candidate
    Compare to cached rolling baseline
    Compare to frozen epoch baseline

  SCORING:
    Any metric regresses > regression_tolerance (2%)? → DISCARD, log "regress"
    Composite improvement < significance_threshold (1%)? → DISCARD, log "neutral"
    Cumulative epoch drift > 5%? → HALT session
    Otherwise → KEEP

  IF KEEP:
    Merge worktree to main
    Tag commit: exp-<id>
    Update rolling baseline cache

  IF DISCARD:
    Delete worktree

  Log to experiments.tsv
  Update theme cooldowns
  Check stagnation (5 consecutive non-improvements per theme)
  All themes stagnated? → EXIT EARLY

  → LOOP
```

### Constraint Philosophy: Verifiability, Not Scope

autoresearch has NO line limit. The agent can rewrite all 630 lines of `train.py`. The safety net is the reset mechanism (git reset on regression), not the scope limit. The constraint is *temporal* (5-minute training budget), not *spatial* (number of lines).

autoimprove adopts the same philosophy: **the real constraint is verifiability, not scope.** A well-tested 20-file refactor is safer than an untested 2-line change. File/line limits are soft guidance for the experimenter, not hard gates. The hard gates are: tests pass, coverage gate passes, no regressions. If a large change survives all gates, it deserves to be kept.

### Trust Escalation Ratchet

Instead of static constraint tiers, the system earns scope through demonstrated competence:

```
Tier 0 (cold start):     3 files, 150 lines   — auto-merge
Tier 1 (after 5 keeps):  6 files, 300 lines   — auto-merge
Tier 2 (after 15 keeps): 10 files, 500 lines  — auto-merge
Tier 3 (ambitious):      no scope limit        — propose-only, human reviews
```

- Tiers escalate after N consecutive successful merges with zero regressions
- Any regression resets the ratchet one tier down
- Tier 3 changes are never auto-merged — they're queued as proposals for morning review
- The significance threshold scales with tier: 1% → 2% → 3% → human judgment

### Phase Transitions

The system operates in three phases. Transitions are triggered by keep-rate metrics:

**Phase 1: Grind** (autonomous)
- Small-to-medium changes, auto-merged on success
- Morning report = commit log of kept/discarded experiments
- This is the core loop described above

**Phase 2: Propose** (human-approved)
- Triggered when: keep rate drops below 25% for 3 consecutive sessions, or all themes stagnate
- The system drafts larger changes as structured proposals, never auto-merges
- Morning report = proposal queue with rationale, scope, risk assessment
- Human approves/rejects/defers each proposal
- Approved proposals become next Grind targets with expanded limits

```
PROPOSAL #1: Extract authentication middleware
  Scope: 4 files, ~200 lines affected
  Rationale: auth logic duplicated in 6 route handlers
  Risk: medium — touches request pipeline
  Estimated effort: 2 experiments
  [APPROVE] [REJECT] [DEFER]
```

**Phase 3: Research** (investigation)
- Triggered when: proposal backlog is empty, or manually
- No code changes. No keep/discard. Pure analysis
- The system reads the codebase end-to-end, maps dependencies, measures things
- Morning report = analyst memo

```
RESEARCH REPORT: Dependency Structure
  - 3 circular imports detected (files: X, Y, Z)
  - Module `utils` imported by 34 files but has no tests
  - Config loading happens in 5 different places
  - Oldest untouched file: parser.py (187 days)
```

**Phase transitions:**
- Grind → Propose: automatic, triggered by stagnation metrics
- Propose → Research: manual, or when proposal backlog is empty
- Research → Propose: manual (human reads report, decides what to investigate)
- Any → Grind: after major merge, or after 30+ days (codebase has drifted)

## Configuration: `autoimprove.yaml`

Lives in the project root. This is the `program.md` equivalent — the human-editable file that programs the researcher.

```yaml
project:
  name: my-project
  path: .

# --- BUDGET ---
budget:
  max_tokens_per_experiment: 100000
  max_time_per_experiment: 10m
  max_experiments_per_session: 20
  max_cost_per_session: $10

# --- HARD GATES (must all pass or experiment is auto-discarded) ---
gates:
  - name: tests
    command: npm test
    expect: exit_code_0
  - name: typecheck
    command: npm run typecheck
    expect: exit_code_0
  - name: no_regression
    description: "benchmark scores must not decrease by more than threshold"
    regression_tolerance: 0.02  # 2% worse is ok (noise margin)

# --- BENCHMARKS (the fitness function) ---
benchmarks:
  - name: dogfood
    type: script
    command: lcm dogfood
    metrics:
      - name: checks_passed
        extract: "grep -oP '\\d+(?=/39 passed)'"
        direction: higher_is_better
        weight: 3.0

  - name: compact_quality
    type: script
    command: node test/benchmarks/compact-quality.js
    metrics:
      - name: compression_ratio
        extract: json:.compression_ratio
        direction: higher_is_better
        weight: 2.0
      - name: information_retention
        extract: json:.retention_score
        direction: higher_is_better
        weight: 2.0

  - name: token_efficiency
    type: task  # runs a real task, extracts deterministic metrics (not LLM-as-judge)
    prompt: "Compact this 500-message conversation and report token counts"
    fixture: test/fixtures/large-conversation.json
    metrics:
      - name: output_tokens
        extract: json:.usage.output_tokens
        direction: lower_is_better
        weight: 1.0
      - name: wall_time_ms
        extract: json:.elapsed_ms
        direction: lower_is_better
        weight: 1.0

# --- THEMES (what the agent can try) ---
themes:
  auto:
    strategy: weighted_random
    weights:
      failing_tests: 5
      todo_comments: 3
      coverage_gaps: 2
      lint_warnings: 2
      stale_code: 1
      prompt_quality: 1
    cooldown_per_theme: 3  # skip for 3 experiments after attempt

  manual:
    - name: prompt_quality
      scope: ".claude-plugin/skills/**/*.md"
      instruction: "Improve clarity, reduce ambiguity, tighten trigger conditions"
    - name: test_coverage
      scope: "test/**/*"
      instruction: "Add tests for untested edge cases in src/"
    - name: performance
      scope: "src/**/*"
      instruction: "Reduce allocations, batch operations, optimize hot paths"

# --- CONSTRAINTS (soft guidance — hard gate is verifiability) ---
constraints:
  trust_ratchet:
    tier_0: { max_files: 3, max_lines: 150, significance: 0.01, mode: auto_merge }
    tier_1: { max_files: 6, max_lines: 300, significance: 0.02, mode: auto_merge, after_keeps: 5 }
    tier_2: { max_files: 10, max_lines: 500, significance: 0.03, mode: auto_merge, after_keeps: 15 }
    tier_3: { max_files: null, max_lines: null, significance: null, mode: propose_only }
    regression_penalty: -1  # drop one tier on any regression
  forbidden_paths:
    - autoimprove.yaml
    - test/benchmarks/**
    - test/fixtures/**
  test_modification: additive_only  # can add tests, cannot delete or weaken assertions
  require_commit_message: true

# --- PHASES ---
phases:
  grind:
    active: true  # starts here
    stagnation_threshold: 0.25  # keep rate below 25% for 3 sessions → transition
    stagnation_sessions: 3
  propose:
    max_proposals_per_session: 5
  research:
    trigger: manual  # or "auto" when proposal backlog is empty

# --- SAFETY ---
safety:
  epoch_drift_threshold: 0.05     # halt if cumulative drift from session start > 5%
  coverage_gate_threshold: 0.80   # changed files must have >= 80% coverage
  stagnation_window: 5            # early stop after 5 consecutive non-improvements
  state_checkpoints:              # files to hash before/after for isolation
    - "*.sqlite"
    - ".cache/**"
  state_checkpoint_excludes:      # volatile files to skip when hashing
    - "*.lock"
    - "*.log"
  clean_between_experiments:      # commands to reset external state
    - "rm -rf .cache/benchmark-*"
```

## Scoring System

### Dual Baseline

- **Epoch baseline**: Frozen at session start, written to disk as `experiments/epoch-baseline.json`. Never updated. Used for drift detection.
- **Rolling baseline**: Updated after each successful merge. Used for keep/discard decisions. Cached until main changes.

### Composite Score

```
score = sum(metric_delta * weight) / sum(weights)

where metric_delta = (candidate - baseline) / baseline
  normalized so positive = improvement regardless of direction
```

### Decision Matrix

| Condition | Verdict | Action |
|---|---|---|
| Any hard gate fails | **fail** | Discard, don't run benchmarks |
| Any metric regresses > 2% | **regress** | Discard |
| Composite improvement < 1% | **neutral** | Discard, increment stagnation counter |
| Composite improvement >= 1%, no regressions | **keep** | Merge worktree, update rolling baseline |
| Cumulative epoch drift > 5% | **halt** | Stop entire session, flag in report |

### Why No LLM Judge in v1

The soft-quality signal (LLM-as-judge for "is this prompt better?") is the noisiest, most expensive, and hardest-to-calibrate component. v1 uses only deterministic metrics. The LLM judge is a v2 feature once the hard-metric loop is proven to deliver value on its own.

## Experiment Log

### `experiments.tsv`

```
id  timestamp  theme  branch  files_changed  composite_score  baseline_score  epoch_score  verdict  tokens_used  wall_time  commit_msg
001  2026-03-25T22:01  test_coverage  autoimprove/test-001  2  0.847  0.832  0.832  keep  45000  4m30s  Add edge case tests for FTS5 sanitization
002  2026-03-25T22:12  prompt_quality  autoimprove/prompt-002  1  0.833  0.847  0.832  neutral  38000  3m15s  Tighten lcm-compact skill trigger conditions
003  2026-03-25T22:20  performance  autoimprove/perf-003  3  0.000  0.847  0.832  fail  12000  1m02s  Batch SQLite writes in compaction - broke migration
```

### `experiments/<id>/context.json`

Per-experiment reproducibility record:
```json
{
  "id": "001",
  "model_version": "claude-sonnet-4-6-20260321",
  "baseline_sha": "a1b2c3d",
  "experimenter_prompt": "...",
  "theme": "test_coverage",
  "scope": "test/**/*",
  "constraints": { "max_files": 3, "max_lines": 150 },
  "recent_experiments_provided": ["..."],
  "timestamp": "2026-03-25T22:01:00Z"
}
```

## Plugin Structure

```
autoimprove/
  .claude-plugin/
    plugin.json
    skills/
      autoimprove.md          # main loop skill (orchestrator)
      autoimprove-init.md     # scaffold autoimprove.yaml for a new project
      autoimprove-report.md   # morning report: grind log / proposal queue / research memo
    agents/
      experimenter.md         # the agent that runs inside each worktree (grind phase)
      proposer.md             # drafts larger changes as proposals (propose phase)
      researcher.md           # investigates codebase, writes reports (research phase)
    commands/
      autoimprove-run.md      # start a session: /autoimprove run [--phase grind|propose|research]
      autoimprove-status.md   # check running session + current trust tier
      autoimprove-history.md  # browse experiment log with filtering
      autoimprove-proposals.md # review/approve/reject pending proposals
```

### Commands

- `/autoimprove run` — Start a grind session. Options: `--experiments N`, `--theme <name>`, `--budget $N`
- `/autoimprove run --phase propose` — Run in propose phase (draft larger changes for review)
- `/autoimprove run --phase research` — Run in research phase (investigate, no code changes)
- `/autoimprove status` — Check running session, current trust tier, phase
- `/autoimprove report` — Morning review (format adapts to current phase)
- `/autoimprove history` — Browse full experiment log with filtering
- `/autoimprove proposals` — Review/approve/reject pending proposals from propose phase
- `/autoimprove init` — Scaffold `autoimprove.yaml` for the current project (detects project type, finds test commands, suggests benchmarks)

## The Morning Report

```
autoimprove report -- lcm -- 2026-03-25 overnight session

Summary
  Experiments: 18 run, 4 kept, 9 neutral, 3 discarded, 2 failed
  Epoch drift:  +2.3% improvement from session start
  Budget used:  847K / 1M tokens, $7.20 / $10.00
  Duration:     3h 42m
  Stagnated:    performance (5 neutral), lint_warnings (5 neutral)

Kept Experiments (merged to main)
  #003  test_coverage   +4.1%  "Add FTS5 sanitization edge cases"
  #007  test_coverage   +2.2%  "Cover compaction DAG depth edge cases"
  #011  refactor        +3.8%  "Extract promotion pipeline into dedicated module"
  #016  todo_comments   +1.4%  "Implement TODO: batch SQLite inserts in bulk import"

Notable Discards
  #005  performance     -1.1%  "Memoize repeated FTS5 queries" (regression: +15ms p99)
  #014  refactor         0.0%  "Split daemon routes into per-resource files" (neutral)

Full log: ./experiments.tsv
Per-experiment context: ./experiments/*/context.json
```

## Adversarial Analysis

This design was stress-tested through two rounds of FOR/AGAINST adversarial review.

### Round 1 Attacks and Fixes

| Attack | Severity | Fix |
|---|---|---|
| **Baseline drift** — 10x1.9% regressions compound to 17% | Critical | Epoch baseline frozen at session start. Dual scoring. Halt if cumulative drift >5% |
| **Gate/benchmark inversion** — agent removes untested functionality | High | Coverage gate: changed files must have >=80% test coverage |
| **Shallow worktree isolation** — shared DBs, caches, env vars | High | State hash checkpoint before/after. clean_between_experiments commands |
| **150-line blind spot** — cross-boundary refactors unreachable | Medium | Trust escalation ratchet: scope expands with demonstrated competence. Tier 3 = no scope limit, propose-only |
| **No stagnation exit** — burns budget on empty search space | Medium | Early stop after 5 consecutive non-improvements per theme |
| **experiments.tsv not reproducible** — records outcomes not causes | Medium | Full context.json per experiment (model version, SHA, prompt, seed) |

### Round 2 Attacks and Assessment

| Attack | Severity | Assessment |
|---|---|---|
| **Epoch baseline window attack** — experimenter infers baseline from stored data | Low | context.json is written AFTER the experiment, in experiments/ dir, not in the worktree. Experimenter never sees it |
| **Coverage gate redirect** — trivially-true tests game coverage | Medium | Valid residual risk. Mitigated by morning review visibility. Tests still must pass. Acceptable for v1 |
| **Constraints as covert channel** — tier info leaks significance threshold | Low | Knowing the tier doesn't help without knowing the current score value. Can't calibrate "just above threshold" without observing the threshold |
| **Patience attack** — alternating tiny wins reset stagnation counter | Low | Requires adversarial intent across fresh agent invocations with no shared memory. Each experimenter independently re-derives strategy — implausible |
| **Retrospective state hash** — before hash may already be contaminated | Medium | Fix: run clean_between_experiments FIRST, then hash, then experiment. Order matters |
| **context.json as reward signal** — reproducibility artifact leaks patterns | Low | Theoretical. Would require fine-tuning on experiment logs. Not a v1 concern |

### The Deep Critique

> "The two-agent split assumes LLM blindness is enforceable through information restriction. An LLM reasons about what it would be measured on from context alone."

This is philosophically true but practically irrelevant. autoresearch's agent also knows val_bpb is the metric. The point isn't perfect blindness — it's removing the direct numerical optimization gradient. The experimenter should make changes it genuinely believes are improvements. Defense in depth (blind to metrics + coverage gate + forbidden_paths) makes gaming harder than genuine improvement.

## Why This Is Genius / Why This Is Dumb

| Genius | Dumb |
|---|---|
| Self-improving tooling with real fitness functions (tests, benchmarks) — most people don't have measurable quality signals | The fitness function for "is this code better?" is fundamentally harder than val_bpb |
| Keep/discard via git worktrees is elegant and reversible | Token cost per iteration ($0.50-1.50) is much higher than a 5-min GPU training run |
| Overnight autonomous improvement compounds — even 1 in 5 succeeding yields 4 improvements per night | LLM code editing has no convergence guarantee unlike gradient descent |
| The human programs the researcher, not the research — autoresearch's actual insight | The loop might converge to overfitting benchmarks |
| Meta-improvement (improving the improvement process) is where the real insight lives | Prompt optimization is a different beast than gradient descent |
| Built on projects with strong test coverage — the safety net exists | Debugging a self-modifying system is notoriously hard |
| Stagnation mapping tells you where low-hanging fruit is exhausted — useful data independent of the loop | v1 deterministic-only metrics may miss the improvements that matter most (quality, clarity) |

## v2 Roadmap (Out of Scope for v1)

- **LLM-as-judge**: Before/after comparison for soft quality signals (prompt clarity, code readability)
- **Parallel experiments**: Multiple worktrees running simultaneously
- **Remote triggers**: Scheduled overnight runs on Anthropic's infra
- **Cross-project learning**: Share experiment history patterns across projects
- **Benchmark rotation**: Periodically swap benchmark tasks to prevent overfitting
- **Auto-theme discovery**: Analyze the codebase to suggest new themes automatically
- **Novelty fingerprinting**: Hash behavioral outputs to detect and reward divergent experiments, avoid retreading
