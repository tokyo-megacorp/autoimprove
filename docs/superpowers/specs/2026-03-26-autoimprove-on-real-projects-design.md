# Running autoimprove on Real Projects

**Date:** 2026-03-26
**Status:** Approved
**Author:** Pedro + Claude

## Goal

A setup guide for deploying autoimprove on real target projects (lossless-claude, xgh, and others). Produces reusable design principles — not hardcoded configs. Actual per-project configuration is done via `/autoimprove init` in each target repo.

## Architecture

autoimprove.yaml and benchmark/metrics.sh live in the **target repo**, not in the autoimprove repo. (Exception: when autoimprove runs on its own codebase for dogfooding/integration validation, autoimprove itself becomes the target repo — see the dogfooding section at the end of this document.) The autoimprove plugin is installed globally; each target project opts in by running `/autoimprove init`.

```
target-project/
├── autoimprove.yaml        ← improvement strategy
├── benchmark/
│   └── metrics.sh          ← project-specific fitness signal
├── scripts/
│   └── evaluate.sh         ← symlink or copy from autoimprove plugin
└── experiments/            ← generated at runtime
```

---

## Principle 1: Find your val_bpb equivalent

The most important design decision is identifying the **direct fitness signal** — the metric that IS the thing being optimized, not a proxy for it.

### autoresearch comparison

| autoresearch | autoimprove |
|---|---|
| `val_bpb` — bits per byte on validation set | Your project's real quality metric |
| Lower = better model. Cannot be gamed without actually training better. | Must be: direct, fast to compute, hard to game without actually improving |

### Identifying direct vs. proxy signals

**Direct signals** — the metric IS the outcome:
- Compression ratio (lossless-claude) — lower bytes = better compression, period
- Test pass rate on a real benchmark suite — tests either pass or they don't
- Build time, binary size, memory usage — observable system properties

**Proxy signals** — the metric correlates with the outcome but can be gamed:
- Test count — can be inflated with trivial tests
- Line count — can be gamed by padding or splitting
- Word count in documentation — meaningless without quality

### Rule of thumb

Ask: "Can an optimizer improve this metric without actually improving the thing I care about?"
- Yes → proxy. Use with caution; pair with a quality gate.
- No → direct. Use as your primary benchmark metric.

For **lossless-claude**: compression ratio is direct. test_count is proxy.
For **xgh**: context tree quality score is direct (if deterministic). test_count is proxy.

> **Caveat:** Even direct signals can be gamed by reducing scope — e.g., better compression by dropping support for edge-case inputs. This is why the hard gate (test suite) is non-negotiable: it catches functional regressions that metric improvement alone would miss. Direct signal + passing gate = genuine improvement.

---

## Principle 2: Protect the evaluator — always

The evaluation script (`scripts/evaluate.sh`) and the benchmark script (`benchmark/metrics.sh`) must always be in `forbidden_paths`. This is the autoimprove equivalent of autoresearch's immutable `prepare.py`.

**Minimum forbidden_paths for any target project:**
```yaml
constraints:
  forbidden_paths:
    - autoimprove.yaml          # self-config
    - scripts/evaluate.sh       # the evaluator
    - benchmark/metrics.sh      # the scoring script
    - benchmark/**              # all benchmark infrastructure
```

Add any other files that, if modified, would invalidate the evaluation:
- Test fixtures used by the gate command
- Data files used by benchmarks
- Configuration that affects what the gate measures

**Why this matters:** An optimizer that can modify its own evaluation has no meaningful constraint. forbidden_paths is the hard boundary equivalent to prepare.py's read-only status.

---

## Principle 3: Design the benchmark script to resist gaming

A benchmark script that measures something gameable will eventually be gamed — not maliciously, but because the experimenter optimizes for what it can observe.

### Structural safety tripwires (reusable pattern)

Regardless of project type, include these as secondary metrics with zero tolerance. The **specific phrases and files are project-dependent** — define them based on your project's load-bearing invariants.

**Pattern (adapt to your project):**
```bash
# broken_constraints: identify 2-3 invariants that must hold in your project's core files.
# For each project, choose: which file, which phrases, what line-count floor.
broken_constraints=0

# Example for autoimprove-on-itself:
for phrase in "forbidden_paths" "additive only" "NEVER reveal" "worktree"; do
  grep -q "$phrase" agents/experimenter.md || broken_constraints=$((broken_constraints + 1))
done
lines=$(wc -l < agents/experimenter.md)
[ "$lines" -lt 20 ] && broken_constraints=$((broken_constraints + 1))

# Example for a Node.js project with an auth module:
# for phrase in "rate_limit" "sanitize" "authenticate"; do
#   grep -rq "$phrase" src/auth/ || broken_constraints=$((broken_constraints + 1))
# done

# broken_refs: files or modules referenced in core config must exist
broken_refs=0
# (project-specific: check that key imports, config references, or skill paths resolve)

echo "{..., \"broken_constraints\": $broken_constraints, \"broken_refs\": $broken_refs}"
```

These are not improvement targets — they are safety tripwires. `broken_constraints` and `broken_refs` should always be 0. Any nonzero value = immediate discard.

### Metric shape guidance

| Goal | Direction | Tolerance | Significance |
|---|---|---|---|
| Primary fitness signal (e.g. compression ratio) | lower/higher | small (0.01–0.02) | small (0.005–0.01) |
| Safety tripwires (broken_constraints, broken_refs) | lower | 0.0 | 0.0 |
| Test count (if used as proxy) | higher | 0.0 | 0.01 |

**Zero tolerance on safety tripwires** — the system should never allow any regression in structural integrity, even small ones.

### Benchmark noise check (do this before running)

Run your benchmark 3 times on an unmodified codebase:
```bash
bash benchmark/metrics.sh
bash benchmark/metrics.sh
bash benchmark/metrics.sh
```

If the primary metric varies by more than your `significance` threshold across runs, you have a noise problem. Fix it before running: average multiple runs in metrics.sh, increase the significance threshold, or choose a more stable metric. A benchmark with more variance than signal produces random keep/discard decisions that degrade the experiment log.

---

## Principle 4: Choose themes that have measurable signals

Only include themes that have a corresponding metric in your benchmark. A theme with no measurable signal will stagnate immediately (neutral verdict every time) and waste budget.

### Theme → metric mapping required

```yaml
themes:
  auto:
    priorities:
      test_coverage: 5     # maps to: test_count, test_coverage_pct
      compression: 3       # maps to: compression_ratio (lossless-claude specific)
      lint_warnings: 2     # maps to: warning_count
```

**If you can't measure it, don't theme it.** The loop will stagnate and enter cooldown, but the budget is wasted reaching that conclusion.

### v1 recommendation: start with one theme

Start with the theme that maps to your direct fitness signal. Add themes only after the first theme shows diminishing returns (stagnation).

---

## Principle 5: The v2 meta-evaluation

autoresearch measures val_bpb directly — lower bits per byte = better model. autoimprove's structural metrics are proxies for "is the plugin actually running better experiments?"

The direct equivalent — **experiment keep rate on a real session** — is computable but expensive:
1. Run autoimprove on the target project for N experiments
2. Record keep_rate = keeps / total_experiments
3. Compare to baseline keep_rate

This is v2 work. The blocker is cost: one meta-evaluation = one full session. Not practical per iteration.

**When meta-evaluation becomes useful:**
- After significant plugin changes (new theme, new trust tier, new constraint)
- As a periodic health check (e.g., once per 10 self-improvement sessions)
- When structural metrics show improvement but you're unsure if it translates to real gains

Document keep_rate in experiments.tsv when running on real projects. Over time, this becomes the ground-truth signal.

---

## Applying this to lossless-claude

When running `/autoimprove init` in the lossless-claude repo:

1. **Gate:** `npm test` or the dogfood test suite command
2. **Primary metric:** compression ratio from the compression benchmark — direct signal
3. **Secondary metrics:** test_count (proxy, zero tolerance drop), broken_refs (safety)
4. **Themes:** test_coverage (maps to test_count), compression (maps to compression_ratio)
5. **Forbidden paths:** the benchmark script, autoimprove.yaml, any evaluation fixtures

## Applying this to xgh

When running `/autoimprove init` in the xgh repo:

1. **Gate:** `bash test/*.sh` or equivalent
2. **Primary metric:** context tree quality score (if deterministic) or test_count
3. **Secondary metrics:** broken_refs (safety)
4. **Themes:** test_coverage (maps to test_count), context_quality (maps to quality score)
5. **Forbidden paths:** the benchmark script, autoimprove.yaml, provider config files

## Applying this to autoimprove itself (dogfooding)

Running autoimprove on itself is primarily a **loop validation exercise** — confirms the full session completes without crashing, worktree management works, TSV logging holds up. The structural improvements are a useful side effect.

1. **Gate:** `bash test/evaluate/test-evaluate.sh`
2. **Primary metric:** test_count (proxy — direct signal requires running full sessions)
3. **Safety tripwires:** broken_constraints, broken_refs
4. **Theme:** test_coverage only (skill_quality and constraint_hardening stagnate immediately — no measurable signal)
5. **Forbidden paths:** scripts/evaluate.sh, benchmark/self-metrics.sh, autoimprove.yaml, .claude-plugin/**
6. **Primary value:** integration validation, not metric improvement

---

## Setup workflow

For any new target project:

```bash
# 1. In the target project directory:
cd ~/Developer/lossless-claude

# 2. Run init (scaffolds autoimprove.yaml and benchmark/metrics.sh)
/autoimprove init

# 3. Customize benchmark/metrics.sh for project-specific metrics
# (add compression ratio, context tree score, etc.)

# 4. Run init verification
bash scripts/evaluate.sh experiments/evaluate-config.json /dev/null

# 5. Trial run
/autoimprove run --experiments 3

# 6. Review experiments/experiments.tsv and adjust config
```

---

## What this spec does NOT cover

- The autoimprove YAML schema (see `docs/configuration.md`)
- The experiment loop mechanics (see `skills/run/SKILL.md`)
- Trust ratchet configuration (see `DESIGN.md`)
- Scheduling automated sessions (v2 — requires cron or CI integration)
