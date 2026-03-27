# Round 2 Final Verdicts -- The Referee

## Finding 1: Annotation has no schema/consumer/reader -- write-only artifact

**FINAL VERDICT: Enthusiast wins. Severity: HIGH.**

The Adversary conceded this one outright and they were right to. The context.json schema has no `annotation` or `debate_summary` field. The morning report template has a fixed format with no annotation section. This is a textbook write-only artifact -- the system generates debate output and stores it nowhere that any downstream consumer reads. Resolution: either add a `debate_summary` field to context.json and an "Annotations" section to the morning report, or don't generate the annotation at all. I lean toward adding both -- the data is valuable, but only if it is readable.

## Finding 2: max_tokens_per_debate has no enforcement mechanism

**FINAL VERDICT: Enthusiast wins with Adversary's qualification. Severity: HIGH.**

The Adversary correctly notes that mid-agent token interruption does not exist in Claude Code -- you cannot kill a spawned agent at exactly 30K tokens. But refusing to spawn the next round is coarse enforcement that works. The real gap: the spec names `max_tokens_per_debate` as a sub-budget but specifies no enforcement pathway. Resolution: spec must define enforcement as "orchestrator tracks cumulative debate tokens across rounds; if budget exhausted, skip remaining rounds and emit the Judge verdict on available evidence." This is a one-paragraph addition, not an architectural change.

## Finding 3: Worktree deletion before debate can read diff

**FINAL VERDICT: Adversary wins. DEBUNKED.**

The Adversary is unambiguously correct. Git diffs are captured as text strings before the worktree is deleted. The debate agents receive the diff as input data, not as a live filesystem. The worktree is gone but the diff persists. This was a misunderstanding of the data flow. No spec change needed.

## Finding 4: Answer key comparison is unsolved NLP

**FINAL VERDICT: Split decision. Severity: MEDIUM.**

Both sides have a point. The Adversary is right that structured answer keys (file path, line number, defect type, fix pattern) enable deterministic field-level matching -- you compare `{file: "auth.js", line: 42, type: "null_check"}` against the agent's output, not free-text similarity. But the Enthusiast is right that the spec is silent on format. Resolution: spec must define an answer key schema (JSON with file/line/type/description fields) and a deterministic matching algorithm (exact match on file+type, fuzzy on line number within +/-5). This is straightforward engineering, not unsolved NLP.

## Finding 5: GitHub case studies are non-reproducible

**FINAL VERDICT: Enthusiast wins. Severity: HIGH.**

The Adversary conceded and correctly so. External GitHub repos rot: dependencies break, CI configs change, build systems evolve. A challenge suite that references `octocat/spoon-knife@v2.3` will fail in 6 months when that tag is deleted or the build system changes. No lightweight solution is specified. Resolution: v1 challenge suites must be local-only (planted bugs in `test-project/` or the target project itself). GitHub sourcing is a v2 feature that requires pinned snapshots (vendored tarballs, not live git clones). Remove GitHub sourcing from v1 scope entirely.

## Finding 6: Single-pass vs multi-round output schema mismatch

**FINAL VERDICT: Adversary wins. Severity: LOW (downgraded from MEDIUM).**

The Adversary is right that a `rounds[]` array handles both shapes trivially -- single-pass is `rounds: [{ enthusiast, adversary, judge }]`, multi-round is `rounds: [r1, r2, ...]`. This is routine data modeling. Resolution: spec should define the output schema explicitly (always a `rounds[]` array), but this is a 5-line schema definition, not an architectural concern. Downgraded to LOW.

## Finding 7: Context vs budget tension

**FINAL VERDICT: Split decision. Severity: MEDIUM (downgraded from HIGH).**

Both sides are right about different things. The tension is real: debate agents need the full diff as context, and diffs can be large. But the Adversary correctly notes that trust tiers bound diff size (Tier 0: 150 lines, Tier 1: 300 lines, Tier 2: 500 lines). A 500-line diff fits comfortably in 30K tokens of sub-budget alongside agent prompts. The tension exists but is manageable within existing constraints. Resolution: spec should note that debate context is bounded by trust tier max_lines and that the 30K sub-budget assumes worst-case Tier 2 diffs. No architectural change needed.

## Finding 8: Morning report has no annotation section

**FINAL VERDICT: Enthusiast wins. Severity: HIGH (downstream of #1).**

This is the consumer side of Finding 1. The morning report template in DESIGN.md has fixed sections (Summary, Kept Experiments, Notable Discards, Full log). There is no "Debate Annotations" or "Review Notes" section. If debate annotations are generated but never surfaced in the report, the human never sees them. Resolution: add an optional "Review Annotations" section to the morning report that appears when debate data exists. Format: experiment ID, one-line Judge verdict, key concern raised. This is additive -- it does not change the existing sections.

---

## Overall Scorecard

| # | Finding | Winner | Final Severity |
|---|---------|--------|---------------|
| 1 | Write-only annotation | Enthusiast | HIGH |
| 2 | No budget enforcement | Enthusiast (qualified) | HIGH |
| 3 | Worktree deletion timing | Adversary (debunked) | N/A |
| 4 | Answer key comparison | Split | MEDIUM |
| 5 | GitHub case studies | Enthusiast | HIGH |
| 6 | Output schema mismatch | Adversary | LOW |
| 7 | Context vs budget tension | Split | MEDIUM |
| 8 | Morning report gap | Enthusiast | HIGH |

**Enthusiast: 4 wins. Adversary: 2 wins. Split: 2.**

---

## Required Design Modifications Before Implementation

### Must-fix (block implementation)

1. **Define debate output schema.** Add to spec: `rounds[]` array, each containing `{ enthusiast_argument, adversary_argument, judge_verdict, round_number }`. Single-pass is `rounds.length === 1`. This is the data contract everything else depends on.

2. **Add debate fields to context.json.** New optional field: `debate_summary: { rounds: [...], final_verdict: string, token_cost: number }`. Written only when debate runs.

3. **Add "Review Annotations" section to morning report.** Appears when debate data exists. Format per experiment: `#ID verdict "key concern"`. Fixes findings 1 and 8 simultaneously.

4. **Define max_tokens_per_debate enforcement.** Orchestrator tracks cumulative debate tokens. If exhausted before all rounds complete, Judge renders verdict on available evidence. Skip remaining rounds. One paragraph in the spec.

5. **Define answer key schema for challenge suites.** JSON format: `{ file, line_range, defect_type, fix_pattern, severity }`. Matching algorithm: exact on file + defect_type, fuzzy (+/-5 lines) on line_range. Deterministic, no LLM comparison.

6. **Remove GitHub sourcing from v1 challenge suites.** Local-only planted bugs. GitHub case studies deferred to v2 with vendored snapshot requirement.

### Should-fix (improve quality but do not block)

7. **Document that debate context size is bounded by trust tier max_lines.** Explicit note that 30K sub-budget assumes worst-case Tier 2 (500-line diff).

8. **Remove review_gate from v1 entirely** (per Revised Approach C -- confirm this is reflected in DESIGN.md, not just stated in the debate preamble).

### Already resolved (no action needed)

9. Worktree deletion timing (Finding 3) -- debunked, no change needed.
10. Output schema mismatch (Finding 6) -- trivially solved by always using `rounds[]` array.
