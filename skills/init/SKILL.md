---
name: init
description: "Use when setting up autoimprove on a new project — scaffolding autoimprove.yaml, configuring gates and benchmarks. Examples:

<example>
Context: User wants to start using autoimprove on their project.
user: \"set up autoimprove for my project\"
assistant: I'll use the init skill to scaffold autoimprove.yaml with gates and benchmarks.
<commentary>Initial setup of autoimprove — init skill.</commentary>
</example>

<example>
Context: User has a new codebase and wants to configure autoimprove.
user: \"configure autoimprove for this repo\"
assistant: I'll use the init skill to create the autoimprove configuration.
<commentary>Project onboarding — init skill.</commentary>
</example>

<example>
Context: Onboarding a monorepo sub-package.
user: \"init autoimprove for packages/api\"
assistant: I'll use the init skill scoped to packages/api.
<commentary>Monorepo sub-package — init skill.</commentary>
</example>

Do NOT use to check session state (use status). Do NOT use to reset state — delete experiments/state.json manually."
argument-hint: "[<path>] [--update]"
allowed-tools: [Read, Write, Edit, Bash, Glob]
---

<SKILL-GUARD>
You are NOW executing the init skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Scaffold an `autoimprove.yaml` configuration for the current project. Detect the project type, test commands, and available tooling, then generate a working config with sensible defaults.

If `autoimprove.yaml` already exists, ask the user if they want to overwrite it or update specific sections.

**Initialize progress tracking:**
```
TodoWrite([
  {id: "detect",     content: "🔍 Detect project type and tooling", status: "in_progress"},
  {id: "config",     content: "🛠️ Generate autoimprove.yaml",        status: "pending"},
  {id: "benchmarks", content: "📊 Create benchmark script",          status: "pending"},
  {id: "verify",     content: "✅ Verify gates and metrics",         status: "pending"}
])
```

---

## 1. Detect Project Type

Look for these files to determine the project type:
- `package.json` → Node.js (check for `test` script, TypeScript via `tsconfig.json`)
- `pyproject.toml` or `setup.py` → Python (check for pytest, mypy)
- `Cargo.toml` → Rust (cargo test, cargo clippy)
- `go.mod` → Go (go test, go vet)
- `.claude-plugin/plugin.json` → Claude Code plugin

## 2. Detect Test Command

Read the project config to find the test command:
- Node.js: `npm test` or the `test` script from `package.json`
- Python: `pytest` or `python -m pytest`
- Rust: `cargo test`
- Go: `go test ./...`

Verify the command exists by running it briefly. Note whether tests pass or fail.

## 3. Detect Type Checker

- TypeScript: `npx tsc --noEmit` (if `tsconfig.json` exists)
- Python: `mypy .` (if mypy in dependencies)
- Rust: `cargo check`
- Go: `go vet ./...`

Mark: `TodoWrite([{id: "detect", status: "completed"}, {id: "config", status: "in_progress"}])`

## 4. Suggest Benchmarks

**Default to smart defaults — do not block on this question.**

For any project with a test suite, the universal defaults work:
- `test_count` — grep for test definitions in the test directory
- `todo_count` — count TODO/FIXME in source files

Proceed with these defaults unless the user specifically asks to customize. Do NOT ask an open-ended "what do you want to measure?" — that blocks users who don't know the answer.

Only ask if the user has already indicated they want custom metrics (e.g., "I want to track coverage" or "I have my own benchmark script"). Present as a multiple-choice offer:

```
Benchmark defaults: test_count + todo_count (good for any project).
Want to add anything?
  1. Use defaults → proceed (recommended)
  2. Add test coverage (requires lcov or coverage.json output)
  3. Add source lines of code
  4. I have a custom benchmark script already
```

If the project is a Claude Code plugin (`.claude-plugin/plugin.json` detected), add `skill_behavior_tests` as a third default if the project has any test scripts that count passing assertions.

## 5. Generate autoimprove.yaml

Write the YAML file using the Write tool. Include comments explaining each section. Example structure:

```yaml
project:
  name: my-project
  path: .

budget:
  max_experiments_per_session: 20

gates:
  - name: tests
    command: npm test
  # - name: typecheck
  #   command: npx tsc --noEmit

benchmarks:
  - name: project-metrics
    type: script
    command: bash benchmark/metrics.sh
    metrics:
      - name: test_count
        extract: "json:.test_count"
        direction: higher_is_better
        tolerance: 0.0        # zero tolerance — test count must never drop
        significance: 0.05    # 5% improvement to count as meaningful

themes:
  auto:
    strategy: weighted_random
    cooldown_per_theme: 3
    priorities:
      failing_tests: 5
      todo_comments: 3
      coverage_gaps: 2
      lint_warnings: 2

constraints:
  forbidden_paths:
    - autoimprove.yaml
    - benchmark/**
  test_modification: additive_only
  trust_ratchet:
    tier_0: { max_files: 3, max_lines: 150, mode: auto_merge }
    tier_1: { max_files: 6, max_lines: 300, mode: auto_merge, after_keeps: 5 }
    tier_2: { max_files: 10, max_lines: 500, mode: auto_merge, after_keeps: 15 }

safety:
  epoch_drift_threshold: 0.05
  regression_tolerance: 0.02
  significance_threshold: 0.01
  stagnation_window: 5
```

Mark: `TodoWrite([{id: "config", status: "completed"}, {id: "benchmarks", status: "in_progress"}])`

## 6. Create Benchmark Script if Needed

If the user wants metrics that require a script, create `benchmark/metrics.sh`. Example:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"

test_count=$(grep -r "it(\|test(" "$DIR/test" --include="*.js" 2>/dev/null | wc -l | tr -d ' ')
todo_count=$(grep -rn "TODO\|FIXME" "$DIR/src" --include="*.js" 2>/dev/null | wc -l | tr -d ' ')

echo "{\"test_count\": $test_count, \"todo_count\": $todo_count}"
```

Make it executable: `chmod +x benchmark/metrics.sh`

## 7. Create Experiments Directory

```bash
mkdir -p experiments
```

## 8. Generate evaluate-config.json

The orchestrator generates `experiments/evaluate-config.json` at session start, but generate a preview now so the user can verify the setup. Then write `experiments/evaluate-config.json` from the YAML config following the same mapping rules the orchestrator uses (see the `run` skill).

Mark: `TodoWrite([{id: "benchmarks", status: "completed"}, {id: "verify", status: "in_progress"}])`

## 9. Verify Setup

Run `evaluate.sh` in init mode to verify gates and benchmarks work:

```bash
bash scripts/evaluate.sh experiments/evaluate-config.json /dev/null
```

Parse the JSON output and report to the user:
- Which gates passed
- Which metrics were captured and their values
- Any errors to fix before running

Suggest next step: `/autoimprove run --experiments 3` for a trial run.

Mark: `TodoWrite([{id: "verify", status: "completed"}])`

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  {id: "detect", status: "completed"},
  {id: "config", status: "completed"},
  {id: "benchmarks", status: "completed"},
  {id: "verify", status: "completed"}
])
```

---

## 10. When NOT to Use

- **Updating a single section of an existing config** — edit `autoimprove.yaml` directly (it is plain YAML with inline comments).
- **Resetting experiment state** — delete `experiments/state.json` and `experiments/epoch-baseline.json` manually; init does not touch these.
- **Adding a new benchmark to a running project** — append to the `benchmarks` array in `autoimprove.yaml` and re-run `bash scripts/evaluate.sh experiments/evaluate-config.json /dev/null` to verify, then re-generate `evaluate-config.json` with `/autoimprove run` (it regenerates this file at session start).

---

## 11. Edge Cases

**`autoimprove.yaml` already exists**

Always ask before overwriting. Suggested prompt:
```
autoimprove.yaml already exists. Choose:
  1. Overwrite — generate fresh config (current config is lost)
  2. Update — add missing sections only
  3. Cancel
```
Default to Cancel if no argument is passed.

**Monorepo / nested packages**

If multiple `package.json` or `pyproject.toml` files are found, ask the user which sub-package to target. Set `project.path` to the sub-package directory and make all gate/benchmark commands relative to it.

**Test command exits non-zero during detection (step 2)**

Note this as a warning but do not block init:
```
Warning: test command exited non-zero (existing failures).
autoimprove will require a clean baseline before running. Fix tests first or start with a narrower gate.
```

**No test command found**

If no recognized test command exists, generate the config with the gate commented out and note:
```
# No test command detected. Uncomment and fill in:
# - name: tests
#   command: <your test command>
```

---

## 12. Common Failure Patterns

- **Generated gate command is wrong for this project:** Init detects project type heuristically. If the generated `autoimprove.yaml` has the wrong test command (e.g., `npm test` when you use `yarn test`), edit it directly. Then run `/autoimprove diagnose --gates` to confirm.
- **Benchmark script writes mixed stdout/stderr:** The benchmark template expects clean JSON on stdout. If the project's test runner mixes progress output into stdout, metric extraction will fail. Redirect noisy output to `/dev/null` in the benchmark command.
- **`experiments/` directory already exists from a prior init:** Init is safe to re-run — it will not overwrite `experiments.tsv` or `state.json`. Only `autoimprove.yaml` and `evaluate-config.json` are regenerated (with confirmation if they already exist).
- **No test command auto-detected but the project has tests:** Init generates a commented-out gate. Fill it in manually — the exact command matters, since the gate must exit 0 for a clean baseline and non-0 when tests fail.

---

## 13. Integration Notes

- **After init** → run `/autoimprove test all` to confirm the test infrastructure is wired correctly before starting the grind loop.
- **evaluate-config.json** is regenerated by `/autoimprove run` at every session start from `autoimprove.yaml` — do not hand-edit it; your changes will be overwritten.
- **trust_ratchet tiers** are intentionally conservative at tier 0 (3 files, 150 lines). Tighten further if your codebase has many coupled files — aggressive experiments on tightly coupled code risk higher revert rates.
- **Re-running init on an existing project** updates `autoimprove.yaml` only — existing experiment logs and state are preserved. This is safe to do after a major project restructure where the benchmark commands need updating.
- **`/autoimprove diagnose`** should be run immediately after init to validate the generated configuration. Init generates a best-effort config based on heuristics — diagnose catches any extraction or gate issues before the first session.
- **For monorepos:** set `project.path` to the sub-package you want to improve, not the repo root. Benchmarks should run from that sub-path so metric extraction stays scoped.

---

## 14. Usage Examples

### Example 1 — New Node.js project from scratch

```
user: set up autoimprove for my project
```

Init detects `package.json` with a `test` script (`jest --coverage`). It confirms tests pass, asks what to measure (user says "test count and TODO count"), generates `benchmark/metrics.sh`, writes `autoimprove.yaml` with gate `npm test` and two metrics, then runs `evaluate.sh` to confirm. Output:

```
autoimprove initialized for my-project (Node.js)

Gates
  [PASS] tests — npm test (42 tests, 0 failures)

Metrics (baseline)
  test_count: 42
  todo_count: 7

Config written to autoimprove.yaml
Next step: /autoimprove run --experiments 3
```

### Example 2 — Monorepo with multiple packages

```
user: init autoimprove for packages/api
```

Init finds three `package.json` files but scopes to `packages/api/`. Sets `project.path: packages/api` in the config and makes the gate command `cd packages/api && npm test`. Warns that benchmarks will run relative to `packages/api/` — cross-package metrics need separate init runs.

### Example 3 — Project with failing tests at init time

```
user: configure autoimprove for this repo
```

Init detects `pyproject.toml` with pytest. Running `pytest` exits non-zero (3 failing tests). Init does NOT block — it writes the config and adds a warning:

```
Warning: pytest exited non-zero (3 failures).
Clean up existing failures before running your first session,
or start with --theme failing_tests to let autoimprove fix them first.
```

### Example 4 — Update mode on an existing config

```
user: init autoimprove --update
```

`autoimprove.yaml` already exists. The `--update` flag skips the overwrite prompt and instead adds only missing sections (e.g., a missing `safety` block or unset `stagnation_window`). Existing sections are not touched. Reports which sections were added.

### Example 5 — Claude Code plugin project

```
user: set up autoimprove here
```

Init detects `.claude-plugin/plugin.json`. Recognizes this as a Claude Code plugin. Suggests skill-behavior tests as a benchmark metric (count of passing skill behavior assertions). Generates a config with `themes.auto.priorities.skill_quality: 5` elevated.

---

## 15. Recommended Post-Init Checklist

After init completes, verify the setup is solid before the first run:

1. **Gate check** — does `evaluate.sh` exit 0 with all gates passing?
2. **Metric extraction** — are all metric values non-zero and plausible?
3. **Forbidden paths** — does `constraints.forbidden_paths` cover auto-generated files (e.g., `dist/`, `*.lock`)?
4. **Trust tier start** — is tier 0 tight enough? For a new project with untested experiments, tighten to `max_files: 2, max_lines: 100`.
5. **Theme priorities** — do the weights reflect where the most improvement potential is? Raise failing_tests if there are known failures; raise coverage_gaps for well-tested projects seeking coverage growth.
6. **Trial run** — `/autoimprove run --experiments 3` with a fresh epoch baseline confirms the full pipeline works end-to-end before committing to a full session.
