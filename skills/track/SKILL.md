---
name: track
description: |
  Manage user-defined measurable goals for the autoimprove experiment loop.
  Trigger on: '/track', 'track goal', 'add goal', 'list goals', 'remove goal',
  'what are my goals', 'show goals', 'track my progress on'.
  Do NOT trigger on generic 'track changes' or git-related tracking.
argument-hint: "[list | remove <name>]"
allowed-tools: [Read, Write, Edit, Bash, TodoWrite]
---

<SKILL-GUARD>
You are NOW executing the track skill. Do NOT invoke this skill again via the Skill tool.
</SKILL-GUARD>

# track - User Goal Management

Manage measurable goals that bias the autoimprove experiment loop toward user-defined outcomes.
Goals are stored in `experiments/state.json` under `goals[]` and injected into the run loop via the B+C model
(3x weight multiplier + guaranteed floor slots).

Initialize progress tracking at the start:

```javascript
TodoWrite([
  { id: "parse",     content: "Parse track subcommand",          status: "in_progress" },
  { id: "state",     content: "Load goals state",                status: "pending" },
  { id: "bench",     content: "Detect benchmarks or cold-start", status: "pending" },
  { id: "target",    content: "Capture target delta",            status: "pending" },
  { id: "priority",  content: "Capture priority",                status: "pending" },
  { id: "save",      content: "Confirm and save goal",           status: "pending" },
  { id: "list",      content: "List tracked goals",              status: "pending" },
  { id: "remove",    content: "Remove tracked goal",             status: "pending" }
])
```

---

# 1. Parse Subcommand

Read the arguments passed to this skill:

- **No args or unknown:** go to Step 2 (interview flow)
- **`list`:** go to Step 7 (list goals)
- **`remove <name>`:** go to Step 8 (remove goal)

Mark `parse` complete before continuing.

---

# 2. Load State and Enforce Cap

Read `experiments/state.json`. If it does not exist yet, treat `goals[]` as empty.

If the file exists but lacks `goals`, treat it as:

```json
{
  "version": "1.0",
  "goals": []
}
```

Count goals where `status == "active"`. If the count is `>= 3`, print:

> "You already have 3 active goals - the maximum. Run `/track list` to see them, or `/track remove <name>` to free a slot."

Stop. Do not proceed to the interview.

Mark `state` complete and `bench` in progress.

---

# 3. Detect Benchmarks

Inspect `autoimprove.yaml` from the project root.

- If it has a legacy `benchmark.script` field, use that script.
- Otherwise, if it has `benchmarks[]`, use the configured benchmark commands and merge their JSON outputs into a single metric map.
- If neither exists, treat this as a cold-start project.

**If benchmark commands exist:**

1. Run each benchmark command from the project root.
2. If any command exits non-zero, times out, or produces invalid JSON, print:

> "Benchmark script failed. Run it manually to debug, then retry `/track`."

Stop.

3. Merge the JSON outputs into one object keyed by metric name.
4. Display the available metrics and current values in a readable table, for example:

```
Available metrics (current values):
  test_runtime_ms   -> 4218
  coverage_pct      -> 87.3
  bundle_size_kb    -> 312
```

5. Ask: "Which metric do you want to improve? (type the exact key)"
6. Validate that the response matches one of the displayed keys.
   - If it does not, re-prompt once.
   - If it still does not match, print an error and stop.
7. Store the validated key as `TARGET_METRIC`.
8. Set `COLD_START = false`.

**If no benchmark commands exist:**

1. Ask: "Describe what you want to improve (e.g. 'make tests faster', 'increase coverage to 95%')."
2. Extract a candidate `target_metric` name from the description.
3. Confirm with the user:

> "I'll track this as: `target_metric: <extracted>`. Is that right? (y/n)"

4. If the user says no, ask them to type the metric name directly.
5. Store the final value as `TARGET_METRIC`.
6. Set `COLD_START = true`.

Mark `bench` complete and `target` in progress.

---

# 4. Set Target Delta

Ask: "What's your target? Use a signed percentage or absolute value."

Examples:
- `-20%` -> reduce by 20%
- `+10%` -> increase by 10%
- `>=90%` -> reach at least 90%
- `<=5` -> stay at or below 5

Validate the answer:

- Relative targets must include `+` or `-`
- Absolute targets must include `>=` or `<=`
- If the input is ambiguous, re-prompt until it is explicit

Store the result as `TARGET_DELTA`.

**Pre-flight validation (benchmark path only):**

- Confirm `TARGET_METRIC` still exists in the benchmark output.
- If the requested relative change is greater than `30%` in magnitude, warn:

> "That's an ambitious target. The system may take many sessions to reach it. Continue? (y/n)"

- If the user does not confirm, ask for a revised target.

Set `NEEDS_VALIDATION = true` only when `COLD_START = true`. Otherwise set it to `false`.

Mark `target` complete and `priority` in progress.

---

# 5. Priority Weight

Ask: "How urgent is this goal? (1 = low priority, 5 = highest)"

Validate that the answer is an integer from `1` to `5`. Re-prompt if it is missing, non-integer, or out of range.

Map:
- `1` -> `1x`
- `2` -> `2x`
- `3` -> `3x`
- `4` -> `4x`
- `5` -> `5x`

Store the validated value as `PRIORITY_WEIGHT`.

Mark `priority` complete and `save` in progress.

---

# 6. Confirm and Save

Derive a default goal name if the user did not provide one explicitly:

- Preferred format: `<TARGET_METRIC> <TARGET_DELTA>`
- Normalize whitespace and keep it short

Show the summary:

```
New goal:
  metric:   <TARGET_METRIC>
  target:   <TARGET_DELTA>
  priority: <PRIORITY_WEIGHT>/5
  status:   active
  cold-start: <yes/no>
```

Ask: "Save this goal? (y/n)"

If the user says no, print:

> "Cancelled. Nothing saved."

Stop.

If the user says yes:

1. Read `experiments/state.json` if it exists. If it does not, start from:

```json
{
  "version": "1.0",
  "goals": []
}
```

2. Ensure the top-level object has `"version": "1.0"`.
3. Ensure `goals` exists and is an array.
4. Append:

```json
{
  "name": "<goal name>",
  "target_metric": "<TARGET_METRIC>",
  "target_delta": "<TARGET_DELTA>",
  "priority_weight": <PRIORITY_WEIGHT>,
  "status": "active",
  "needs_validation": <true if COLD_START else false>,
  "added_at": "<today YYYY-MM-DD>"
}
```

5. Write the updated JSON back to `experiments/state.json`.
6. Print:

> "Goal saved. It will take effect on the next `/autoimprove run`."

Mark `save` complete.

---

# 7. List Goals (`/track list`)

Read `experiments/state.json`. If the file does not exist, or `goals[]` is empty, print:

> "No goals tracked yet. Run `/track` to add one."

Stop.

Group goals by status and print a concise summary, for example:

```
Active goals:
  #1  test_runtime_ms   -> -20%   [priority: 3/5]  added: 2026-04-01
  #2  coverage_pct      -> +5%    [priority: 5/5]  added: 2026-04-02  cold-start (needs_validation)

Achieved:
  #3  bundle_size_kb    -> -15%   [achieved: 2026-03-28]

Removed/paused: 0
```

Rules:

- Show all `active` goals first
- Show `achieved` goals next
- Summarize `removed` and `paused` goals afterward
- If a goal has `needs_validation: true`, append `cold-start (needs_validation)`
- If a section is empty, omit it except for the final removed/paused count

Mark `list` complete.

---

# 8. Remove Goal (`/track remove <name>`)

Parse `<name>` from the skill arguments.

If no name was provided, print:

> "Usage: `/track remove <name>`"

Stop.

Read `experiments/state.json`. Search `goals[]` for a goal whose `name` matches the provided value:

- Match case-insensitively
- Allow partial matches only if they resolve to exactly one goal

If no goal matches, print:

> "Goal '<name>' not found. Run `/track list` to see existing goals."

Stop.

If multiple goals match the partial name, print a short disambiguation message listing the matching names and stop.

If exactly one goal matches, confirm:

> "Remove goal '<name>' (metric: <target_metric>, target: <target_delta>)? (y/n)"

If the user says no, print:

> "Cancelled."

Stop.

If the user says yes:

1. Set the goal's `status` to `"removed"`
2. Write the updated `experiments/state.json`
3. Print:

> "Goal removed. It will no longer affect the experiment loop."

Mark `remove` complete.

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  { id: "parse", status: "completed" },
  { id: "state", status: "completed" },
  { id: "bench", status: "completed" },
  { id: "target", status: "completed" },
  { id: "priority", status: "completed" },
  { id: "save", status: "completed" },
  { id: "list", status: "completed" },
  { id: "remove", status: "completed" }
])
```
