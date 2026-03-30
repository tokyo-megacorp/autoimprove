# Calibration Protocol

Cross-model calibration measures the quality gap between Opus (gold standard) and Haiku (cheap) on the same adversarial-review input. The output is a structured gap report that identifies blind spots and generates concrete prompt improvement suggestions.

## What Calibration Does and Why

Claude models at different capability tiers produce different quality outputs on the same task. The grind loop uses cheaper models (Haiku/Sonnet) for cost efficiency. Without calibration, we don't know:

- Which findings Haiku consistently misses
- Whether Haiku is adding noise (false positives)
- Whether Haiku findings lack the depth needed to be actionable
- What specific prompt changes would close the gap

Calibration answers these questions by running both models on the same input and comparing outputs with a Sonnet evaluator.

**Why a separate skill instead of a built-in benchmark:**
The adversarial review's Enthusiast→Adversary→Judge pattern already uses three sequential agents. Adding an inline Opus comparison would bloat every AR run. Calibration is a separate diagnostic tool run on demand — not every review needs it.

## Goodhart Boundary (What MUST NOT Happen)

> "When a measure becomes a target, it ceases to be a good measure." — Goodhart's Law

The `gap_score` output from calibration is **diagnostic only**. Strict prohibitions:

1. **NEVER add `gap_score` or `haiku_find_rate` to `autoimprove.yaml` benchmarks.** If the grind loop targets these metrics, the model will learn to produce structurally similar outputs rather than actually improve reasoning quality.
2. **NEVER let calibration results automatically trigger theme selection or grind loop experiments.** Human reviews the findings and decides which prompt improvements to apply.
3. **NEVER use gap trends as a success metric for autoimprove sprints.** Coverage metrics (test pass rate, benchmark regressions) are valid; calibration gap is not.

**What the experimenter sees:**
- "Your adversary prompt misses exit-code checks in shell scripts — add this explicit instruction."

**What the experimenter does NOT see in any automated pipeline:**
- "gap_score dropped from 7.2 to 4.1 — experiment succeeded."

## Phase 1 Scope

Phase 1 (issue #56) is hardcoded for `adversarial-review` only.

**Why AR first:** It is the most frequently run skill in the grind loop. Finding Haiku's blind spots here has the highest leverage — every experiment's quality gate runs AR.

**Usage:**
```
/calibrate adversarial-review diff
/calibrate adversarial-review <file-path>
/calibrate adversarial-review pr <number>
```

**Phase 1 inputs supported:**
- `diff` — current working-tree diff (`git diff HEAD`, fallback to `git diff --staged`)
- `<file-path>` — read a specific file
- `pr <number>` — fetch PR diff via `gh pr diff`

## How to Interpret gap_score

The `gap_score` (0–10) measures divergence between Opus and Haiku outputs:

| Score | Interpretation | Action |
|-------|---------------|--------|
| 0–2 | Haiku matches Opus quality | No immediate action needed |
| 3–4 | Minor gaps — mostly depth/evidence differences | Review `depth_gaps`, consider small prompt additions |
| 5–6 | Moderate gaps — some classes of findings missed | Apply `prompt_improvements` for missed categories |
| 7–8 | Significant gaps — Haiku missing critical findings | Prioritize prompt improvements in next grind cycle |
| 9–10 | Severe gaps — models are diverging on fundamental issues | Escalate: consider model upgrade for AR or complete prompt rewrite |

**Target:** `gap_score < 3` and `haiku_find_rate ≥ 80%`.

The `haiku_find_rate` (0.0–1.0) is the fraction of Opus findings that Haiku also found. A rate of 0.8 means Haiku found 80% of what Opus found.

## How to Apply prompt_improvements

Each `prompt_improvements` entry in the gap report specifies:
- `target`: which agent file to modify (`agents/enthusiast.md`, `agents/adversary.md`, or `agents/judge.md`)
- `improvement`: exact text to add or change
- `reason`: why this change closes the specific gap observed

**Process:**
1. Run `/calibrate adversarial-review diff` on a representative input
2. Review the gap report — check that each `prompt_improvements` entry is grounded in a real missed finding
3. Apply the improvements to the target agent files manually
4. Run calibration again on a different input to verify the gap closed
5. Repeat until `gap_score < 3`

**Do not apply all improvements at once.** Change one agent at a time to isolate which changes are effective. The grind loop's A/B comparison mechanism is the right tool for systematic improvement; calibration is the diagnostic that tells you what to target.

## LCM Signal Storage

Each calibration run stores a signal via `lcm_store`:
```
tags: ['signal:calibration', 'skill:adversarial-review', 'model:opus-vs-haiku']
content: gap_score, haiku_find_rate, missed count, false positive count, improvement count, summary
```

If LCM is unavailable, results are written to `~/.autoimprove/calibration/` as dated JSON files.

These signals accumulate a longitudinal record of calibration runs. The autoimprove harvester can query them with `lcm_search(tags: ['signal:calibration'])` to identify trends — but only for human review, not for automated theme injection (see Goodhart Boundary above).

## Phase 2 Roadmap

Phase 2 is deferred until gap_score has been measured at least **3 times manually** for adversarial-review. This baseline requirement ensures Phase 2 automation is grounded in empirical data, not speculation.

**Phase 2 planned scope:**
- Generic skill wrapping: `/calibrate <any-skill> <input>`
- `xgh:dispatch` adapter for weekly cron automation (scheduled calibration)
- Calibration trend tracking: longitudinal gap_score visualization
- Automatic grind loop theme suggestions from calibration signals (with human approval gate)

**Phase 2 trigger:** Pedro or Co-CEO session confirms 3+ calibration runs with logged LCM signals.

Tracked in: ipedro/autoimprove#57
