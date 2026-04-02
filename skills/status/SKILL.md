---
name: status
description: "Use when checking the current autoimprove session state — trust tier, active worktrees, theme cooldowns, stagnation counters, and pending proposals. Examples:

<example>
Context: User wants to know what autoimprove is doing right now.
user: \"autoimprove status\"
assistant: I'll use the status skill to show the current session state.
<commentary>Session state check — status skill.</commentary>
</example>

<example>
Context: User wants to see the trust tier and progress toward the next tier.
user: \"what trust tier is autoimprove on?\"
assistant: I'll use the status skill to report the current trust tier and progress.
<commentary>Trust tier check — status skill.</commentary>
</example>

Do NOT use to view experiment history (use the report skill). Do NOT use to start a session (use the run skill)."
argument-hint: "[--verbose]"
allowed-tools: [Read, Bash, Glob]
---

<SKILL-GUARD>
You are NOW executing the status skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Show a concise snapshot of the current autoimprove session: trust tier, active worktrees, theme cooldowns, stagnation counters, and pending proposals. Read-only — makes no changes.

---

# 1. 🩺 Check Prerequisites

```bash
test -f autoimprove.yaml || echo "MISSING"
```

If missing, print: `autoimprove is not initialized here. Run /autoimprove init.` and stop.

Initialize progress tracking:

```javascript
TodoWrite([
  { id: "prereqs",   content: "🩺 Check prerequisites",        status: "in_progress" },
  { id: "state",     content: "📋 Read state files",           status: "pending" },
  { id: "worktrees", content: "🔍 List active worktrees",      status: "pending" },
  { id: "totals",    content: "📊 Parse experiment totals",    status: "pending" },
  { id: "trust",     content: "✅ Compute trust tier progress", status: "pending" },
  { id: "themes",    content: "🔄 Summarize theme state",      status: "pending" },
  { id: "proposals", content: "💡 Check pending proposals",    status: "pending" },
  { id: "output",    content: "📋 Format and print output",    status: "pending" },
])
```

Mark `prereqs` done. Mark `state` in_progress.

---

# 2. 📋 Read State Files

Read these files, noting which are absent:

- `autoimprove.yaml` — project name, trust ratchet tiers, stagnation window
- `experiments/state.json` — trust tier, consecutive keeps, cooldowns, stagnation counters, session count
- `experiments/experiments.tsv` — full log (count rows by verdict)
- `experiments/rolling-baseline.json` — SHA and timestamp of current rolling baseline
- `experiments/epoch-baseline.json` — SHA and timestamp of the frozen epoch baseline

If `state.json` is missing: print `No session started yet. Run /autoimprove run.` and stop.

Mark `state` done. Mark `worktrees` in_progress.

---

# 3. 🔍 List Active Worktrees

```bash
git worktree list --porcelain
```

Filter for paths containing `autoimprove/`. Each active worktree is an experiment in progress. Extract: short path, branch name, HEAD SHA (first 8 chars).

Mark `worktrees` done. Mark `totals` in_progress.

---

# 4. 📊 Parse Experiment Totals

From `experiments/experiments.tsv`, count rows by verdict: `kept`, `neutral`, `regress`, `fail`, `crash`. Extract the most recent row: id, timestamp, theme, verdict.

Mark `totals` done with count (e.g., "📊 Parse experiment totals — N total"). Mark `trust` in_progress.

---

# 5. ✅ Compute Trust Tier Progress

From `autoimprove.yaml`, read the trust ratchet tiers. From `state.json`, read `trust_tier` and `consecutive_keeps`. Compute keeps remaining until next tier: `after_keeps - consecutive_keeps` from the next tier's config. If at tier 3 (propose-only), print "maximum tier reached."

Mark `trust` done. Mark `themes` in_progress.

---

# 6. 🔄 Summarize Theme State

From `state.json`, read `theme_cooldowns` and `theme_stagnation`. In normal mode: list only stagnated themes (at or above `stagnation_window`) and count themes in cooldown. In `--verbose` mode: show the full cooldown table with remaining-count per theme and all non-zero stagnation counts.

Mark `themes` done. Mark `proposals` in_progress.

---

# 7. 💡 Check for Pending Proposals

```bash
ls experiments/proposals-*.md 2>/dev/null | sort | tail -1
```

Count `PROPOSAL #` occurrences in the latest file. If any found: `N proposal(s) pending — run /autoimprove proposals to review`.

Mark `proposals` done. Mark `output` in_progress.

---

# 8. 📋 Format Output

```
autoimprove status — <project name> — <date>

Session
  Sessions run:    <session_count>
  Experiments:     <total> total (<kept> kept, <neutral> neutral, <regress> regressed, <fail> failed)
  Last experiment: #<id> (<theme>, <verdict>) — <relative timestamp>

Trust
  Current tier:    <N> — <max_files> files / <max_lines> lines / <mode>
  Next tier:       <consecutive_keeps>/<after_keeps> consecutive keeps needed

Active Worktrees
  <short-path> [<branch>] @ <sha>     ← one line per active worktree
  None — session is idle              ← if no worktrees

Themes
  Stagnated:   <theme1>, <theme2>  (N+ consecutive non-improvements)
  In cooldown: <N> theme(s)

Baselines
  Rolling:  <sha> (updated <relative timestamp>)
  Epoch:    <sha> (frozen at session start)

Proposals                             ← only if pending proposals exist
  <N> pending — run /autoimprove proposals to review
  Latest: experiments/proposals-<date>.md
```

**Relative timestamps:** <1 min → "just now", <1 hour → "N minutes ago", <24 h → "N hours ago", older → "YYYY-MM-DD HH:MM".

**Missing files:** Replace with `(not yet initialized)` rather than erroring.

Mark `output` done in TodoWrite.

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  { id: "prereqs", status: "completed" },
  { id: "state", status: "completed" },
  { id: "worktrees", status: "completed" },
  { id: "totals", status: "completed" },
  { id: "trust", status: "completed" },
  { id: "themes", status: "completed" },
  { id: "proposals", status: "completed" },
  { id: "output", status: "completed" }
])
```

---

# 9. Notes

- Active worktrees after a session ends may be crash orphans. Run `/autoimprove run` — it performs crash recovery automatically (step 2f).
- If epoch and rolling baselines diverge significantly, run `/autoimprove report` for metric-level drift detail.
- Trust tier drops one tier on any regression (`regression_penalty` in config). If `consecutive_keeps` is unexpectedly low, check the log for recent regressions.
- Theme cooldowns are per-session, not per-experiment. A theme that ran twice in one session still only decrements its cooldown counter once.
- Stagnation counters and trust tier progress are the two most actionable signals: stagnation → change theme or adjust scope; tier progress → increase scope if you're close to the next tier.
- The SHA shown for rolling and epoch baselines is the git commit SHA of the snapshot taken, not the HEAD commit. If you reset or rebased, these SHAs may no longer exist in the repo — that will cause benchmark drift comparisons to fail silently.

---

# Usage Examples

## Example 1 — Quick health check before starting a session

```
user: autoimprove status
```

Shows trust tier, how many keeps until the next tier, any stagnated themes, and whether there are orphan worktrees. Good first command each morning before running `/autoimprove run`.

## Example 2 — Verbose theme table

```
user: /autoimprove status --verbose
```

Prints the full cooldown table with remaining-count per theme and all non-zero stagnation counters. Use this when a theme seems under-represented and you want to see exactly when its cooldown expires.

## Example 3 — Check for pending proposals before approving

```
user: what trust tier is autoimprove on?
```

Returns the trust tier and progress toward the next tier. If the output shows `Proposals: 3 pending`, follow up with `/autoimprove proposals` before running another session.

## Example 4 — Diagnose why a session seems stuck

```
user: autoimprove status --verbose
```

Use when `/autoimprove run` keeps picking the same theme or producing neutral results. The verbose output shows exact cooldown counts per theme and non-zero stagnation counters — this tells you whether a theme is being avoided (cooldown) or is genuinely not producing improvements (stagnation). Stagnated themes trigger Phase 2 when the stagnation window is reached.

---

# Edge Cases and Pitfalls

- **`state.json` missing but `experiments.tsv` present**: This can happen after a manual state reset or a failed init. The skill stops at step 2 and tells you to run `/autoimprove run`. The TSV is preserved — no data is lost.
- **Orphan worktrees showing as "active"**: `git worktree list` includes any worktree that was never cleaned up after a crash. They appear active even if no experiment is running. `/autoimprove run` detects and removes them; the status skill only reports them.
- **Baseline timestamps far in the past**: The rolling baseline is updated after each kept experiment. If it shows "3 days ago", the session may have been idle or every recent experiment regressed/failed.
- **Trust tier unexpectedly low**: A single regression resets `consecutive_keeps` to 0 and drops the tier by one. Check the last few entries in the experiment log with `/history --last 5` to identify the culprit.
- **Theme cooldown counts seem wrong**: Cooldowns are decremented per session run, not per experiment. Running multiple experiments in one session decrements the counter once.

---

# Common Failure Patterns

- **`state.json` has wrong session_id after manual intervention:** If you manually reset or copied state from another project, the session_id may not match the TSV rows. Status reports what's in `state.json` — verify with `/history --last 5` if the counts seem inconsistent.
- **Stagnation counter stuck at non-zero:** A stagnation counter increments when a theme produces non-improvements repeatedly. It resets to 0 when that theme produces a keep. If a theme never runs (cooldown too long), its counter never resets. Lower the cooldown in `autoimprove.yaml` or run a focused session with `--theme <name>`.
- **Pending proposals blocking run:** If Phase 2 proposals are generated but none are approved, the run skill may stall waiting for approval. Status will show the proposal count — use `/autoimprove proposals list` to review and approve before the next run.
- **Trust tier shows lower than expected:** A single regressed experiment resets consecutive_keeps to 0, which can drop the tier. If this seems wrong, check `/history --last 5` to find the regressed experiment and verify the benchmark was working correctly at that point.

---

# Integration Points

- **run skill**: Status shows the current state; run starts the next session. Always check status before run to avoid starting a session with stagnated themes or orphan worktrees.
- **report skill**: Status gives a session-level snapshot. For metric-level drift (which benchmarks improved or regressed), use `/autoimprove report`.
- **history skill**: Status shows only the most recent experiment. For a filterable log, use `/history`.
- **proposals skill**: When status shows pending proposals, `/autoimprove proposals` is the next step — it lists and lets you approve or reject each one.

---

# When NOT to Use

- **Do not use** to review past experiment metrics in depth — use the report skill for that.
- **Do not use** to start or resume a session — use the run skill.
- **Do not use** as a substitute for `git worktree list` when debugging a specific worktree's branch or commit — status only surfaces the path and HEAD SHA.
- **Do not use** to check if tests pass — status reads state files, it does not re-run gates or benchmarks.

---

# Recommended Session Start Checklist

Before each `/autoimprove run`, run `/autoimprove status` and verify:

1. No orphan worktrees (crash from last session)
2. No stagnated themes you intended to run (cooldown may block them)
3. Trust tier is as expected (a surprise drop signals a recent regression)
4. No pending proposals that should be reviewed first (blocks Phase 2 auto-run)
