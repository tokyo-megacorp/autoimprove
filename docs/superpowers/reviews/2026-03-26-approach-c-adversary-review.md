# Approach C (Parallel Tracks) -- Adversary Review

> Reviewer role: The Adversary. Attempts to debunk every finding. Penalized 3x for wrong debunks, so concedes when findings are genuinely valid.

---

## Finding 1: CRITICAL -- "LLM debate contradicts 'No LLM judge in v1'"

**Verdict: PARTIALLY VALID**

The Enthusiast conflates two distinct roles: (a) LLM agents as a **standalone review tool** (`/autoimprove review`) and (b) LLM agents as a **scoring judge in the grind loop**. The "No LLM judge in v1" principle in DESIGN.md is specifically about **scoring** -- the section reads: "The soft-quality signal (LLM-as-judge for 'is this prompt better?') is the noisiest, most expensive, and hardest-to-calibrate component. v1 uses only deterministic metrics."

Approach C is explicitly a "Parallel Tracks" design. The debate agents as standalone tools (`/autoimprove review`, `/autoimprove challenge`) do not participate in the keep/discard scoring loop. They are a separate feature track. The LLM is already used pervasively in autoimprove -- the Experimenter is an LLM agent, the Orchestrator uses LLM reasoning for theme selection. The design principle bans LLM **judgment of metric quality**, not LLM usage.

**What holds:** The `review_gate:` config option *does* wire LLM judgment into the loop, which genuinely conflicts with the v1 principle. If the optional review_gate is activated, the contradiction is real.

**What doesn't hold:** Claiming the standalone debate agents "obliterate" the principle is an overstatement. Three LLM agents that run outside the scoring loop are no more a violation than the Experimenter agent itself. The principle targets scoring, not all LLM usage. The severity should be HIGH (for the review_gate piece) not CRITICAL (for the agents' mere existence).

---

## Finding 2: CRITICAL -- "review_gate breaks evaluate.sh as single evaluator"

**Verdict: VALID**

I concede this one. Key Invariant #2 states unambiguously: "evaluate.sh is the single evaluator. All gate checks, benchmark runs, metric extraction, and verdict computation happen inside it. Only read the JSON output." A `review_gate:` that routes through debate agents and feeds a Judge verdict into keep/discard decisions creates a second evaluation pathway outside evaluate.sh. This is a genuine invariant violation.

The Enthusiast's reasoning is correct: the same code change could receive different debate verdicts on different runs, making experiments non-reproducible. This is precisely the kind of non-determinism the design was engineered to prevent.

**One caveat:** This only applies if `review_gate:` is activated. If Approach C ships the review_gate as opt-in and clearly documents that activating it relaxes the deterministic-only invariant, the contradiction is acknowledged rather than accidental. But as specified (no documentation of this tradeoff), the finding stands.

---

## Finding 3: CRITICAL -- "Token budget blow-up"

**Verdict: PARTIALLY VALID**

The math is correct but the framing is misleading. The Enthusiast calculates 1 + 3N agents per experiment (with N rounds), arriving at 10 agents for `--rounds 3`. This is accurate arithmetic. However:

1. **The debate agents only fire when `review_gate:` is active in the loop.** For standalone `/autoimprove review`, there is no experiment budget to blow -- it is a user-invoked tool with its own implicit session budget. The Enthusiast frames this as a universal problem but it only applies to the optional loop integration.

2. **Budget controls already exist.** `max_tokens_per_experiment: 100000` is the cap. If debate consumes the budget, the experiment halts at the budget check, not "before benchmarks run" as if that were some catastrophic failure. The budget system is *designed* to prevent runaway costs. Hitting the cap is the system working correctly, not a bug.

3. **The missing piece is real.** There is no debate-specific sub-budget (e.g., `max_tokens_for_review: 30000`). Without it, debate could crowd out the actual experiment. This is a legitimate spec gap.

**Net:** The concern about needing a debate-specific budget cap is valid. The apocalyptic framing ("consume the entire budget before benchmarks even run") ignores that budget enforcement already exists and would prevent exactly this. Severity should be HIGH (missing sub-budget), not CRITICAL (system-breaking blow-up).

---

## Finding 4: CRITICAL -- "Debate contaminates experimenter blindness"

**Verdict: DEBUNKED**

The Enthusiast's reasoning contains a fundamental logical error. They claim: "If debate agent output flows into keep/discard decisions, it creates a feedback channel that undermines the separation of concerns (experimenter can't game what it can't observe)."

This gets the blindness invariant backwards. Key Invariant #1 states: "Never include metric names, benchmark definitions, scoring logic, tolerance/significance, current scores, or evaluate-config.json in the **experimenter prompt**." The blindness constraint is about what goes *into* the Experimenter, not what happens *after* the Experimenter finishes.

Consider the existing flow: the Experimenter commits code, returns control to the Orchestrator, then the Orchestrator runs gates, benchmarks, and scoring. The Experimenter never sees the scoring output -- it has already terminated. Adding a debate step after the Experimenter commits changes nothing about experimenter blindness. The debate agents analyze the *output* of a completed experiment. The Experimenter is already done. There is no feedback channel because the Experimenter is not running when the debate happens.

The Enthusiast even acknowledges this indirectly: "the experimenter's changes are now being judged by subjective criteria it cannot observe or adapt to." Exactly -- it *cannot observe or adapt to* them. That is blindness working as designed. Post-hoc evaluation of a completed experiment, by any mechanism (deterministic or LLM), does not contaminate the experimenter's decision-making because the experimenter has already made all its decisions and terminated.

The DESIGN.md explicitly addresses this: "The point isn't perfect blindness; it's removing the direct numerical optimization gradient." Debate verdicts applied after experiment completion do not create an optimization gradient for the Experimenter because the Experimenter never receives them.

---

## Finding 5: CRITICAL -- "Unspecified loop insertion point"

**Verdict: VALID**

I concede this one. The Loop Flow in DESIGN.md specifies a precise sequence: EXPERIMENT -> HARD GATES -> BENCHMARKS -> SCORING -> KEEP/DISCARD. The Approach C proposal says `review_gate:` wires debate into the loop but does not specify where:

- **Before gates?** Wastes debate tokens on changes that fail tests.
- **After gates, before benchmarks?** Debate without metric context; saves benchmark cost on debate-rejected changes.
- **After benchmarks, before scoring?** Debate has full information but adds latency to every experiment.
- **As part of scoring?** Fundamentally changes the scoring model.

Each position has radically different cost, latency, and semantic implications. The Enthusiast is right that this is unspecified and that the spec needs to pick a position and justify it. This is a genuine gap.

---

## Scorecard

| # | Finding | Verdict | Severity Adjustment |
|---|---------|---------|-------------------|
| 1 | LLM debate contradicts no-LLM-judge | PARTIALLY VALID | CRITICAL -> HIGH (standalone agents are not the issue; review_gate is) |
| 2 | review_gate breaks evaluate.sh | VALID | CRITICAL confirmed |
| 3 | Token budget blow-up | PARTIALLY VALID | CRITICAL -> HIGH (budget enforcement exists; sub-budget is the real gap) |
| 4 | Debate contaminates experimenter blindness | DEBUNKED | Experimenter has terminated before debate runs; no feedback channel exists |
| 5 | Unspecified loop insertion point | VALID | CRITICAL confirmed |

**Summary:** 2 fully valid, 2 partially valid (with severity downgrades), 1 debunked. The Enthusiast's strongest findings (#2 and #5) correctly identify real invariant violations and spec gaps. The weakest finding (#4) misunderstands the direction of the blindness constraint -- post-hoc evaluation cannot contaminate a terminated agent. Findings #1 and #3 contain valid cores but are overstated in severity by conflating the standalone tools with the optional loop integration.
