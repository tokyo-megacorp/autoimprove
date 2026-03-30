# Idea Matrix — Parallel Adversarial Review

**Problem:** How to parallelize the adversarial review (Enthusiast + Adversary) to cut wall-clock time, while preserving debate quality. Constraint: Agent tool is fire-and-forget (no streaming).

## Score Matrix

| Cell | Option | Feas. | Risk | Synergy | Cost | Avg | Dealbreaker | Verdict |
|------|--------|-------|------|---------|------|-----|-------------|---------|
| 1 | A alone (Independent Adversary) | 4 | 2 | 1 | 2 | 2.25 | YES | Debate collapses into monologues — Judge guesses matches |
| 2 | B alone (Pipeline per file) | 3 | 2 | 2 | 3 | 2.50 | YES | Cross-file findings lost, quadratic aggregation |
| 3 | C alone (Teammate relay) | 3 | 2 | 2 | 3 | 2.50 | YES | Async overhead makes it slower than sequential |
| 4 | A + B | 4 | 3 | 5 | 3 | 3.75 | -- | High synergy but needs prototyping |
| 5 | A + C | 3 | 2 | 4 | 2 | 2.75 | YES | Fire-and-forget kills mid-task communication |
| 6 | B + C | 3 | 2 | 4 | 2 | 2.75 | YES | Message ordering breaks finding_id pairing |
| 7 | A + B + C | 2 | 2 | 1 | 1 | 1.50 | YES | Over-engineered, coordination overhead > gains |
| 8 | D (Two-pass hybrid) | 4 | 3 | 4 | 3 | 3.50 | -- | Round 1 parallel + Round 2+ sequential = sweet spot |
| 9 | E (Dual Enthusiast) | 4 | 2 | 3 | 3 | 3.00 | YES | Adversary still bottleneck, zero parallelism gain |

## Dimension Aggregates

| Dimension | Avg | Min | Max | Cells scoring 1-2 |
|-----------|-----|-----|-----|-------------------|
| Feasibility | 3.3 | 2 | 4 | Cell 7 |
| Risk | 2.2 | 2 | 3 | Cells 1,2,3,5,6,7,9 |
| Synergy | 2.9 | 1 | 5 | Cells 1,2,3,7 |
| Impl. Cost | 2.4 | 1 | 3 | Cells 1,5,6,7 |

**Risk is the weakest dimension overall** (avg 2.2/5). Every option carries non-trivial risk — this is an inherently constrained problem space.

## Dealbreaker Filter

**7 of 9 cells have dealbreakers.** Only 2 survive:

| Rank | Cell | Score | Option |
|------|------|-------|--------|
| 1 | 4 (A+B) | 3.75 | Independent Adversary + Pipeline per file |
| 2 | 8 (D) | 3.50 | Two-pass hybrid |

## Cluster Analysis

- **Solo options (cells 1-3):** All dealbreakers. No single mechanism solves the problem alone.
- **Hybrids with C (cells 5-7):** All dealbreakers. Teammate relay is architecturally mismatched to debate cycles. SendMessage is async and turn-boundary-scoped — no mid-task streaming.
- **E (Dual Enthusiast):** Doesn't address the bottleneck (Adversary). More findings = more Adversary work = slower.
- **Survivors (cells 4, 8):** Both involve parallel round-1 execution. D is simpler; A+B has higher ceiling.

## Critical Tension: Cell 4 vs Cell 8

**Cell 4 (A+B)** scores highest (3.75) but inherits dealbreakers from A (ungrounded debate) and B (cross-file loss) that the cell-4 agent dismissed as resolved by the combination. This is optimistic — the combination might work, but the component risks don't disappear, they compound.

**Cell 8 (D — Two-pass hybrid)** scores 3.50 with no dealbreaker inheritance:
- Round 1: E and A run in parallel, both independently reviewing code
- Round 2+: Standard sequential E→A→J with full context from round 1
- Preserves the existing schema (verdicts[] keyed by finding_id) in rounds 2+
- Only round 1 needs a new Adversary prompt (independent defense mode)

## Top Insights

1. **"Orthogonal critique is a feature, not a bug"** (Cell 8): Round 1 independent Adversary produces broader coverage than targeted rebuttal — it catches things the Enthusiast missed entirely. This *increases* total coverage vs sequential-all-the-way.

2. **"Teammate relay is mismatched to debate"** (Cell 3, 5, 6, 7): SendMessage is turn-boundary-scoped, not mid-turn streaming. Debates need tight feedback loops; teammates excel at independent tasks. Every hybrid involving C failed.

3. **"Per-file splitting destroys the highest-value signal"** (Cell 2, 7): Cross-file findings (imports, type dependencies, architectural coupling) are the most valuable debate targets. File-level isolation loses exactly the findings worth debating.

4. **"Adversary is the critical path"** (Cell 9): Any option that doesn't reduce Adversary's serial wait doesn't save wall-clock time. Dual Enthusiast adds findings but doesn't parallelize the bottleneck.

5. **"Two agents seeing the same code independently = deduplication tax is real but manageable"** (Cell 4, 8): Judge handles overlapping findings naturally through its matching logic. The tax exists but is O(N) not O(N^2).

## Recommended Design

**Winner:** D (Two-pass hybrid) — score 3.50/5

**Verdict:** Go with conditions

**Why it emerged:** Only option that preserves debate quality (sequential rounds 2+) while cutting round-1 time in half. The surprise insight — independent round 1 produces orthogonal critique — turns a compromise into an upgrade. Lower implementation cost than A+B (no per-file splitting, no Judge aggregation changes). Minimal schema changes (only round-1 Adversary prompt differs).

**How it works:**

```
Round 1 (parallel):
  Enthusiast ──┐
               ├→ Judge (matches findings to defenses, initial rulings)
  Adversary ──┘
  (Adversary prompt: "Review this code independently. Defend what's correct. Output defenses[].")

Round 2+ (sequential, standard):
  Enthusiast(code + prior_rulings) → Adversary(code + findings) → Judge(findings + verdicts)
  (Standard prompts, full debate quality, converges from round-1 seed)
```

**Conditions:**
1. Round-1 Adversary must produce structured `defenses[]` output that Judge can match to findings (need a defense schema)
2. Judge round-1 logic must handle findings+defenses (not findings+verdicts) — branching in Judge prompt based on round number

**Dealbreakers avoided:**
- A alone: ungrounded debate (fixed by rounds 2+ being sequential)
- B alone: cross-file signal loss (not splitting by file at all)
- C/teammates: async overhead (not using teammates)

**Required mitigations:**
- Round-1 Judge matching quality — if Judge can't reliably match defenses to findings, round-1 rulings will be noisy. Mitigation: accept noisier round-1 as "broad pass", rely on rounds 2+ for precision.

**Recommended improvements:**
- From Cell 4: If single-file targets are common, consider file-level E+A parallelism as a v2 optimization
- From Cell 9: Single Enthusiast with richer multi-angle prompting (security + correctness + performance) instead of dual agents

**First step:** Modify SKILL.md section 3a/3b to dispatch E and A in parallel for round 1 only. Add round-1 Adversary prompt variant that reviews code independently. Add Judge round-1 matching logic.

## Structured Data

```json
{
  "problem": "Parallelize adversarial review while preserving debate quality",
  "ranking": [
    { "cell": 4, "label": "A + B", "composite": 3.75, "dealbreaker": false },
    { "cell": 8, "label": "D (Two-pass hybrid)", "composite": 3.50, "dealbreaker": false },
    { "cell": 9, "label": "E (Dual Enthusiast)", "composite": 3.00, "dealbreaker": true },
    { "cell": 5, "label": "A + C", "composite": 2.75, "dealbreaker": true },
    { "cell": 6, "label": "B + C", "composite": 2.75, "dealbreaker": true },
    { "cell": 2, "label": "B alone", "composite": 2.50, "dealbreaker": true },
    { "cell": 3, "label": "C alone", "composite": 2.50, "dealbreaker": true },
    { "cell": 1, "label": "A alone", "composite": 2.25, "dealbreaker": true },
    { "cell": 7, "label": "A + B + C", "composite": 1.50, "dealbreaker": true }
  ],
  "by_score_band": { "strong": 0, "neutral": 2, "weak": 7 },
  "convergence": {
    "winner": "D (Two-pass hybrid)",
    "winner_cell": 8,
    "winner_composite": 3.50,
    "verdict_type": "conditional",
    "conditions": [
      "Round-1 Adversary must produce structured defenses[] matchable by Judge",
      "Judge must branch on round number for findings+defenses vs findings+verdicts input"
    ],
    "reasoning": "Only option preserving debate quality while cutting round-1 time 2x. Surprise upside: orthogonal critique improves coverage.",
    "dealbreakers": [
      { "cell": 1, "reason": "Debate collapses into ungrounded monologues" },
      { "cell": 2, "reason": "Cross-file findings destroyed" },
      { "cell": 3, "reason": "Async teammate overhead slower than sequential" },
      { "cell": 7, "reason": "Coordination overhead exceeds parallelism gains" }
    ],
    "top_insights": [
      "Independent round-1 Adversary produces orthogonal critique — increases total coverage",
      "Teammate relay is architecturally mismatched to debate (async turn-boundary, not streaming)",
      "Per-file splitting destroys highest-value cross-file findings",
      "Adversary is the critical path — options not reducing its serial wait save zero time",
      "Deduplication tax for parallel independent review is O(N) and manageable by Judge"
    ],
    "required_mitigations": [
      "Accept noisier round-1 rulings as broad pass; rely on rounds 2+ for precision"
    ],
    "recommended_improvements": [
      "Single Enthusiast with multi-angle prompting instead of dual agents (from Cell 9)",
      "File-level parallelism as v2 optimization for large targets (from Cell 4)"
    ]
  },
  "errors": 0
}
```
