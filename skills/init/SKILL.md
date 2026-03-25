---
name: init
description: "This skill should be used when the user invokes \"/autoimprove init\", asks to \"set up autoimprove\", \"scaffold autoimprove.yaml\", \"configure autoimprove for my project\", or wants to start using autoimprove on a new codebase."
allowed-tools: [Read, Write, Edit, Bash, Glob]
---

Scaffold an `autoimprove.yaml` configuration for the current project. Detect the project type, test commands, and available tooling, then generate a working config with sensible defaults.

If `autoimprove.yaml` already exists, ask the user if they want to overwrite it or update specific sections.

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

## 4. Suggest Benchmarks

Ask the user what they want to measure. Suggest project-specific options:
- Test count (grep for test definitions)
- TODO/FIXME count
- Source lines of code
- Test-to-code ratio
- Custom benchmark scripts the user already has

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
