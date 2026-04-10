# Multi-Tenant Skills Refactor — Design Spec

**Date:** 2026-04-11
**Author:** Claude Sonnet 4.6 (via superpowers:brainstorming)
**Parent discovery:** MAGI `patterns/multi_tenancy_skill_architecture_bug.md` (2026-04-10)
**Approach refined via:** 5 idea-matrix runs (Q1–Q5) during this brainstorming session

## TL;DR

autoimprove skills hardcode CWD-relative paths to plugin-local helpers (`bash scripts/evaluate.sh`, `Read references/loop.md`, etc.). This breaks the moment a user installs autoimprove on any repo that isn't autoimprove itself — those paths resolve to the USER's CWD, not the plugin directory, and the files don't exist there.

This spec lays out a 5-decision refactor that:

1. **Rewrites `skills/test`** to delegate to `scripts/evaluate.sh --tests-only` (new flag)
2. **Moves `scripts/` → `skills/_shared/`** with uniform `${CLAUDE_SKILL_DIR}/../_shared/X.sh` references
3. **Keeps `SAFETY.md` at plugin root** with a documented double-parent exception (read-only, no uniformity pressure)
4. **Keeps `references/loop.md` and `tasktree.md` co-located** in `skills/run/references/` with zero-hop `${CLAUDE_SKILL_DIR}/references/X.md`
5. **Tests via env-var injection** added to `test/evaluate/test-evaluate.sh`, plus one manual end-to-end verification

## Context

### How we got here

Yesterday (2026-04-10) Pedro flagged during Phase 2 of the behavioral-benchmark pilot that "these skills are wrong bud, this is a plugin meant to autoimprove itself but also other repos." The discovery:

- autoimprove is a Claude Code plugin installed at `~/.claude/plugins/cache/<marketplace>/autoimprove/<version>/`
- Users invoke its skills from THEIR target project's CWD
- Several skills hardcode `scripts/X.sh`, `test/X.sh`, `references/X.md` as if CWD IS the plugin root
- The paths only resolve correctly when autoimprove improves itself (the dogfood case)

The dogfood trap: every experiment this session ran on autoimprove's own code, so relative paths resolved "correctly" by accident. The moment the plugin would be invoked on any other project, those same paths would be wrong.

### The fix mechanism

Claude Code v2.1.64+ provides `${CLAUDE_SKILL_DIR}` — an env-var substituted in skill body content (prose + bash blocks) that resolves to the absolute path of the skill's own directory. This is the canonical way to make a skill-local file reference portable.

With `${CLAUDE_SKILL_DIR}`:
- Skill-private content: `${CLAUDE_SKILL_DIR}/<file>` (zero hops, inside the skill)
- Cross-skill shared content: `${CLAUDE_SKILL_DIR}/../<other-skill>/<file>` (sibling, one hop)
- Plugin-root shared content: `${CLAUDE_SKILL_DIR}/../../<file>` (double-parent, exception)

The refactor picks a layout policy and applies `${CLAUDE_SKILL_DIR}` consistently.

### What's out of scope

- **Cross-tenant state file pollution.** autoimprove has three flat-file state stores (`experiments.tsv`, `context.json`, `epoch-baseline.json`) with no tenant namespacing. This IS a latent multi-tenancy bug but it's a deeper design concern. Flagged as a separate issue, not addressed here.
- **The `test` skill rewrite's legacy argument interface.** The current `[challenge|integration|evaluate|harvest|agents|skills|all]` suite selector is an abstraction leak from autoimprove's internal layout. This refactor drops it.
- **Declarative safety rules (Cell 9 Q3 alternative).** Converting `SAFETY.md` into Claude Code's native permission mechanisms (`allowed-tools` frontmatter, plugin.json deny lists) is a bigger architectural change and is out of scope.

## Scope

### Files changed

**New locations:**
- `skills/_shared/` (new directory) — replaces `scripts/`
- `scripts/evaluate.sh` — gets a new `--tests-only` flag

**Moved:**
- `scripts/evaluate.sh` → `skills/_shared/evaluate.sh`
- `scripts/cleanup-worktrees.sh` → `skills/_shared/cleanup-worktrees.sh`
- `scripts/theme-weights.sh` → `skills/_shared/theme-weights.sh`
- `scripts/harvest.sh` → `skills/_shared/harvest.sh`
- `scripts/harvest-themes.sh` → `skills/_shared/harvest-themes.sh`
- `scripts/ar-write-round.sh` → `skills/_shared/ar-write-round.sh`
- Other `scripts/*.sh` that skills reference — audited and moved accordingly

**Rewritten (content changes):**
- `skills/test/SKILL.md` — becomes a thin wrapper around `${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh --tests-only`; drops legacy suite argument interface
- `skills/run/SKILL.md` — Step 0 SAFETY.md load path, all scripts/ references, references/ reads
- `skills/run/references/loop.md` — all scripts/ references in the experiment loop steps
- `skills/cleanup/SKILL.md` — cleanup-worktrees.sh path
- `skills/rollback/SKILL.md` — evaluate.sh path
- `skills/init/SKILL.md` — evaluate.sh path (verification step only; the files it CREATES in the user's project are correct and unchanged)
- `skills/adversarial-review/SKILL.md` — ar-write-round.sh path
- `skills/calibrate/SKILL.md` — already updated yesterday (references SAFETY.md); path reference may need update for `${CLAUDE_SKILL_DIR}` pattern

**Touched as part of the refactor:**
- `scripts/evaluate.sh` — add `--tests-only` flag
- `autoimprove.yaml` — update `constraints.forbidden_paths` to reference new locations (`skills/_shared/**` instead of `scripts/**` and `benchmark/**`)
- `test/evaluate/test-evaluate.sh` — add env-var injection portability section

**Unchanged:**
- `SAFETY.md` (stays at plugin root)
- `skills/run/references/loop.md` and `tasktree.md` (stay in skills/run/references/)
- All scripts in `scripts/` that are NOT referenced by skills (autoimprove-trigger.sh, install-hooks.sh, replay-pattern-layer.sh — these are plugin infrastructure, not skill helpers)

### Decisions

#### Decision 1 (Q1) — `test` skill rewrite

**Winner: Cell 8 of Q1 matrix — `evaluate.sh` delegation with `--tests-only` flag.**

**Rationale:** `scripts/evaluate.sh` already reads `gates:` from `autoimprove.yaml` and runs them. It's already multi-tenant by design. The test skill's current implementation is a duplicate with hardcoded paths. The fix is to delegate, not refactor the duplicate.

**Changes:**

1. Add `--tests-only` flag to `scripts/evaluate.sh` (which becomes `skills/_shared/evaluate.sh` after Q2). The flag causes evaluate.sh to run gates[] and skip benchmarks[], then exit.

2. Rewrite `skills/test/SKILL.md` body to a thin wrapper. Argument interface becomes:
   - no argument → run all gates
   - `--quiet` → suppress per-gate output
   - `--gate <name>` → filter to a specific gate by name
   
   **DROP** the legacy `[challenge|integration|evaluate|harvest|agents|skills|all]` suite arguments. They were an abstraction leak — those names don't map to autoimprove.yaml gate names (which are `evaluate_tests`, `ar_effectiveness_smoke`, `no_padding`). Using them would cause silent no-ops (Cell 1's gotcha).

3. Implementation body:
   ```bash
   bash "${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh" --tests-only $ARGUMENTS
   ```

**For the dogfood case:** autoimprove's own `autoimprove.yaml gates:` already lists `bash test/evaluate/test-evaluate.sh`, `bash tests/test-ar-effectiveness.sh`, and `bash benchmark/gate-no-padding.sh`. Those commands resolve against the target project's CWD (autoimprove's own root when dogfooding), so existing behavior is preserved.

#### Decision 2 (Q2) — Script organization → `skills/_shared/`

**Winner: Cell 8 of Q2 matrix — `skills/_shared/` registry pattern.**

**Rationale:** Co-locating scripts with specific skills creates ambiguous ownership (who owns evaluate.sh?) and sibling-path rename traps. Keeping a flat `scripts/` at plugin root forces the `${CLAUDE_SKILL_DIR}/../..` double-parent pattern which is fragile against any future skill-nesting change. The `skills/_shared/` pattern solves both:

- Uniform single-hop sibling path `${CLAUDE_SKILL_DIR}/../_shared/X.sh` from any skill
- No ownership ambiguity — `_shared/` holds everything shared
- Underscore prefix (Python convention) signals "not a skill, utility code"
- Scripts live alongside skills in the `skills/` tree, keeping file layout flat
- No co-location ownership debates

**Blocking prerequisite (must verify before any file moves):**

**Does Claude Code's skill loader actually ignore underscore-prefixed directories under `skills/`?** If Claude Code tries to load `skills/_shared/` as a skill and fails (no SKILL.md, wrong structure), the entire decision collapses. The pre-implementation test:

1. Create `skills/_shared/` with a single placeholder file (`.keep` or `README.md`)
2. Run `/reload-plugins`
3. Invoke `Skill list` or attempt to load `_shared` as a skill
4. Verify: skills/_shared/ is NOT listed as a skill and does NOT cause any load error

If this check fails, revert to an alternative pattern (likely flat `scripts/` at plugin root with the `../../` double-parent exception, similar to SAFETY.md).

**Changes:**

- `git mv scripts/{evaluate,cleanup-worktrees,theme-weights,harvest,harvest-themes,ar-write-round}.sh skills/_shared/`
- Every reference updated to `${CLAUDE_SKILL_DIR}/../_shared/<script>.sh`
- Other scripts in `scripts/` (autoimprove-trigger, install-hooks, replay-pattern-layer) STAY at `scripts/` because they're plugin infrastructure not called from skills

**Updated Q1 decision:** the test skill's delegation path becomes `${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh --tests-only` (one hop, not `../../scripts/` two hops).

#### Decision 3 (Q3) — SAFETY.md location

**Winner: Cell 1 of Q3 matrix — SAFETY.md stays at plugin root (Pedro overrode the composite winner).**

**Rationale:** The sharpest insight in the Q3 matrix was Cell 1's read-only asymmetry argument: `SAFETY.md` is never INVOKED (like a script), only READ (as a document). The `${CLAUDE_SKILL_DIR}/../_shared/` pattern was designed to solve runtime path resolution for invoked scripts — that problem does not exist for read-only documents. A read path is just a string argument to the `Read` tool; one hop vs two hops is cosmetic, not functional.

Additionally: SAFETY.md has stature equivalent to `CLAUDE.md`, `README.md`, `DESIGN.md` — top-level policy documents. Moving it into `skills/_shared/` would bury it in a technical directory and hurt human discoverability.

The composite-winner (Cell 8 — two-file split with root stub + `_shared/` canonical) was rejected because the stub creates silent contributor-confusion risk (Cell 4's warning: contributors see the stub at root, edit it, changes silently discarded).

**Changes:**

- `SAFETY.md` stays at `autoimprove/SAFETY.md` (no file movement)
- `skills/run/SKILL.md` Step 0 reference updated from `Read SAFETY.md` (broken) to `Read "${CLAUDE_SKILL_DIR}/../../SAFETY.md"`
- `skills/run/references/loop.md` Step 3g (SAFETY.md inlining into experimenter prompts) updated the same way
- The double-parent exception is documented inline where it appears — a comment in the skill bodies explaining why this one file uses `../../` while everything else uses `../_shared/`

#### Decision 4 (Q4) — references/ location

**Winner: Cell A of Q4 (approved directly, no matrix) — keep `references/` in `skills/run/`.**

**Rationale:** `skills/run/references/loop.md` and `skills/run/references/tasktree.md` are run-skill-private. They're read only by `skills/run/SKILL.md`. Skill-private content belongs co-located with its owning skill, accessed via `${CLAUDE_SKILL_DIR}/references/X.md` (zero hops, inside the skill directory).

Moving them to `skills/_shared/references/` would be a layering violation — `_shared/` is for cross-skill content, and nothing else reads these files.

**Changes:**

- Files stay at `skills/run/references/loop.md` and `tasktree.md`
- `skills/run/SKILL.md` instruction updated from `Read references/loop.md` (broken) to `Read "${CLAUDE_SKILL_DIR}/references/loop.md"`
- Same for `tasktree.md`

#### Decision 5 (Q5) — Testing strategy

**Winner: Cell 8 of Q5 matrix — env-var injection unit tests added to `test/evaluate/test-evaluate.sh`.**

**Rationale:** The existing 442-test suite runs from the plugin's own CWD, which is exactly why it missed the portability bug. The fix is not a new test harness (Option C) or manual smoke (Option B) — it's extending the existing runner with a portability section that simulates the external-user CWD scenario deterministically:

1. `export CLAUDE_SKILL_DIR=<absolute path to a skill's dir>`
2. `cd $(mktemp -d)` — CWD is now explicitly NOT the plugin root
3. Invoke the refactored scripts via `bash "${CLAUDE_SKILL_DIR}/../_shared/X.sh"` — the exact pattern skills use
4. Assert exit 0 and expected behavior

This approach:
- Uses existing test infrastructure (no new harness)
- No LLM variance (no subagent dispatch)
- Runs in the same `bash test/evaluate/test-evaluate.sh` invocation (~18s)
- Mechanically replicates the exact external-user CWD scenario
- Regression-proofs the refactor

**Plus one manual end-to-end verification** post-refactor: invoke `/autoimprove cleanup --dry-run` from a non-plugin-root CWD once to confirm Claude Code's actual `${CLAUDE_SKILL_DIR}` substitution works at runtime. ~2 minutes. The env-var tests validate OUR use of the variable; the manual test validates the platform's substitution.

**Known limitation (out of scope for this refactor):** Cell 5 Q5 flagged that cross-tenant state file pollution is a latent bug — `experiments.tsv`, `context.json`, `epoch-baseline.json` have no tenant namespacing. If two users run autoimprove on different repos using the same plugin install, their state files might collide. This is NOT addressed by the refactor and is flagged as a separate open issue.

**Changes:**

- Add a new section to `test/evaluate/test-evaluate.sh`:

```bash
echo "=== Multi-tenant portability tests ==="

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test: evaluate.sh resolves via ${CLAUDE_SKILL_DIR}
echo "--- Test: evaluate.sh works from non-plugin-root CWD ---"
TMP=$(mktemp -d)
cd "$TMP"
export CLAUDE_SKILL_DIR="$PLUGIN_ROOT/skills/test"
# Create a minimal autoimprove.yaml with a trivial gate
cat > autoimprove.yaml <<EOF
gates:
  - name: trivial
    command: "true"
benchmarks: []
EOF
result=$(bash "${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh" --tests-only 2>&1 || true)
assert_eq "exit code 0 for trivial gate" "0" "$?"
cd "$PLUGIN_ROOT"
rm -rf "$TMP"

# Test: cleanup-worktrees.sh resolves via ${CLAUDE_SKILL_DIR}
echo "--- Test: cleanup-worktrees.sh works from non-plugin-root CWD ---"
# ... (similar pattern for cleanup, ar-write-round, etc.)
```

Target coverage: one env-var test per refactored script in `skills/_shared/`.

## Implementation ordering

The refactor has dependencies — doing steps out of order can produce broken intermediate states. The correct order:

### Phase 0 — Prerequisite verification (HARD BLOCK)

**Before touching any file:**

1. Create `skills/_shared/` as an empty directory (just a `.keep` or placeholder file)
2. Run `/reload-plugins`
3. Verify Claude Code does NOT try to load `skills/_shared/` as a skill
4. If verification fails: **STOP**. Revert the directory creation. Re-evaluate with Pedro — likely fall back to flat `scripts/` at plugin root with double-parent paths.
5. If verification passes: delete the placeholder, proceed to Phase 1

### Phase 1 — Add `--tests-only` flag to evaluate.sh

Before moving files, add the flag so the test skill rewrite can target it:

1. Edit `scripts/evaluate.sh` (at its current location, not yet moved)
2. Add `--tests-only` flag that skips the benchmarks loop and exits after gates
3. Run the existing test suite — `bash test/evaluate/test-evaluate.sh` should still pass (442 tests)
4. Commit: `feat(evaluate): add --tests-only flag`

### Phase 2 — Move `scripts/` → `skills/_shared/` (atomic)

In a single commit:

1. `git mv scripts/evaluate.sh skills/_shared/evaluate.sh` (and the other 5 scripts)
2. Update all references in skills, loop.md, autoimprove.yaml's `constraints.forbidden_paths`
3. Use `${CLAUDE_SKILL_DIR}/../_shared/<script>.sh` pattern uniformly
4. Update SAFETY.md references in `skills/run/SKILL.md` Step 0 and `loop.md` Step 3g to `${CLAUDE_SKILL_DIR}/../../SAFETY.md`
5. Update references/ reads in `skills/run/SKILL.md` to `${CLAUDE_SKILL_DIR}/references/X.md`
6. Run existing tests — must still pass
7. Commit: `fix(skills): move scripts/ → skills/_shared/ for multi-tenancy`

### Phase 3 — Rewrite test skill

1. Rewrite `skills/test/SKILL.md` body to delegate to `${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh --tests-only`
2. Drop the legacy suite argument interface
3. Add `--quiet` and `--gate <name>` argument handling
4. Test the rewritten skill via `/autoimprove test` in dogfood mode — should run the 3 gates and exit clean
5. Commit: `refactor(test): thin wrapper over evaluate.sh --tests-only`

### Phase 4 — Add portability tests

1. Edit `test/evaluate/test-evaluate.sh` to add the `=== Multi-tenant portability tests ===` section
2. Add one env-var injection test per refactored script
3. Run the full suite — new count should be 442 + N (where N = number of new portability tests)
4. Commit: `test(evaluate): add multi-tenant portability section`

### Phase 5 — Manual end-to-end verification

1. `cd $(mktemp -d)` in a real shell
2. Invoke `/autoimprove cleanup --dry-run` from that CWD
3. Verify the skill finds scripts via `${CLAUDE_SKILL_DIR}/../_shared/cleanup-worktrees.sh` and runs
4. Invoke `/autoimprove test` from the same CWD
5. Verify it runs autoimprove.yaml gates (if a minimal one was set up)
6. If either fails: investigate, fix, re-test
7. No commit for this step — just verification

### Phase 6 — Push

Push all Phase 1–4 commits to `main`. Each phase is a separate commit for clean history and easy revert.

## Testing strategy (consolidated)

- **Phase 0 prereq check:** blocking — must pass before any file changes
- **Existing 442 evaluate tests:** must still pass after every phase
- **Existing ar-effectiveness smoke (9 tests):** must still pass
- **Existing no_padding gate:** must still pass
- **New portability tests** (N new tests in test-evaluate.sh): catch `${CLAUDE_SKILL_DIR}` resolution bugs
- **One manual end-to-end smoke test** (Phase 5): catches Claude Code platform substitution bugs that env-var tests miss

## Open questions / deferred work

1. **Cross-tenant state file pollution.** `experiments.tsv`, `context.json`, `epoch-baseline.json` have no tenant namespacing. Separate issue; not addressed here.

2. **Declarative safety rules (Q3 Cell 9).** Converting `SAFETY.md` to Claude Code `allowed-tools` + `plugin.json` permissions would eliminate the per-experimenter token burn from inlining 130 lines into every prompt. Out of scope for this refactor.

3. **Automated multi-tenant harness (Q5 Cell 6).** The B+C sequential approach (manual smoke then automated harness) was runner-up in Q5. If Cell 8's env-var tests prove insufficient over time, revisit this as a follow-up.

4. **Other scripts in `scripts/` not referenced by skills.** `autoimprove-trigger.sh`, `install-hooks.sh`, `replay-pattern-layer.sh` are plugin infrastructure. They stay at `scripts/` because they're invoked directly by users or hooks, not by skills. If any of these turn out to be called from skills later, they'll need to move too.

5. **Init skill output files.** `skills/init/SKILL.md` creates files in the TARGET project (e.g., `benchmark/metrics.sh`). These references are correct — they're target-project paths, not plugin paths. The init skill's plugin-local references (to `scripts/evaluate.sh` for verification) need to update, but the generated files do not.

6. **`skills/calibrate/SKILL.md`** may have path references that weren't fully audited. The agent should verify during implementation.

## References

- **Q1 matrix:** conversation, idea-matrix run for test skill design. Winner Cell 8 (evaluate.sh delegation).
- **Q2 matrix:** conversation, idea-matrix run for script organization. Winner Cell 8 (skills/_shared/).
- **Q3 matrix:** conversation, idea-matrix run for SAFETY.md location. Composite winner Cell 8 overridden by user preference for Cell 1 (root).
- **Q5 matrix:** conversation, idea-matrix run for testing strategy. Winner Cell 8 (env-var injection).
- **Claude Code docs:** `${CLAUDE_SKILL_DIR}` added in v2.1.64. Substitutes in skill body (prose + bash blocks). Not in frontmatter hooks (known bug, GitHub issues #36135, #30578).
- **Known gotcha:** `/reload-plugins` destroys symlinks in plugin directory — rules out symlink-based hybrids.
- **MAGI notes:**
  - `patterns/multi_tenancy_skill_architecture_bug.md` (2026-04-10) — original discovery
  - `patterns/three_layer_fixture_threat_model.md` (2026-04-10 corrected) — related portability finding
  - `patterns/repo_local_safety_md_portable.md` (2026-04-10) — SAFETY.md creation context
- **Session 25 commits:** `1a0bf5e`, `e77d31f`, `430dec8` — related infrastructure changes

## Status

Design approved by Pedro via brainstorming flow 2026-04-11. Ready to transition to `writing-plans` skill for detailed implementation plan.
