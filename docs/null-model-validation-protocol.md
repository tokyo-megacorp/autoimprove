# Null-Model Validation of Idea-Matrix — Preregistered Protocol v11

**Version:** 11 (2026-04-17, post-v10.3 abort redesign)
**Status:** awaiting execution (pre-registration fresh — no amendments yet)
**Budget estimate:** ~$8-9, 3-5h
**Previous versions:** v1–v10.3 archived in git history. v10.3 aborted per §10.5 on D1 and D3 — banned-token gate conflated product names with domain concepts, yielding H6 rates of 0.28 and 0.24 respectively. D0 and D2 passed cleanly under Fix A + Fix B. See `docs/null-model-validation-abort-v2.md` for full post-mortem.

**Motivation:** v11 surgically fixes the one root cause identified in v10.3's abort: the banned-token metric (now H6b) was designed as if all banned tokens were product/library names substitutable by synonyms, but in v10.3 `§2 D1/D3` it silently included domain-intrinsic concept vocabulary (`cache`, `retry`, etc.). The test failed on its own terms — Haiku cannot describe caching mechanisms without using the word "cache".

v11 resolves this by:
1. Splitting H6 into H6a (schema discipline) and H6b (product-name lexical discipline) — each with its own threshold. This makes banned-list design flaws visible as diagnostic signal instead of hidden H1/H3 confound.
2. Tightening every domain's banned-token list to **product/library names only**, by pre-registration. Concept vocabulary is never banned.

All other v10.3 design elements (Fix A solo-only ranking, Fix B balanced permutation, §5 blind coding, §6 D0 synthetic control, §8 amendment discipline, §10 abort=failure rule) are preserved verbatim.

This document is a clean pre-registration. No amendments exist at the start of v11. Any deviation post-execution-start requires the §8 amendment procedure.

---

## 1. Hypotheses Under Test

Each hypothesis has (a) a single pre-committed statistical test, (b) a single pre-committed threshold, (c) explicit dependencies on §3.1 gates succeeding. §7 mirrors these definitions literally.

**H1 (L5a validity):** For a given problem domain, the mechanism-category of the matrix winner is stable across neutrally-framed reruns.
- **Rerun-level winner extraction (Fix A, v10.1+):** the "solo winner" of a rerun is the SOLO cell (1, 2, or 3) with the highest composite. If 2 or more solo cells share the highest composite within 0.001, the rerun has no solo winner — counts as non-target. Combos (4–7) and alts (8–9) are scored and reported but never eligible for H1 winner aggregation.
- **Test:** for each real domain D1/D2/D3, count VALID reruns (per §3.1) where the solo winner's `mechanism_novelty` is blind-classified (§5) into the pre-registered target category.
- **Threshold:** ≥14/20 in the target category for ≥2 of 3 real domains. Denominator fixed at 20 — invalidated or tied reruns count as non-target.
- **Prerequisite:** H6a ≥ 0.80 AND H6b ≥ 0.80 AND H7 ≥ 0.80 for that domain. If any of the three fails for a domain, H1 auto-FAILS for that domain.

**H2 (inter-model winner-identity agreement):** Sonnet and Opus identify the same winning solo cell as Haiku under the same blind neutral prompt.
- **Prerequisite:** H6a ≥ 0.80 AND H6b ≥ 0.80 AND H7 ≥ 0.80 for that domain (Haiku side). If any fails, H2 auto-FAILS for that domain. Sonnet and Opus have their own 3-grid floor (below) instead of an H6a/H6b/H7 threshold, because n=3 makes per-model rate thresholds statistically meaningless.
- **Sample-size floors:**
  - **Sonnet, Opus (3-grid, drop-and-aggregate with 2/3 floor — v11 change from v10's strict rule):** count valid-and-winner-bearing reruns (valid per §3.1 AND has a solo winner per the tie rule). If fewer than 2 of the 3 reruns meet this, H2 auto-fails for that model on that domain. Otherwise identify the modal solo winner across the 2 or 3 winner-bearing reruns. If there is no unique mode (e.g., 2 winner-bearing reruns disagree), H2 auto-fails for that model. **Rationale for v11 relaxation:** with H6b added as an independent drop channel, the v10 strict rule would auto-fail Sonnet/Opus 3-grids ~15–25% of the time from natural banned-token retry failures. The 2/3 floor preserves statistical meaning (both surviving reruns must agree) while tolerating one H6b-driven drop per model.
  - **Haiku (20-grid representativeness floor):** count winner-bearing reruns (valid per §3.1 AND has a rerun-level solo winner per the tie rule). If <16, H2 auto-fails on Haiku side. Otherwise identify unique modal solo winner across those winner-bearing reruns.
- **Test:** Haiku modal == Sonnet modal == Opus modal (all three must match) for pass.
- **Threshold:** pass for ≥2 of 3 real domains.

**H3 (mechanism category is not uniform):** Empirical distribution of blind-classified winning categories is not consistent with uniform 1/4 draw.
- **Test:** exact binomial on target-category frequency vs p₀=0.25 per domain.
- **Threshold:** p < 0.0125 (Bonferroni for 4 tests) for ≥2 of 3 real domains.

**H4 (post-matrix falsification discriminates):** L11 falsification on modal winners of D1/D2/D3 produces non-degenerate verdict distribution.
- **Test:** classify 3 verdicts as {strong, framing_dependent, falsified}.
- **Threshold:** no single verdict accounts for all 3.
- **Honesty note:** underpowered — sanity check, not validation.

**H5 (null — matrix does not fabricate structure):** On synthetic flat D0, matrix should NOT produce dominant solo-winner category.
- **Test:** exact binomial on D0's most-frequent solo-winner semantic category vs p₀=0.25.
- **Threshold:** p ≥ 0.0125 (fail-to-reject uniformity). If p<0.0125, H5 is falsified and D1/D2/D3 positive results lose standing per §6.

**H6a (schema discipline — NEW split in v11):** Individual cell outputs pass the FIVE structural gates (parse, exact 4-key schema, convention string, score type/bounds in [1,10], dealbreaker infrastructure grounding) at a rate sufficient for composites to be comparable.
- **Test:** `H6a_rate = schema_ok_cells / 180` per domain.
- **Threshold:** rate ≥ 0.80 per domain, in all 4 domains.
- **Measures:** "can the model produce correctly-structured JSON with sane scores?" — independent of domain vocabulary.

**H6b (product-name lexical discipline — NEW split in v11):** Individual cell outputs avoid the pre-registered product/library-name banned list in model-generated text fields.
- **Test:** `H6b_rate = lexical_ok_cells / 180` per domain, where a cell is `lexical_ok` iff `mechanism_novelty` and `dealbreaker` (when non-null) contain no banned token per case-insensitive word-boundary regex.
- **Threshold:** rate ≥ 0.80 per domain, in all 4 domains.
- **Measures:** "does the model reason in mechanism-level vocabulary rather than parroting product names from the prompt?"
- **Design invariant (v11):** pre-registered banned lists contain ONLY product/library/service names. Concept-level vocabulary (`cache`, `retry`, `migration`, `window`) is NEVER banned. If a banned list is discovered post-hoc to contain a concept word, the protocol ABORTS per §10.6 (new v11 abort condition).

**H7 (rerun-level validity):** Reruns survive the §3.1 "any drop invalidates the entire rerun" rule at a rate sufficient for the surviving reruns to be a representative sample.
- **Test:** `H7_rate = valid_reruns / 20` per domain, where a rerun is `valid` if zero of its 9 cells were dropped after retry. A cell is dropped if either H6a or H6b fails after the allowed retry.
- **Threshold:** rate ≥ 0.80 per domain, in all 4 domains.
- **Consequence of H6a OR H6b OR H7 failure for a domain:** H1, H2, H3 auto-FAIL for that domain.

### Power Analysis (unchanged)

Under H0 uniform p=0.25, P(X≥14/20) = 0.00014. Bonferroni-corrected (4 categories): ~5.5e-4. Below α=0.01.

Under H1 true p=0.70, power ≈ 0.58. Under p=0.85, power ≈ 0.93. Honest limitation: negative result is consistent with both no-effect and missed-modest-effect. Positive result excludes no-effect with >99% confidence.

---

## 2. Domains (3 real + 1 synthetic control)

Each domain specifies: 3 options, 4 MEE mechanism categories (single-axis partition — §2.1), target category prediction, banned tokens (product/library names only per v11 design invariant), and environment block (L8 context).

### 2.1 MEE Category Design Principle

Unchanged from v3. Each taxonomy is a partition (one axis of differentiation), not a tagset.

### 2.2 Environment Blocks (L8)

Unchanged from v3. Each domain pre-registers a paragraph describing deployment context to prevent Haiku from hallucinating dealbreakers about infrastructure that isn't present.

### 2.3 Banned Token Design (v11)

Banned tokens are **product/library/service names that appear in OPTION DESCRIPTIONS** (not env blocks) OR well-known equivalents in that ecosystem. They exist to prevent the model from parroting a specific brand as if it were the mechanism. They MUST NOT include:
- The domain's conceptual noun (e.g., `cache`, `retry`, `migration`, `deploy`).
- Adjectives/verbs describing the mechanism (e.g., `shared`, `async`, `eventual`).
- Algorithm family names that describe a class of mechanism rather than a product (e.g., `lru` describes an eviction policy; `token-bucket` describes a rate-limit algorithm — these are CONCEPTS, not products).
- Env-block-mentioned infrastructure names (e.g., `postgresql`, `kubernetes`, `grafana`) — these are deployment context the model should be free to reference. Infrastructure grounding is already enforced by Gate 7.

**Decidability guidance for edge cases:**
- `postgresql` / `postgres` — **product name**, but in env block = NOT banned per "env-block exception" above.
- `SQL`, `HTTP`, `REST` — **concepts** (specification families), never banned.
- `git` / `docker` / `kubernetes` — product names when used as nouns referring to the system; but if they are env-block infrastructure, NOT banned.
- Eponymous patterns like `kubernetes-style` or `docker-ize` — treat as CONCEPTS (pattern generalizations), not banned.
- **CamelCase / titlecase of concept words** (e.g., `CircuitBreaker`, `TokenBucket`, `LRUCache`) — treat as CONCEPTS when the underlying word is a concept, not banned. The word-boundary regex in Gate 6 will naturally match `CircuitBreaker` only if the literal token `circuitbreaker` or similar is in the banned list; `circuit` alone in a ban list matching `CircuitBreaker` via partial match is a tokenization bug, not a design feature.
- When genuinely ambiguous: default to NOT banning. False-allow is less costly than false-ban, because Gate 7 (infra-grounding) still catches unsupported product claims in dealbreakers.

Any post-hoc discovery that a banned list contains a concept word triggers §10.6 abort.

### Domain D1: Caching strategy for a read-heavy web service

**Options:**
- A: In-process LRU cache per instance
- B: Shared Redis cluster
- C: Read-replica database with connection pooling

**Axis:** Where does the authoritative read-path state live?
- `in-process-private` (A)
- `out-of-process-shared` (B)
- `source-replica` (C)
- `recompute-on-demand`

**Target category:** `out-of-process-shared` (B).

**Environment block:**
```
Service runs as 8 stateless replicas behind a load balancer on Kubernetes.
PostgreSQL primary is the system of record (4 vCPU, 16GB, read IOPS at 60% ceiling).
Prometheus + Grafana for metrics. Service mesh (Istio) provides mTLS and retries.
No existing cache infrastructure. Network latency within cluster <1ms p99.
Deploy pipeline rolls replicas 1-at-a-time; no blue/green.
```

**Banned tokens (v11, product/library names only):** `redis`, `memcached`, `hazelcast`, `ignite`, `couchbase`, `ehcache`, `varnish`. These are cache-system products the model might parrot from knowledge, not from the env block. **Not banned:** env-block-mentioned products (`kubernetes`, `istio`, `grafana`, `prometheus`, `postgresql`) — they are deployment context, not mechanism choices. Banning env-block vocabulary would inflate H6b failures from natural context echo without adding signal.

### Domain D2: Schema migration on a 50M-row production table

**Options:**
- A: In-place `ALTER TABLE` with lock
- B: Shadow table + atomic rename
- C: Dual-write to old and new columns with async backfill

**Axis:** Does the migration hold a write lock during its runtime?
- `lock-and-mutate` (A)
- `parallel-build-then-swap` (B)
- `incremental-reconcile` (C)
- `rebuild-from-log`

**Target category:** `parallel-build-then-swap` (B).

**Environment block:**
```
Primary PostgreSQL 15, 50M-row table under active write load (~200 writes/sec).
Write downtime tolerance: 5 minutes planned maintenance window max.
Read replicas exist (2 async). Logical replication available.
No CDC pipeline. No event log. Application code controlled by same team.
Rollback SLA: 10 minutes from detection. Customer-facing — errors visible.
```

**Banned tokens (v11, product/library names only — unchanged from v10.3 which already complied):** `flyway`, `liquibase`, `alembic`, `gh-ost`, `pt-online-schema-change`, `postgresql`, `postgres`, `rails`, `django`.

### Domain D3: Failure-handling strategy for a flaky external API

Reworded from v10.3's "Retry strategy for flaky external API" to avoid embedding a concept word in the problem statement.

**Options:**
- A: Exponential backoff with randomized delay
- B: Stateful controller that halts attempts when aggregate failure rate crosses a threshold and periodically probes
- C: Dead-letter queue with manual replay

**Axis:** What information drives the retry decision?
- `time-only` (A)
- `failure-rate-state` (B)
- `deferred-delegation` (C)
- `parallel-fallback`

**Target category:** `failure-rate-state` (B).

**Environment block:**
```
API consumed: third-party payment processor. p99 latency 500ms, failure rate
spikes to 30% during their deploys (weekly, unannounced). No webhook/callback
from them. Our service processes 50 req/sec peak. Idempotency keys are supported.
Redis available for shared state. Ops team on-call 24/7 for P1; P2 batched.
User-facing latency budget 1.5s p95. Failed request cost: blocked checkout.
```

**Banned tokens (v11, product/library names only):** `tenacity`, `hystrix`, `resilience4j`, `polly`, `opossum`, `failsafe`. These are retry/circuit-breaker library names. **Not banned:** env-block-mentioned products (`redis`, `stripe` via "payment processor", any `aws-*` SDK names) — they are deployment/consumer context, not mechanism choices. Same rationale as D1.

### Domain D0 (synthetic control)

Unchanged from v10.3 (passed H5 with p=0.38). Reproduced here for completeness.

**Options:** A=mornings, B=afternoons, C=evenings. Axis: time-of-day. Target: NONE.

**Environment block:** flat — every window is equivalent, 8 engineers one time zone, no SLA, no traffic pattern.

**Banned tokens:** `standup`, `lunch`, `traffic`, `on-call`, `monitoring`, `rollback`. (These ARE domain-adjacent concept words, but D0's purpose is to test the null — the banned list's stringency is part of the null test. If D0 passes H5 despite this, the matrix is robust to prompt-level priming noise.)

**Note on D0 banned list inconsistency with v11 design invariant:** D0 is explicitly exempted from §2.3 because its role is a stress-test control, not a real domain. If D0 failed H6b in a future run, we would reconsider D0's list too — but the v10.2 run passed H6a=H6b=1.0 on D0 despite this list, which is evidence the model CAN avoid these when the domain vocabulary is sparse.

---

## 3. Neutral Prompt Construction

Unchanged from v10.2 (including Fix B permutation per Amendment 2/3 of v10.3, now preserved natively in v11).

Each cell prompt is constructed from the v10.2 template. Per rerun, a pre-registered balanced permutation rotates which semantic option maps to labels A/B/C. The listing order in "## All Options Under Consideration" is always A, B, C (positions stay constant); only the semantic assignment rotates. Solo cells 1/2/3 evaluate labels A/B/C with the rerun's rotated semantics.

Balanced sequence (reused from v10.2): 3 blocks of 6 unique permutations + 2 bonus. Each (label, semantic) pair appears 6 or 7 times across 20 reruns (max imbalance = 1).

Cell template verbatim from v10.2, unchanged in v11.

### 3.1 Schema Validation (v11, 6 gates, with H6 split)

After each rerun batch, every cell output is validated against 6 gates. **Important change from v10.3:** Gate 6 (banned-token scan) is REQUIRED for cell `ok` just like the other gates, BUT the gate-level failures are reported under two separate buckets for H6a vs H6b computation.

```python
# Gates 1-5 compose H6a (schema discipline).
# Gate 6 composes H6b (product-name lexical discipline).
# Gate 7 (infra grounding) composes H6a (still part of schema discipline — it's a
#   structural check on dealbreaker consistency, not a lexical check).

def validate(cell_output):
    # Gate 1: parses as JSON           → fails: parse_fail            → counts as H6a miss
    # Gate 2: exact 4-key scores schema → fails: schema_fail           → H6a miss
    # Gate 3: convention string         → fails: convention_fail       → H6a miss
    # Gate 4: scores int in [1,10]      → fails: score_type_fail       → H6a miss
    # Gate 5: composite recomputed      → never fails (always overwrites) — not a gate
    # Gate 6: banned-token scan         → fails: banned_token_fail:X   → H6b miss
    # Gate 7: infra grounding           → fails: infra_grounding_fail  → H6a miss
```

**Per cell:**
- Any gate fails → re-dispatch ONCE with stricter preamble naming the failure.
- Second failure → cell is `dropped` for that rerun. Record WHICH gate failed (H6a bucket or H6b bucket).

**Per rerun:**
- A rerun with ≥1 dropped cell (from either bucket) is INVALIDATED.
- H1/H2/H3 handling of invalidated reruns same as v10: counts as non-target for H1/H3, breaks 3-grid for H2 Sonnet/Opus, contributes to the 16/20 winner-bearing floor check for H2 Haiku.

**Per domain, three metrics computed independently:**

```
H6a_rate = schema_ok_cells     / 180   # passed gates 1, 2, 3, 4, 7
H6b_rate = lexical_ok_cells    / 180   # passed gate 6
H7_rate  = valid_reruns        / 20    # reruns with zero drops from either bucket
```

| Symbol | Definition |
|--------|------------|
| `schema_ok_cells` | cells that passed gates 1, 2, 3, 4, 7 after retry (independent of Gate 6 outcome). |
| `lexical_ok_cells` | cells that passed Gate 6 after retry (independent of other gates). |
| `valid_reruns` | reruns with zero dropped cells (i.e., every cell passed ALL gates, 1–7). |

**Worked example (cross-gate orthogonality):**

A domain has 20 reruns × 9 cells = 180 cells. Suppose 170 cells pass gates 1–5,7 on first try (H6a candidates 170); 150 of those also pass Gate 6 on first try. The other 20 lexical-fail and retry: 16 pass on retry, 4 still fail → H6b = 166/180 = 0.92. Meanwhile 10 cells initially failed gates 1–5,7: 7 pass on retry, 3 still fail → H6a = 177/180 = 0.98. `valid_reruns` is the count of reruns where ALL 9 cells are drop-free (NOT 20 minus total drops — drops may co-occur in the same rerun). If the 7 drops (3 H6a + 4 H6b) are spread across 7 distinct reruns, valid_reruns = 13 → H7 = 0.65 (fails 0.80). If the 7 drops are clustered in 3 reruns, valid_reruns = 17 → H7 = 0.85 (passes). Same total H6a/H6b rates, different H7 depending on drop distribution. This is why H7 is tracked independently and why per-rerun fail-bucket attribution is a required §9 diagnostic: clustered-vs-spread drops matter.

Passes gate → cell composite is usable for solo-winner extraction (Fix A). Solo winner extraction (Fix A) ignores combos/alts always — unchanged from v10.1.

**Authoritative:** §1 H6a, H6b definitions control. §7 mirrors §1 verbatim. §3.1 explains procedure. On any perceived conflict between sections, §1 wins.

---

## 4. Execution Plan

Identical to v10.3 §4. 20 Haiku reruns × 9 cells per domain × 4 domains = 720 Haiku cell dispatches. 3 Sonnet + 3 Opus reruns × 9 cells × 3 real domains = 162. Schema re-dispatches estimated 15–25% → ~150 extra. Blind-coding judges = 12. **Grand total: ~1,044 dispatches. Budget ~$8-9. Wall clock ~2–3h with parallelism.**

---

## 5. Blind Coding

Identical to v10.3 §5. Two judges (Haiku + Sonnet). Cohen kappa ≥ 0.75. Third judge is Pedro for disagreements. Co-error check in report.

**v11 addition (Fix B interaction):** Each blind-coding batch includes the rerun's Fix B permutation mapping (A→semantic, B→semantic, C→semantic) alongside the winner's cell number, label, and `mechanism_novelty` sentence. This is required for the judge to translate winner label to the semantic option before classifying into the 4-category taxonomy. Judges DO NOT see the solo winner's composite score, dealbreaker, or the non-winning cells' scores — only what is necessary to classify the mechanism description into one of the 4 pre-registered categories for that domain.

---

## 6. Synthetic Control D0

Unchanged. D0 first. If H5 fails (dominant category emerges on flat options), protocol ABORTS per §10. No amount of positive D1/D2/D3 results rescues that.

---

## 7. Analysis (Mirrors §1 Verbatim)

Analysis code at `docs/null-model-runs-v11/analyze.py`, written AFTER reruns complete, zero free choices.

Rules:

- **H6a (run first, all 4 domains):** compute `H6a_rate = schema_ok_cells / 180`. Fail H6a for any domain < 0.80.
- **H6b (run second, all 4 domains):** compute `H6b_rate = lexical_ok_cells / 180`. Fail H6b for any domain < 0.80.
- **H7 (run third, all 4 domains):** compute `H7_rate = valid_reruns / 20`. Fail H7 for any domain < 0.80.
- **For each domain, H1/H2/H3 are auto-FAILED if ANY of H6a, H6b, H7 failed for that domain.** Otherwise proceed.
- **H1:** for each of D1/D2/D3 where H6a, H6b, H7 all passed, identify each valid rerun's solo winner (Fix A, ties = non-target). Compute `target_count = count(valid reruns where solo winner's blind-classified semantic category == target)`. Denominator fixed at 20. Pass H1 if target_count ≥ 14 for ≥2 of 3 domains.
- **H2:** mirrors §1 H2 verbatim. Haiku 16/20 winner-bearing floor. Sonnet/Opus 3-grid drop-and-aggregate with 2/3 winner-bearing floor (v11 change): at least 2 of 3 reruns must be valid-and-winner-bearing, and those 2 or 3 must have a unique modal winner; otherwise H2 auto-fails for that model on the domain. Cross-model modal match required across Haiku, Sonnet, Opus. Pass ≥2/3 real domains.
- **H3:** exact binomial on target_count vs p₀=0.25, p<0.0125 for ≥2/3.
- **H4:** post-matrix falsification verdict distribution, no single verdict accounts for all 3.
- **H5:** D0 binomial on most-frequent semantic category vs p₀=0.25, p≥0.0125 = pass.

---

## 8. Protocol Amendments

v11 starts fresh. No amendments at pre-registration. Any deviation post-execution-start requires a dated Amendment section with:
1. Affected procedure.
2. Explicit justification.
3. Hypotheses affected.
4. **Amendment counts as failure for any hypothesis where it relaxes a threshold or substitutes a test.**

Precedence rule (retained from v10.1 Amendment 1): §1 is authoritative. §7 mirrors §1 verbatim. §3.1 is procedural. On conflict, §1 wins.

---

## 9. Expected Deliverable

`docs/null-model-validation-report-v11.md`:
- H1–H7 (including H6a, H6b split) pass/fail table with exact numbers.
- Per-lesson decision: which of L1–L11 are supported, downgraded, or retracted.
- Co-error check results.
- Diagnostic: per-domain position/label bias counts, semantic category distribution, product-name leakage examples (if any).
- **Required co-occurrence diagnostic (v11):** per-rerun fail-bucket attribution — for each invalidated rerun, tag which bucket(s) caused the drops: `H6a-only`, `H6b-only`, `both`. Reported as a 3-row table per domain. This surfaces whether H7 failure (if any) is driven by clustered same-bucket drops or by independent cross-bucket drops — important for diagnosing whether a future v12 should increase retry budget (clustered) or tighten a specific gate (independent).
- Updated idea-matrix skill PR (if findings warrant).
- Codex round invitation for v12 if any residual design flaw surfaces.

---

## 10. Abort Conditions

Protocol aborts on:
- Cumulative cost > 2× budget ($14).
- Kappa < 0.75 between model judges on any domain → that domain's H1/H3 = FAILED (per v2 rule), NOT full protocol abort.
- Pedro rejects conceptual-leakage review and cannot construct acceptable neutral prompts.
- **§10.5 (retained):** H6a rate for any domain < 0.50 after re-dispatches → domain auto-fails H6a/H1/H3; if ≥2 domains hit this, whole protocol aborts.
- **§10.6 (NEW in v11):** Post-hoc discovery that a pre-registered banned-token list contains ANY concept word (i.e., violates §2.3 design invariant) → protocol aborts AS-WRITTEN and the banned list must be corrected BEFORE any re-run, which requires a new pre-registration (v12+), not an amendment. **Remediation actor:** Pedro (Co-CEO) or his explicitly designated delegate revises the offending banned list(s) applying §2.3 decidability guidance, then spawns a Codex adversarial round on the revised lists before committing v12+ pre-registration. The delegate MUST produce a full audit trail (named delegation commit + revised list commit + Codex round output commit). Automated stripping is NOT permitted — every revision is a pre-registration event.

**Rule (unchanged):** every abort counts as failure of the relevant hypothesis. Never "inconclusive."

On abort, write `docs/null-model-validation-abort-v11.md`.

---

## 11. Changelog

### v10.3 → v11 (this version, full pre-registration after v10.3 abort)

v10.3 aborted per §10.5 on D1 (H6=0.283) and D3 (H6=0.239). Root cause: banned-token lists for those domains contained concept vocabulary (`cache`, `retry`, etc.) that Haiku cannot avoid when reasoning about the domain itself. This confound silently masqueraded as H6 failure. D0 (H5 p=0.38) and D2 (H1 14/20, H3 p=3e-5) both passed cleanly under Fix A + Fix B.

v11 changes (pre-registered, each specific):

| # | v10.3 flaw | v11 fix |
|---|------------|---------|
| 28 | H6 conflated schema discipline with prompt-banned-token compatibility. Domains with domain-intrinsic banned tokens failed H6 without indicating whether schema discipline itself was broken. | Split H6 → H6a (schema discipline, gates 1–5,7) and H6b (lexical product-name discipline, gate 6). Each has independent ≥0.80 threshold. Both gate H1/H2/H3. See §1 H6a/H6b and §3.1. |
| 29 | D1 banned list included concept words `cache, lru, ttl, eviction, invalidation, cdn` — impossible to avoid when describing caching mechanisms. | D1 banned list now product/library names only: `redis, memcached, hazelcast, ignite, couchbase, ehcache, varnish`. Env-block-mentioned infrastructure (`kubernetes, istio, grafana, prometheus, postgresql`) evaluated and EXCLUDED per the §2.3 env-block exception — banning them would inflate H6b failures from natural context echo. See §2 D1 (authoritative). |
| 30 | D3 banned list included concept words `retry, backoff, circuit, jitter` — impossible to avoid when describing retry mechanisms. Domain title "Retry strategy…" baked the concept into the prompt. | D3 banned list now product/library names only: `tenacity, hystrix, resilience4j, polly, opossum, failsafe`. Env-block-adjacent products (`redis, stripe, aws-sdk`) evaluated and EXCLUDED per the §2.3 env-block exception. Domain title rephrased to "Failure-handling strategy for a flaky external API" to remove concept word from problem statement. See §2 D3 (authoritative). |
| 31 | No pre-registered guard forced future banned lists to be product/library names only. Any future domain could silently repeat the v10.3 mistake. | §2.3 adds explicit design invariant: "banned tokens are product/library/service names only; concept vocabulary is never banned." §10.6 adds abort condition for post-hoc discovery of concept words in banned lists. |

v10.3 Amendments 2 and 3 (Fix A solo-only + Fix B balanced permutation) are PROMOTED from amendments to native v11 design. They are documented inline in §1 (Fix A) and §3 (Fix B) rather than as amendments, since they passed empirical validation on D0 (null) and D2 (positive signal).

### Prior version history

See git log for `docs/null-model-validation-protocol.md`. v1–v10.3 history summarized in v10.3 §11.
