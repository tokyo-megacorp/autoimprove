---
name: idea-matrix
description: |
  Invoke for 'idea matrix', '/idea-matrix', '3x3 matrix', 'convergence report', or to evaluate 3+ design options. Spawns parallel haiku agents to score options and pairwise combinations, synthesizes a convergence report.

  <example>
  user: "Run idea matrix: A: Redis, B: in-memory LRU, C: file cache"
  assistant: I'll use idea-matrix to score all three options and their combinations.
  <commentary>Explicit invocation with inline options.</commentary>
  </example>

  <example>
  user: "We've discussed hooks, skills, and stop-hooks. Which is strongest?"
  assistant: I'll run idea-matrix on the three options to surface the strongest design.
  <commentary>Options exist in context — converge mid-brainstorm without re-prompting user.</commentary>
  </example>

  <example>
  user: "Give me a convergence report on JWT vs session cookies vs OAuth."
  assistant: I'll use idea-matrix to generate a convergence report across all three strategies.
  <commentary>"Convergence report" is a direct trigger phrase.</commentary>
  </example>
argument-hint: "<problem statement> + <options list> [--brief]"
allowed-tools: [Read, Glob, Grep, Bash, Agent, TodoWrite]
---

<SKILL-GUARD>
You are NOW executing the idea-matrix skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Pre-digest project context, spawn 9 tool-less haiku agents in parallel to score design options and their combinations on a structured rubric, then synthesize a convergence report.

---

# 1. Parse Input

From the user's input (or the current conversation context), extract:

- **problem**: The design problem or decision being explored
- **options**: A list of design options (minimum 3). Each option has a short label and a description.
- **brief_mode**: `true` if `--brief` flag is present, `false` otherwise. In brief mode, skip the full score table and dimension aggregates — output only the winner summary (see step 6).

If the user provided options inline (e.g., "A: hooks, B: skill, C: stop hook"), use those directly.

If the user invoked `/idea-matrix` during a brainstorming session where options were already discussed, gather the options from conversation context.

If fewer than 3 options are available, ask the user to provide more before proceeding. The matrix needs at least 3 options to generate meaningful combinations.

Store as:

```
PROBLEM = "<problem statement>"
OPTIONS = [
  { label: "A", name: "<short name>", description: "<what this option does>" },
  { label: "B", name: "<short name>", description: "<what this option does>" },
  { label: "C", name: "<short name>", description: "<what this option does>" },
  ...any additional options (Alt1, Alt2, etc.)
]
```

---

# 2. Generate the 3x3 Matrix Cells

From the options list, generate exactly 9 exploration cells. The matrix is **options and their combinations**:

**For 3 base options (A, B, C):**

| Cell | What the agent scores |
|------|----------------------|
| 1. A alone | Option A in isolation — full assessment |
| 2. B alone | Option B in isolation — full assessment |
| 3. C alone | Option C in isolation — full assessment |
| 4. A + B | Hybrid combining A and B — synergies and conflicts |
| 5. A + C | Hybrid combining A and C — synergies and conflicts |
| 6. B + C | Hybrid combining B and C — synergies and conflicts |
| 7. A + B + C | All three combined — is the full stack viable? |
| 8. Alt 1 | First alternative/variant (if provided), else best-of-breed remix from 1-7 |
| 9. Alt 2 | Second alternative/variant (if provided), else contrarian approach |

**If the user provided more than 3 options** (e.g., 3 base + 2 alternatives), assign cells 8 and 9 to the provided alternatives.

**If the user provided exactly 3 options**, cells 8 and 9 are creative synthesis:
- Cell 8: "Best-of-breed remix" — the agent proposes its own hybrid from the best parts of each option
- Cell 9: "Contrarian approach" — the agent challenges all 3 options and proposes something fundamentally different

Store as `CELLS[1..9]`, each with a label and assignment description.

**Initialize progress tracking:**

Use plain-language descriptions — the user cares about intention and direction, not cell numbers or implementation labels. Describe what each idea *achieves* or *bets on*, not what it's technically called.

Examples of good vs bad content strings:
- Bad: `"Cell 1 — A alone (--sensitivity flag)"`
- Good: `"Idea #1 — Audit whether the winner holds under different priorities"`
- Bad: `"Cell 4 — A+B (sensitivity + weights)"`
- Good: `"Idea #4 — Let users set priorities, then verify the choice is stable"`

```
TodoWrite([
  {id: "cell-1", content: "Idea #1 — [what Option A achieves, in plain language]", status: "pending"},
  {id: "cell-2", content: "Idea #2 — [what Option B achieves, in plain language]", status: "pending"},
  {id: "cell-3", content: "Idea #3 — [what Option C achieves, in plain language]", status: "pending"},
  {id: "cell-4", content: "Idea #4 — [what combining A+B unlocks]", status: "pending"},
  {id: "cell-5", content: "Idea #5 — [what combining A+C unlocks]", status: "pending"},
  {id: "cell-6", content: "Idea #6 — [what combining B+C unlocks]", status: "pending"},
  {id: "cell-7", content: "Idea #7 — [what all three together achieve]", status: "pending"},
  {id: "cell-8", content: "Idea #8 — [best-of-breed: what the remix optimizes for]", status: "pending"},
  {id: "cell-9", content: "Idea #9 — [contrarian: what assumption this challenges]", status: "pending"},
  {id: "devil", content: "Devil's advocate — stress-test the winner", status: "pending"}
])
```

---

# 3. Context Pre-Digestion (Orchestrator Research Phase)

**This is the critical step.** YOU (the orchestrator, running on the main model) do the hard work of researching the codebase. Haiku agents receive pre-digested context only — they never touch the codebase.

**3a. Research the codebase:**
- Read all files relevant to the design problem (architecture, config, key modules)
- Check recent commits for context on current direction
- Identify patterns, conventions, and constraints that would affect each option

**3b. Produce an architecture brief (~500 tokens):**
Summarize into a dense, self-contained brief that covers:
- Project structure and key modules
- Relevant existing patterns and conventions
- Technical constraints (language, framework, dependencies)
- Integration points that the options would touch

**3c. Extract per-option context:**
For each option, extract specific code patterns or files that are most relevant. This becomes part of that cell's agent prompt.

**3d. Assemble agent prompts:**
Each agent prompt should be fully self-contained at ~800 tokens total:
- Problem statement (~100 tokens)
- Architecture brief (~500 tokens)
- Cell assignment + option descriptions (~100 tokens)
- Scoring rubric (~100 tokens)

Store as `BRIEF` (shared) and `CELL_CONTEXT[1..9]` (per-cell additions if needed).

**Why this matters:** No tool calls = agents are faster and cheaper. Pre-digested context = haiku reasons about the right things instead of exploring blindly. The orchestrator does research; haiku does evaluation.

---

# 4. Dispatch 9 Haiku Agents in Parallel

Spawn all 9 agents simultaneously using the Agent tool. **No tools** — agents receive everything they need in the prompt.

**Agent prompt template for each cell:**

```
You are an idea explorer scoring a specific design option or combination.

## Problem
{PROBLEM}

## Architecture Brief
{BRIEF}

## All Options Under Consideration
{For each option: label, name, description}

## Your Assignment
Cell {N}: {CELL_LABEL}
{CELL_DESCRIPTION}
{CELL_CONTEXT if any per-cell additions}

## Instructions
1. Score this option/combination against the architecture brief
2. For hybrid cells: focus on synergies AND conflicts between the options
3. For creative cells (remix/contrarian): propose a concrete alternative grounded in the brief
4. Surface non-obvious insights — the orchestrator knows the obvious trade-offs

## Scoring Rubric (return as JSON, no prose)
{
  "cell": {N},
  "label": "{CELL_LABEL}",
  "thesis": "<one sentence: your position on this option BEFORE scoring>",
  "scores": {
    "feasibility": <1-5>,
    "risk": <1-5>,
    "synergy_potential": <1-5>,
    "implementation_cost": <1-5>
  },
  "dealbreaker": { "flag": <true|false>, "reason": "<if true, one sentence>" },
  "surprise": "<one non-obvious insight citing specific detail from the brief, or null>",
  "recommendation": "<if this option wins, the first implementation step is...>",
  "verdict": "<one sentence: pursue or not, and why>"
}

Scoring guide:
- 5 = ideal, 4 = good, 3 = adequate, 2 = concerning, 1 = showstopper
- Risk is inverted: 5 = lowest risk, 1 = highest risk (higher is always better)
- Score 3 only when genuinely neutral. If all scores cluster around 3, your output is worthless — differentiate.
- Return ONLY the JSON. No prose, no fences.
```

**Agent configuration:**
- Model: `haiku`
- Tools: none (agents reason about pre-digested context only)

**Cells 8 and 9 use differentiated prompts.** When the user provided exactly 3 base options, append this to the cell 8 and 9 prompts instead of the generic Instructions block:

*Cell 8 — Best-of-breed remix:*
```
## Your Assignment
Propose a concrete hybrid that combines the strongest elements of options A, B, and C.
Do NOT score the existing options — design a new option that outperforms all three.
Anchor your proposal in the architecture brief: reference specific files, patterns, or constraints.
Your "scores" should reflect the proposed hybrid, not any original option.
Your "recommendation" must be a concrete first implementation step for your proposal.
```

*Cell 9 — Contrarian:*
```
## Your Assignment
Challenge the framing. All three options may be solving the wrong problem.
Propose a fundamentally different approach that none of options A, B, or C explored.
Be specific: name the assumption all three options share and explain why it's wrong.
Your "scores" should reflect your contrarian proposal, not any original option.
Your "verdict" must state what you'd do instead and why it dominates.
```

**Mark all cells in_progress before dispatching** (they all dispatch simultaneously):
```
TodoWrite([{id: "cell-1", status: "in_progress"}, ..., {id: "cell-9", status: "in_progress"}])
```

**Dispatch all 9 agents in a single parallel batch.** Do NOT dispatch sequentially.

---

# 5. Collect and Validate Results

As agents return, validate and track each result:

- **Sparse-output check:** if the raw response is ≤ 50 characters, re-prompt once: `"Your response appears incomplete. Return the full JSON object with all fields — do not truncate."` If still sparse, record `error: "sparse_output"` and continue.
- **Valid JSON** with `scores`, `dealbreaker`, `verdict` fields: store in `RESULTS[cell_number]`. Mark cell completed: `TodoWrite([{id: "cell-N", status: "completed"}])`.
- **Invalid JSON**: re-prompt once: `"Your response was not valid JSON. Return only the corrected JSON object."` If still invalid, record as `{ "cell": N, "label": "...", "error": "malformed_json" }` and continue.
- **Score validation**: All scores must be 1-5. If out of range, clamp to nearest valid value.

Wait for all 9 agents to complete before proceeding to synthesis.

---

# 6. Synthesize Convergence Report

Analyze all 9 results and produce a convergence report. This is YOUR analysis — not a summary of agent outputs.

**6a. Build the Score Matrix**

Present the full 3x3 grid with numerical scores:

```
## Idea Matrix — {PROBLEM}

| Cell | Option | Feas. | Risk | Synergy | Cost | Avg | Dealbreaker | Verdict |
|------|--------|-------|------|---------|------|-----|-------------|---------|
| 1 | A alone | 4 | 5 | 3 | 4 | 4.0 | -- | ... |
| 2 | B alone | 3 | 3 | 3 | 3 | 3.0 | -- | ... |
| ... | ... | ... | ... | ... | ... | ... | ... | ... |
```

**Avg** = mean of the 4 scores. Cells with `dealbreaker: true` are flagged regardless of scores.

**6b. Cross-Cutting Dimension View**

After the per-cell matrix, present aggregate scores BY DIMENSION across all 9 cells:

```
### Dimension Aggregates

| Dimension | Avg | Min | Max | Cells scoring 1-2 |
|-----------|-----|-----|-----|-------------------|
| Feasibility | 3.7 | 2 | 5 | Cell 7, Cell 9 |
| Risk | 3.2 | 1 | 5 | Cell 4 |
| Synergy | 3.9 | 2 | 5 | Cell 3 |
| Impl. Cost | 3.1 | 1 | 4 | Cell 7, Cell 8 |
```

This reveals which dimensions are consistent across options (all cells score similar risk) versus divergent (feasibility varies wildly), and which dimensions are the weakest overall.

**6c. Identify Convergence**

Rank cells by composite score (average of all 4 dimensions). Compute the **confidence margin** = winner composite − runner-up composite.

- **margin ≥ 0.5** → clear winner, proceed normally
- **0.3 ≤ margin < 0.5** → moderate confidence — note it in the report
- **margin < 0.3** → **narrow win** — do NOT declare a single winner. Present top 2 as tied candidates with the note: "Margin too small to distinguish — consider running the matrix with sharper option differentiation or additional constraints." Set `verdict_type: "narrow_win"`.

Then analyze:
- **Top scorer**: Which cell has the highest composite? Is it a solo, hybrid, or creative option?
- **Dealbreaker filter**: Eliminate any cells flagged as dealbreakers
- **Score band distribution**: Count cells by band — strong (4-5 avg), neutral (3 avg), weak (1-2 avg).
- **Cluster analysis**: Do hybrid cells score consistently higher than solos? Does this suggest combination is the right path?
- **Top insights**: Cherry-pick the 3-5 most impactful surprises across all 9 cells. These are the findings that change the trade-off calculus.
- **Risk patterns**: Are there risks that appear across multiple cells?

**§6c-i — Poor-Differentiation Protocol**

If 7 or more of the 9 cells land in the neutral band (avg 2.5–3.5), the matrix has failed to differentiate the options. **Do not fabricate a winner.** Instead:

| Diagnosis | Signal | Recovery Action |
|-----------|--------|-----------------|
| Options are too similar | Solos score nearly identically | Stop. Ask the user to replace 1-2 options with genuinely different approaches. |
| Problem statement is too vague | Agents score based on different assumptions | Stop. Ask the user to clarify the specific decision constraint (e.g., "optimize for X given constraint Y"). |
| Agent score collapse | Most cells return 3 across all 4 dimensions | Re-run cells 8 and 9 with explicit instruction to be contrarian and differentiate. |

When this protocol triggers:
- Set `verdict_type: "no_clear_winner"` in the JSON output.
- Write the Recommended Design section as: "**No winner emerged.** [Diagnosis]. [Recovery action]."
- Do NOT rank options from 1–9 as if a winner exists — this misleads the user.

**6d. Recommended Design**

```
### Recommended Design

**Winner:** {label} — {one-line summary} (score: {avg}/5)
**Verdict:** Go | Go with conditions | No clear winner

**Why it emerged:** {2-3 sentences citing specific scores and patterns across the matrix}

**Conditions** (if "Go with conditions" — these must be true for the recommended design to succeed):
1. {specific condition from risk scores or dealbreaker analysis}
2. {specific condition from surprise insights}

**Dealbreakers avoided:** {cells eliminated and why}

**Top insights across all cells:**
- {most impactful surprise from any cell}
- {second most impactful}
- {third}

**First step:** {recommendation field from the winning cell}

**Required mitigations** (blocking — must address before proceeding):
- {risk or conflict from non-winning cells that applies to the winner}

**Recommended improvements** (non-blocking — worth carrying forward):
- {high-scoring aspect from non-winning cells that would strengthen the winner}
```

**6d.5. Devil's Advocate Challenge**

Skip this step if `verdict_type` is `no_clear_winner` or `narrow_win` (no winner to challenge).

Mark progress: `TodoWrite([{id: "devil", status: "in_progress"}])`.

Spawn 1 Haiku agent to challenge the winning option:

```
You are a devil's advocate. The following design option was selected as the winner
of an idea matrix evaluation. Your job is NOT to score it — your job is to find its
single most credible failure mode.

## Problem
{PROBLEM}

## Winner
{WINNER_LABEL}: {WINNER_DESCRIPTION}
Score: {WINNER_COMPOSITE}/5 — {WINNER_VERDICT}

## Architecture Brief
{BRIEF}

Find the ONE thing most likely to make this choice fail in practice.
Be specific: cite the architecture brief, name exact integration points or constraints.
Vague risks ("it might not scale") are worthless — name the specific failure.

Output as JSON:
{
  "challenge": "<one sentence: the credible failure mode>",
  "evidence": "<specific detail from the brief that makes this a real risk>",
  "mitigation": "<concrete first step to reduce this risk before committing to the winner>"
}
```

Parse the response. If valid: add as `"devil_advocate"` to the convergence report under the winner section. If malformed: skip silently. Mark: `TodoWrite([{id: "devil", status: "completed"}])`.

**6d.6. Brief Mode Output (`--brief`)**

If `brief_mode` is true, replace the full report (6a–6d) with this compact block and skip 6e:

```
## Idea Matrix — {PROBLEM}

Winner: {WINNER_LABEL} — {WINNER_DESCRIPTION}
Confidence: {clear|moderate|narrow}  (margin: {confidence_margin:.2f})
Why it won: {2 sentences from synthesis — cite specific score patterns}
Key risk: {devil_advocate.challenge or "none identified"}
{If conditions: "Conditions: {list}"}
First step: {recommendation from winning cell}
```

**Narrow win exception:** if `verdict_type == "narrow_win"`, also include:
```
Runner-up: {RUNNER_UP_LABEL} — {RUNNER_UP_DESCRIPTION}  (margin: {margin:.2f} — too close to dismiss)
```

This format is optimized for pipeline handoff (e.g., to `/adversarial-review`): the reviewer gets the winner, the pre-identified risk, and the confidence level without wading through 9 cells of scores.

**6e. Output Structured JSON**

After the human-readable report, output the full structured data:

```json
{
  "problem": "<problem statement>",
  "options": [<OPTIONS array>],
  "cells": [<RESULTS array, all 9 with scores>],
  "ranking": [
    { "cell": <N>, "label": "<label>", "composite": <avg>, "dealbreaker": <bool> }
  ],
  "by_score_band": {
    "strong": <count of cells with avg >= 4>,
    "neutral": <count of cells with avg >= 3 and < 4>,
    "weak": <count of cells with avg < 3>
  },
  "dimension_aggregates": {
    "feasibility": { "avg": <N>, "min": <N>, "max": <N> },
    "risk": { "avg": <N>, "min": <N>, "max": <N> },
    "synergy_potential": { "avg": <N>, "min": <N>, "max": <N> },
    "implementation_cost": { "avg": <N>, "min": <N>, "max": <N> }
  },
  "convergence": {
    "winner": "<cell label>",
    "winner_cell": <cell number>,
    "winner_composite": <avg score>,
    "verdict_type": "go | conditional | no_clear_winner",
    "conditions": ["<what must be true for the winner to succeed>"],
    "reasoning": "<why this emerged — cite scores>",
    "dealbreakers": [{ "cell": <N>, "reason": "<why>" }],
    "top_insights": ["<most impactful surprises across all 9 cells, max 5>"],
    "risks": ["<key risks from matrix>"],
    "required_mitigations": ["<blocking risks/conflicts from non-winning cells that apply to the winner>"],
    "recommended_improvements": ["<non-blocking insights from non-winning cells worth carrying forward>"]
  },
  "errors": <count of malformed agent outputs>,
  "confidence_margin": <winner_composite - runner_up_composite>,
  "devil_advocate": {
    "challenge": "<failure mode>",
    "evidence": "<specific detail>",
    "mitigation": "<first step>"
  }
}
```

---

# 6f. Self-Assessment

```
## Self-Assessment
- Model used: haiku (9 cells) + haiku (devil's advocate)
- Codebase complexity: [1=trivial config, 3=moderate, 5=complex multi-subsystem]
- Could synthesis (step 6) have used a cheaper model? [yes/no + one sentence]
- Error rate: {N}/9 cells had malformed or sparse output
```

Populate honestly — this data feeds model-selection calibration.

---

# 7. Notes

- **9 agents is the fixed grid.** The 3x3 structure (3 solo + 3 pairs + 1 trio + 2 wild) is the core design.
- **Haiku only, no tools.** Agents reason about pre-digested context. The orchestrator does the codebase research.
- **Scores enable objective comparison.** Numerical rubric eliminates ambiguity in prose-based assessments.
- **The convergence report is the deliverable.** Lead with the synthesis and recommendation, not the raw scores.
- **Works standalone or during brainstorming.** Can be invoked via `/idea-matrix` at any point — enriches design discussions or produces standalone analysis.
