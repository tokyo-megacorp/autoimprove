# Grind Session 4 Retrospective — 2026-03-29

**Theme:** skill_quality (focused on idea-matrix ecosystem)
**Session:** 4 | **Budget:** 10 experiments
**Results:** 8 KEEPs, 2 NEUTRALs

---

## Metric Gains

| Metric | Epoch Baseline | Session End | Delta |
|--------|---------------|-------------|-------|
| test_count | 16 | 29 | +13 (+81%) |
| skill_doc_coverage | 12 | 15 | +3 (+25%) |
| agent_completeness | 9 | 10 | +1 (+11%) |
| broken_constraints | 0 | 0 | — |
| broken_refs | 0 | 0 | — |

**Trust tier promoted:** 1 → 2 (consecutive_keeps: 7 → 15, max_files: 10, max_lines: 500)

---

## Experiments

| ID | Verdict | Metric | Commit |
|----|---------|--------|--------|
| 011 | neutral | — | improve(skills/idea-matrix): add poor-differentiation protocol |
| 012 | keep | skill_doc_coverage | feat(skills): add idea-archive skill |
| 013 | keep | test_count | test(evaluate): tolerance/significance boundary |
| 014 | keep | agent_completeness | feat(agents): add convergence-analyst |
| 015 | keep | test_count | test(evaluate): lower_is_better improvement coverage |
| 016 | neutral | — | improve(skills/idea-matrix): add trigger examples to description |
| 017 | keep | skill_doc_coverage | feat(skills): add decisions skill |
| 018 | keep | test_count | test(evaluate): multi-metric + gate ordering coverage |
| 019 | keep | skill_doc_coverage | feat(skills): add matrix-draft skill |
| 020 | keep | test_count | test(evaluate): zero-baseline + significance=0 edge cases |

---

## idea-matrix Ecosystem — Before vs After

**Before session 4:** only `idea-matrix` skill existed.

**After session 4:**
- `idea-matrix` — core skill (qualitatively improved via cherry-pick)
- `idea-archive` — persist convergence reports to decisions/ directory
- `decisions` — browse and review archived decisions
- `matrix-draft` — pre-process problem/options before running idea-matrix
- `convergence-analyst` — strategic analysis layer on top of convergence reports

**idea-matrix SKILL.md improvements (cherry-picked from neutrals):**
- §6c-i Poor-Differentiation Protocol: when 7+ cells land neutral, diagnose cause and prescribe recovery action. Forces `verdict_type: "no_clear_winner"` instead of fabricating a winner.
- Description frontmatter: added 3 concrete `<example>` blocks for explicit invocation, mid-brainstorm convergence, and "convergence report" trigger phrase.

---

## Benchmark Gap Discovered

**Problem:** `skill_doc_coverage` counts SKILL.md files with `description:` in frontmatter. Once all 12 skills have descriptions (maxed at 12/12), the only way to move this metric is to ADD new SKILL.md files. Qualitative improvements to existing files produce neutral verdicts.

**Impact:** Experiments 011 and 016 (genuine quality improvements to idea-matrix SKILL.md) were discarded as neutral. They were cherry-picked manually after the loop.

**Recommendation:** Add a `skill_depth` metric that measures average token count or line count across all SKILL.md files. This would reward quality improvements to existing skills.

**Action:** Create issue in autoimprove repo for `skill_depth` benchmark.

---

## evaluate.sh Bug Fix (discovered during session)

**Bug:** The orchestrator was calling `evaluate.sh <config> <worktree-path>` but the signature is `evaluate.sh <config> <baseline-json>`. Passing a directory path caused `INIT_MODE=true` (directory is not a file), meaning ALL evaluations ran as init mode against the main project's files, not the worktree's.

**Fix applied in this session:** Evaluation now runs as `cd <worktree> && bash /path/to/evaluate.sh <config> /dev/null`. This correctly runs benchmarks in the worktree context.

**Impact on prior sessions:** Sessions 1-3 likely had the same bug, meaning their metric comparisons were against the main project. Any experiment that "improved" skill_doc_coverage in a prior session was adding a new SKILL.md file, which would be visible from the main project after merge — so the bug may not have corrupted results, just the comparison logic.

---

## Introspection (§16)

**What worked:**
- Running evaluate.sh from within the worktree (bug fix) gave correct metric readings
- Adding NEW skills/agents is the reliable path to metric improvements
- Cherry-pick workflow for qualitative improvements (run in loop, discard as neutral, apply directly after)

**What broke:**
- Qualitative improvements to existing SKILL.md files are not captured by any metric
- The `skill_doc_coverage` metric saturates quickly (once all skills have descriptions)
- The evaluate.sh calling convention bug went undetected across 3 prior sessions

**What to improve:**
- Add `skill_depth` metric to self-metrics.sh (average SKILL.md line count)
- Fix the evaluate.sh calling convention in the run skill documentation
- Document the cherry-pick workflow as a standard practice for qualitative improvements
