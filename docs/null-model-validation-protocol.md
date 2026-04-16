# Null-Model Validation of Idea-Matrix — Preregistered Protocol

**Version:** 2.0 (2026-04-16)
**Status:** awaiting execution (budget-gated to post-reset)
**Budget estimate:** ~$6, 3-5h
**Previous version:** v1 (2026-04-16 morning, commit c6245ad) was rejected in Codex round-3 adversarial review for: inconsistency between §1 and §7 pass/fail definitions; arbitrary 9/12 threshold without power analysis; D0 not integrated in execution schema; categories not genuinely mutually exclusive; banned tokens purely lexical; kappa 0.6 plus correlated judges masking co-error as agreement; analysis-choice open to p-hacking; abort conditions acting as escape hatch.

v2 addresses all eight criticisms. Changes summarized in §11.

**Motivation:** Codex round-2 adversarial review identified "absence of null model" as the single strongest objection to the 11 lessons from 2026-04-15 matrix experiments. Without a calibrated baseline of how often prompts of this shape converge on "hook-based", "passive-pull", or "neutral cluster" patterns by geometry alone, ≥50% of L5–L11 could be artifact rather than signal extracted by the matrix.

This document preregisters the design BEFORE execution. Any deviation during the run must be logged as a protocol amendment, not silently corrected.

---

## 1. Hypotheses Under Test

Every hypothesis has (a) a single pre-committed statistical test and (b) a single pre-committed threshold. §7 below mirrors these definitions literally — no alternative interpretations are permitted at analysis time.

**H1 (L5a validity):** For a given problem domain, the mechanism-category of the matrix winner is stable across neutrally-framed reruns.
- **Test:** For each domain, count how many of the 20 reruns produce a winner whose `mechanism_novelty` string is blind-classified into the same *single* category that is itself pre-registered as that domain's "prediction target" (see §2).
- **Threshold:** Pass if count ≥ 14/20 in the pre-registered target category for ≥2 of 3 real domains (D1, D2, D3). "Modal category" is NOT used — only the pre-registered target. This prevents post-hoc category selection.
- **Applies to:** L5a ("winner-by-mechanism-category = ship").

**H2 (inter-model independence):** Sonnet and Opus identify the same winning cell as Haiku, under the same blind neutral prompt.
- **Test:** For each of the 3 real domains, take the Haiku modal winner cell (most frequent winner across 20 reruns). Dispatch the same cell's neutral prompt to Sonnet and Opus, 5 reruns each. For each model, count how many of the 5 reruns return a cell score ≥ the Haiku modal winner's mean composite.
- **Threshold:** Pass if Sonnet ≥3/5 AND Opus ≥3/5 for ≥2 of 3 real domains.
- **Applies to:** L3 ("cross-model check").

**H3 (mechanism category is not uniform):** The empirical distribution of blind-classified winning categories across 20 reruns per domain is not consistent with uniform draw from the 4-category space.
- **Test:** Exact binomial test on the target category's frequency vs the null p₀=0.25. One test per real domain.
- **Threshold:** Pass if p-value < 0.0125 (Bonferroni-corrected for 4 tests: H3 on D1, D2, D3, D0) for ≥2 of 3 real domains.
- **Applies to:** L5a, L10 ("neutral cluster is signal").

**H4 (post-matrix falsification discriminates):** Running the L11 neutral-falsification step on the modal winners of the 3 real domains produces a non-degenerate verdict distribution.
- **Test:** Classify each of the 3 L11 falsification verdicts as {strong, framing_dependent, falsified}. Count frequencies.
- **Threshold:** Pass if no single verdict accounts for all 3 outcomes. (With n=3 domains this is coarse — it only detects complete degeneracy.)
- **Applies to:** L11 ("post-matrix falsification is mandatory").
- **Honesty note:** H4 is severely underpowered. It detects only full collapse, not distributional shape. Accept as "sanity check" not "validation".

**H5 (null — the matrix does not fabricate structure from prompt geometry):** On the synthetic flat domain D0 where options are genuinely interchangeable, the matrix should NOT produce a dominant winner category.
- **Test:** Exact binomial test on D0's target category frequency vs p₀=0.25.
- **Threshold:** Pass if p-value ≥ 0.0125 (i.e., we FAIL to reject uniformity — uniformity is the desired outcome on D0). If p < 0.0125 on D0, H5 is falsified and the entire protocol's positive results on D1/D2/D3 lose their standing.
- **Applies to:** meta-critique (Codex Q4).

### Power Analysis (Justifying n=20 and threshold 14/20)

Under H0 (uniform 4-category draw, p=0.25), probability of ≥14/20 in the target category is 0.00014. Bonferroni-corrected for 4 categories by union bound: ~5.5e-4. Well below α=0.01.

Under H1 with true p=0.70 (modest effect size), power ≈ 0.58. Under p=0.85, power ≈ 0.93. The protocol is therefore well-powered to detect strong effects and moderately-powered for modest effects. **Honest limitation:** a negative result (count<14/20) is consistent with both no-effect AND modest-effect-that-we-missed. A positive result excludes no-effect with >99% confidence. This asymmetry is documented and accepted.

---

## 2. Domains (3 real + 1 synthetic control, 4 total)

Domains chosen to span different answer manifolds. Each domain specifies:
- the 3 options presented to the matrix,
- the 4 pre-registered mechanism categories (hierarchical, MEE by design — see §2.1),
- the **target category** (one of the 4) that we predict the matrix will select as winner,
- the banned tokens (lexical floor; conceptual ceiling addressed in §3).

### 2.1 MEE Category Design Principle

v1 categories overlapped (Redis on disk fits both `network-shared` and `persistent-disk`). v2 taxonomizes each domain by a **single primary axis**, making categories a partition rather than a tagset. If a string could plausibly fit two categories under v1, it falls into exactly one under v2 because we force a single axis of differentiation.

### Domain D1: Caching strategy for a read-heavy web service

**Options:**
- A: In-process LRU cache per instance
- B: Shared Redis cluster
- C: Read-replica database with connection pooling

**Axis:** *Where does the authoritative read-path state live?* (MEE by construction — one answer per architecture)
- `in-process-private` — serving process holds its own copy, no coordination (A)
- `out-of-process-shared` — separate coordinating process, networked (B)
- `source-replica` — read-path state is a replica of the system of record (C)
- `recompute-on-demand` — no dedicated cached state; compute each time

**Target category (pre-registered prediction):** `out-of-process-shared` (B). Based on conventional wisdom for read-heavy services; if matrix reproduces this, signal exists.

**Banned tokens (lexical floor):**
`redis`, `memcached`, `lru`, `cdn`, `cache`, `ttl`, `eviction`, `invalidation`, `hazelcast`, `ignite`, any product names.

### Domain D2: Schema migration on a 50M-row production table

**Options:**
- A: In-place `ALTER TABLE` with lock
- B: Shadow table + atomic rename
- C: Dual-write to old and new columns with async backfill

**Axis:** *At what moment does the new state become authoritative?*
- `instant-cutover` — single atomic moment (A and B share this pattern at different layers, so we refine: B's cutover is the rename, A's is the ALTER completion)
- Refined axis: *Does the migration hold a write lock during its runtime?*
- `lock-and-mutate` — holds lock, mutates in place (A)
- `parallel-build-then-swap` — builds new state parallel, swaps atomically (B)
- `incremental-reconcile` — writes flow to both, reconcile asynchronously (C)
- `rebuild-from-log` — no lock, no swap; replay event log to derive new schema

**Target category:** `parallel-build-then-swap` (B). Conventional wisdom for production migrations.

**Banned tokens:**
`flyway`, `liquibase`, `alembic`, `gh-ost`, `pt-online-schema-change`, `rails migration`, `django migration`, any tool names.

### Domain D3: Retry strategy for flaky external API

**Options:**
- A: Exponential backoff with jitter
- B: Circuit breaker with half-open probe
- C: Dead-letter queue with manual replay

**Axis:** *What information drives the retry decision?*
- `time-only` — retry timing is a function of attempt count and fixed backoff (A)
- `failure-rate-state` — retry behavior adapts based on recent failure observations (B)
- `deferred-delegation` — the decision is handed off to a later actor (C)
- `parallel-fallback` — multiple targets attempted concurrently, first success wins

**Target category:** `failure-rate-state` (B). Conventional wisdom for systemic protection against flaky dependencies.

**Banned tokens:**
`tenacity`, `retry`, `backoff`, `circuit`, `hystrix`, `resilience4j`, `polly`, `jitter`, any library names.

### Domain D0 (synthetic control): Deploy window choice

**Options:**
- A: Deploy on weekday mornings
- B: Deploy on weekday afternoons
- C: Deploy on weekday evenings

**Axis (pre-registered for completeness, though we predict no signal):** *Time-of-day category.*
- `morning`
- `afternoon`
- `evening`
- `other` (night/weekend/never, covering contrarian remix)

**Target category:** NONE — D0 is the null control. We predict uniform distribution. H5 passes when D0 shows no dominant category.

**Banned tokens:** `standup`, `lunch`, `traffic`, `on-call`, `monitoring`, `rollback`. (These are framing nudges; if the matrix uses them to discriminate, we'd rather not know — we want to force a genuinely flat choice.)

---

## 3. Neutral Prompt Construction

Each cell prompt is derived from a template, with domain-specific option descriptions. Neutrality is enforced at two levels:

**Lexical (automated):** regex scan the final prompt text for banned tokens. Any hit = protocol violation, rebuild prompt from template.

**Conceptual (manual):** after lexical scan passes, a human-in-the-loop (Pedro) reads the 12 cell prompts per domain before dispatch and approves or rejects based on whether the prompt leaks the answer via paraphrase. If Pedro rejects, rebuild. This gate exists because purely lexical bans are defeat-able by trivial rephrasing ("in-memory key-value store" for Redis) — only human judgment catches conceptual leakage.

**Cost of manual gate:** ~5 minutes per domain (60 prompts total across D0-D3 × 9 cells, but cells share a shared context block so Pedro reviews ~12 unique prompt bodies total). Acceptable.

**Cell template (Haiku version):**
```
CRITICAL: Do NOT invoke any tools. Answer only from this prompt. Return JSON immediately.

You are scoring a design option for the following problem.

## Problem
{PROBLEM}

## Option Under Evaluation
{OPTION_DESCRIPTION}

## All Options Under Consideration
A: {A_description}
B: {B_description}
C: {C_description}

## SCORING CONVENTION (MANDATORY — HIGHER=BETTER on all dimensions)
- feasibility: 1 showstopper → 10 trivial to build
- risk: 1 highest risk → 10 lowest risk / most robust
- synergy_potential: 1 incompatible → 10 composes cleanly
- implementation_cost: 1 days of work → 10 minutes

## Output (JSON only)
{
  "cell": {N},
  "label": "{LABEL}",
  "risk_direction_used": "higher_safer",
  "scores": {"feasibility": N, "risk": N, "synergy_potential": N, "implementation_cost": N},
  "composite": <avg of 4>,
  "mechanism_novelty": "<one sentence naming what THIS option does that others do not; no banned terms; no hedged or multi-category answers — commit to one>",
  "dealbreaker": null or "<one sentence>"
}
```

*Cell 8 (remix)* addendum: `Propose a hybrid. Describe its mechanism in one sentence using new vocabulary — do NOT reference options A/B/C by name.`

*Cell 9 (contrarian)* addendum: `Propose a fundamentally different approach. Describe its mechanism in one sentence; the mechanism must NOT belong to the same family as any of A/B/C.`

---

## 4. Execution Plan (v2 — Integrated D0)

**Per domain × 4 domains (D0, D1, D2, D3):**
- 20 Haiku reruns, `allowed-tools: []`, temperature default.

**Plus for H2 only (3 real domains):**
- 5 Sonnet reruns of the Haiku modal winner cell.
- 5 Opus reruns of the same cell.

**Total dispatches:**
- 4 × 20 × 9 = 720 Haiku cell-level dispatches.
- 3 × 2 × 5 = 30 Sonnet+Opus cell-level dispatches.
- Plus blind-coding judges (§5): ~3 dispatches per domain × 4 domains = 12.
- Grand total: ~762 dispatches.

**Parallelism:** up to 9 parallel per batch. Execution is batched per-rerun (9 cells in parallel), 20 reruns per domain. Full pipeline: ~20 min per domain via parallelism. 4 domains: ~90 min wall clock. Add Sonnet/Opus and coding: +30 min.

**Budget estimate:** Haiku ~$0.002/call × 720 = $1.44. Sonnet+Opus ~$0.02 × 30 = $0.60. Coding ~$0.30. Total ~$2.40. Add 2× buffer: **$5-6**.

**Output schema:** every rerun writes to `/tmp/null-model-runs/<DOMAIN>/rerun-XX.json`. (Runs NOT committed to repo — volume; analysis summary IS committed.)

---

## 5. Blind Coding (Mechanism Category Classification, v2)

Addresses Codex critique: kappa 0.6 with correlated model judges masks co-error. v2 strengthens three ways:

1. **Higher kappa threshold:** require Cohen's kappa ≥ 0.75 between the two model judges. 0.6 is lenient for a protocol meant to retract lessons; 0.75 is the "substantial agreement" threshold in Landis-Koch.

2. **Third judge is HUMAN, not model:** disagreements between Haiku and Sonnet judges are resolved by Pedro, not Opus. This breaks the model-family correlation chain. Human adjudication cost: ~15 min of Pedro time for ~80 disagreements (worst case, if kappa=0.75 exactly).

3. **Explicit co-error acknowledgment:** the REPORT produced in §9 must include a section comparing human-only adjudications against model consensus. If on sampled subset the human disagrees with both judges >15% of the time, kappa between judges is co-error, not signal, and the corresponding H-result is downgraded to "model-correlated coding; human validation required for confidence".

**Procedure:**
1. Extract every `winner_mechanism_novelty` string → `coding-input.tsv`, columns `coding_id | text`. No rerun_id, no model, no cell.
2. Shuffle rows.
3. Dispatch Haiku judge and Sonnet judge with identical shuffled input and the category taxonomy for that domain (including `other`).
4. Compute Cohen's kappa.
5. **If kappa < 0.75:** domain fails its H1/H3 test. Record as failure, not as "dropped" — this is the v2 fix for "aborted = silent pass".
6. For rows where Haiku and Sonnet disagree: Pedro adjudicates. Time-budget 15 min. If unable to complete, remaining disagreements are marked `other` (conservative — reduces H1 pass rate, never inflates it).
7. Write resolved classifications back to each rerun record.

---

## 6. Synthetic Control (H5) — Integrated into Execution Plan

v1 treated D0 as optional add-on. v2 runs D0 **first**, before D1-D3, with identical schema and identical blind-coding pipeline. If H5 fails (D0 shows dominant category), abort the entire protocol — no point running D1-D3 if the null baseline is already poisoned by prompt geometry.

D0 categories pre-registered in §2. D0 banned tokens pre-registered in §2.

---

## 7. Analysis (Mirrors §1 Exactly)

Analysis code in `/tmp/null-model-runs/analyze.py`, written AFTER all reruns complete. Pre-committed decision rules:

- **H1:** for each of D1, D2, D3 (not D0), compute `target_count = count(rerun where blind_classified_category == pre_registered_target)`. Pass H1 if `target_count ≥ 14` for at least 2 of the 3 domains. (Exact language from §1.)

- **H2:** for each of D1, D2, D3, identify the Haiku modal winner cell. Count Sonnet reruns with composite ≥ Haiku-mean and Opus reruns with composite ≥ Haiku-mean (n=5 each). Pass if both counts ≥ 3/5 for at least 2 of the 3 domains. (Exact from §1.)

- **H3:** for each of D1, D2, D3, run scipy.stats.binom_test(target_count, 20, 0.25, alternative='greater'). Pass if p < 0.0125 for at least 2 of 3 domains. (Exact from §1. Test is binomial, not chi-sq, and is fixed here — no choice at analysis time.)

- **H4:** run post-matrix falsification on the modal winner of each of D1, D2, D3. Classify the 3 verdicts. Pass if no single verdict type is all 3. (Exact from §1.)

- **H5:** run `scipy.stats.binom_test(d0_target_count, 20, 0.25, alternative='greater')` where `d0_target_count` is the most frequent category on D0. Pass if p ≥ 0.0125. (Exact from §1.)

**Any deviation from these exact rules is a protocol violation.** The analysis script must be < 100 lines and contain zero free choices.

---

## 8. Protocol Amendments

Any change after execution start requires:
1. Dated "Amendment" section below.
2. Explicit justification.
3. Note which hypotheses the change affects.
4. Amendment counts as failure for any hypothesis where the amendment relaxes a threshold or substitutes a test. This blocks "move-the-goalposts" amendments.

No amendments yet (v2 is still pre-execution).

---

## 9. Expected Deliverable

After execution, produce `docs/null-model-validation-report.md`:

- H1/H2/H3/H4/H5 pass/fail table with exact numbers.
- Per-lesson decision: which of L1–L11 are supported, downgraded, or retracted based on which hypotheses passed.
- Co-error check (§5.3): human-vs-model-consensus disagreement rate on sampled subset; downgrade affected H-results if rate > 15%.
- Updated idea-matrix skill PR (if any) linked for re-review.
- Codex round-4 adversarial review invitation — give Codex the full data and let it challenge.

Budget for report + codex round 4: ~$1 extra.

---

## 10. Abort Conditions (v2 — Abort = Failure, Not Escape)

The protocol aborts mid-run on:
- Total cumulative cost exceeds 2× the $6 budget estimate.
- Banned-token scan trips more than once per domain after 2 rebuild attempts (signals the prompt space is not neutralizable for this domain).
- Kappa between model judges < 0.75 for a given domain (explicit failure per §5.5).
- Pedro rejects conceptual-leakage review (§3) and cannot construct an acceptable neutral prompt.

**v2 rule:** every abort counts as **failure of the hypothesis that was being tested**. Aborts are never "inconclusive" or "dropped" — they count against the relevant H. This removes the v1 escape hatch where "aborted" masked a genuine null result.

On abort, write `docs/null-model-validation-abort.md` with: trigger, partial data, explicit statement of which hypotheses now fail, and which lessons are consequently retracted/downgraded.

---

## 11. Changelog (v1 → v2)

Addresses each of the 8 Codex round-3 critiques explicitly:

| # | v1 flaw | v2 fix |
|---|---------|--------|
| 1 | §1 and §7 disagreed on H1/H2/H4 thresholds | §7 now mirrors §1 literally; single test per hypothesis |
| 2 | 9/12 threshold unjustified | §1 power analysis block; n=20 threshold 14/20 with honest power quotes |
| 3 | D0 not in execution schema, no categories | §6 D0 runs first; §2 D0 categories pre-registered |
| 4 | Categories not MEE (e.g., Redis-on-disk fits 2) | §2.1 single-axis principle; categories rewritten as partitions |
| 5 | Banned tokens purely lexical | §3 adds human conceptual-leakage gate on top of lexical scan |
| 6 | Kappa 0.6 + two model judges = co-error | §5 kappa ≥ 0.75; human as 3rd judge; co-error check in report |
| 7 | "chi-sq OR exact multinomial" = post-hoc choice | §7 single test per H (exact binomial everywhere); script <100 lines |
| 8 | Abort = inconclusive escape hatch | §10 abort = hypothesis failure; §8 amendments lowering rigor count as fail |

v1 was stronger than nothing; v2 is the minimum defensible protocol given Codex's critique. v3 would require genuinely independent judges (external human coders, not Pedro alone) and n≥30 per domain for power ≥ 0.7 on modest effects — out of current budget.
