# Rubric: Progress Transparency

**Version:** 1.0.0
**Applies to:** technique, discipline-enforcing (any multi-step skill the user watches execute)

Skills that run multi-step processes where the user can see the task list. Covers how well the skill communicates live progress, intent, and results — not just whether steps are correct.

## Dimensions

### 1. TodoWrite Initialization (REQUIRED)

**Score criteria:**
- 0: No TodoWrite — user sees nothing until the skill finishes
- 3: TodoWrite exists but initialized lazily (inside a branch, not at the top)
- 5: TodoWrite initialized at the top with all major steps as `pending`
- 7: All steps initialized + in_progress/completed marks at each transition point
- 10: All above + round/iteration resets (e.g., re-emit pending for each loop cycle)

**Test generation:**
- Unit prompt: "Run this skill and show me what the task list looks like at each phase"
- Unit prompt: "What does the user see while step 3 is running?"

**Transform rules:**
- Add a `TodoWrite([...])` block immediately after argument parsing, before any tool calls
- One entry per major user-visible step (not internal sub-steps)
- At each step boundary: mark current as `completed`, next as `in_progress`

### 2. Intention-First Labeling (REQUIRED)

**Score criteria:**
- 0: Content strings use internal variable names or step IDs: `"Cell 4 — A+B (sensitivity + weights)"`
- 3: Generic labels like `"Step 3"` or `"Running analysis"`
- 5: Labels describe action but not outcome: `"Spawn Enthusiast agent"`
- 7: Labels describe what the step achieves for the user: `"🔍 Scan codebase for issues"`
- 10: Labels describe intent + expected output: `"🔍 Enthusiast — surface findings"`, updated at completion to `"🔍 Enthusiast — 8 findings"`

**Anti-patterns:**
- Variable names in labels: `"NOVEL_FINDINGS.length findings found"` (use the resolved count: `"8 findings"`)
- Implementation labels: `"Cell 1 — A alone (--sensitivity flag)"` → `"Idea #1 — Audit robustness after the fact"`
- Step numbers without context: `"Step 3 of 9"` → `"⚗️ Running experiment 3"`

**Transform rules:**
- Replace all content strings with user-facing descriptions of what the step achieves
- Frame from the user's perspective: what will they understand or decide after this step?
- Remove internal variable names, cell numbers, and flag names from labels

### 3. Live Enrichment at Completion (REQUIRED)

**Score criteria:**
- 0: Completion marks don't update the content: `{status: "completed"}` only
- 3: Completion adds a generic label: `"Step 3 — done"`
- 5: Completion updates the count but uses variable syntax: `"Enthusiast — {N} findings"`
- 7: Completion updates with resolved counts: `"🔍 Enthusiast — 8 findings"`
- 10: All three agents/steps update with their distinct result type: Enthusiast → finding count, Adversary → challenge count, Judge → confirmed/debunked split

**Why this matters:** The task list is a result summary the user can read after the skill finishes — not just a progress spinner. A completed task that still says "Surface findings" taught the user nothing. One that says "🔍 Enthusiast — 8 findings" is an actionable record.

**Transform rules:**
- At every `status: "completed"` mark, also update `content` with the actual output
- Pattern: `"[emoji] [Step name] — [N] [output type]"` (e.g., `"✅ Gates — 2/2 passed"`, `"📊 Score — 4.25/5"`)
- If no countable output: include the verdict or state: `"🚀 Handed off to /idea-matrix"`

### 4. Semantic Markers (recommended)

**Score criteria:**
- 0: No visual differentiation between steps
- 3: Some labels have emojis, inconsistently
- 7: Each persona or phase has a consistent emoji: 🔍 discovery, ⚔️ challenge, ⚖️ judgment, ✅ validation
- 10: Emoji serves as identity marker the user can track across rounds: same emoji always means the same agent/phase

**Emoji assignment guide:**
| Role / Phase | Emoji | Use for |
|---|---|---|
| Discovering / scanning | 🔍 | Enthusiast, analysis, search |
| Challenging / attacking | ⚔️ | Adversary, stress-test, pressure |
| Judging / arbitrating | ⚖️ | Judge, scoring, ruling |
| Validating / passing | ✅ | Gates, verification, confirmation |
| Failing / error | ⚠️ | Warnings, blocked, degraded |
| Building / fixing | 🛠️ | Scaffold, repair, implement |
| Measuring / scoring | 📊 | Benchmarks, metrics, scores |
| Ideating / proposing | 💡 | Options, proposals, suggestions |
| Archiving / storing | 🗂️ | Save, log, persist |
| Looping / iterating | 🔄 | Rounds, retries, cycles |
| Experimenting | ⚗️ | Experiments, trials, probes |
| Targeting / selecting | 🎯 | Theme selection, prioritization |

**Anti-patterns:**
- Decorative emojis that don't carry meaning: `"✨ Running analysis ✨"`
- Different emojis for the same role across steps: 🔍 in step 1, 🧐 in step 4 for the same agent
- Emojis that contradict the step role: ✅ for a step that might fail

---

## Routing

Add `progress-transparency` to the REQUIRED rubric list for:
- `technique` skills
- `discipline-enforcing` skills

It is RECOMMENDED (not required) for `reference` and `pattern` skills, which typically don't execute as multi-step flows.
