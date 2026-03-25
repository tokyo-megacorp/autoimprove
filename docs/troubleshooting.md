# Troubleshooting

## evaluate.sh fails to run

**"jq: command not found"**

Install jq: `brew install jq` (macOS) or `apt install jq` (Linux).

**"config not found"**

The orchestrator generates `experiments/evaluate-config.json` from your `autoimprove.yaml`. If this file is missing, the config generation step failed. Check that `autoimprove.yaml` exists and is valid YAML.

**Permissions error**

```bash
chmod +x scripts/evaluate.sh
```

## All experiments fail gates

**Tests failing in worktree but passing on main**

The worktree is created from current HEAD. If your tests depend on:
- Node modules: the worktree may need `npm install`. Add it as the first gate:
  ```yaml
  gates:
    - name: install
      command: npm install --silent
    - name: tests
      command: npm test
  ```
- Environment variables: ensure they're available in the shell evaluate.sh runs in
- Relative paths: the worktree has a different absolute path than your main checkout

**Typecheck failing on experimenter's changes**

The experimenter doesn't run the typecheck itself — it only verifies via the test suite. If you have a typecheck gate, type errors are caught at evaluation time. This is working as intended — the gate protects main.

## All experiments are neutral

The experimenter is making changes, but none improve your metrics above the significance threshold.

**Significance too high**

Lower `significance` per metric or the global `significance_threshold`:
```yaml
safety:
  significance_threshold: 0.005  # 0.5% instead of 1%
```

**Metrics aren't sensitive enough**

If your benchmark outputs round numbers (e.g., test count), small changes may not cross the threshold. Check that your metrics actually change when the experimenter's changes are reasonable.

**Benchmark command not measuring what you think**

Run it manually and inspect the output:
```bash
bash benchmark/metrics.sh
```

Then run evaluate.sh standalone to verify extraction:
```bash
bash scripts/evaluate.sh experiments/evaluate-config.json /dev/null
```

Check that the `metrics` object in the output has the values you expect.

## All experiments regress

**Tolerance too tight**

If you set `tolerance: 0.0`, any decrease at all (even rounding noise) triggers regression. Set a small buffer:
```yaml
tolerance: 0.02  # allow 2% noise
```

**Noisy metrics**

Timing-based metrics naturally fluctuate. Either:
- Use percentiles instead of averages
- Increase tolerance for noisy metrics
- Replace with deterministic metrics (line counts, test counts)

## Stagnation — themes exhausted too quickly

**Stagnation window too small**

Increase `stagnation_window` to give each theme more chances:
```yaml
safety:
  stagnation_window: 10  # was 5
```

**Not enough themes**

Add more themes or broaden existing ones. The experimenter can only work on configured themes.

**Trust tier too restrictive**

At tier 0 (3 files, 150 lines), many improvements are out of scope. You can start at a higher tier if you trust the system:
```yaml
constraints:
  trust_ratchet:
    tier_0: { max_files: 6, max_lines: 300, mode: auto_merge }
```

## Orphaned worktrees

If a session crashes, worktrees may be left behind. The orchestrator cleans these up on the next session start, but you can clean them manually:

```bash
# List all worktrees
git worktree list

# Remove orphaned autoimprove worktrees
git worktree list --porcelain | grep -A2 'autoimprove/' | grep 'worktree ' | awk '{print $2}' | xargs -I{} git worktree remove --force {}

# Clean up orphaned branches
git branch | grep 'autoimprove/' | xargs -I{} git branch -D {}
```

## Epoch drift halt

The session halted because cumulative metric drift exceeded `epoch_drift_threshold` (default 5%).

This is a safety mechanism. It means the rolling baseline has drifted far enough from the session-start snapshot that continued auto-merging could compound errors.

**If the drift is positive (improvement):** This is fine — your project improved more than 5% in one session. Start a new session to reset the epoch baseline.

**If the drift is negative (regression):** Something went wrong. Check `experiments/experiments.tsv` for which experiments were kept and inspect their changes:
```bash
# See kept experiments
grep 'keep' experiments/experiments.tsv

# Check the git log for experiment tags
git log --oneline --decorate | grep 'exp-'
```

## Rebase failures

When a keep is approved, the experimenter's commits are rebased onto main. If another experiment was already merged (changing main), the rebase may conflict.

Rebase failure = automatic discard. This is expected behavior — it means two experiments touched the same code. The first one wins.

If this happens frequently, your experiments may have overlapping scope. Try narrower theme scopes or lower `max_files`.

## Running evaluate.sh manually

You can test evaluate.sh outside the loop:

```bash
# Init mode — just capture current metrics, no scoring
bash scripts/evaluate.sh experiments/evaluate-config.json

# Scoring mode — compare against a baseline
bash scripts/evaluate.sh experiments/evaluate-config.json experiments/rolling-baseline.json
```

The output is JSON. Pipe through `jq` for readability:
```bash
bash scripts/evaluate.sh experiments/evaluate-config.json | jq .
```
