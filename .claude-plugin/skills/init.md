---
name: init
description: "Scaffold autoimprove.yaml for the current project by detecting project type, test commands, and suggesting benchmarks."
---

You are scaffolding an `autoimprove.yaml` configuration for this project.

## Steps

### 1. Detect Project Type

Look for these files to determine the project type:
- `package.json` → Node.js (check for `test` script, TypeScript via `tsconfig.json`)
- `pyproject.toml` or `setup.py` → Python (check for pytest, mypy)
- `Cargo.toml` → Rust (cargo test, cargo clippy)
- `go.mod` → Go (go test, go vet)
- `.claude-plugin/plugin.json` → Claude Code plugin

### 2. Detect Test Command

Read the project config file to find the test command:
- Node.js: `npm test` or the `test` script from package.json
- Python: `pytest` or `python -m pytest`
- Rust: `cargo test`
- Go: `go test ./...`

Verify the command exists by running it. Note if tests pass or fail.

### 3. Detect Type Checker

- TypeScript: `npx tsc --noEmit` (if tsconfig.json exists)
- Python: `mypy .` (if mypy in dependencies)
- Rust: `cargo check`
- Go: `go vet ./...`

### 4. Suggest Benchmarks

Ask the user what they want to measure. Suggest project-specific options:
- Test count (grep for test definitions)
- TODO/FIXME count
- Source lines of code
- Test-to-code ratio
- Custom benchmark scripts the user already has

### 5. Generate autoimprove.yaml

Write the YAML file using the Write tool. Include comments explaining each section.

### 6. Create benchmark script if needed

If the user wants metrics that require a script (test count, TODO count, etc.), create `benchmark/metrics.sh` with the appropriate extraction logic.

### 7. Create experiments directory

```bash
mkdir -p experiments
```

### 8. Verify setup

Run `evaluate.sh` in init mode to verify gates and benchmarks work:
```bash
bash scripts/evaluate.sh experiments/evaluate-config.json /dev/null
```

Report the results to the user.
