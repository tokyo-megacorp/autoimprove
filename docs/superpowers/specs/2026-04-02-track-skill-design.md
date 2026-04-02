# track skill — Design Spec
_2026-04-02_

## Problem

autoimprove's experiment loop selects themes autonomously, but users have specific outcomes they want to optimize for (e.g., "reduce test runtime by 20%"). There's no way to express these goals or give them priority in the loop.

## Design Decisions (resolved via idea-matrix)

| Decision | Winner | Confidence |
|----------|--------|------------|
| Priority model | B+C: 3× weight multiplier + guaranteed floor slots | Moderate (0.50) |
| Interview style | Benchmark-Led Guided Interview | Moderate (0.50) |
| Storage (v1) | `state.json` goals[] | — |
| Storage (v2) | `goals.yaml` (separate lifecycle file) | — |

## Architecture

`track` is a conversational skill that conducts the Benchmark-Led Guided Interview and persists goals in `state.json` under a `goals[]` key. The `run` skill reads this key on startup and injects active goals into the theme selection loop using the B+C priority model.

No new files in v1. `goals.yaml` promoted in v2 once lifecycle patterns are clear from real usage.

### state.json schema (goals section)

```json
{
  "version": "1.0",
  "goals": [
    {
      "name": "reduce test runtime",
      "target_metric": "test_runtime_ms",
      "target_delta": "-20%",
      "priority_weight": 3,
      "status": "active",
      "added_at": "2026-04-02"
    }
  ]
}
```

`status` values: `active` | `paused` | `achieved` | `stale` | `removed`

### Delta Sign Semantics

`target_delta` is always relative to the epoch baseline:
- `"-20%"` → reduce metric by 20% (e.g., `test_runtime_ms` from 5000 → ≤4000)
- `"+10%"` → increase metric by 10% (e.g., `coverage_pct` from 80 → ≥88)
- Absolute values also accepted: `"-500ms"`, `"≥90%"`

Direction is explicit in the sign — the system does not infer direction from metric name.

## Commands

| Command | Action |
|---------|--------|
| `/track` | Start interview to add a new goal |
| `/track list` | List active goals with progress |
| `/track remove <name>` | Mark goal as `removed`; error if name not found |

**`/track remove` error:** If `<name>` does not match any goal in `state.json`, return: `"Goal '<name>' not found."` (not silent success).

**Max 3 active goals:** Enforced at `/track` interview time. If 3 active goals already exist, reject with: `"Max 3 active goals already set. Run /track remove <name> or /track list to manage existing goals."` Do not silently degrade.

## Interview Flow (Benchmark-Led)

```
1. Check: does autoimprove.yaml have a benchmark script AND has it been run at least once?
   Yes → execute it, parse JSON output, display metric table with current values
         → user selects target_metric from the displayed keys (not free text)
   No  → cold-start path (see below)

2. [Benchmark path only] User selects target_metric from real benchmark output keys.

3. "What's your target? (e.g. -20%, or absolute: under 2000ms)"
   target_delta must include sign (+ or -). Prompt until valid.

4. Pre-flight validation [benchmark path only — skip on cold-start]:
   a. Confirm key exists in benchmark output JSON (already guaranteed by step 2)
   b. Estimate if delta is achievable within current tier constraints
   Fail → explain constraint, offer to adjust delta or proceed as aspirational

5. "How urgent? (1-5)" → maps to priority_weight (1=1×, 5=5×)
   Validate: must be integer 1–5. Reject out-of-range with re-prompt.

6. Confirm summary → write to state.json goals[]
```

**Benchmark script failure (step 1):** If the script exits non-zero, fails to produce valid JSON, or times out → abort interview with: `"Benchmark script failed. Run it manually to debug, then retry /track."` Do not fall through to cold-start.

### Cold-start fallback (no benchmarks)

When no benchmark has been run yet:
1. User describes goal in prose
2. Skill extracts candidate `target_metric` name + `target_delta` and confirms with user
3. Store goal with `needs_validation: true` — pre-flight checks are skipped
4. `run` validates metric key on first experiment; if key missing, marks goal `status: "stale"`

Pre-flight (step 4 above) is **conditional on benchmarks existing**. Cold-start goals skip pre-flight entirely.

## Integration with `run`

On startup, `run`:

1. Reads `state.json goals[]`, filters where `status == "active"` only (paused/achieved/stale/removed excluded)
2. **Scheduling algorithm:**
   - Floor slots (default: 2) are reserved first — guaranteed picks for active goals regardless of weight ordering
   - 3× weight multiplier then ranks active goals within remaining (non-floor) slots
   - If fewer active goals than floor_slots, unused floor slots revert to auto-theme selection
3. **Re-validates** each goal's `target_metric` against current benchmark output on startup. If key no longer exists: mark `status: "stale"`, log warning, continue with other goals (do not halt)
4. **After each experiment:** compares `current_metric` against epoch baseline. Goal is `achieved` when `(current - epoch_baseline) / epoch_baseline` crosses `target_delta` threshold (≥ for positive deltas, ≤ for negative). Achieved goals: set `status: "achieved"`, excluded from future slot allocation

**`needs_validation: true` goals:** On startup, `run` attempts to validate the metric key. If benchmark output contains the key → clear flag, activate normally. If not → mark `status: "stale"`, warn user.

## Constraints

- `priority_weight` range: 1–5 (maps to 1×–5× multiplier)
- `floor_slots`: configurable in `autoimprove.yaml` under `goals.floor_slots` (default: 2)
- Max 3 concurrent `active` goals — enforced at `/track` interview time
- `run` re-validates goals on startup independently of `/track` pre-flight

## Design Debt & Open Questions (v2)

Confidence 0.50 was recorded on both key decisions (priority model and interview style). The following questions remain open for v2 validation with real experiment data:

1. **Epoch vs rolling baseline for achievement detection** — epoch baseline chosen for v1 simplicity; rolling may be more useful for long-running goals
2. **Floor+weight interaction edge cases** — behavior when all active goals are at priority_weight=1 and floor_slots=2 (low-weight goals guaranteed slots)
3. **Achieved goal retention policy** — currently excluded from slots; consider auto-archiving to `goals.yaml` in v2
4. **Goal expiry** — no deadline enforcement in v1; whether stale goals should auto-expire after N sessions

## Out of Scope (v1)

- Goal progress history over time (v2 with `goals.yaml`)
- Goal expiry / deadline enforcement
- Automatic goal suggestion from experiment history
- `/track pause` and `/track resume` commands
- v1→v2 migration tooling (state.json `"version": "1.0"` field enables future detection)
