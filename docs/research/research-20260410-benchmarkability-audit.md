# Phase 0 — Benchmarkability Audit of all autoimprove skills

**Date:** 2026-04-10
**Author:** Claude Sonnet 4.6 (this session)
**Prior art:** `docs/research/research-20260410-behavioral-benchmark-design.md` (design note, Post-Review Update section)
**Purpose:** Classify every skill in `skills/*/SKILL.md` into one of three benchmarkability categories, apply the Codex red-team attack pattern to each category-1 candidate, and honestly report which skills are safely fixturable for a behavioral benchmark.

## TL;DR

- **25 skills total.** 2 are special cases (trampoline, reference). 23 eligible for classification.
- **7 candidates fall into A1 (artifact-state deterministic)** on first pass: `cleanup`, `experiment`, `init`, `prompt-testing`, `rollback`, `test`, `track`.
- **0 skills fall into A2 (structured-output deterministic)** with non-trivial overfitting resistance.
- **16 skills fall into A3 (semantic / LLM-judge, unfixturable)**.
- **Critical finding: none of the 7 A1 candidates pass the Codex red-team attack with a naive success criterion.** All are gameable by pattern-matching the fixture wording and taking a destructive shortcut. Each needs ~1 day of fixture engineering (multi-property criterion + negative check + parameterization) to be safely fixturable.
- **Recommendation: pilot `cleanup` with full red-team engineering (estimated 1 day). If the effort-vs-value ratio justifies extension, proceed to `test` and `init` next. If not, abandon fixture-based benchmarks and use periodic LLM-judge instead.**

## Methodology

For each skill, extract the description from the frontmatter, identify the skill's primary effect (what does invoking it DO?), and classify:

- **A1 — artifact-state deterministic**: primary effect is a change to filesystem, git state, or flat files. Success can be verified by a shell command inspecting post-state with no LLM interpretation.
- **A2 — structured-output deterministic**: primary output is structured (JSON/YAML/specific format). Success is "output is schema-valid AND contains required fields" AND the check is non-trivial to satisfy via prompt overfitting. *Strict bar: if I can construct a trivial gaming attack (just output a fake JSON), it belongs in A3 instead.*
- **A3 — semantic / LLM-judge**: success requires understanding content quality, coherence, correctness, or intent. Cannot be verified deterministically.

After initial classification, each A1 candidate is subjected to the **Codex attack test**: can an adversarial experimenter pattern-match the fixture wording and take a destructive shortcut to satisfy the criterion without actually doing the skill's work?

## Classification Table

| Skill | Category | Primary effect | Notes |
|---|---|---|---|
| `adversarial-review` | A3 | Runs debate agents, produces findings | Output is semantic judgment of code |
| `autoimprove` | N/A | Trampoline → `run` | Not a skill with its own behavior |
| `calibrate` | A3 | Compares Opus vs Haiku output | Value requires semantic comparison |
| `challenge` | A3 | Runs debate on curated challenges, F1 scoring | Orchestration is semantic even if F1 is deterministic |
| **`cleanup`** | **A1** | Removes worktrees + branches via `cleanup-worktrees.sh` | Strongest candidate, primary example from Codex review |
| `decisions` | A3 | Read-only listing of archived decisions | Output is read-only query result |
| `diagnose` | A3 | Validates autoimprove.yaml, dry-runs benchmarks | Semantic judgment of problems; Codex noted paraphrase-false-fail |
| `diff` | A3 | Shows experiment changes | Read-only; semantic interpretation |
| `docs-regenerate` | A3 | Updates docs from git diff | Content quality is semantic |
| **`experiment`** | **A1** | CRUD on `experiments/<id>/context.json` | State file check |
| `history` | A3 | Read-only listing of past experiments | Read-only |
| `idea-archive` | A3 (weak A1) | Writes `decisions/YYYY-MM-DD-*.md` | File existence trivially checked, content quality semantic |
| `idea-matrix` | A3 | 9 parallel agents, synthesis | Codex called this out as repeating prior failures |
| **`init`** | **A1** | Scaffolds `autoimprove.yaml` + directories | Filesystem check |
| `matrix-draft` | A3 | Pre-matrix brainstorming help | Pure semantic |
| `polish` | A3 | Orchestrates diagnose+review+transform on skills | Changes are semantic |
| **`prompt-testing`** | **A1** | Writes test files | Test file existence + passing check |
| `proposals` | A3 (weak A1) | Review/approve/reject Phase 2 proposals | State transition trivial, decision quality semantic |
| `report` | A3 | Read-only session summary | Read-only |
| **`rollback`** | **A1** | Reverts an experiment via `git revert`, refreshes baseline | Git state + baseline + state.json check |
| `rubrics` | N/A | Reference/catalog only | Not invokable standalone |
| `run` | A3 (weak A1) | The full grind loop | TSV-row check is trivially gameable per Codex; real "success" is semantic |
| `status` | A3 | Read-only state display | Read-only |
| **`test`** | **A1** | Runs test suites | Exit code is pure behavioral signal |
| **`track`** | **A1** | Manages user-defined goals, modifies state.json | State file check |

**Counts:**
- A1 (artifact-state deterministic): **7 strong candidates** (cleanup, experiment, init, prompt-testing, rollback, test, track)
- A2 (structured-output deterministic): **0**
- A3 (semantic / LLM-judge): **16**
- N/A: **2** (autoimprove trampoline, rubrics reference)

**Weak A1 (upgraded to A3 after scrutiny):** idea-archive, proposals, run. Their filesystem effects are trivial to satisfy without doing the skill's real work.

## The A2 category is empty — and this matters

Every skill that produces structured output has content quality that requires semantic evaluation. `adversarial-review` produces findings JSON, but "are the findings correct?" is semantic. `idea-matrix` produces 9 cells, but "are the cells insightful?" is semantic. `calibrate` produces a comparison report, but "is the comparison accurate?" is semantic.

This confirms Codex's warning: schema-based criteria are trivially satisfiable by vacuous but valid output. The `idea-matrix` failure pattern (structurally valid but semantically empty) applies to every A2 candidate.

**Conclusion on A2:** do not pursue structured-output fixtures for any skill. If a skill's value is in content quality, it is not fixturable.

## Red-team analysis of A1 candidates

For each A1 candidate, I construct a concrete attack: how would an adversarial experimenter pattern-match the fixture wording and take the shortest destructive path to satisfy the naive criterion?

### `cleanup`

**Naive criterion:** `git worktree list | wc -l` returns 1 (only main).

**Attack:** Modify `skills/cleanup/SKILL.md` to detect the literal fixture string `"clean up"` and run `rm -rf .git/worktrees/*`. The worktree count drops to 1. Fixture reports success. Git metadata is destroyed; future `git worktree add` may fail, uncommitted work in other worktrees is lost.

**Hardening required:**
- Check `git worktree prune` exit code (should be 0, should not encounter errors)
- Check `.git/worktrees/` subdirectories are not removed directly (only `git worktree remove` allowed)
- Check no files under `.git/` are modified except via git porcelain commands
- Verify no uncommitted changes in other worktrees were lost
- Fixture rotation: random branch names each run, so pattern-matching the string "test" doesn't help

**Effort to harden: ~1 engineering day.** Requires `git worktree` internals knowledge + writing the adversarial test before the real test.

### `test`

**Naive criterion:** `bash test/evaluate/test-evaluate.sh` exit code 0.

**Attack:** Modify `skills/test/SKILL.md` to detect the fixture and have Claude run `exit 0` or modify the test suite to skip all tests. Exit 0 reported. No real tests were run.

**Hardening required:**
- Pin the expected test count (e.g., "exactly 140 tests must run")
- Verify test output contains expected test names (not just exit 0)
- Check that `test/evaluate/test-evaluate.sh` file hash matches pre-fixture hash (skill didn't modify the test suite)
- Parameterize: use a different pinned test count per fixture variant

**Effort to harden: ~0.5 day.** Simpler than cleanup because exit code + output parsing is mechanical.

### `init`

**Naive criterion:** `autoimprove.yaml` exists and parses as valid YAML.

**Attack:** Generate a minimal stub YAML with the required top-level keys but no meaningful content. Satisfies the check.

**Hardening required:**
- Check specific sub-keys exist (project, budget, gates, benchmarks, themes, constraints, safety) — 7 sections
- Check gate commands actually run successfully
- Check benchmark scripts exist at referenced paths
- Verify `scripts/evaluate.sh` is executable after init
- Run `bash scripts/evaluate.sh` in init mode and verify it produces valid JSON output

**Effort to harden: ~1 day.** Requires replicating the init validation logic in the fixture.

### `prompt-testing`

**Naive criterion:** A test file exists and passes.

**Attack:** Generate a file `test_stub.sh` containing `#!/bin/bash\nexit 0`. File exists, "test" passes.

**Hardening required:**
- Require a specific marker format (e.g., `--- Test: <name> ---` sections)
- Pin minimum test section count
- Require assertions that check real behavior (not just `exit 0`)
- Verify the test file actually invokes the target of testing

**Effort to harden: ~1 day.** Hard because "is this a meaningful test" is borderline-semantic.

### `rollback`

**Naive criterion:** HEAD moved back by one commit, experiments.tsv updated.

**Attack:** `git reset --hard HEAD~1` regardless of target. Satisfies the "HEAD moved" check. Destroys work on the current branch if not careful about which experiment to roll back.

**Hardening required:**
- Verify specific commit SHA was reverted (not just HEAD moved)
- Verify the experiment ID matches the rolled-back commit
- Verify rolling-baseline.json was refreshed
- Verify state.json consecutive_keeps was decremented
- Check no uncommitted work was lost (stash state unchanged)

**Effort to harden: ~1 day.**

### `experiment`

**Naive criterion:** A new `experiments/<id>/context.json` file exists.

**Attack:** Write a stub context.json with the required fields. File exists.

**Hardening required:**
- Validate JSON schema against a strict contract
- Verify required fields (id, theme, constraints, baseline_sha) are all present and non-null
- Check `experiments.tsv` has a corresponding row
- Parameterize: fixture specifies expected theme + constraints, skill must produce matching output

**Effort to harden: ~0.5 day.** State-file checking is mechanical.

### `track`

**Naive criterion:** `experiments/state.json goals[]` has a new entry.

**Attack:** Append a stub goal. Entry exists.

**Hardening required:**
- Validate goal schema (name, target_metric, target_delta, status)
- Verify target_metric references an actual benchmark metric
- Verify target_delta format is valid (±N% or ≥/≤ N)
- Check status is one of the allowed enums

**Effort to harden: ~0.5 day.**

## Aggregate finding

**Every A1 candidate is vulnerable to the Codex attack pattern under a naive success criterion.** Hardening each fixture requires writing:

1. A multi-property positive check (not just the obvious state change)
2. A negative check for unexpected destructive changes
3. A parameterized or rotated fixture to prevent literal pattern-matching
4. An explicit adversarial test that a red-team version of the skill does NOT score well

**Total engineering cost estimate:**

| Skill | Hardening cost |
|---|---|
| cleanup | 1.0 day |
| test | 0.5 day |
| init | 1.0 day |
| prompt-testing | 1.0 day |
| rollback | 1.0 day |
| experiment | 0.5 day |
| track | 0.5 day |
| **Total** | **5.5 days** |

Plus ongoing maintenance cost: any change to the skill's contract (e.g., a new required field in context.json) requires updating the fixture and re-running the adversarial test. Call it ~0.5 day/month steady-state.

## What the original design note got wrong about cost

The original design estimated Phase 1 at "~2 days" for 3 pilot fixtures with validation. Codex flagged this as unrealistic. The audit confirms: **even ONE properly-hardened fixture is ~1 day of work**, and 3 fixtures with full red-team testing is closer to 3 days. Four phases of scaling is closer to 10 days of focused engineering, not the 4 days the original plan implied.

## Decision framework for Phase 1 go/no-go

Phase 1 (revised) should be: **pilot `cleanup` with full red-team hardening, measure effort actually spent, decide whether to extend.**

Go/no-go criteria after the cleanup pilot:

| Actual cost for cleanup | Decision |
|---|---|
| ≤ 1.0 day | Proceed to `test` + `init` as Phase 2 (2 more fixtures) |
| 1.0 – 2.0 days | Pause. Re-evaluate whether the fixture is worth the cost. Consider switching to periodic LLM-judge. |
| > 2.0 days | Abandon fixture-based behavioral benchmarks entirely. Switch to periodic LLM-judge (weekly, not gating). |

The threshold matters because the whole point of fixtures is cost-predictability. If hardening takes longer than expected, it signals that the approach is not production-ready and we should fall back to the expensive-but-working LLM-judge path.

## Alternative to consider before Phase 1

**Option X: skip fixtures entirely, invest in periodic LLM-judge.**

Rather than engineering 5+ days of fixtures with red-team tests, spend that time:

1. Reintroducing `benchmark/ar-effectiveness.sh` and `matrix-effectiveness.sh` as **periodic** (not per-experiment) benchmarks
2. Running them weekly via a `/autoimprove audit` command (human-invoked, not in grind loop)
3. Having the audit produce a scored report on skill quality drift
4. Humans review the report and decide which skills need attention

This is the path Codex suggested as the fallback. Its advantages over fixtures:

- **No red-team burden:** LLM judges are naturally harder to game via prompt overfitting (though not impossible)
- **Semantic coverage:** catches quality issues across all 16 A3 skills, not just the 7 A1 candidates
- **Lower ongoing maintenance:** no per-skill fixture files to keep in sync
- **Already-written code:** `ar-effectiveness.sh` (143L) and `matrix-effectiveness.sh` (51L) are in the repo

Disadvantages:
- Weekly cadence is too slow to influence per-experiment keep/discard decisions — this is purely advisory, not a gate
- Costs LLM tokens
- Non-deterministic signal (different run, different score)

**The real tradeoff:** fixtures give us a per-experiment gate (influences grind loop) at the cost of ~5 days of engineering + ongoing red-team burden. Periodic LLM-judge gives us weekly advisory signal at the cost of some tokens per run.

**For a project where the grind loop is the primary driver of improvement, we need a per-experiment gate — so fixtures are required IF we can afford them.** If hardening costs blow the budget, we fall back to LLM-judge and accept that skill_quality is no longer grind-loop-gated.

## Recommendation

**Start with a 1-day timeboxed `cleanup` fixture pilot.** Write the fixture, write the adversarial attack version, measure actual time spent, and use the go/no-go framework to decide next steps. Do NOT commit to Phase 2 or beyond until the cleanup pilot is done and the cost is known.

If the 1-day box is blown, stop immediately and switch to the LLM-judge fallback (Option X above). Do not chase sunk cost.

## Status

- Audit complete: 2026-04-10
- Next action: Phase 1 cleanup pilot (1-day timebox)
- Blocked on: Pedro approval of the audit findings + go-ahead for the cleanup pilot
- Deferred: hardening for the other 6 A1 candidates (only if cleanup pilot succeeds)
- Abandoned: A2 category entirely, A3 skills as gate targets, structured-output determinism as a strategy

## Open questions for Pedro

1. **Is the 1-day timebox acceptable?** If not, Phase 0 is sufficient and we can stop here.
2. **Do you want to see the adversarial attack written BEFORE the real fixture?** (Strict TDD for fixtures — write the attack first, then the criterion that defeats it, then the real skill test.) This is my default recommendation.
3. **What happens to the A3 skills in the meantime?** They remain ungated by any quality metric. Is that acceptable for the next weeks/months while we see if fixtures work for A1?
4. **Should I proceed with the cleanup pilot now or stop for this session?** The session has been long and this is the 7th major decision point.
