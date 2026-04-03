# Research: Goodhart-Safe Model Routing Optimization

**Date:** 2026-04-03  
**Issue:** #55  
**Method:** idea-matrix (3x3, 9 Haiku explorers)  
**Status:** complete — recommendation ready

---

## Problem

How to allow the autoimprove grind loop to optimize its own model routing (Haiku vs Sonnet per step) without Goodhart risk — where the experimenter games the cost metric instead of improving quality.

**Hard constraints:**
1. Experimenter must remain blind to benchmark scores and cost metrics
2. Quality gate (tests must pass) is non-negotiable
3. Routing changes must be measurable and reversible

---

## Options Evaluated

| Label | Description |
|-------|-------------|
| A | Post-facto cost: measured by orchestrator after quality gate, never in experimenter prompt |
| B | Config-level routing: immutable per-session, adjusted by meta-loop between sessions |
| C | Quality-gate-first: two-phase eval — quality first, cost observed second (non-scoreable) |
| A+B | Post-facto + config routing combined |
| A+C | Post-facto + quality-gate-first (evidence collection only) |
| B+C | Config routing + quality-gate-first with inter-session adjustment |
| A+B+C | Full stack: all three layers + human-approval meta-loop |
| Alt1 | Blind A/B: twin sessions with different models, orchestrator compares |
| Alt2 | Static heuristic routing: human-authored rules from #53 spike data, no optimization |

---

## Scores

| Cell | Feasibility | Goodhart Safety | Measurement | Adoptability | Risk | Avg |
|------|-------------|-----------------|-------------|--------------|------|-----|
| A | 5 | 5 | 3 | 5 | 5 | 4.6 |
| B | 4 | 5 | 3 | 4 | 5 | 4.2 |
| **C** | **5** | **5** | **4** | **5** | **5** | **4.8** |
| A+B | 4 | 5 | 4 | 4 | 4 | 4.2 |
| A+C | 5 | 5 | 3 | 5 | 5 | 4.6 |
| B+C | 4 | 5 | 4 | 4 | 5 | 4.4 |
| A+B+C | 3 | 5 | 5 | 2 | 4 | 3.8 |
| Alt1 | 4 | 5 | 4 | 3 | 4 | 4.0 |
| **Alt2** | **5** | **5** | **4** | **5** | **5** | **4.8** |

---

## Recommendation

**Winner: Alt2 + C** (implement in two steps)

### Step 1 — Alt2: Static heuristic routing (immediate, after #53 spike)

Apply a fixed human-authored routing config based on #53 spike data:

```yaml
budget:
  experimenter_model: sonnet       # experimenter requires judgment — keep Sonnet
  step_models:
    harvest: haiku                 # short, well-defined, no judgment needed
    theme_selection: haiku         # weighted_random — deterministic logic
    benchmark_eval: haiku          # parsing JSON output, no judgment
```

No optimization loop. No Goodhart risk. Cost savings come from the one-time spike data, not from ongoing auto-tuning. **Infrastructure already exists** — `experimenter_model` was added in #53.

### Step 2 — C: Quality-gate-first cost observation (non-scoreable)

After quality gate passes, log `model_cost` as a non-scoreable observation in `experiments.tsv`. This builds an evidence base for future routing decisions without creating any optimization pressure on the experimenter.

Add to experiments.tsv schema:
```
experiment_id  theme  verdict  model  tokens_used  ...
```

The `tokens_used` field is logged by the orchestrator post-hoc and never fed into scoring or theme weights.

---

## Why not A+B+C?

A+B+C scored 3.8 (lowest feasible). The human-approval meta-loop adds significant complexity and the weekly cadence means routing improvements lag experiments. The static heuristic (Alt2) gives ~60% of the cost savings at ~10% of the implementation complexity.

## Why not Alt1 (blind A/B)?

High measurement quality but doubles cost during the trust-building phase — exactly when Haiku quality gaps matter most. The #53 spike provides equivalent baseline data at lower cost.

## Key Insights

- **Alt2 (static):** "Static heuristic routing eliminates the Goodhart problem entirely by removing the optimization loop — the system cannot game metrics it never measures."
- **C:** "Decoupling cost as a non-scoreable observation is the only architecture that structurally prevents Goodhart gaming — the experimenter cannot optimize toward an invisible signal."
- **A+B+C:** "The human-approval gate is the critical trust anchor — but the weekly cadence means routing improvements lag experiments by at least one full session."

---

## Next Steps

1. Run #53 spike (set `experimenter_model: haiku` in autoimprove.yaml, run 1 grind session, measure keep rate)
2. If keep rate ≥60%: apply Alt2 static heuristic config permanently
3. Add `tokens_used` column to experiments.tsv schema (C step)
4. After 20+ experiments with cost data: reassess whether a meta-loop is warranted
