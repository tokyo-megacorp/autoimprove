# Commands Reference

autoimprove provides 8 slash commands accessible from within Claude Code. All commands are thin wrappers that delegate to [skills](skills.md).

---

## `/autoimprove`

Runs the improvement loop on the current project. This is the direct top-level alias for `/autoimprove run`.

```
/autoimprove [--experiments N] [--theme THEME]
```

**Options:**

| Option | Description |
|---|---|
| `--experiments N` | Override `max_experiments_per_session` for this run. E.g. `--experiments 5` for a quick trial. |
| `--theme THEME` | Pin the session to a single theme. E.g. `--theme failing_tests`. Useful for focused work. |

**What it does:**

Loads the top-level `autoimprove` skill, which delegates to the main orchestrator flow used by `/autoimprove run`.

---

## `/autoimprove run`

Runs the improvement loop on the current project.

```
/autoimprove run [--experiments N] [--theme THEME]
```

**Options:**

| Option | Description |
|---|---|
| `--experiments N` | Override `max_experiments_per_session` for this run. E.g. `--experiments 5` for a quick trial. |
| `--theme THEME` | Pin the session to a single theme. E.g. `--theme failing_tests`. Useful for focused work. |

**What it does:**

1. Reads `autoimprove.yaml` from the current directory.
2. Measures the current project state and saves it as the epoch baseline.
3. Runs the experiment loop: pick theme → spawn experimenter → evaluate → keep or discard.
4. Prints a session summary when done (experiments run, kept, discarded, drift, budget used).

**Requirements:**
- `autoimprove.yaml` must exist in the project root (run `/autoimprove init` to create it).
- The project must be a git repository.
- `jq` must be installed.
- At least one gate and one benchmark with at least one metric must be configured.

**Example:**

```
/autoimprove run --experiments 10 --theme todo_comments
```

Runs up to 10 experiments focused on resolving TODO comments.

---

## `/autoimprove report`

Generates a summary report of recent experiment activity.

```
/autoimprove report
```

**No options.** Reads from `experiments.tsv` and `experiments/<id>/context.json`.

**What it shows:**

- Total experiments run, kept, discarded, and failed
- Per-theme breakdown (keeps, discards, stagnation status)
- Metric trends since epoch baseline (current rolling vs. frozen start)
- Current trust tier and consecutive keep count
- Any active theme cooldowns

Use this after a session to understand what changed, or in the morning to catch up on an overnight run.

---

## `/autoimprove init`

Scaffolds an `autoimprove.yaml` configuration file in the current directory.

```
/autoimprove init
```

**No options.** Interactive — the orchestrator inspects the project and asks clarifying questions.

**What it does:**

1. Detects the project type (Node.js, Python, etc.) and suggests appropriate gate commands.
2. Asks for the benchmark command and metric extraction pattern.
3. Writes a starter `autoimprove.yaml` with sensible defaults.
4. Does not overwrite an existing `autoimprove.yaml` — it will warn and exit if one is present.

**After running `/autoimprove init`:**

Review and edit the generated `autoimprove.yaml`. Specifically:
- Confirm that the gate commands match your actual test runner invocation.
- Add your benchmark command and tune the `extract` pattern for each metric.
- Add any paths to `forbidden_paths` that should never be touched.
- Optionally configure a `coverage_gate` if you have a coverage reporter.

See [configuration.md](configuration.md) for the full schema reference.

---

## `/autoimprove review`

Runs an adversarial debate review (Enthusiast → Adversary → Judge) on code.

```
/autoimprove review [file|diff] [--rounds N] [--single-pass]
```

**Options:**

| Option | Description |
|---|---|
| `file` | Path to a file or glob pattern to review. Use `diff` to review staged/unstaged changes. |
| `--rounds N` | Hard cap on debate rounds (default: unlimited, safety cap 10). |
| `--single-pass` | Sugar for `--rounds 1`. Fast, cheaper, less thorough. |

**What it does:**

1. Reads the target code (file or diff).
2. Initializes a telemetry run at `~/.autoimprove/runs/<RUN_ID>/`.
3. For each round: Enthusiast finds issues → Adversary debunks → Judge arbitrates.
4. Checks for deterministic convergence between rounds (stops when rulings stabilize).
5. Presents confirmed findings, debunked findings, and summary.
6. Writes telemetry (per-round data + final run summary).

**Output:** Human-readable summary + structured JSON.

---

## `/autoimprove challenge`

Benchmarks debate agent accuracy against curated code challenges with known bugs.

```
/autoimprove challenge [--suite puzzles|all] [--language python|typescript|go|rust|all]
```

**Options:**

| Option | Description |
|---|---|
| `--suite` | Which challenge suite to run. Default: `puzzles`. |
| `--language` | Filter to a specific language. Default: `all`. |

**What it does:**

1. Loads the challenge manifest (`challenges/manifest.json`).
2. For each challenge: runs a single-pass debate review, then scores findings against the answer key.
3. Scoring uses precision-weighted F1: rewards finding real bugs, penalizes false positives.
4. Reports per-challenge and aggregate results.
5. Logs results to `experiments.tsv` for longitudinal tracking.

**Requirements:**
- `challenges/` directory with manifest and challenge files (included with the plugin).
- `scripts/score-challenge.sh` (included with the plugin).
- `jq` installed.

---

## `/autoimprove test`

Runs the autoimprove test suites.

```
/autoimprove test [challenge|integration|evaluate|all]
```

**Options:**

| Option | Description |
|---|---|
| `challenge` | Run only the challenge scoring tests (`test/challenge/test-score-challenge.sh`). |
| `integration` | Run only the integration tests (`test/challenge/test-integration.sh`). |
| `evaluate` | Run only the evaluate tests (`test/evaluate/test-evaluate.sh`). |
| `all` or no argument | Run all three suites. |

**What it does:**

Runs bash test scripts directly (no skill delegation). Reports total pass/fail counts across all suites.

---

## `/autoimprove prompt-testing`

Write tests for Claude Code skills and agents — triggering tests, unit tests, agent output tests, and integration tests.

```
/autoimprove prompt-testing [skill-name | agent-name | all]
```

**What it does:**

Invokes the [prompt-testing](skills.md#prompt-testing) skill, which teaches four test types for plugin components:
- **Unit tests** — verify skill content with `claude -p` + text assertions
- **Agent tests** — inject system prompt + verify JSON output schema
- **Triggering tests** — verify correct skill fires via `--output-format stream-json`
- **Explicit request tests** — verify named invocation + no premature work before skill loads

This is a methodology/reference skill, not an automated test runner.

---

## `/autoimprove idea-matrix`

Run a 3x3 haiku idea exploration matrix on design options.

```
/autoimprove idea-matrix [problem statement + options, or invoke during brainstorming]
```

**What it does:**

1. Parses the problem statement and 3+ design options from user input or conversation context.
2. Generates a 3x3 matrix: 3 solo options, 3 pairwise hybrids, 1 trio, 2 wild cards.
3. The orchestrator pre-digests codebase context into a ~500 token architecture brief.
4. Dispatches 9 parallel haiku agents (no tools — pure reasoning on pre-digested context).
5. Each agent scores its cell on 4 dimensions (feasibility, risk, synergy potential, implementation cost) rated 1-5.
6. Synthesizes a convergence report: score matrix, dimension aggregates, recommended design with verdict.

**Output:** Human-readable convergence report + full structured JSON.

**When to use:** During brainstorming sessions when you have 3+ design options and want systematic evaluation of all combinations. Works standalone or mid-conversation.
