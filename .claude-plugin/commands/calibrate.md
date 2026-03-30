---
name: calibrate
description: "Run cross-model calibration for autoimprove skills — compare Opus (gold standard) vs Haiku (cheap) on the same input to identify reasoning gaps. Phase 1: adversarial-review only."
argument-hint: "adversarial-review <file|diff>"
---

This command runs the calibrate skill to measure the quality gap between Opus and Haiku on adversarial-review tasks.

## Arguments

| Argument | What is calibrated |
|----------|--------------------|
| `adversarial-review diff` | Current working-tree diff (default input) |
| `adversarial-review <file-path>` | A specific file |
| `adversarial-review pr <number>` | A GitHub PR diff |

## Usage Examples

```
# Calibrate on the current working diff
/calibrate adversarial-review diff

# Calibrate on a specific file
/calibrate adversarial-review src/scripts/evaluate.sh

# Calibrate on a GitHub PR
/calibrate adversarial-review pr 42
```

## What It Does

1. Gathers the target input (diff, file, or PR).
2. Spawns Opus and Haiku agents **in parallel**, each running an adversarial code review on the same input.
3. Spawns a Sonnet evaluator to compare the two outputs and compute a gap report.
4. Displays the gap report: missed findings, false positives, depth gaps, and concrete prompt improvements.
5. Stores a calibration signal via `lcm_store` (or writes to `~/.autoimprove/calibration/` if LCM unavailable).

## Output

```
## Calibration Report — adversarial-review

Gap Score: 4/10  (target: <3)
Haiku Find Rate: 65%  (target: ≥80%)

Missed by Haiku (2 findings)
  - [CRITICAL] evaluate.sh exits 0 on missing jq — gates never fire
  - [HIGH]     Rolling baseline updated before gate check

Prompt Improvements Recommended (2)
  - Target: agents/adversary.md
    Change: Add explicit check for shell script exit codes on missing dependencies
    Reason: Haiku skips this class of issue without a direct prompt cue
```

## Goodhart Boundary

- The `gap_score` is **diagnostic only** — it is never added to `autoimprove.yaml` benchmarks.
- It is never used as a grind loop metric or to influence theme selection weights.
- Results are for human review: decide which `prompt_improvements` to apply manually.

## Phase 1 Scope

Hardcoded for `adversarial-review` only. Generic skill wrapping (`/calibrate idea-matrix`, etc.) is deferred to Phase 2.

**Phase 2 trigger:** gap_score measured at least 3 times manually before automation.

## Related Commands

- `/adversarial-review` — the skill being calibrated
- `/autoimprove run` — grind loop whose prompts are improved via calibration output
