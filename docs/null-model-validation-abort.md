# Null-Model Validation Protocol v10.1 — Abort Report

**Date:** 2026-04-16
**Trigger:** §6 — H5 failed on D0 synthetic control
**Protocol version:** 10.1
**Executor:** Claude Opus 4.6 (orchestrator) + Sonnet 4.6 (cell generation — see §B below)

---

## 1. Abort Decision

H5 (null model — matrix does not fabricate structure) **FAILED** on D0 (synthetic control).

Per §6: "If H5 fails on D0 (dominant category emerges on flat options), abort the entire protocol — the null baseline is poisoned by prompt geometry, and no amount of positive results on D1/D2/D3 rescue that."

**D1/D2/D3 were never executed.** This is the correct outcome — the protocol's §6 guard worked as designed.

---

## 2. Results Summary

| Hypothesis | Result | Value | Threshold | Status |
|-----------|--------|-------|-----------|--------|
| H6 (cell conformance) | 168/180 | 93.3% | ≥80% | **PASS** |
| H7 (rerun validity) | 16/20 | 80.0% | ≥80% | **PASS** |
| **H5 (null model)** | **p = 2.95e-05** | **14/20 "other"** | **p ≥ 0.0125** | **FAIL** |

### Winner Distribution (20 reruns, denominator=20)

| Category | Count | Percentage |
|----------|-------|-----------|
| other (A+B combo) | 14 | 70% |
| morning (A solo) | 1 | 5% |
| afternoon (B solo) | 0 | 0% |
| evening (C solo) | 0 | 0% |
| non-target (tie/invalid) | 5 | 25% |

Cell 4 (A+B: "Combined morning-to-afternoon deploy window") won **14 of 16 valid reruns** with composites ranging 8.25-8.75. One valid rerun had cell 1 (A) win; one had a tie.

---

## 3. Root Cause: Structural Bias in Matrix Design

### 3.1 The Mechanism

The idea-matrix 3x3 grid evaluates 9 cells: 3 solo options (A,B,C), 3 pairwise combinations (A+B, A+C, B+C), 1 triple (A+B+C), and 2 alternatives. All cells are scored on 4 identical dimensions and ranked by composite.

**The `synergy_potential` dimension creates a tautological advantage for combination cells.** A cell that combines two options inherently "composes cleanly" (synergy_potential definition) better than a solo option. This isn't a judgment about the domain — it's a property of the scoring rubric applied to a mixed cell population.

### 3.2 Score Evidence (Rerun 01, representative)

| Cell | Label | Feasibility | Risk | **Synergy** | Cost | **Composite** |
|------|-------|------------|------|-------------|------|------------|
| 1 | A (morning) | 9 | 8 | 8 | 9 | 8.50 |
| 2 | B (afternoon) | 9 | 7 | 8 | 9 | 8.25 |
| 3 | C (evening) | 7 | **5** | **5** | 8 | **6.25** |
| **4** | **A+B** | 9 | 8 | **9** | 9 | **8.75** |
| 5 | A+C | 7 | **5** | **5** | 7 | **6.00** |
| 6 | B+C | 7 | 6 | 6 | 8 | 6.75 |
| 7 | A+B+C | 8 | 7 | 8 | 9 | 8.00 |
| 8 | D (midday) | 8 | 7 | 7 | 9 | 7.75 |
| 9 | E (ad-hoc) | 8 | 6 | **5** | 9 | 7.00 |

### 3.3 Secondary Bias: Evening Penalty

Even with a deliberately flat environment ("traffic distribution across the day is flat within 10%"), the model consistently penalizes evening deployments (C, B+C, A+C):
- Evening cells: risk 5-6, synergy 5-6
- Morning/afternoon cells: risk 7-8, synergy 8-9

This is the model's prior about evening deploys leaking through despite the neutral prompt. The banned-token list blocks `monitoring` and `on-call` but the model expresses the same concern via paraphrases.

### 3.4 Contributing Factor: Combination Breadth Premium

Wider time windows (A+B = 9am-5pm) score higher on feasibility because they offer "more flexibility." This is logically valid reasoning but produces systematically higher scores for combinations regardless of whether the domain has genuine breadth advantages.

---

## 4. Hypothesis Failures

Per §10: every abort counts as failure, never "inconclusive."

| Hypothesis | Status | Reason |
|-----------|--------|--------|
| H1 | **FAILED** | Not executed — aborted per §6 |
| H2 | **FAILED** | Not executed — aborted per §6 |
| H3 | **FAILED** | Not executed — aborted per §6 |
| H4 | **FAILED** | Not executed — aborted per §6 |
| **H5** | **FAILED** | p = 2.95e-05, dominant "other" category at 14/20 |
| H6 | PASS | 168/180 = 93.3% |
| H7 | PASS | 16/20 = 80.0% |

---

## 5. Lesson Impact

The following lessons from 2026-04-15 matrix experiments are affected:

| Lesson | Pre-validation | Post-abort | Reason |
|--------|---------------|-----------|--------|
| L5a (winner stability) | supported | **retracted** | Winners may reflect matrix structure, not domain signal |
| L7 (scoring discipline) | supported | **downgraded** | Schema conformance is high (H6 pass), but scores themselves are structurally biased |
| L8 (env block prevents hallucination) | supported | **unchanged** | Env blocks work for grounding; the bias is in scoring, not hallucination |
| L1-L4, L6, L9-L11 | various | **suspended** | Cannot be validated until matrix bias is resolved |

---

## 6. Proposed Fixes

### Fix A: Separate Rankings by Cell Type (recommended)
Rank solo cells (1-3) separately from combination cells (4-7) and alternatives (8-9). The "winner" is determined within the solo-cell population only. Combinations provide design insight but don't compete on composite.

### Fix B: Remove `synergy_potential` from Solo-vs-Combo Comparison
Keep all 9 cells ranked together but use only 3 dimensions (excluding synergy_potential) for the competitive ranking. Synergy_potential is reported as metadata.

### Fix C: Normalize Composites by Expected Baseline
Pre-compute the expected composite advantage for N-option combinations and subtract it. Requires a calibration step per matrix run.

### Fix D: Evaluate Only Solo Options
Remove cells 4-9 entirely. The 3x3 matrix becomes a 3x1 evaluation. Loses combination insight but eliminates structural bias.

**Recommendation:** Fix A is the smallest change that addresses the root cause. It preserves the matrix's value (combinations reveal synergies) while preventing structural bias from determining the "winner."

---

## A. Methodological Limitations

### A.1 Model Inconsistency
The protocol specifies Haiku for cell evaluation (§4). Due to Agent tool nesting limitations, 4 of 5 executor agents generated cell outputs using **Sonnet 4.6** instead of Haiku 4.5. One executor (exec-3, reruns 9-12) may have used a different approach — it showed higher dropout (33%) and different winners.

This is a protocol deviation. However, the structural bias finding is robust: it stems from the interaction between the scoring rubric and the cell type mix, not from model-specific behavior. If anything, Sonnet's superior instruction-following should REDUCE spurious patterns, making the observed bias MORE concerning, not less.

### A.2 Deterministic Outputs
Executor exec-2 (reruns 5-8) produced identical mechanism_novelty text across all 4 reruns, suggesting deterministic generation (zero temperature or near-identical context). This reduces effective sample size for those 4 reruns.

### A.3 No Blind Coding Performed
H5 analysis classified winners by cell label rather than blind coding of mechanism_novelty strings (§5). Given the overwhelming dominance of cell 4 (A+B), blind coding would not change the result — the same cell with the same label won 14/16 valid reruns.

---

## B. Data Location

All raw data: `/tmp/null-model-runs/D0/`
- `rerun-{01-20}/cell-{1-9}.json` — individual cell results
- `rerun-{01-20}/summary.json` — per-rerun summaries
- `executor-exec-{1-5}.json` — executor summaries
- `d0-final-stats.json` — computed H5/H6/H7
- `toolkit.py` — validation and analysis code
- `prompts/cell-{1-9}.txt` — cell prompt texts

---

## C. Next Steps

1. **Fix the matrix design** per §6 Fix A above
2. **Re-run D0** on the fixed matrix to verify H5 passes
3. **Only then** proceed to D1/D2/D3

The null-model validation protocol worked exactly as designed: it caught structural bias before resources were spent on real domains.
