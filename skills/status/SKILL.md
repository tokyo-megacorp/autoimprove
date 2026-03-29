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

# 1. Check Prerequisites

```bash
test -f autoimprove.yaml || echo "MISSING"
```

If missing, print: `autoimprove is not initialized here. Run /autoimprove init.` and stop.

---

# 2. Read State Files

Read these files, noting which are absent:

- `autoimprove.yaml` — project name, trust ratchet tiers, stagnation window
- `experiments/state.json` — trust tier, consecutive keeps, cooldowns, stagnation counters, session count
- `experiments/experiments.tsv` — full log (count rows by verdict)
- `experiments/rolling-baseline.json` — SHA and timestamp of current rolling baseline
- `experiments/epoch-baseline.json` — SHA and timestamp of the frozen epoch baseline

If `state.json` is missing: print `No session started yet. Run /autoimprove run.` and stop.

---

# 3. List Active Worktrees

```bash
git worktree list --porcelain
```

Filter for paths containing `autoimprove/`. Each active worktree is an experiment in progress. Extract: short path, branch name, HEAD SHA (first 8 chars).

---

# 4. Parse Experiment Totals

From `experiments/experiments.tsv`, count rows by verdict: `kept`, `neutral`, `regress`, `fail`, `crash`. Extract the most recent row: id, timestamp, theme, verdict.

---

# 5. Compute Trust Tier Progress

From `autoimprove.yaml`, read the trust ratchet tiers. From `state.json`, read `trust_tier` and `consecutive_keeps`. Compute keeps remaining until next tier: `after_keeps - consecutive_keeps` from the next tier's config. If at tier 3 (propose-only), print "maximum tier reached."

---

# 6. Summarize Theme State

From `state.json`, read `theme_cooldowns` and `theme_stagnation`. In normal mode: list only stagnated themes (at or above `stagnation_window`) and count themes in cooldown. In `--verbose` mode: show the full cooldown table with remaining-count per theme and all non-zero stagnation counts.

---

# 7. Check for Pending Proposals

```bash
ls experiments/proposals-*.md 2>/dev/null | sort | tail -1
```

Count `PROPOSAL #` occurrences in the latest file. If any found: `N proposal(s) pending — run /autoimprove proposals to review`.

---

# 8. Format Output

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

---

# 9. Notes

- Active worktrees after a session ends may be crash orphans. Run `/autoimprove run` — it performs crash recovery automatically (step 2f).
- If epoch and rolling baselines diverge significantly, run `/autoimprove report` for metric-level drift detail.
- Trust tier drops one tier on any regression (`regression_penalty` in config). If `consecutive_keeps` is unexpectedly low, check the log for recent regressions.

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

---

# Edge Cases and Pitfalls

- **`state.json` missing but `experiments.tsv` present**: This can happen after a manual state reset or a failed init. The skill stops at step 2 and tells you to run `/autoimprove run`. The TSV is preserved — no data is lost.
- **Orphan worktrees showing as "active"**: `git worktree list` includes any worktree that was never cleaned up after a crash. They appear active even if no experiment is running. `/autoimprove run` detects and removes them; the status skill only reports them.
- **Baseline timestamps far in the past**: The rolling baseline is updated after each kept experiment. If it shows "3 days ago", the session may have been idle or every recent experiment regressed/failed.
- **Trust tier unexpectedly low**: A single regression resets `consecutive_keeps` to 0 and drops the tier by one. Check the last few entries in the experiment log with `/history --last 5` to identify the culprit.
- **Theme cooldown counts seem wrong**: Cooldowns are decremented per session run, not per experiment. Running multiple experiments in one session decrements the counter once.

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
