---
name: diagnose
description: |
  Use when autoimprove produces unexpected results: experiments all neutral, benchmarks silently fail, metrics missing, or gates error. Validates autoimprove.yaml, dry-runs gates and benchmarks, probes each metric's extract pattern.

  <example>
  user: "why are all my experiments neutral?"
  assistant: I'll use the diagnose skill to dry-run benchmarks and check metric extraction.
  <commentary>Neutral experiment mystery — diagnose skill, not run.</commentary>
  </example>

  <example>
  user: "validate my autoimprove config"
  assistant: I'll use the diagnose skill to check gates, benchmarks, and metric extraction.
  <commentary>Pre-run validation — diagnose skill, not init or run.</commentary>
  </example>

  <example>
  user: "diagnose why test_count metric is missing"
  assistant: I'll trace that metric's extract pattern against live benchmark output.
  <commentary>Targeted metric debug — diagnose skill.</commentary>
  </example>

  Do NOT use to start a session (use run), check session state (use status), or run tests (use test).
argument-hint: "[--gates] [--benchmarks] [--metric METRIC_NAME] [--config] [--all]"
allowed-tools: [Read, Bash]
---

<SKILL-GUARD>
You are NOW executing the diagnose skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Validate the autoimprove configuration and dry-run all gates and benchmarks to surface problems before (or after) running the grind loop. Read-only with respect to project state — no experiments are started, no baselines modified, no state files written.

Parse arguments:
- `--gates` — check only gate commands
- `--benchmarks` — check only benchmark commands and metric extraction
- `--metric METRIC_NAME` — check only the named metric's extract pattern against live benchmark output
- `--config` — validate only the YAML config structure (no shell commands run)
- `--all` or no argument — run all checks

---

# 1. Prerequisites Check

```bash
test -f autoimprove.yaml || { echo "MISSING_CONFIG"; exit 1; }
command -v jq >/dev/null || { echo "MISSING_JQ"; exit 1; }
```

If `autoimprove.yaml` is missing, print:
```
autoimprove is not initialized here. Run /autoimprove init first.
```
and stop.

If `jq` is missing, print:
```
jq is required for metric extraction diagnostics.
Install with: brew install jq
```
and stop.

---

# 2. Parse and Validate autoimprove.yaml

Read `autoimprove.yaml`. Check for required top-level sections:

| Section | Required | Notes |
|---------|----------|-------|
| `project.name` | yes | Non-empty string |
| `project.path` | yes | Must exist on disk |
| `budget.max_experiments_per_session` | yes | Integer ≥ 1 |
| `gates` | yes | Array with ≥ 1 entry; each entry needs `name` and `command` |
| `benchmarks` | yes | Array with ≥ 1 entry; each benchmark needs `name`, `command`, and `metrics` |
| `themes.auto.priorities` | yes | Map with ≥ 1 theme and numeric weight |
| `themes.cooldown_per_theme` | yes | Integer ≥ 0 |
| `safety.regression_tolerance` | recommended | Defaults to 0.02 if absent |
| `safety.significance_threshold` | recommended | Defaults to 0.01 if absent |
| `safety.stagnation_window` | recommended | Defaults to 5 if absent |
| `constraints.test_modification` | recommended | Should be `additive_only` |

For each metric in every benchmark, check:

| Field | Required | Valid values |
|-------|----------|-------------|
| `name` | yes | Non-empty string, no spaces |
| `extract` | yes | Starts with `json:`, `regex:`, or `line:` |
| `direction` | yes | `higher_is_better` or `lower_is_better` |
| `tolerance` | no | Float 0–1; defaults to `safety.regression_tolerance` |
| `significance` | no | Float 0–1; defaults to `safety.significance_threshold` |

Print each issue as a warning or error:
- **ERROR** — blocks the loop from running correctly
- **WARNING** — non-fatal but likely to cause confusing results

Print each finding on its own line:
```
[ERROR]   gates[0].command: missing field
[WARNING] safety.regression_tolerance: not set — defaulting to 0.02
[ERROR]   benchmarks[0].metrics[1].direction: invalid value "ascending" (expected higher_is_better or lower_is_better)
```

If `--config` was passed, stop here after printing the config findings.

---

# 3. Validate Gate Commands

For each gate in `autoimprove.yaml`:

## 3a. Run the gate command

```bash
cd <project.path>
<gate.command> 2>&1; GATE_EXIT=$?
```

Cap output capture at 200 lines (truncate with a note if exceeded).

## 3b. Report gate result

```
Gate: <name>
  Command:  <command>
  Exit:     <0 = PASS | N = FAIL>
  Output:   <first 5 lines of stdout/stderr, or "(none)">
```

If the gate fails (non-zero exit), label it `[BROKEN]`. If it passes, label it `[OK]`.

## 3c. Detect common gate failure patterns

After running all gates, look for these patterns in the output:

| Pattern | Diagnosis |
|---------|-----------|
| `command not found` | Missing tool — print install hint |
| `No such file or directory` | Wrong `project.path` or script path |
| `ENOENT` | Node module not installed — suggest `npm install` |
| `ModuleNotFoundError` | Python package missing — suggest `pip install` |
| `error[E0`: Rust compile error | Code won't compile — fix before autoimprove can run |
| `cannot find package` | Go module issue — suggest `go mod tidy` |

Print the diagnosis below each broken gate.

---

# 4. Validate Benchmark Commands and Metric Extraction

For each benchmark in `autoimprove.yaml`:

## 4a. Run the benchmark command

```bash
cd <project.path>
BENCH_OUTPUT=$(mktemp)
<benchmark.command> > "$BENCH_OUTPUT" 2>&1; BENCH_EXIT=$?
```

## 4b. Check benchmark exit code

A non-zero exit is suspicious but not always fatal (some benchmarks exit 1 when counts are zero). Note it:
```
[WARNING] benchmark "<name>" exited with code N — check if this is expected.
```

## 4c. Probe each metric's extract pattern

For each metric under this benchmark, test the extract pattern against the actual output:

### Pattern: `json:<jq_path>`

```bash
EXTRACTED=$(jq -r '<jq_path>' "$BENCH_OUTPUT" 2>&1)
```

Check:
1. `jq` exits 0
2. `$EXTRACTED` is not empty and not `null`
3. `$EXTRACTED` is numeric (matches `^-?[0-9]+(\.[0-9]+)?$`)

If any check fails, print:
```
[BROKEN] benchmarks["<bench>"].metrics["<metric>"]
  Extract:   json:<jq_path>
  jq output: <raw output>
  Issue:     <null value | non-numeric | jq error: ...>
  Tip:       Run manually: <benchmark.command> | jq '<jq_path>'
```

### Pattern: `regex:<pattern>`

```bash
EXTRACTED=$(grep -oP '<pattern>' "$BENCH_OUTPUT" | head -1)
```

Check:
1. `grep` exits 0
2. `$EXTRACTED` is not empty
3. `$EXTRACTED` is numeric

If any check fails, print:
```
[BROKEN] benchmarks["<bench>"].metrics["<metric>"]
  Extract:   regex:<pattern>
  Matched:   <raw match or "(nothing matched)">
  Issue:     <no match | non-numeric>
  Tip:       Test manually: <benchmark.command> | grep -oP '<pattern>'
```

### Pattern: `line:<N>`

```bash
EXTRACTED=$(sed -n '<N>p' "$BENCH_OUTPUT")
```

Check:
1. Line N exists in the output
2. `$EXTRACTED` is numeric

If any check fails, print:
```
[BROKEN] benchmarks["<bench>"].metrics["<metric>"]
  Extract:   line:<N>
  Line <N>:  <value or "(line does not exist)">
  Issue:     <no such line | non-numeric>
  Tip:       Run: <benchmark.command> | sed -n '<N>p'
```

## 4d. Print benchmark summary

```
Benchmark: <name>
  Command:  <command>
  Exit:     <N>
  Metrics:
    test_count      [OK]     → 42
    coverage_pct    [OK]     → 78.3
    lint_errors     [BROKEN] → null (expected json:.lint.errors_count)
```

---

# 5. (Optional) Single-Metric Deep Dive — `--metric METRIC_NAME`

If `--metric` was passed, find the named metric across all benchmarks and run only its checks (steps 4a–4c for that metric). Print the full raw benchmark output (not truncated) so the user can inspect the exact structure manually.

Print:
```
Full benchmark output for context:
---
<full output, all lines>
---
```

Then run the extract probe and show its result. This mode is most useful when debugging a regex or jq path interactively.

---

# 6. Summarize Findings

After all checks complete, print a consolidated summary:

```
autoimprove diagnose — <project name> — <date>

Config
  [OK]      autoimprove.yaml is structurally valid
  [WARNING] safety.regression_tolerance not set (using 0.02 default)

Gates (N checked)
  [OK]   tests  (npm test — exit 0)
  [OK]   types  (npx tsc --noEmit — exit 0)

Benchmarks (N checked, M metrics)
  [OK]     project-metrics → test_count: 42
  [OK]     project-metrics → coverage_pct: 78.3
  [BROKEN] project-metrics → lint_errors: null — jq path .lint.errors_count not found

Diagnosis
  1 broken metric — fix the extract pattern in autoimprove.yaml.
     The benchmark output uses key "lintErrors" not "lint.errors_count":
     Run: bash benchmark/metrics.sh | jq keys
```

**Severity levels in the Diagnosis block:**
- **No issues** — `All clear. Safe to run /autoimprove run.`
- **Warnings only** — `N warning(s). The loop will run but may produce confusing results.`
- **Errors** — `N error(s) found. Fix before running /autoimprove run.`

---

# 7. Common Failure Patterns and Fixes

The diagnose skill recognizes these failure signatures and prints actionable fixes:

## All experiments neutral

**Symptoms:** Every experiment shows verdict `neutral`. Metrics never change.

**Causes to check:**
1. Benchmark output format changed since `autoimprove.yaml` was written — jq paths are stale.
2. Benchmark runs against the wrong path (e.g., measuring `src/` but experimenter edits `lib/`).
3. `significance_threshold` is too high — small but real improvements are discarded.

**Diagnose finds:** Broken extract patterns, or extracted value = 0 on every run.

## All experiments fail

**Symptoms:** Every experiment shows verdict `fail`. No code changes pass the gate.

**Causes to check:**
1. Gate command is broken in the current environment (missing dependency, wrong working directory).
2. Tests were already failing before autoimprove started — baseline was never clean.
3. Gate timeout — the command takes longer than the experiment budget allows.

**Diagnose finds:** Non-zero gate exit code, `command not found`, or stale project path.

## Metrics extracted as non-numeric

**Symptoms:** `evaluate.sh` exits non-zero with a parse error; the loop crashes or always discards.

**Causes to check:**
1. Benchmark prints a table or sentence instead of pure numbers.
2. jq path resolves to an object, not a scalar.
3. `regex:` pattern matches too broadly (captures units, e.g., "42 tests" instead of "42").

**Diagnose finds:** Non-numeric extracted value; print the raw line alongside the pattern.

## Benchmark silently exits 0 but emits no output

**Symptoms:** All metrics show as `null` or 0. Benchmark appears to pass but produces nothing.

**Causes to check:**
1. Benchmark script has an early return branch for edge cases.
2. Output is written to a file instead of stdout.
3. The command requires environment variables not set in the autoimprove context.

**Diagnose finds:** Empty `$BENCH_OUTPUT` despite exit 0. Prints notice and suggests running the command manually.

---

# 8. Usage Examples

## Example 1 — Pre-flight before first run

```
user: validate my autoimprove config
```

Runs all checks. If everything passes:
```
All clear. Safe to run /autoimprove run.
```

If a benchmark metric has a broken jq path, the summary names the exact key that's wrong and shows the correct path from the live output.

## Example 2 — Investigating neutral experiments

```
user: why are all my experiments neutral?
```

The skill runs `--all` mode. It finds that `test_count` extracts correctly (42) but `coverage_pct` is `null` because the benchmark script changed its output key from `.coverage` to `.total_coverage`. Prints:

```
[BROKEN] project-metrics → coverage_pct: null
  Extract: json:.coverage
  Tip: Run: bash benchmark/metrics.sh | jq '.total_coverage'
```

## Example 3 — Debug a specific metric

```
user: diagnose why the lint_errors metric is missing
```

Runs `--metric lint_errors`. Prints the full benchmark output (untruncated) then traces the jq extraction failure, showing exactly where the path diverges from the actual JSON structure.

## Example 4 — Check only gates before a session

```
user: /autoimprove diagnose --gates
```

Runs only the gate commands and reports exit codes. Fast check (seconds) before kicking off a long experiment session.

---

# 9. When NOT to Use

- **Checking active session state** (trust tier, cooldowns, active worktrees) → use `/autoimprove status`
- **Reviewing past experiment scores** → use `/autoimprove report`
- **Running the full test suite** → use `/autoimprove test`
- **Starting an experiment session** → use `/autoimprove run`
- **Reconfiguring autoimprove.yaml** → use `/autoimprove init` (re-scaffold) or edit the file directly

---

# 10. Integration Points

- **`/autoimprove init`** — Creates the initial `autoimprove.yaml`. Run `/autoimprove diagnose` immediately after init to verify the generated config is correct before the first `/run`.
- **`/autoimprove run`** — Includes a preflight check (step 2h) that validates benchmarks produce expected metrics. The diagnose skill is the deeper, interactive version of that check — use it when the preflight fails or produces surprising results.
- **`/autoimprove test`** — Runs test suites (TAP/shell assertions) to verify the autoimprove system itself. Diagnose runs gate and benchmark commands to verify the *project's* configuration. They are complementary: `test` checks the tool; `diagnose` checks the config.
- **`scripts/evaluate.sh`** — The evaluator uses the same extraction patterns that diagnose probes. If `diagnose` shows a metric as `[OK]`, evaluate.sh will extract it correctly. If `[BROKEN]`, fix it before running the loop.
