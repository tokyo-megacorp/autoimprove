# Debate Agents & Code Challenges — Design Spec

**Date:** 2026-03-26
**Status:** Draft
**Author:** Pedro + Claude
**Validated by:** 6-round adversarial debate (Enthusiast/Adversary/Judge)

## Overview

Three debate agents (Enthusiast, Adversary, Judge) that review code through structured adversarial debate. Available as standalone plugin agents and as post-verdict advisory annotations in the autoimprove loop. Code challenges provide deterministic benchmarks for calibrating agent accuracy.

This feature was designed and validated using the debate agents themselves — the spec was reviewed through 6 rounds of Enthusiast/Adversary/Judge debate, producing 22 unique actionable modifications.

## Architecture

### Agents

Three plugin agents in `.claude-plugin/agents/`:

| Agent | Role | Incentive Structure |
|---|---|---|
| **Enthusiast** | Aggressively find issues. High recall, low precision expected. | Rewarded per-finding by severity. Hyper-enthusiastically flags everything. |
| **Adversary** | Debunk Enthusiast's findings. Aggressive but cautious. | Gains points for correct debunks. 3x penalty for wrong debunks. |
| **Judge** | Arbitrate competing claims. Determine ground truth. | Rewarded for matching ground truth. Penalized for errors. |

**Flow:** Sequential per round. Enthusiast -> Adversary -> Judge. Each round builds on prior round output.

**Verdict resolution:** Last round wins. The final round's Judge has the most context (all prior rounds' findings and verdicts) and produces the authoritative ruling.

**Convergence early-exit:** If round N's Judge agrees with round N-1 on all findings (no new findings, no verdict changes), remaining rounds are skipped.

**Duplicate detection:** Each round's Enthusiast receives prior rounds' findings. New findings must reference prior finding IDs when overlapping. The Judge flags duplicates in rulings.

### Output Schema

All three agents produce structured JSON:

```json
{
  "round": 1,
  "enthusiast": {
    "findings": [
      {
        "id": "F1",
        "severity": "critical|high|medium|low",
        "file": "src/parser.ts",
        "line": 42,
        "description": "Off-by-one in boundary check",
        "evidence": "Line 42 uses `<` but the loop is 0-indexed with length comparison",
        "prior_finding_id": null
      }
    ]
  },
  "adversary": {
    "verdicts": [
      {
        "finding_id": "F1",
        "verdict": "valid|debunked|partial",
        "severity_adjustment": "high",
        "reasoning": "Confirmed: the loop exits one iteration early..."
      }
    ]
  },
  "judge": {
    "rulings": [
      {
        "finding_id": "F1",
        "final_severity": "high",
        "winner": "enthusiast|adversary",
        "resolution": "Valid off-by-one. Change < to <= on line 42."
      }
    ],
    "summary": "2 findings confirmed, 1 debunked. Net: 1 high, 1 medium.",
    "convergence": false
  }
}
```

### Commands

**`/autoimprove review`** — Standalone debate on any target.

```
/autoimprove review [file|diff|PR] [--rounds N] [--single-pass]
```

- `--single-pass` is sugar for `--rounds 1`
- Default rounds auto-scaled by diff size: 1 round for <50 lines, 2 rounds for normal diffs, 3 rounds for >5 files. Override with `--rounds N`.
- Output: structured JSON + human-readable summary
- Standalone mode context envelope: file content, surrounding imports, recent git history for touched files. No loop metadata (theme, trust tier, experiment history).

**`/autoimprove challenge`** — Benchmark agents against ground truth.

```
/autoimprove challenge [--suite puzzles|all] [--language python|typescript|go|rust|all]
```

- v1: curated puzzles only. GitHub case studies deferred to v2 (reproducibility burden).
- Results logged to `experiments.tsv` with `type: challenge` for longitudinal tracking.
- Aggregate scoring: precision-weighted F1 (see Scoring section).

### Loop Integration (advisory only)

Debate runs **post-verdict** — after keep/discard is decided and logged. It never influences the keep/discard decision. This preserves the "no LLM judge in v1" principle.

- For **KEEP** experiments: reviews the merged diff on main.
- For **DISCARD** experiments: reviews the captured diff text (worktree already deleted — diff is data, not a directory).
- Configurable in `autoimprove.yaml`:

```yaml
debate:
  enabled: true
  default_rounds: 2
  convergence_exit: true
  max_tokens_per_debate: 30000
```

**Budget enforcement:** The orchestrator tracks cumulative tokens after each agent returns. If the sub-budget is exceeded, it refuses to spawn the next agent (coarse enforcement — cannot interrupt mid-agent).

**Experimenter blindness preserved:** Debate output is stored in `context.json` but explicitly excluded from the experimenter prompt template. Post-hoc analysis of a completed experiment cannot create a feedback channel to an already-terminated agent.

### context.json Addition

```json
{
  "debate_annotation": {
    "rounds": [ /* ... per-round output as above ... */ ],
    "final_summary": "2 findings confirmed (1 high: missing null check in parser)",
    "total_tokens_used": 24500
  }
}
```

### Morning Report Addition

```
Debate Annotations
  #003 test_coverage [KEEP]
    2 findings confirmed (1 high: missing null check in parser)
    Disagreements:
      F2: Enthusiast flagged race condition (HIGH) — Adversary debunked (test is single-threaded)
  #005 performance [DISCARD]
    0 findings (clean diff, discarded on metric regression)
```

The morning report surfaces disagreements — not just final verdicts. The value of debate IS the disagreement signal.

## Code Challenges

### Directory Structure

```
challenges/
  manifest.json              — index of all challenges
  python/
    off-by-one/
      challenge.py           — buggy code
      answer-key.json        — structured ground truth
      README.md              — description for humans
    null-handling/
      challenge.py
      answer-key.json
  typescript/
    type-narrowing/
      challenge.ts
      answer-key.json
    async-race/
      challenge.ts
      answer-key.json
  go/
    goroutine-leak/
      challenge.go
      answer-key.json
    interface-nil/
      challenge.go
      answer-key.json
  rust/
    lifetime-leak/
      challenge.rs
      answer-key.json
    unsafe-ub/
      challenge.rs
      answer-key.json
```

### Answer Key Schema

```json
{
  "challenge": "off-by-one",
  "language": "python",
  "bugs": [
    {
      "id": "B1",
      "file": "challenge.py",
      "line": 12,
      "type": "off-by-one",
      "severity": "high",
      "description": "Loop uses < instead of <= for inclusive range",
      "fix_pattern": "< instead of <=",
      "fix_pattern_mode": "substring"
    }
  ],
  "scoring": {
    "match_file": true,
    "match_line_range": 3,
    "match_type": true
  }
}
```

**`fix_pattern` matching:** Default is substring match against the agent's resolution text. Optional `fix_pattern_mode: "regex"` for patterns requiring regex. Never raw eval.

### Challenge Scoring

**Per-bug matching:** A finding matches a bug if it identifies the correct file, is within `match_line_range` lines, and matches the bug type. Field-level, deterministic — no NLP.

**Aggregate scoring:** Precision-weighted F1.

```
precision = true_positives / (true_positives + false_positives)
recall    = true_positives / (true_positives + false_negatives)
F1        = 2 * (precision * recall) / (precision + recall)
```

- `true_positives`: findings that match an answer key bug
- `false_positives`: findings that match no answer key bug
- `false_negatives`: answer key bugs with no matching finding
- Pass threshold: F1 >= 0.5

An agent that finds 3/3 bugs but reports 97 false positives scores differently than one with 3/3 and 0 false positives.

**Longitudinal tracking:** Challenge results are appended to `experiments.tsv` with `type: challenge`, enabling trend analysis over time. Same infrastructure as experiment tracking.

### manifest.json

```json
{
  "version": "1.0",
  "challenges": [
    {
      "id": "python/off-by-one",
      "language": "python",
      "difficulty": "easy",
      "bug_count": 1,
      "tags": ["boundary", "loop"]
    }
  ]
}
```

## Calibration

### Optimal Round Count

Derived from 6-round empirical calibration on this design spec:

| Use Case | Default Rounds | Rationale |
|---|---|---|
| Trivial diff (<50 lines) | 1 (`--single-pass`) | Not worth debating |
| Normal experiment | 2 | Catches architectural + implementation issues |
| Cross-module (>5 files) | 3 | + completeness gaps |
| Design review / security | 4 | + runtime failure modes |
| >4 rounds | **Avoid** | 60% duplicate rate, 3x cost per modification |

### Convergence Signal

**Stop when >40% of findings are duplicates.** Empirical data:

- Rounds 1-5: 0% duplicate rate
- Round 6: 60% duplicate rate (well past threshold)

### Per-Round Issue Classes

Each round catches a qualitatively different class of issue:

| Round | Class | Example |
|---|---|---|
| 1 | "This won't work" | Architectural contradictions |
| 2 | "This will be painful to build" | Implementation gaps |
| 3 | "You'll hit this during coding" | Completeness/spec omissions |
| 4 | "This breaks in production" | Runtime failure modes |
| 5+ | Diminishing returns | Repeats + low-severity edge cases |

### Adversary Calibration

The 3x penalty for wrong debunks produces a consistent 15-20% debunk rate across all rounds. This is the right balance — cautious enough to avoid suppressing valid findings, aggressive enough to filter noise.

### Cost Profile

- ~18K tokens per actionable modification (rounds 1-5)
- ~60K tokens per modification at round 6 (3x cost cliff)
- Total for 6-round design review: ~573K tokens, 22 unique modifications

### Smart Defaults in autoimprove.yaml

```yaml
debate:
  default_rounds: 2
  convergence_exit: true
  single_pass_threshold_lines: 50
  deep_review_threshold_files: 5
  deep_review_rounds: 3
  max_tokens_per_debate: 30000
  duplicate_exit_threshold: 0.4
```

## Robustness (from rounds 4-6)

Issues surfaced during runtime-focused review rounds:

| Issue | Resolution |
|---|---|
| Benchmark commands can hang | Wrap in `timeout ${config.timeout_seconds:-300}` |
| Concurrent sessions race on state files | Lockfile (`autoimprove.lock` with PID) at session start |
| Tab characters in commit messages corrupt TSV | Strip tabs before writing: `tr '\t' ' '` |
| `set -u` in evaluate.sh can exit with no JSON | Add ERR trap; validate stdout is non-empty JSON before parsing |
| Additive-only test constraint is prompt-only | Add pre-merge gate that diffs test files, rejects net assertion removal |
| `weights` vs `priorities` naming mismatch | Standardize on `priorities` everywhere; validate in parser |
| No preflight check for benchmark commands | Validate commands exist at session start with clear error message |
| O(M*N) jq forks in evaluate.sh | Refactor to single jq pass per benchmark output file |
| Extract metric uses eval | Restrict to json (jq) and regex (grep -oP) extractors only; no raw eval |

## What's Deferred to v2

| Feature | Reason |
|---|---|
| `review_gate:` as scoring signal | Requires LLM-as-judge infrastructure |
| GitHub-sourced case studies | Reproducibility burden (dependencies rot, builds break) |
| Mid-agent token interruption | Needs Claude Code runtime support |
| Debate influencing keep/discard | Violates "no LLM judge in v1" principle |
| Agent personas (search strategy diversity) | Data-driven, not speculative — add when stagnation data justifies |

## Adversarial Validation

This spec was stress-tested through 6 rounds of Enthusiast/Adversary/Judge debate:

| Round | Findings | Valid Mods | Debunked | Class |
|---|---|---|---|---|
| 1 | 31 | 5 | 1 | Architectural contradictions |
| 2 | 22 | 6 | 1 | Implementation gaps |
| 3 | 13 | 7 | 2 | Completeness gaps |
| 4 | 9 | 4 | 1 | Runtime robustness |
| 5 | 10 | 4 | 3 | Scale & philosophy |
| 6 | 5 | 2 | 3 (60% dupes) | Diminishing returns |
| **Total** | **90** | **28 (22 unique)** | **11** | |

All valid findings have been incorporated into this spec. The debate process itself served as the first proof-of-concept for the debate agents.
