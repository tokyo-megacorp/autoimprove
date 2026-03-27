# Approach C -- Adversary Review, Round 3

3x penalty for wrong debunks. I will be aggressive but honest.

---

## Finding 1: No dedup/convergence across rounds + undefined final verdict derivation

**VALID. Severity: HIGH.**

This is a genuine gap. The round 2 fixes defined the `rounds[]` array and `debate_summary.final_verdict`, but never specified how `final_verdict` is derived from the per-round `judge_verdict` entries. If round 1 Judge says "keep with concern" and round 2 Judge says "discard", what populates `final_verdict`? "Last round wins" is the obvious default but it is unstated. Similarly, there is no deduplication -- the Enthusiast in round 2 sees round 1 output and can restate findings in new language. The Judge in round 2 must rule on findings that overlap with round 1 rulings, with no mechanism to reference prior rulings as settled.

I considered debunking the dedup half (the Judge can simply reference round 1 verdicts), but that pushes dedup responsibility to the LLM without any structural support. At 3x penalty, the honest call is: the `final_verdict` derivation gap is real and the dedup concern is real. Both need one-paragraph spec additions.

---

## Finding 2: Challenge scoring has no aggregate formula

**VALID. Severity: HIGH.**

The round 2 resolution defined field-level matching (exact on file + defect_type, fuzzy on line_range). But aggregate scoring is genuinely unspecified. If a challenge pack has 5 planted bugs and the agent reports 8 findings, 3 of which match answer key entries, we have: recall = 3/5, precision = 3/8. Are the 5 false positives penalized? Is the score recall? F1? Raw count of true positives?

This matters because the challenge system's purpose is to measure agent quality over time. Without a defined aggregate metric, two challenge runs are not comparable. The Enthusiast is correct that a 100-finding report with 3 true positives should score differently than a 3-finding report with 3 true positives.

The fix is small (one formula definition), but the gap is real.

---

## Finding 3: `--rounds N>2` burns tokens with no convergence detection

**PARTIALLY VALID. Severity: MEDIUM (downgraded from HIGH).**

The Enthusiast is right that there is no early termination when rounds converge. But this is HIGH severity only if users routinely set `--rounds 5`. The default is 2. The round 2 fixes added coarse budget enforcement that skips remaining rounds when sub-budget is exhausted.

The real question: is convergence detection worth the complexity? It requires comparing Judge verdicts across rounds for semantic equivalence, which is either brittle (string match on verdict) or expensive (another LLM call). For a v1 feature with default N=2, the marginal round is exactly one extra round. The waste is bounded and small.

I am downgrading to MEDIUM because: (a) the budget cap already prevents runaway cost, (b) N=2 default means convergence detection saves at most 1 round, and (c) implementing convergence detection for N>2 is v2 complexity for a v1 feature. But the finding is valid in principle -- "no early exit" is a real gap.

---

## Finding 4: Standalone `/autoimprove review` lacks context

**PARTIALLY VALID. Severity: MEDIUM (downgraded from HIGH).**

The Enthusiast claims standalone mode "has no access to experiment metadata (theme, constraints, recent history, trust tier)." This is true but overstated. Standalone `/autoimprove review` is explicitly a separate feature track -- a general-purpose code review tool. It is designed to work without loop context. The absence of theme/constraints/trust is by design, not by omission.

What IS a valid gap: the spec does not define what context standalone mode DOES receive. Does it get the project's `autoimprove.yaml`? The test suite configuration? The benchmark definitions? If it gets nothing, it is a generic code reviewer that any LLM can do. If it gets project configuration, it can be meaningfully calibrated. The spec should define the standalone context envelope.

Downgraded because "lacks context" conflates "missing required data" with "operating in a different mode." But the undefined context envelope is a real gap.

---

## Finding 5: `fix_pattern` in answer key is a dead field

**VALID. Severity: MEDIUM.**

I want to debunk this -- `fix_pattern` could be documentation for human readers of the answer key. But the Enthusiast's argument is precise: if it is documentation-only, it should not be in the answer key schema that defines scoring fields. Its presence in the schema implies it participates in scoring, but no matching algorithm is specified.

The round 2 resolution (Finding 4) defined matching on `file`, `line_range`, and `defect_type`. `fix_pattern` and `severity` are in the schema but not in the matching algorithm. Either they participate in scoring (specify how) or they are metadata (move them out of the scoring schema into a separate `metadata` block). The field is genuinely ambiguous.

---

## Finding 6: 4-language coverage is 4x maintenance

**DEBUNKED. Severity: N/A.**

This is an opinion about implementation prioritization, not a design flaw. The Enthusiast argues that language-agnostic agents do not benefit from multi-language challenges "in proportion to the maintenance cost." But:

1. **The premise is wrong.** LLM agents are NOT equivalently capable across languages. Claude's Rust bug-finding ability differs meaningfully from its Python bug-finding ability. Language-specific challenges test language-specific blind spots.

2. **The maintenance math is inflated.** "4N sets of planted bugs, answer keys, and test harnesses" assumes each challenge is independently authored. In practice, the same logical bug (off-by-one, null check, resource leak) is translated across languages -- the answer key schema is identical, only the file paths and line numbers differ.

3. **This is a scope/priority call, not a design defect.** The spec can say "start with Python, add languages as needed." That is implementation guidance, not a design fix. The design supporting multiple languages is correct; the rollout order is a planning decision.

At 3x penalty, I am confident this is not a design bug. It is a "you could do less work" observation dressed up as a finding.

---

## Finding 7: Morning report compresses debate to 1 line

**PARTIALLY VALID. Severity: LOW (downgraded from MEDIUM).**

The round 2 resolution for Finding 8 explicitly defined the morning report format: "experiment ID, one-line Judge verdict, key concern raised." The Enthusiast now complains this loses disagreement signal. This is a feature request, not a design flaw.

The morning report is a summary artifact. Its job is triage: which experiments need human attention? The one-line format answers this. If the human wants debate depth, they open `context.json` which has the full `rounds[]` array. This is the same summary-then-drill-down pattern used everywhere in the system (experiments.tsv is a summary, context.json is the detail).

The Enthusiast's specific example ("4 findings, 2 conceded, 2 rebutted") is valid -- a disagreement ratio would be useful. But "add a disagreement count" is a LOW enhancement, not a MEDIUM design flaw. The compression is intentional.

---

## Finding 8: Tier 3 proposals and debate annotations are parallel review mechanisms

**DEBUNKED. Severity: N/A.**

This conflates two completely different things:

1. **Tier 3 proposals** are the Propose phase output -- large changes the system lacks autonomy to merge. They require human approval of CODE CHANGES.

2. **Debate annotations** are metadata about the review quality of ALREADY-DECIDED experiments. They do not require approval. They are informational.

These serve different purposes, appear at different times, and require different human actions. A Tier 3 proposal says "here is a change, approve or reject it." A debate annotation says "experiment #47 was auto-merged but the Adversary flagged a concern." The human triages them differently because they ARE different.

The Enthusiast asks "how they relate" -- they do not relate, any more than git log and git blame relate. Both involve git, both are human-readable, both appear in terminal output. They are not "parallel mechanisms" that need reconciliation.

---

## Finding 9: Challenge system has no longitudinal tracking

**VALID. Severity: MEDIUM.**

The core autoimprove loop has rich longitudinal tracking: `experiments.tsv` records every experiment, `context.json` captures per-experiment detail, epoch baselines track drift, trust tiers track capability growth. The challenge system has none of this. Each `/autoimprove challenge` run is a point-in-time snapshot with no persistence.

If the challenge system's purpose is to measure agent reliability over time (which it is -- the spec says challenges are for "calibrating trust in the debate agents"), then longitudinal tracking is essential. You need to answer: "are the agents getting better at finding bugs?" Without history, you cannot answer this.

The fix is straightforward: append challenge results to a `challenges.tsv` or similar, with timestamp, agent versions, corpus version, and aggregate score. This is consistent with the system's existing pattern of flat-file logging.

---

## Summary

| # | Finding | Verdict | Severity |
|---|---------|---------|----------|
| 1 | No dedup/convergence + undefined final verdict | **VALID** | HIGH |
| 2 | No aggregate scoring formula | **VALID** | HIGH |
| 3 | No convergence detection for N>2 rounds | **PARTIALLY VALID** | MEDIUM (from HIGH) |
| 4 | Standalone review lacks context | **PARTIALLY VALID** | MEDIUM (from HIGH) |
| 5 | `fix_pattern` is a dead field | **VALID** | MEDIUM |
| 6 | 4-language maintenance burden | **DEBUNKED** | N/A |
| 7 | Morning report compresses debate | **PARTIALLY VALID** | LOW (from MEDIUM) |
| 8 | Proposals and annotations are parallel mechanisms | **DEBUNKED** | N/A |
| 9 | No longitudinal challenge tracking | **VALID** | MEDIUM |

**Score: 5 VALID, 2 PARTIALLY VALID, 2 DEBUNKED.**

The Enthusiast found real gaps in findings 1, 2, 5, and 9 -- all are genuine spec omissions that need one-paragraph fixes. Findings 3 and 4 are valid in principle but overstated in severity. Findings 6 and 8 are not design flaws.
