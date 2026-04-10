# Behavioral Benchmark Design — val_bpb analog for skills

**Date:** 2026-04-10
**Status:** Design note, not yet implemented
**Owner:** TBD
**Prior art:** karpathy/autoresearch (`~/Developer/autoresearch`)

## TL;DR

autoimprove's 13 deterministic metrics are mostly structural (line-counting regex proxies). karpathy's autoresearch — the original inspiration — uses **one** behavioral metric: `val_bpb` measured by running the model against a pinned held-out shard. The metric is un-gameable because it measures runtime behavior, not artifact structure.

We validated the structural approach against the `superpowers` plugin (gold-standard reference) and found 3 of 4 prompt-quality metrics are anti-quality — autoimprove scores HIGHER than the gold standard on "higher is better" metrics. The grind loop has been optimizing away from narrative-rich quality.

This note specifies the replacement: a behavioral benchmark for skills that invokes each skill on a fixed test task and measures outcome against a pinned success criterion.

## Why structural metrics fail for skill quality

**The artifact vs behavior gap.** Structural metrics (`imperative_ratio`, `example_density`, etc.) measure properties of the SKILL.md text itself — line counts, regex matches, section presence. They're cheap and deterministic but measure the wrong thing. A skill's value is whether it makes Claude produce better outputs when invoked, not whether its prose has high directive density.

**Superpowers skills prove the point.** `using-superpowers.md` (the flagship introduction skill) scores 0.0000 on our current `imperative_ratio` benchmark. The gold standard fails our quality gate. That's the reductio.

**Every structural metric becomes a Goodhart target eventually.** Pattern-grep can be satisfied by pasting patterns. Line-counts can be inflated. Even LLM-based rubric scoring (the Rubric Escalation Ladder idea) is structural — it scores artifact properties, not behavior.

## What karpathy did right

Single metric: `val_bpb` (validation bits-per-byte). Computed by running the model on a pinned validation shard and taking `total_nats / (log(2) * total_bytes)`. The metric is:

1. **Behavioral** — runs the actual artifact (the trained model) on held-out data
2. **Un-gameable by structure** — no way to improve it without making the model actually predict better
3. **Single number** — no composite scoring, no dimension aggregates
4. **Tied to an immutable eval harness** — `prepare.py` is declared read-only (`program.md:28-31`)

The experimenter is NOT blind to the score. Karpathy shows it after every run (`grep "^val_bpb:" run.log`, `program.md:100`). Blindness is unnecessary because the metric is structurally un-gameable.

## The analog for skills: `skill_behavioral_score`

### Core design

For each skill, define a **fixture** — a `(task, success_criterion)` pair that represents what the skill is supposed to help with. The benchmark:

1. Spawns a Claude agent with the test task and WITHOUT the skill loaded → record baseline output
2. Spawns another Claude agent with the test task and WITH the skill loaded → record treatment output
3. Evaluates both against the success criterion deterministically
4. Metric = `treatment_success_rate - baseline_success_rate` (bounded [-1, 1])
5. Aggregate across all skill fixtures: `mean(skill_behavioral_score)` is the single gate metric

Higher is better. A skill that makes outputs worse produces a negative delta — immediate red flag. A skill that has no effect produces ~0 — drives the aggregate down, signaling useless skills.

### Why this satisfies the autoresearch pattern

- **Behavioral:** measures actual Claude outputs, not the skill's text
- **Un-gameable structurally:** the experimenter can make the skill look as directive/imperative/bulleted as it wants — the metric only cares whether the skill helps Claude solve the task
- **Single number at the gate layer** (even though computed per-skill)
- **Pinned eval harness:** fixtures go in a read-only location (`benchmark/skill-fixtures/`) treated as sacred like karpathy's `prepare.py`

### What to fixture

Each skill needs a minimal fixture. Examples:

| Skill | Fixture task | Success criterion |
|---|---|---|
| `skills/diagnose` | "Given a failing test output, identify the root cause" (fed fixed output) | Output contains specific root-cause string |
| `skills/idea-matrix` | "Score 3 options for X" (fed fixed problem) | Output contains 9 valid cell JSON objects |
| `skills/cleanup` | "Clean up the test worktrees" (fed fixed git state) | Worktree count reduced to 0 |
| `skills/run` | "Run 1 experiment on theme X" | `experiments.tsv` has 1 new row, verdict is one of {keep, neutral, regress, gate_fail} |

Not every skill needs a fixture on day one. Start with the high-value ones — skills actually modified in recent experiments.

### Cost control (the reason this was removed before)

The previous behavioral benchmarks (`ar-effectiveness.sh`, `matrix-effectiveness.sh`) were removed in 2026-03-30 because they spawned claude CLI sessions per experiment → minutes per run, burned token pools, broke Haiku grinds. We must not repeat that.

Mitigations:

1. **Run 1x per session, not per experiment.** Use the `run_frequency: session` field (new — add to `evaluate-config.json` schema).
2. **Only fixture changed skills.** If experiment N only touched `skills/cleanup/SKILL.md`, run only the cleanup fixture, not all 25.
3. **Cache baseline outputs.** Rerun baseline only when epoch baseline refreshes, not per experiment. The (task, no-skill) output is a fixed reference.
4. **Budget cap:** max 2 fixture invocations per experiment. Hard ceiling.
5. **Haiku by default for the fixture runs.** Sonnet only if signal is ambiguous.
6. **Deterministic success criteria.** Avoid LLM-judge loops. The success criterion is a regex or a shell command checking artifact state, not another LLM call.

### Schema changes

Add to `autoimprove.yaml` benchmarks:

```yaml
  - name: skill-behavioral
    type: llm-judge
    run_frequency: session   # NEW: "experiment" | "session"
    command: bash benchmark/skill-behavioral.sh
    metrics:
      - name: skill_behavioral_score
        extract: "json:.skill_behavioral_score"
        direction: higher_is_better
        tolerance: 0.05
        significance: 0.05
```

Add to `scripts/evaluate.sh` benchmark runner:

- Read `run_frequency` field; if "session" and experiment is not first of session, skip and use last cached result
- Add `benchmark/skill-fixtures/` to the sacred path list (human-edit-only)
- Integrate with budget-check skill to abort if weekly budget < 40%

Add new files:

- `benchmark/skill-behavioral.sh` — orchestrator for the fixture loop
- `benchmark/skill-fixtures/<skill-name>.yaml` — one per fixtured skill
- `benchmark/skill-fixtures/README.md` — fixture authoring guide (human-facing)

### Fixture schema

```yaml
# benchmark/skill-fixtures/diagnose.yaml
skill: skills/diagnose
task_prompt: |
  You are debugging a failing test. Here is the output:
  <FIXED TEST OUTPUT>
  Identify the root cause in one sentence.
success_criterion:
  type: regex
  pattern: "(race condition|missing lock|null deref)"
baseline_model: haiku
treatment_model: haiku
timeout_seconds: 60
```

### Pilot plan

Phase 1 (~2 days): implement `skill-behavioral.sh` + fixture schema + 3 pilot fixtures (diagnose, cleanup, idea-matrix). Run manually, not wired to grind loop. Validate that the same skill scored across 5 runs produces consistent results.

Phase 2 (~1 day): wire into `evaluate.sh` as a session-level benchmark. Integrate with budget-check. Run in shadow mode (computed but not gating) for 3 sessions to collect calibration data.

Phase 3 (~1 day): promote to gate. Tighten tolerance based on pilot variance.

Phase 4 (ongoing): add fixtures for more skills as they become grind targets.

## Open questions

1. **Determinism.** Even with temperature=0, Claude outputs vary slightly. Does single-run-per-fixture produce stable scores, or do we need N=3 and take median? Pilot will tell.

2. **Baseline drift.** If we update the baseline_model between sessions, baseline outputs shift, which shifts the delta. Should baseline be pinned to a specific model version for the lifetime of a fixture? Probably yes.

3. **Negative deltas.** What if removing a skill IMPROVES Claude's output on some task? That's a real outcome worth surfacing — not a bug, a signal that the skill is net-harmful.

4. **Fixture rot.** If a skill evolves, does its fixture still measure the right thing? Fixtures need versioning and explicit review cadence.

5. **What about agents and commands?** The same pattern applies. Scope Phase 1-3 to skills only, extend to agents/commands later.

## What this replaces

After Phase 3, delete these metrics from `autoimprove.yaml`:
- `trigger_precision` (the last structural prompt-quality metric — even the "right-pointing" one is still structural)
- `skill_doc_coverage` (already broken per session 25 debug, returns 0 due to BSD grep)
- `agent_completeness` (structural, untested against gold standard)

Keep:
- `test_count`, `broken_constraints`, `broken_refs` — these ARE behavioral-ish (test suite state)
- `revert_rate`, `bug_escape_rate`, `ar_severity_trend`, `fix_durability` — reliability metrics, domain-appropriate

## References

- `~/Developer/autoresearch/program.md` lines 28-37, 100-109 — karpathy's eval + anti-gaming philosophy
- `~/Developer/autoresearch/prepare.py` lines 344-365 — `evaluate_bpb` implementation
- MAGI note `patterns/autoresearch_behavioral_vs_structural_metrics.md` — the investigation that produced this design
- MAGI note `patterns/imperative_ratio_empirical_anti_quality.md` — the empirical failure that triggered the investigation
- MAGI note `decisions/imperative_ratio_fix_decision.md` — the idea-matrix trail
- Commit `1a0bf5e fix(config): remove imperative_ratio metric` — the first delete
- Commit `40c42b2 Revert "fix(experimenter): codify skill_quality directive-ratio pattern"` — the companion revert

## Status & next actions

This document is the `val_bpb` analog DESIGN. Implementation is not started. Before implementing:

1. Pedro approval on the overall direction
2. Decide which skills get fixtures in Phase 1
3. Decide whether the existing `benchmark/ar-effectiveness.sh` / `matrix-effectiveness.sh` can be repurposed as pilot fixtures (they're still in the repo)
4. Sketch success criteria for the pilot fixtures to avoid LLM-judge-in-the-loop
