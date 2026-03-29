---
name: autoimprove-init
description: Scaffold autoimprove.yaml and project configuration for a new target codebase.
argument-hint: "[project-path]"
---

Invoke the `autoimprove:init` skill now. Do not do any work before the skill loads.

Arguments: $ARGUMENTS

---

## Arguments

| Argument | Description |
|----------|-------------|
| `project-path` | Path to the project root to configure. Defaults to the current directory. |

## Usage Examples

```
# Initialize autoimprove in the current directory
/autoimprove init

# Initialize for a specific project path
/autoimprove init ~/Developer/my-project

# Re-run after gates or benchmarks change to update the config
/autoimprove init
```

## What It Does

1. Detects the project type by inspecting `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, or `.claude-plugin/plugin.json`.
2. Identifies the test command and type checker for the detected project type.
3. Asks what metrics to track (test count, TODO count, SLOC, coverage, or custom).
4. Writes `autoimprove.yaml` with gates, benchmarks, theme weights, constraints, and safety thresholds — all commented with explanations.
5. Creates `benchmark/metrics.sh` if a script-based metric was requested.
6. Creates the `experiments/` directory.
7. Runs `scripts/evaluate.sh` in init mode to verify gates and benchmarks work before the first session.

If `autoimprove.yaml` already exists, the skill asks whether to overwrite or update specific sections.

## Output

- `autoimprove.yaml` — main configuration file
- `benchmark/metrics.sh` — benchmark script (only if metrics require one)
- `experiments/` — directory created for session artifacts
- `experiments/evaluate-config.json` — preview config generated for verification

## Supported Project Types

| Detection file | Project type | Default test command |
|----------------|-------------|----------------------|
| `package.json` | Node.js / TypeScript | `npm test` |
| `pyproject.toml` or `setup.py` | Python | `pytest` |
| `Cargo.toml` | Rust | `cargo test` |
| `go.mod` | Go | `go test ./...` |
| `.claude-plugin/plugin.json` | Claude Code plugin | (detected from config) |

## Related Commands

- `/autoimprove run` — start the experiment loop after initialization
- `/autoimprove report` — review session results
