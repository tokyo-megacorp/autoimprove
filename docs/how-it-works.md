# How autoimprove Works

## Mental Model: autoresearch Mapping

autoimprove is directly inspired by [karpathy/autoresearch](https://github.com/karpathy/autoresearch). The mental model maps as:

| autoresearch | autoimprove |
|---|---|
| `program.md` | `autoimprove.yaml` — human programs the strategy |
| `prepare.py` | `evaluate.sh` — deterministic, immutable evaluation script |
| Training loop | Orchestrator skill — the improvement loop |
| Experiment branch | git worktree — isolated per-experiment workspace |
| Metric CSV | `experiments.tsv` + `experiments/<id>/context.json` |
| Keep/discard | Set logic verdict: `keep`, `neutral`, `regress`, `gate_fail` |

The key invariant in both systems: **the evaluation script is not touched by the automated loop**. `evaluate.sh` is your ground truth. The loop works around it.

---

## Architecture

```
Claude Code
  └── Orchestrator skill          # the loop controller
        ├── reads autoimprove.yaml
        ├── manages state.json, experiments.tsv
        ├── spawns → Experimenter agent (per worktree)
        └── runs → evaluate.sh (gates + benchmarks + scoring)
```

**Two agents, one evaluator:**

- **Orchestrator** — picks themes, creates worktrees, spawns the experimenter, calls `evaluate.sh`, reads the verdict, keeps or discards, updates state. It knows everything.
- **Experimenter** — runs inside an isolated git worktree. Knows the theme, scope constraints, and recent experiment summaries. Does not know metric names, scoring thresholds, or how it will be judged. This separation prevents Goodhart's Law gaming.
- **evaluate.sh** — a deterministic bash script. Takes a config JSON and a baseline JSON, runs gates, runs benchmarks, extracts metrics, applies set logic, and outputs a verdict JSON. `jq` is the only dependency. Claude never evaluates; only `evaluate.sh` evaluates.

**State files** (in `experiments/`):

| File | Contents |
|---|---|
| `epoch-baseline.json` | Metrics at session start — frozen, never updated during session |
| `rolling-baseline.json` | Metrics after last keep — updated on each merge |
| `state.json` | Trust tier, consecutive keeps, theme cooldowns, stagnation counters |
| `experiments.tsv` | Append-only log of all experiments (id, theme, verdict, delta) |
| `experiments/<id>/context.json` | Full metric breakdown, commit SHA, prompt, model version |

---

## Session Flow

```
SESSION START
  Read autoimprove.yaml → generate evaluate-config.json
  Run evaluate.sh (no baseline) → save as epoch-baseline + rolling-baseline
  Load/create state.json
  Crash recovery: clean orphaned worktrees, mark crashed experiments

LOOP (repeat until budget exhausted or all themes stagnated):
  1. Check experiment budget
  2. Pick theme (weighted random, respecting cooldowns)
  3. Spawn experimenter in worktree
     → experimenter receives: theme, scope, last 5 summaries
     → experimenter does NOT receive: metric names, scoring logic
  4. Experimenter commits changes, returns
  5. Diff worktree → build changed_files list for coverage gate
  6. Run evaluate.sh against rolling-baseline
  7. Read verdict:
     gate_fail → discard worktree
     regress   → discard worktree
     neutral   → discard worktree, increment theme stagnation
     keep      → rebase onto main (fast-forward), merge, update rolling-baseline
  8. Log to experiments.tsv + context.json
  9. Check epoch drift → halt if cumulative drift > threshold
  10. Update cooldowns, stagnation counters, trust tier

SESSION END
  Print summary (experiments run, keeps, discards, drift, budget used)
```

---

## Scoring: Set Logic

autoimprove uses **set logic**, not weighted composites. There are no weights and no averaging.

**KEEP** = all of these are true:
- All hard gates pass (tests, typecheck)
- Coverage gate passes (if configured)
- No metric has regressed more than its `tolerance` fraction
- At least one metric has improved more than its `significance` fraction

**Any single regression vetoes the keep**, regardless of improvements elsewhere. This is deliberate. A change that makes 5 things better and 1 thing worse is a change you need to understand — autoimprove will not silently accept it.

The tolerance and significance thresholds are per-metric control knobs. Noisy metrics get wider tolerance; critical metrics get tighter thresholds.

---

## Safety Mechanisms

### Epoch Baseline

At session start, metrics are measured and frozen as the **epoch baseline**. This baseline is never updated. As experiments are kept, the **rolling baseline** advances.

If the rolling baseline drifts more than `epoch_drift_threshold` (default 5%) from the epoch baseline on any metric, the session halts. This catches compound regression drift — small losses that individually pass tolerance but accumulate across a session.

### Coverage Gate

When configured, after gates pass and before benchmarks run, `evaluate.sh` checks that coverage on changed files meets the `threshold`. This prevents the experimenter from improving metrics by removing code that was being tested.

### Trust Ratchet

Scope starts small (tier 0: 3 files, 150 lines) and expands only through demonstrated success. After 5 consecutive keeps → tier 1. After 15 → tier 2. Regressions subtract from the consecutive count. Tier 3 (unlimited scope) is `propose_only` — never auto-merged.

### Stagnation Detection

If a theme produces 5 consecutive non-improvements (`neutral`, `regress`, or `gate_fail`), it is marked as stagnated and excluded from selection. When all themes are stagnated, the session exits early. This prevents wasted compute on exhausted improvement opportunities.

### Fast-Forward Only Merges

Worktrees are created from current HEAD. When a keep is approved, the experimenter's commits are rebased onto the latest main and fast-forwarded. If the rebase fails (conflict), the experiment is treated as a discard. This guarantees a clean linear history.

### Forbidden Paths and Additive-Only Tests

The experimenter cannot modify `autoimprove.yaml`, benchmark scripts, or test fixtures. It can add tests but cannot delete or weaken assertions. These constraints preserve the integrity of the evaluation infrastructure itself.
