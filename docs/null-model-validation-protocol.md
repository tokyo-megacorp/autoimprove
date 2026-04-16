# Null-Model Validation of Idea-Matrix — Preregistered Protocol

**Version:** 9.0 (2026-04-16)
**Status:** awaiting execution (budget-gated to post-reset)
**Budget estimate:** ~$8-9, 3-5h
**Previous versions:**
- v1-v7 (commits c6245ad, c9ffd33, 25b35e4, 478e861, 41b5035, af6fd4a, c9285d8) — see §11.
- v8 (commit 1245903) — addressed round-8. Codex round-9 then identified two remaining high-severity issues: (a) §3.1's "any drop in 3-grid → H2 auto-fail" sentence still conflicted with §1/§7's "drop invalidated reruns from list, fail only if empty or no unique mode" — same data could pass under §§1/7 and fail under §3.1; (b) under the §1/§7 procedure, Sonnet or Opus could produce a "unique modal winner" from a single surviving rerun (out of 3), since H7's representativeness gate applied only to 20-rerun main runs, not to 3-rerun H2 grids.

v9 unifies all three sections on a single rule with explicit asymmetric sample-size handling. Changes summarized in §11.

**Motivation:** Codex round-2 adversarial review identified "absence of null model" as the single strongest objection to the 11 lessons from 2026-04-15 matrix experiments. Issue #105 added two more: scoring discipline cannot be enforced by prompt alone; evaluation without codebase infrastructure context produces false dealbreakers. A validation protocol that ignores either is itself invalid.

This document preregisters the design BEFORE execution. Any deviation must be logged as a protocol amendment — see §8.

---

## 1. Hypotheses Under Test

Each hypothesis has (a) a single pre-committed statistical test, (b) a single pre-committed threshold, (c) a dependency on schema enforcement (§3.1) succeeding. §7 mirrors these definitions literally.

**H1 (L5a validity):** For a given problem domain, the mechanism-category of the matrix winner is stable across neutrally-framed reruns.
- **Rerun-level winner extraction:** the "winner cell" of a single rerun is the cell with the highest composite (per §3.1 Gate 5 recomputation). **If 2 or more cells share the highest composite within 0.001, the rerun has no winner — it counts as a non-target outcome.** This is the single tie rule used by both H1 and H2 below.
- **Test:** for each domain, count VALID reruns (per §3.1 invalidation rule) where the winner cell's `mechanism_novelty` is blind-classified (§5) into the pre-registered target category.
- **Threshold:** ≥14/20 in the target category for ≥2 of 3 real domains (D1, D2, D3). Denominator is fixed at 20 (invalidated reruns and tied-winner reruns count as non-target).
- **Prerequisite:** H6 (cell conformance ≥80%) AND H7 (rerun validity ≥80%) BOTH pass for that domain. If either fails, H1 is FAILED for that domain.

**H2 (inter-model winner-identity agreement):** Sonnet and Opus identify the same winning *cell* as Haiku under the same blind neutral prompt.
- **Prerequisite:** H6 AND H7 pass for the domain (composites must be comparable). If either fails for a domain, H2 is auto-FAILED for that domain (not skipped, not analyzed).
- **Rerun-level winner extraction:** same as H1 above — highest composite, ties within 0.001 = no winner for that rerun.
- **Sample-size floor (v9 fix for round-9 finding):** because Sonnet and Opus only have 3 reruns each, the modal-winner test is too fragile to tolerate any partial loss. **Any rerun in a Sonnet or Opus 3-grid that is invalidated (per §3.1) OR has no rerun-level winner (per the tie rule above) makes that entire 3-grid unusable, and H2 auto-fails for that model on that domain.** This restores the v6 strict-grid rule and unifies it with §3.1. Haiku does NOT use this floor (it has 20 reruns; the H1/H7 thresholds already protect representativeness there) — Haiku's modal is computed over its valid-with-winner reruns per the procedure below.
- **Test (mirrored verbatim in §7):**
  1. **Sonnet and Opus:** verify all 3 reruns are valid AND each has a rerun-level winner. If any rerun is invalidated or has no winner, H2 auto-fails for that model on that domain. Otherwise, identify the unique modal winner across all 3 reruns. If no unique mode, H2 auto-fails for that model.
  2. **Haiku:** take valid reruns only (per §3.1); build the list of rerun-level winners (excluding "no winner" reruns); identify the unique modal winner across that list. If the list is empty OR there is no unique mode, H2 auto-fails for the domain.
  3. Pass H2 for the domain if Haiku, Sonnet, and Opus all yielded a unique modal winner AND Sonnet-modal == Haiku-modal AND Opus-modal == Haiku-modal.
- **Threshold:** pass for ≥2 of 3 real domains.
- **Honesty note:** v3-v4 used single-cell design unable to test winner identity. v5 ran full grid. v6-v8 progressively tightened tie/invalidation semantics. v9 unifies the §3.1 strict-grid rule with the §1/§7 procedure for Sonnet/Opus while keeping Haiku's procedure (20-rerun, drop invalid/tied) for the larger sample. Asymmetric by sample size, justified by statistical fragility of n=3.

**H3 (mechanism category is not uniform):** Empirical distribution of blind-classified winning categories is not consistent with uniform 1/4 draw.
- **Test:** exact binomial (scipy.stats.binomtest) on target-category frequency vs p₀=0.25, one test per real domain.
- **Threshold:** p < 0.0125 (Bonferroni-corrected, 4 tests) for ≥2 of 3 real domains.

**H4 (post-matrix falsification discriminates):** L11 falsification on modal winners of D1/D2/D3 produces non-degenerate verdict distribution.
- **Test:** classify 3 verdicts as {strong, framing_dependent, falsified}; count.
- **Threshold:** no single verdict accounts for all 3.
- **Honesty note:** underpowered — sanity check, not validation.

**H5 (null — matrix does not fabricate structure):** On synthetic flat D0, matrix should NOT produce dominant winner category.
- **Test:** exact binomial on D0 target-category frequency vs p₀=0.25.
- **Threshold:** p ≥ 0.0125 (FAIL-to-reject uniformity). If D0 shows p<0.0125, H5 is falsified and D1/D2/D3 positive results lose standing.

**H6 (cell-level schema conformance) — NEW in v3, scoped in v6:** Individual cell outputs pass the 7-gate validator at a rate high enough for composites to be comparable. **This metric is cell-only — it does NOT incorporate rerun invalidation. See H7 for that.**
- **Test:** `H6_rate = ok_cells / total_dispatched_cells` per domain, where `ok_cells` is the count of cells passing all 7 gates of §3.1 (after the one allowed retry). `total_dispatched_cells = 180` per domain (9 cells × 20 reruns). An invalidated rerun's individually-passing cells STILL count as `ok` here — H6 is purely cell-level.
- **Threshold:** rate ≥ 80% per domain, in all 4 domains.
- **Applies to:** L7 (issue #105 — prompt-only discipline drifts).

**H7 (rerun-level validity) — NEW in v6:** Reruns survive the §3.1 "any drop invalidates the entire rerun" rule at a rate high enough that the surviving reruns are a representative sample.
- **Test:** `H7_rate = valid_reruns / total_reruns` per domain. A rerun is `valid` if it has zero dropped cells after retry. `total_reruns = 20` per domain.
- **Threshold:** rate ≥ 80% per domain, in all 4 domains.
- **Why separate from H6:** Codex round-6 noted that the v5 conflation of cell-conformance with rerun-invalidation could let one stubborn cell zero out eight valid siblings. Splitting fixes that — H6 measures schema discipline; H7 measures rerun usability. Both gate H1/H2/H3.
- **Consequence of H6 OR H7 failure:** H1, H2, H3 for that domain are auto-FAILED.

### Power Analysis (Justifying n=20 and threshold 14/20)

Under H0 (uniform 4-category, p=0.25), P(X≥14/20) = 0.00014. Bonferroni-corrected for 4 categories: ~5.5e-4. Well below α=0.01.

Under H1 true p=0.70 (modest effect), power ≈ 0.58. Under p=0.85 (strong effect), power ≈ 0.93. **Honest limitation:** negative result is consistent with both no-effect and missed-modest-effect. Positive result excludes no-effect with >99% confidence.

---

## 2. Domains (3 real + 1 synthetic control, 4 total)

Each domain specifies: 3 options, 4 MEE mechanism categories (single-axis partition — see §2.1), target category prediction, banned tokens, and — new in v3 — an **environment block** (L8 infrastructure context).

### 2.1 MEE Category Design Principle

v1 categories overlapped. v2 fixed by choosing a single axis of differentiation per domain. v3 retains this; each taxonomy is a partition, not a tagset.

### 2.2 Environment Blocks (L8 — New in v3)

Each domain pre-registers a paragraph describing the deployment context. This prevents haiku from hallucinating dealbreakers about infrastructure that is present or absent. The block is part of every cell prompt (§3).

### Domain D1: Caching strategy for a read-heavy web service

**Options:**
- A: In-process LRU cache per instance
- B: Shared Redis cluster
- C: Read-replica database with connection pooling

**Axis:** *Where does the authoritative read-path state live?*
- `in-process-private` — serving process holds its own copy, no coordination (A)
- `out-of-process-shared` — separate coordinating process, networked (B)
- `source-replica` — read-path state is a replica of the system of record (C)
- `recompute-on-demand` — no dedicated cached state

**Target category:** `out-of-process-shared` (B).

**Environment block:**
```
Service runs as 8 stateless replicas behind a load balancer on Kubernetes.
PostgreSQL primary is the system of record (4 vCPU, 16GB, read IOPS at 60% ceiling).
Prometheus + Grafana for metrics. Service mesh (Istio) provides mTLS and retries.
No existing cache infrastructure. Network latency within cluster <1ms p99.
Deploy pipeline rolls replicas 1-at-a-time; no blue/green.
```

**Banned tokens:** `redis`, `memcached`, `lru`, `cdn`, `cache`, `ttl`, `eviction`, `invalidation`, `hazelcast`, `ignite`, product names.

### Domain D2: Schema migration on a 50M-row production table

**Options:**
- A: In-place `ALTER TABLE` with lock
- B: Shadow table + atomic rename
- C: Dual-write to old and new columns with async backfill

**Axis:** *Does the migration hold a write lock during its runtime?*
- `lock-and-mutate` (A)
- `parallel-build-then-swap` (B)
- `incremental-reconcile` (C)
- `rebuild-from-log` — no lock, replay event log

**Target category:** `parallel-build-then-swap` (B).

**Environment block:**
```
Primary PostgreSQL 15, 50M-row table under active write load (~200 writes/sec).
Write downtime tolerance: 5 minutes planned maintenance window max.
Read replicas exist (2 async). Logical replication available.
No CDC pipeline. No event log. Application code controlled by same team.
Rollback SLA: 10 minutes from detection. Customer-facing — errors visible.
```

**Banned tokens:** `flyway`, `liquibase`, `alembic`, `gh-ost`, `pt-online-schema-change`, `rails migration`, `django migration`, tool names.

### Domain D3: Retry strategy for flaky external API

**Options:**
- A: Exponential backoff with jitter
- B: Circuit breaker with half-open probe
- C: Dead-letter queue with manual replay

**Axis:** *What information drives the retry decision?*
- `time-only` (A)
- `failure-rate-state` (B)
- `deferred-delegation` (C)
- `parallel-fallback` — multiple targets concurrently

**Target category:** `failure-rate-state` (B).

**Environment block:**
```
API consumed: third-party payment processor. p99 latency 500ms, failure rate
spikes to 30% during their deploys (weekly, unannounced). No webhook/callback
from them. Our service processes 50 req/sec peak. Idempotency keys are supported.
Redis available for shared state. Ops team on-call 24/7 for P1; P2 batched.
User-facing latency budget 1.5s p95. Failed request cost: blocked checkout.
```

**Banned tokens:** `tenacity`, `retry`, `backoff`, `circuit`, `hystrix`, `resilience4j`, `polly`, `jitter`, library names.

### Domain D0 (synthetic control): Deploy window choice

**Options:**
- A: Deploy on weekday mornings
- B: Deploy on weekday afternoons
- C: Deploy on weekday evenings

**Axis:** time-of-day.
- `morning`
- `afternoon`
- `evening`
- `other` (night/weekend/never)

**Target category:** NONE — we predict no signal.

**Environment block:**
```
Team is 8 engineers in a single time zone. No external SLAs tied to deploy windows.
CI takes 12 minutes. Rollback takes 3 minutes. No global traffic patterns worth
mentioning — traffic distribution across the day is flat within 10%.
No users report time-of-day preferences.
```
(Deliberately flat — every window is equivalent.)

**Banned tokens:** `standup`, `lunch`, `traffic`, `on-call`, `monitoring`, `rollback`.

---

## 3. Neutral Prompt Construction

Each cell prompt is constructed from a template with two neutrality gates and one schema gate:

**Lexical gate (automated):** regex scan **the model's output text**, NOT the prompt. The prompt's pre-registered environment block (§2.2) may contain neutral mentions of vocabulary that overlaps the banned-token list (e.g., D1's environment notes "no existing cache infrastructure" while `cache` is banned in model output). This is intentional — the goal is to prevent the model from re-introducing banned terms in `mechanism_novelty` and `dealbreaker`, not to censor the deployment context. Output hit = re-dispatch (per §3.1 schema procedure).

**Conceptual gate (human):** Pedro reads the ~12 unique prompt bodies (cells share prefixes) and rejects on paraphrased leakage. ~5 min per domain.

**Schema gate (automated, new in v3):** after dispatch, each cell output is JSON-parsed and validated for exact 4-dimension schema, score type/bounds, composite integrity, and dealbreaker grounding (§3.1).

**Cell template (Haiku):**
```
CRITICAL: Do NOT invoke any tools. Answer only from this prompt. Return JSON immediately.

You are scoring a design option for the following problem.

## Problem
{PROBLEM}

## Available Infrastructure / Environment
{ENVIRONMENT_BLOCK}

## All Options Under Consideration
A: {A_description}
B: {B_description}
C: {C_description}

## Option Under Evaluation
Cell {N}: {LABEL} — {OPTION_DESCRIPTION}

## SCORING CONVENTION (MANDATORY — HIGHER=BETTER on ALL dimensions)

You MUST score EXACTLY these four dimensions, using these EXACT keys. Do not add,
rename, or omit any. Your output will be schema-validated and rejected if the
dimension keys do not match.

- feasibility: 1 showstopper → 10 trivial to build
- risk: 1 highest risk → 10 lowest risk / most robust (HIGHER = SAFER)
- synergy_potential: 1 incompatible → 10 composes cleanly
- implementation_cost: 1 days of work → 10 minutes

## Output (JSON only, no prose, no fences)

{
  "cell": {N},
  "label": "{LABEL}",
  "risk_direction_used": "higher_safer",
  "scores": {
    "feasibility": <int 1-10>,
    "risk": <int 1-10>,
    "synergy_potential": <int 1-10>,
    "implementation_cost": <int 1-10>
  },
  "composite": <mean of the 4 scores>,
  "mechanism_novelty": "<one sentence; no banned tokens; commit to one mechanism, no hedging>",
  "dealbreaker": null or "<one sentence; if risk is based on infrastructure, only cite infrastructure explicitly listed in the Environment block above>"
}

Your "scores" object must contain EXACTLY those 4 keys. Any other keys cause
rejection and re-dispatch. Do not include correctness, complexity, robustness,
token_efficiency, coordination_power, debuggability, failure_isolation,
leverage, novelty, composability, runtime_safety, latency_impact, reliability,
observability_gain, operational_complexity, security_surface, safety,
hook_coverage, or any other dimension. Four dimensions. Named exactly as above.
```

### 3.1 Schema Validation (NEW in v3, hardened in v4 per Codex round-4)

After each rerun batch, every cell output is validated against five gates:

```python
import json, re

REQUIRED = {"feasibility", "risk", "synergy_potential", "implementation_cost"}

def validate(cell_output, env_block_text, banned_tokens):
    # Gate 1: parses
    try:
        obj = json.loads(cell_output)
    except json.JSONDecodeError:
        return "parse_fail"

    # Gate 2: exact 4-key schema
    scores = obj.get("scores", {})
    if set(scores.keys()) != REQUIRED:
        return "schema_fail"

    # Gate 3: convention declared
    if obj.get("risk_direction_used") != "higher_safer":
        return "convention_fail"

    # Gate 4: scores are integers in [1, 10]
    for k, v in scores.items():
        if not isinstance(v, int) or not (1 <= v <= 10):
            return "score_type_fail"

    # Gate 5: composite is recomputed (model-reported value is discarded)
    obj["composite"] = sum(scores.values()) / 4.0

    # Gate 6: lexical scan only on model-generated text fields
    output_text = " ".join([
        obj.get("mechanism_novelty", "") or "",
        obj.get("dealbreaker", "") or "",
    ]).lower()
    for token in banned_tokens:
        if re.search(rf"\b{re.escape(token.lower())}\b", output_text):
            return "banned_token_fail"

    # Gate 7: dealbreaker grounding — if dealbreaker exists and cites
    # infrastructure, the cited infrastructure must appear in the environment
    # block. Heuristic: dealbreaker contains a noun matching some env-block
    # noun, OR the dealbreaker is a generic concern (no infra noun).
    db = (obj.get("dealbreaker") or "").lower()
    if db and _cites_unlisted_infra(db, env_block_text):
        return "infra_grounding_fail"

    return "ok"
```

`_cites_unlisted_infra` is a small Pedro-coded heuristic: extracts noun phrases from the dealbreaker text using a 30-line regex helper, checks each against the environment block text. If any noun phrase names infrastructure (heuristic: ends in `daemon`, `service`, `queue`, `cluster`, `database`, `pipeline`, `mesh`, `cache`, `replica`, etc.) and is NOT in the environment block, the gate fails. The helper code is committed before execution and frozen.

**Enforcement (v6 — single authoritative block, supersedes earlier wording):**

Per cell:
- Any of the 7 gates fails → re-dispatch that cell ONCE with a stricter preamble naming the failure.
- Second failure → mark the cell as `dropped` for that rerun.

Per rerun (main 9-cell or H2 3-grid):
- A rerun with **≥1 dropped cell** is **invalidated**. Invalidated reruns are excluded from H1, H2, H3 winner counting (denominators stay fixed; invalidated reruns count as non-target / fail-domain in those tests).

Per domain, H6 and H7 are computed from the same data with **different perspectives** (no conflation, no double-counting):

```
H6_rate = ok_cells           / total_dispatched_cells   # cell-level perspective
H7_rate = valid_reruns       / total_reruns             # rerun-level perspective
```

| Symbol | Definition |
|--------|------------|
| `ok_cells` | count of cells that passed all 7 gates after the allowed retry. Invalidation of a rerun does NOT subtract from `ok_cells`. |
| `valid_reruns` | count of reruns with **zero** dropped cells after retry. |
| `total_dispatched_cells` | fixed at `9 × 20 = 180` per domain. |
| `total_reruns` | fixed at `20` per domain. |

**Worked example** (resolves the round-7 ambiguity): a domain with 20 reruns where each rerun has exactly 8 ok-cells and 1 dropped cell → `ok_cells = 160`, `valid_reruns = 0`. `H6_rate = 160/180 ≈ 0.89` (passes ≥0.80). `H7_rate = 0/20 = 0` (fails ≥0.80). Result: H6 passes, H7 fails, H1/H2/H3 auto-fail for the domain because **both** must pass.

The two metrics measure different constructs: H6 = "do individual cells obey the schema?", H7 = "are full reruns useful as analysis units?". They can disagree, and that disagreement is informative — it's why both gate H1/H2/H3.

**H2 specific note (v9 — aligned with §1/§7):** Sonnet and Opus 3-grids are subject to a strict sample-size floor: any invalidated rerun OR any rerun with no winner (per the §1 tie rule) makes the entire 3-grid unusable, and H2 auto-fails for that model on that domain. Haiku's 20-rerun grid uses drop-and-aggregate (drop invalidated reruns, drop no-winner reruns from the modal computation, fail only if the remaining list is empty or has no unique mode). The asymmetry is intentional and matches §1/§7 verbatim.

---

## 4. Execution Plan

**Per domain × 4 domains:**
- 20 Haiku reruns × 9 cells, `allowed-tools: []`.

**Plus for H2 (D1, D2, D3 — v5 full grid):**
- 3 Sonnet reruns × 9 cells per domain.
- 3 Opus reruns × 9 cells per domain.

**Total dispatches:**
- 4 × 20 × 9 = 720 Haiku cell dispatches.
- 3 × 2 × 3 × 9 = 162 Sonnet+Opus cell dispatches.
- Schema re-dispatches: estimated 15-25% failure rate → ~150 extra dispatches.
- Blind-coding judges (§5): 12 dispatches.
- **Grand total: ~1,044 dispatches.**

**Budget:** Haiku ~$2.00, Sonnet+Opus ~$3.20, coding ~$0.30, re-dispatches ~$0.50. Total ~$6.00. Add 1.5× buffer: **$8-9**.

**Wall clock:** ~2h with parallelism (9 cells parallel, 20 reruns per domain, 4 domains).

---

## 5. Blind Coding (v3 — unchanged from v2 but clarified)

Requirements:
1. Two judges from different model families (Haiku + Sonnet).
2. Cohen's kappa ≥ 0.75 threshold — below that, domain H1/H3 declared FAILED (not dropped).
3. Third judge is HUMAN (Pedro) — adjudicates disagreements. Breaks model-family correlation chain.
4. Co-error check in report: human-vs-model-consensus disagreement rate on sampled subset. If > 15%, downgrade H-results with the note "coding may reflect model co-error".

Procedure same as v2 §5.

---

## 6. Synthetic Control D0

D0 runs first. If H5 fails on D0 (dominant category emerges on flat options), abort the entire protocol — the null baseline is poisoned by prompt geometry, and no amount of positive results on D1/D2/D3 rescue that.

---

## 7. Analysis (Mirrors §1 Exactly)

Analysis code in `/tmp/null-model-runs/analyze.py`, written AFTER reruns complete, < 100 lines, zero free choices.

Exact decision rules:

- **H6 (run first, all 4 domains):** compute `H6_rate = ok_cells / 180`. Fail H6 for any domain < 0.80.

- **H7 (run second, all 4 domains):** compute `H7_rate = valid_reruns / 20`. Fail H7 for any domain < 0.80.

- **For each domain, H1/H2/H3 are auto-FAILED if H6 OR H7 failed for that domain.** Otherwise proceed.

- **H1:** for each of D1, D2, D3 where both H6 and H7 passed, identify each valid rerun's winner cell (highest composite; ties = non-target). Compute `target_count = count(valid reruns where winner's blind-classified category == target)`. Denominator is always 20 (invalidated reruns count as non-target). Pass H1 if `target_count ≥ 14` for at least 2 of 3 domains.

- **H2:** for each of D1, D2, D3 where both H6 and H7 passed, apply the unified winner extraction from §1 (rerun-level winner = highest composite; ≥2 cells within 0.001 of top = no winner for that rerun) to all reruns of all three models on this domain. Then:
  1. **Sonnet and Opus (strict grid, sample-size floor):** verify all 3 reruns are valid (per §3.1 invalidation rule) AND each rerun has a rerun-level winner (per the tie rule). If any rerun is invalidated or has no winner, H2 auto-fails for that model on that domain. Otherwise, identify the unique modal winner across all 3 reruns. If no unique mode, H2 auto-fails for that model.
  2. **Haiku (drop-and-aggregate):** take only valid reruns; build the list of rerun-level winners (excluding "no winner" reruns); identify the unique modal winner across that list. If the list is empty OR there is no unique mode, H2 auto-fails for the domain.
  3. Pass H2 for the domain if Haiku, Sonnet, and Opus all yielded a unique modal winner AND Sonnet-modal == Haiku-modal AND Opus-modal == Haiku-modal.
- **H2 final pass:** Pass for ≥2 of 3 real domains.

This is the single rule shared between §1 and §7 and §3.1. No alternative interpretation exists. Asymmetric handling between Haiku (n=20, drop tolerated) and Sonnet/Opus (n=3, all-or-nothing) is justified by statistical fragility of small grids.

- **H3:** for each of D1, D2, D3 where both H6 and H7 passed, run `scipy.stats.binomtest(target_count, 20, 0.25, alternative='greater')` using the same `target_count` from H1. Pass if p < 0.0125 for at least 2 of 3 domains.

- **H4:** run post-matrix falsification on modal winners of D1, D2, D3. Classify 3 verdicts. Pass if no single verdict accounts for all 3.

- **H5:** `scipy.stats.binomtest(d0_target_count, 20, 0.25, alternative='greater')` where `d0_target_count` is the most frequent category on D0. Pass if p ≥ 0.0125.

Any deviation is a protocol violation.

---

## 8. Protocol Amendments

Any change post-execution-start requires:
1. Dated "Amendment" section below.
2. Explicit justification.
3. Note affected hypotheses.
4. **Amendment counts as failure for any hypothesis where it relaxes a threshold or substitutes a test.** Blocks move-the-goalposts.

No amendments yet.

---

## 9. Expected Deliverable

`docs/null-model-validation-report.md`:
- H1-H6 pass/fail table with exact numbers.
- Schema conformance rate per domain (H6 output).
- Per-lesson decision: which of L1-L11 are supported, downgraded, or retracted.
- Co-error check results.
- Updated idea-matrix skill PR (if any).
- Codex round-5 invitation.

Budget for report + codex: ~$1.

---

## 10. Abort Conditions (v3 — Abort = Failure)

Protocol aborts on:
- Cumulative cost > 2× budget ($14).
- Banned-token scan trips >1 after 2 rebuild attempts per domain.
- Kappa < 0.75 between model judges per domain → that domain's H1/H3 = FAILED (not aborted; v2 rule).
- Pedro rejects conceptual-leakage review and cannot construct acceptable neutral prompt.
- **NEW v3:** Schema conformance rate for any domain < 0.50 after re-dispatches → domain auto-fails H6, H1, H3; if this happens on ≥2 domains, whole protocol aborts (prompt-only schema discipline is unfixable in this regime).

**Rule:** every abort counts as failure of the relevant hypothesis. Never "inconclusive". Never "dropped silently".

On abort, write `docs/null-model-validation-abort.md`: trigger, partial data, which hypotheses fail, which lessons retract/downgrade.

---

## 11. Changelog

### v8 → v9 (this version)

Addresses Codex round-9 review of v8:

| # | v8 flaw | v9 fix |
|---|---------|--------|
| 23 | §3.1 H2 note ("any drop in 3-grid → H2 auto-fail") still conflicted with §1/§7's "drop invalid/no-winner reruns from list, fail only if empty or no unique mode". Same data could pass under §§1/7 and fail under §3.1. | §1, §7, and §3.1 H2 sections all rewritten to share the same numbered procedure with explicit asymmetric handling: Sonnet/Opus use strict grid (any drop or no-winner = H2 fail for that model on domain); Haiku uses drop-and-aggregate (n=20 tolerates drops). All three sections describe the same procedure. |
| 24 | H2 could pass on a single surviving Sonnet or Opus rerun (out of 3) because invalidated and tied reruns were simply omitted from the modal computation. H7's ≥80% representativeness gate applied only to 20-rerun main runs, not to 3-rerun H2 grids. | §1 H2 introduces a sample-size floor explicitly for Sonnet/Opus 3-grids: any invalidated rerun or no-winner rerun makes the entire grid unusable. This is the conservative v6 rule, restored with explicit justification (n=3 statistical fragility). Haiku retains drop-and-aggregate because its n=20 is large enough and H1/H7 protect representativeness there. |

### v7 → v8 (commit 1245903)

Addresses Codex round-8 review of v7:

| # | v7 flaw | v8 fix |
|---|---------|--------|
| 22 | §7 H2 paraphrased the §1 H2 rule instead of mirroring it verbatim. The two sections could be read as scoring the same dataset two different ways: §1 made tied/invalidated reruns H2-fatal at the rerun level; §7 still talked about computing a Haiku modal winner across "the 20 reruns" without specifying tie/invalidation handling at the rerun level. Real preregistration requires a single procedure. | §1 H2 and §7 H2 now contain the **same numbered 4-step procedure**. Both sections explicitly describe: (1) take valid reruns only, (2) extract rerun-level winners (ties = no winner for that rerun, contributes nothing), (3) require unique modal winner across that list, (4) compare Sonnet/Opus modals to Haiku modal. Empty winner list or non-unique mode = H2 fail for the model on the domain. No paraphrase remains; the procedure is literally identical in both sections. |

### v6 → v7 (commit c9285d8)

Addresses Codex round-7 review of v6:

| # | v6 flaw | v7 fix |
|---|---------|--------|
| 20 | H2 winner extraction defined ties only at modal level. A single rerun with two cells sharing top composite had no defined winner, so modal aggregation across 3 reruns could be flipped by undefined behavior. | §1 H1 and H2 both define the rule explicitly: "winner = highest composite; ≥2 cells within 0.001 of top = no winner for the rerun, counts as non-target / H2-fail". Single rule shared across H1 and H2. |
| 21 | §3.1 had mutually contradictory H6 accounting. v5 sentence "invalidated rerun counts as 9 dropped cells toward H6" remained while v6 explicitly said "invalidation does not subtract from ok_cells". Same data could yield H6 = 0/180 OR 160/180 depending on which sentence the implementer read first. | §3.1 collapsed into a single authoritative enforcement block. Old v5 sentence removed. New block includes a worked example for the exact 8-pass-1-drop case Codex flagged: H6 = 160/180 (passes), H7 = 0/20 (fails), result: H1/H2/H3 auto-fail because both gates must pass. |

### v5 → v6 (commit af6fd4a)

Addresses Codex round-6 review of v5:

| # | v5 flaw | v6 fix |
|---|---------|--------|
| 17 | H2 not gated on H6 — a domain with non-comparable composites could still be evaluated for cross-model winner agreement. | §1 H2 explicit prerequisite: both H6 AND H7 must pass for the domain. Failure of either auto-fails H2 for that domain. |
| 18 | "Modal winner" undefined for ties. Three Sonnet grids could produce three different winners with no rule. | §1 H1 + H2: ties (no unique mode) count as failure (non-target for H1, fail-domain for H2). Conservative, no analyst tiebreak. |
| 19 | v5 H6 conflated cell conformance with rerun invalidation — a single stubborn cell zeroed out eight valid siblings. H6 stopped measuring its stated construct. | Split into two metrics. **H6 (cell-level):** `ok_cells / 180`, no invalidation rollup. **H7 (rerun-level, NEW):** `valid_reruns / 20`. Both gate H1/H2/H3 at ≥80%. |

### v4 → v5 (commit 41b5035)

Addresses Codex round-5 review of v4:

| # | v4 flaw | v5 fix |
|---|---------|--------|
| 14 | H2 ran only Haiku modal-winner cell against Sonnet/Opus. Could not measure cross-model winner identity — Sonnet might rank an untested cell higher. False-positive structurally. | §1 H2 redesigned: full 9-cell grid for Sonnet (×3 reruns) and Opus (×3 reruns) per domain. Compare each model's modal winner against Haiku's. Cost +~$1.50; total budget $8-9. |
| 15 | H6 conformance formula `ok / (total − dropped)` excluded dropped cells from the denominator, so widespread failure could report high conformance among survivors. | §3.1 formula changed to fixed denominator: `ok_cells / total_dispatched_cells` (180 per domain). Drops, retries, and invalidated reruns all count against. |
| 16 | Main 9-cell rerun with exactly 1 dropped cell survived with no analyst-time semantics. Same partial-failure ambiguity v4 fixed for H2 single-cell. | §3.1 single rule: ANY drop invalidates the entire rerun (counts as 9 dropped cells toward H6). Removes post-hoc discretion about scoring 8-of-9 grids. Same rule applied to H2 grids. |

### v3 → v4 (commit 478e861)

Addresses Codex round-4 review of v3:

| # | v3 flaw | v4 fix |
|---|---------|--------|
| 11 | Lexical gate self-contradicted the env blocks it introduced: D1 env block contained "cache infrastructure"; D0 env block contained "rollback"; both were in the banned-token list. Gate would abort by construction. | §3 lexical gate now scans ONLY model-generated text (`mechanism_novelty`, `dealbreaker`), not the prompt. The prompt's env block can mention vocabulary that the model is forbidden from re-using. |
| 12 | Schema validator only checked dimension key-set + convention string. Did not verify score types or 1-10 bounds, did not recompute composite, did not check dealbreaker grounding. Corrupt outputs counted as `ok`. | §3.1 expanded from 2 gates to 7 gates: parse, schema, convention, **score-int-in-bounds**, **composite-recompute (model value discarded)**, **banned-token scan on output**, **dealbreaker infrastructure grounding (must appear in env block)**. |
| 13 | H2 ran single-cell reruns (Sonnet/Opus) but the drop rule required ≥2 failed cells to mark a rerun dropped. Single-cell reruns could fail twice and leave a missing composite with no analysis-time semantics — free choice at score time. | §3.1 explicit rule: single-cell reruns that fail twice count as **0 in the fixed 5-run denominator** (a miss). §7 H2 description references this rule explicitly. |

### v2 → v3 (commit 25b35e4)

Addressed autoimprove#105 findings from MATRIX_5:

| # | v2 flaw | v3 fix |
|---|---------|--------|
| 9 | Assumed prompt-only schema discipline worked. MATRIX_5 disproved: 4/9 cells invented extra dimensions (5-7 dims instead of 4). | §3 template includes explicit "Your output will be schema-validated and rejected" + enumeration of forbidden dimension names. §3.1 adds schema validation procedure. H6 enforces ≥80% conformance. |
| 10 | Neutral prompts lacked codebase infrastructure context, leading haiku to hallucinate dealbreakers (L8). | §2.2 introduces Environment Blocks; each domain pre-registers one in §2. §3 template has mandatory "Available Infrastructure" section. |

### v1 → v2 (commit c9ffd33)

Addressed Codex round-3 (see v2 document history). Summary:
- §1/§7 alignment (single test per H, no post-hoc choice).
- Power analysis for n=20 threshold 14/20.
- D0 integrated (first, with categories).
- MEE categories via single-axis principle.
- Lexical ban + human conceptual-leakage gate.
- Kappa ≥ 0.75, human 3rd judge.
- Single test per hypothesis.
- Abort = hypothesis failure.

### v3 meta-commentary

v3 is now constrained by 3 rounds of adversarial review (Codex rounds 2 + 3 + issue #105). A v4 would need external human coders (not Pedro alone, to eliminate the human-also-correlated-to-Claude-outputs problem) and n≥30 per domain for power ≥0.7 on modest effects — out of current budget. v3 is the defensible floor given available resources.
