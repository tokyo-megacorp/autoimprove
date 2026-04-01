# Skills Reference

autoimprove has 8 skills organized into three feature groups: the grind loop, adversarial review, and design exploration.

---

## autoimprove

**Purpose:** Top-level alias for the autonomous experiment grind loop. Exists so callers can invoke `Skill(autoimprove)` or `/autoimprove` directly.

**Trigger:** "start autoimprove", "run the main autoimprove loop", `/autoimprove`

**Arguments:** `[--experiments N] [--theme THEME]`

**What it does:**

1. Loads the [run](#run) skill instructions
2. Preserves the user arguments exactly
3. Executes the same orchestrator flow as `run`

**Tools:** Read, Write, Edit, Bash, Glob, Grep, Agent

---

## init

**Purpose:** Scaffold `autoimprove.yaml` and project configuration for a new target codebase.

**Trigger:** "set up autoimprove", "configure autoimprove for this repo", `/autoimprove-init`

**What it does:**

1. Detects project type (Node.js, Python, Rust, Go, Claude Code plugin) by checking for `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, or `.claude-plugin/plugin.json`
2. Detects test command and type checker from project config
3. Asks the user about benchmark metrics (test count, TODO count, SLOC, test-to-code ratio, custom scripts)
4. Generates `autoimprove.yaml` with sensible defaults for gates, benchmarks, themes, trust ratchet, and safety
5. Creates `benchmark/metrics.sh` if a script-based benchmark is needed
6. Creates `experiments/` directory and `experiments/evaluate-config.json`
7. Runs `evaluate.sh` in init mode to verify gates and benchmarks work

**Tools:** Read, Write, Edit, Bash, Glob

**Next step after init:** Edit `autoimprove.yaml` to tune thresholds, then `/autoimprove-run --experiments 3` for a trial.

---

## run

**Purpose:** Run the autonomous experiment grind loop — spawn experiments, score them, keep or discard via git worktrees.

**Trigger:** "start autoimprove", "run experiments", `/autoimprove-run`

**Arguments:** `[--experiments N] [--theme THEME]`

**What it does:**

1. **Prerequisites check** — verifies `autoimprove.yaml`, `scripts/evaluate.sh`, and `jq` exist
2. **Session start** — reads config, generates `evaluate-config.json`, captures epoch baseline, loads state, performs crash recovery (cleans orphaned worktrees)
3. **Experiment loop** — for each experiment:
   - Picks a theme (weighted random, respecting cooldowns and stagnation)
   - Spawns an [experimenter](agents.md#experimenter) agent into an isolated git worktree
   - Experimenter makes changes and commits (blind to metrics/scoring)
   - Runs `evaluate.sh` against rolling baseline
   - Applies set logic: any regression = discard, at least one improvement + no regressions = keep
   - Updates rolling baseline, trust tier, and stagnation counters
   - Checks epoch drift — halts session if cumulative drift exceeds threshold
4. **Session end** — prints summary, persists state

**Tools:** Read, Write, Edit, Bash, Glob, Grep, Agent

**Key invariants:**
- Experimenter is blind to metrics (never receives benchmark definitions or scores)
- `evaluate.sh` is the single evaluator (no LLM in the scoring loop)
- Epoch baseline is frozen (never modified after creation)
- All worktrees are cleaned up (every code path removes the worktree)
- Test modification is additive only

See [Architecture](architecture.md) for the full loop flow and safety mechanisms.

---

## report

**Purpose:** Show a session summary — experiments run, kept vs discarded, score trends, metric drift.

**Trigger:** "show the report", "what experiments were kept", `/autoimprove-report`

**Arguments:** `[--since <date>] [--experiment <id>]`

**What it does:**

1. Reads state files: `experiments.tsv`, `state.json`, `epoch-baseline.json`, `rolling-baseline.json`
2. Computes summary: total experiments, verdict breakdown (kept/neutral/regressed/failed/crashed), stagnated themes, trust tier
3. Computes metric drift: `(rolling - epoch) / epoch * 100` for each metric, flags drift exceeding threshold
4. Formats a human-readable report with kept experiments, notable discards, stagnated themes, and metric trends

**Tools:** Read, Bash

---

## adversarial-review

**Purpose:** Run a multi-round Enthusiast → Adversary → Judge debate review on code.

**Trigger:** "adversarial review", "debate review", "run a review round", `/autoimprove-review`

**Arguments:** `[file|diff] [--rounds N] [--single-pass]`

**What it does:**

1. **Parse arguments** — extracts target (file path, glob, or "diff"), round cap, single-pass flag
2. **Gather target code** — reads file(s) or runs `git diff HEAD` / `git diff --staged`
3. **Initialize telemetry** — creates run folder at `~/.autoimprove/runs/<RUN_ID>/` with `meta.json`
4. **Debate rounds** — loops until deterministic convergence or round cap:
   - Spawns [enthusiast](agents.md#enthusiast) → finds bugs/issues (JSON output)
   - Spawns [adversary](agents.md#adversary) → challenges findings, debunks false positives (JSON output)
   - Spawns [judge](agents.md#judge) → arbitrates, renders verdicts (JSON output)
   - Checks convergence: compares `(finding_id, winner, final_severity)` tuples between rounds
   - Writes incremental `round-N.json` to telemetry folder
5. **Format output** — presents confirmed findings, debunked findings, unresolved findings, and summary
6. **Write telemetry** — writes final `run.json` and updates `meta.json` with counts

**Tools:** Read, Glob, Grep, Bash, Agent

**Telemetry output:** `~/.autoimprove/runs/<RUN_ID>/` contains `meta.json`, `round-N.json` (per round), and `run.json` (final). See the [output schema reference](../skills/adversarial-review/references/output-schema.md) for full details.

**Convergence:** The orchestrator performs a deterministic check by comparing ruling tuples between rounds. The Judge's self-reported `convergence` flag is supplemental — the deterministic check is the only valid stop signal.

---

## idea-matrix

**Purpose:** Systematic 3x3 exploration of design options using 9 parallel haiku agents.

**Trigger:** "idea matrix", "explore combinations", "run idea matrix", `/autoimprove-idea-matrix`

**Arguments:** `<problem statement> + <options list>`

**What it does:**

1. **Parse input** — extracts problem statement and 3+ design options (label + description)
2. **Generate 3x3 matrix** — 9 cells: 3 solo options, 3 pairwise hybrids, 1 trio combination, 2 wild cards (user-provided alternatives, or best-of-breed remix + contrarian approach)
3. **Context pre-digestion** — the orchestrator (main model) researches the codebase, produces a ~500 token architecture brief and per-option context. Haiku agents never touch the codebase.
4. **Dispatch 9 agents** — all 9 [idea-explorer](agents.md#idea-explorer) agents dispatched in parallel, each scoring one cell on a structured rubric (feasibility, risk, synergy_potential, implementation_cost, all 1-5)
5. **Collect and validate** — parses JSON responses, re-prompts once on invalid JSON, clamps out-of-range scores
6. **Synthesize convergence report:**
   - Score matrix (all 9 cells with per-dimension scores and averages)
   - Cross-cutting dimension view (aggregates by dimension across all cells)
   - Convergence analysis (top scorer, dealbreaker filter, score band distribution, cluster analysis)
   - Recommended design with verdict (go / conditional / no clear winner), conditions, top insights, required mitigations, and recommended improvements

**Tools:** Read, Glob, Grep, Bash, Agent

**Why haiku + no tools:** Agents are faster and cheaper when they reason about pre-digested context instead of exploring the codebase themselves. The orchestrator does research; haiku does evaluation.

---

## challenge

**Purpose:** Benchmark debate agent accuracy against curated code challenges with known answer keys.

**Trigger:** "test debate agents", "benchmark agents on challenges", `/autoimprove-test challenge`

**Arguments:** `[--suite puzzles|all] [--language python|typescript|go|rust|all]`

**What it does:**

1. Loads `challenges/manifest.json`, filters by language if specified
2. For each challenge: runs a single-pass debate (Enthusiast → Adversary → Judge) on the challenge code
3. Scores findings against the answer key using `scripts/score-challenge.sh` with precision-weighted F1
4. Reports per-challenge results: `F1, Precision, Recall, TP, FP, FN, PASS/FAIL`
5. Aggregates results: overall pass count and average F1
6. Logs to `experiments.tsv` for longitudinal tracking

**Tools:** Read, Bash, Glob, Grep, Agent

**Requirements:** `challenges/` directory with manifest and challenge files, `scripts/score-challenge.sh`, `jq`

---

## prompt-testing

**Purpose:** Methodology guide for writing tests for Claude Code skills and agents.

**Trigger:** "how do I test my skill", "write tests for the judge agent", `/autoimprove-prompt-testing`

**Arguments:** `[skill-name | agent-name | all]`

**What it does:**

This is a reference skill — it teaches the four test types rather than automating them:

| Type | Mechanism | Use when |
|------|-----------|----------|
| **Unit** | `claude -p "question"` + text grep | Verifying skill content says the right things |
| **Agent** | Inject system prompt + JSON assertions | Verifying agent output schema and correctness |
| **Triggering** | `--output-format stream-json` + `"name":"Skill"` grep | Verifying a naive prompt fires the right skill |
| **Explicit request** | stream-json + premature-action check | Verifying named invocation fires + no work before load |

**Key principles:**
- Never use self-reported JSON to test triggering — only `stream-json` tells you what actually happened
- Always use `--model haiku` for prompt tests (triggering tests only verify dispatch, not quality)
- Always include negative tests (prompts that should NOT trigger the skill)
- The premature-action check catches the failure mode where Claude starts working before the skill loads

**Tools:** None specified (reference/methodology skill)
