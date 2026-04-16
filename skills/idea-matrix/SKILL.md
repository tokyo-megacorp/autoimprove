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
argument-hint: "<problem statement> + <options list> [--brief] [--from-spec <spec-path>]"
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
- **SPEC_PATH**: if `--from-spec <path>` is present, store the path after resolving it from the current working directory. Paths may be relative or absolute.

If the user provided options inline (e.g., "A: hooks, B: skill, C: stop hook"), use those directly.

If the user invoked `/idea-matrix` during a brainstorming session where options were already discussed, gather the options from conversation context.

If fewer than 3 options are available, ask the user to provide more before proceeding. The matrix needs at least 3 options to generate meaningful combinations.

Store as:

```
PROBLEM = "<problem statement>"
SPEC_PATH = "<resolved spec path>" # if --from-spec was provided
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

Store as `CELLS[1..9]`, each with:
- `label`: the cell's identifier (e.g., "A", "A+B", "D")
- `description`: the assignment string
- `type`: one of `"solo"` (cells 1-3), `"combo"` (cells 4-7), or `"alt"` (cells 8-9)

The `type` classification is load-bearing — winner determination in step 6c uses **solo cells only** to prevent structural bias. See `docs/null-model-validation-abort.md` (2026-04-16) for the empirical rationale.

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
  {id: "devil", content: "Devil's advocate — stress-test the winner", status: "pending"},
  {id: "falsification", content: "Post-matrix falsification — neutral re-probe (L11)", status: "pending"}
])
```

---

# 3. Context Pre-Digestion (Orchestrator Research Phase)

**This is the critical step.** YOU (the orchestrator, running on the main model) do the hard work of researching the codebase. Haiku agents receive pre-digested context only — they never touch the codebase.

**3a. Research the codebase:**
If `SPEC_PATH` is set, read that Markdown spec and build `BRIEF` from its intro/early sections: extract the problem or decision, architecture constraints (stack, patterns, file references), and any options already explored. The spec was written by superpowers brainstorming and contains sufficient architecture context. Do not re-read the codebase. Skip 3a and continue with 3b-3d using the spec-derived brief.

If `SPEC_PATH` is not set:
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

**3d. Produce an environment block (~150 tokens) — NEW (addresses #105 L8):**
Summarize the deployment and runtime context that cells should assume. This prevents agents from hallucinating dealbreakers about infrastructure that is or is not present (the `postbox hook` matrix dealbroke `A+B+C` citing race conditions the MAGI daemon already serializes — because the prompt never mentioned MAGI's role). Include:
- Existing daemons, services, single-writer arbiters
- Tables, schemas, or stores relevant to the option space
- Hook framework points and invariants
- Constraints (SLAs, rollback budgets, team size) that bound realistic trade-offs

Store as `ENV_BLOCK`. If the problem is truly context-free, emit a one-line `ENV_BLOCK` that says so — do not fabricate infrastructure.

**3e. Assemble agent prompts:**
Each agent prompt should be fully self-contained at ~950 tokens total:
- Problem statement (~100 tokens)
- Architecture brief (~500 tokens)
- Environment block (~150 tokens)
- Cell assignment + option descriptions (~100 tokens)
- Scoring rubric (~100 tokens)

Store as `BRIEF` (shared), `ENV_BLOCK` (shared), and `CELL_CONTEXT[1..9]` (per-cell additions if needed).

**Why this matters:** No tool calls = agents are faster and cheaper. Pre-digested context = haiku reasons about the right things instead of exploring blindly. The orchestrator does research; haiku does evaluation. The env block is the anti-hallucination gate — dealbreakers must be grounded in it.

---

# 4. Dispatch 9 Haiku Agents in Parallel

> **HARD CONSTRAINT — PARALLEL ONLY:** All 9 Agent calls MUST appear in a single message.
> Dispatching agents one-at-a-time is a critical failure — it multiplies latency by 9×.
> If you catch yourself about to dispatch a single agent: STOP. Compose all 9 calls first, then send them together.
>
> Checklist before dispatching:
> - [ ] Have I written all 9 Agent tool calls?
> - [ ] Are all 9 in the same response message (not spread across multiple turns)?
>
> Only then dispatch.

Spawn all 9 agents simultaneously using the Agent tool. **No tools** — agents receive everything they need in the prompt.

**Agent prompt template for each cell:**

```
# No tools — agents must NOT browse the codebase
allowed-tools: []

CRITICAL: Do NOT invoke any tools. Do NOT use Read, Glob, Grep, or Bash. Answer using ONLY the context in this prompt. Return the JSON immediately.

You are an idea explorer scoring a specific design option or combination.

## Problem
{PROBLEM}

## Architecture Brief
{BRIEF}

## Available Infrastructure / Environment
{ENV_BLOCK}

Dealbreakers in your output MUST be grounded in the items listed above. Do not cite infrastructure, daemons, services, or invariants that are not named here — if a risk depends on something not in this block, the risk is hallucinated and the cell will be re-dispatched.

## All Options Under Consideration
{For each option: label, name, description}

## Your Assignment
Cell {N}: {CELL_LABEL}
{CELL_DESCRIPTION}
{CELL_CONTEXT if any per-cell additions}

## SCORING CONVENTION (MANDATORY — READ BEFORE SCORING)

All four dimensions use **HIGHER = BETTER** on a 1-5 scale. Do NOT invert. Do NOT treat lower-is-safer for any dimension.

| Dimension | 1 (worst) | 5 (best) |
|-----------|-----------|----------|
| feasibility | showstopper | trivial to build |
| risk | highest risk / most likely to regress silently | lowest risk / robust under failure |
| synergy_potential | incompatible with other subsystems | composes cleanly, unlocks future work |
| implementation_cost | days of coordinated work | minutes |

**Convention drift is the #1 source of scoring noise in this skill.** Prior runs (2026-04-15 MATRIX_3) had cells spontaneously inverting risk direction, producing outlier composites that flipped winners. The `risk_direction_used` field below exists to catch that — declare it explicitly and match the table above.

## Instructions
1. Score this option/combination against the architecture brief
2. For hybrid cells: focus on synergies AND conflicts between the options
3. For creative cells (remix/contrarian): propose a concrete alternative grounded in the brief
4. Surface non-obvious insights — the orchestrator knows the obvious trade-offs
5. If your winning cell proposes a novel mechanism, fill `mechanism_novelty` with one sentence naming what it does that no other cell does. Leave null otherwise.

## Scoring Rubric (return as JSON, no prose)
{
  "cell": {N},
  "label": "{CELL_LABEL}",
  "thesis": "<one sentence: your position on this option BEFORE scoring>",
  "risk_direction_used": "higher_safer",
  "scores": {
    "feasibility": <1-5>,
    "risk": <1-5>,
    "synergy_potential": <1-5>,
    "implementation_cost": <1-5>
  },
  "dealbreaker": { "flag": <true|false>, "reason": "<if true, one sentence>" },
  "surprise": "<one non-obvious insight citing specific detail from the brief, or null>",
  "mechanism_novelty": "<one sentence naming a mechanism unique to this cell, or null>",
  "recommendation": "<if this option wins, the first implementation step is...>",
  "verdict": "<one sentence: pursue or not, and why>"
}

Scoring guide:
- 5 = ideal, 4 = good, 3 = adequate, 2 = concerning, 1 = showstopper
- Score 3 only when genuinely neutral. If all scores cluster around 3, your output is worthless — differentiate.
- `risk_direction_used` MUST be the string `"higher_safer"`. If you find yourself wanting to write `"lower_safer"`, stop and re-read the convention table — you are about to produce an outlier.
- Return ONLY the JSON. No prose, no fences.
```

**Agent configuration:**
- `description`: `"Idea #N — [3-word theme]"` — 3 words capturing the core bet of this cell (e.g., `"Idea #4 — strict then weighted"`, `"Idea #8 — keep-rate adaptive"`). This is what appears in the agent panel UI — match the intention-first style of the TodoWrite labels.
- Model: `haiku`
- Tools: none (agents reason about pre-digested context only)

**Tool contamination guard:** after dispatch, inspect each agent's `usage.tool_uses` field. If any cell shows `tool_uses > 0`, the agent browsed the codebase instead of reasoning from the pre-digested brief — results are contaminated with asymmetric information. Re-dispatch that cell with an even stricter no-tools preamble. Empirical evidence (2026-04-15 RUN A cell 5): one cell using 25 tool calls produced a composite that differed by −2.0 from tool-blocked replications of the same prompt.

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

**Mark all cells in_progress before dispatching** (they all dispatch simultaneously) — this is the LAST step before the simultaneous parallel dispatch of all 9 agents.:
```
TodoWrite([{id: "cell-1", status: "in_progress"}, ..., {id: "cell-9", status: "in_progress"}])
```

**Dispatch all 9 agents in a single parallel batch.** Do NOT dispatch sequentially.

---

# 5. Collect and Validate Results

As agents return, validate each result through the gates below. This is the anti-drift layer (addresses #105 L7): prompt-only schema discipline failed empirically on MATRIX_5 (postbox hook), where 4 of 9 cells invented 5-7 dimensions instead of the prescribed 4, producing non-comparable composites. Prompt instructions are not enough; post-dispatch validation is required.

**Gate 1 — Parseable JSON.**
If raw response ≤ 50 chars or does not parse as JSON, re-prompt ONCE with: `"Your response was not valid JSON or was incomplete. Return only the corrected JSON object with all required fields."` If still invalid, record `error: "malformed_json"` or `error: "sparse_output"` and continue.

**Gate 2 — Exact 4-dimension schema.**
`scores` must contain EXACTLY the four keys: `feasibility`, `risk`, `synergy_potential`, `implementation_cost`. If any other keys are present (e.g., `correctness`, `robustness`, `token_efficiency`, `complexity`, `leverage`, `novelty`, `composability`, `runtime_safety`, `latency_impact`, `reliability`, `observability_gain`, `operational_complexity`, `security_surface`, `hook_coverage`, or any others), the cell has dimension-drifted. Re-dispatch ONCE with a stricter preamble that names the violation:
> `"Your previous response added dimensions beyond the required four. Use EXACTLY these four keys in scores: feasibility, risk, synergy_potential, implementation_cost. No others. Any other keys cause rejection."`

If the second response still has extra keys, record `error: "schema_fail"` and drop the cell.

**Gate 3 — Convention declared.**
`risk_direction_used` must equal the string `"higher_safer"`. If missing or inverted, re-dispatch ONCE with: `"risk_direction_used must be \"higher_safer\". If your prior scoring used lower=safer for risk, re-score with HIGHER=SAFER per the convention table."` If second response still non-conforming, record `error: "convention_fail"` and drop the cell.

**Gate 4 — Score bounds.**
All scores must be integers in [1, 5]. If out of range or non-integer, clamp integer values and log a warning. If non-integer (e.g., strings), re-dispatch once; drop if second response still non-conforming.

**Gate 5 — Dealbreaker grounding (L8 enforcement).**
If `dealbreaker.flag == true` AND the dealbreaker reason cites infrastructure (a daemon, service, queue, cluster, pipeline, database, mesh, cache, replica, or similar noun), that infrastructure MUST appear in `ENV_BLOCK`. If the dealbreaker names something absent from the env block, re-dispatch ONCE with: `"Your dealbreaker cited <NAMED_INFRA> which is not in the Available Infrastructure block. Dealbreakers must be grounded in listed infrastructure. Re-evaluate using only the env block."` If second response still hallucinates, record `error: "infra_grounding_fail"` and drop the cell.

**Track conformance:**
```
SCHEMA_VIOLATIONS = count(cells where error in {"schema_fail", "convention_fail", "infra_grounding_fail"})
SCHEMA_CONFORMANCE_RATE = (9 - SCHEMA_VIOLATIONS) / 9
```

If `SCHEMA_CONFORMANCE_RATE < 0.80`, surface a warning in the convergence report: prompt-only discipline is drifting on this problem. Carry the rate into §6f self-assessment.

Valid results go in `RESULTS[cell_number]`. Mark: `TodoWrite([{id: "cell-N", status: "completed"}])`.

Wait for all 9 agents to complete (including retries) before proceeding to synthesis.

---

# 5.5. Pre-Synthesis Model Escalation Check

After collecting all 9 results and before beginning synthesis, run two escalation checks. This mirrors the two-path pattern in adversarial-review step 3C.

**Path A — Hard escalation (anomaly-based):**

Count cells where `error == "malformed_json"` OR `error == "sparse_output"` (i.e., cells that returned an error record rather than valid scores).

```
ANOMALOUS_CELLS = count of RESULTS entries where error == "malformed_json" OR error == "sparse_output"
```

If `ANOMALOUS_CELLS >= 3`:
- Log: `[matrix] ≥3 anomalous cells — escalating synthesis to Sonnet`
- Instruct: **"Escalate synthesis to Sonnet: the current model may have caused the high error rate. Ask the user to re-run with a Sonnet model or switch model now before proceeding with synthesis."**
- Do NOT proceed to synthesis until the user confirms or dismisses the escalation.

Path A fires unconditionally — complexity is irrelevant when data quality is this poor.

**Path B — Soft flag (complexity-based):**

Measure:
- `BRIEF_LENGTH` = character count of the `BRIEF` string produced in step 3b
- `OPTION_COUNT` = number of options in `OPTIONS`

If `BRIEF_LENGTH > 500` AND `OPTION_COUNT > 3`:
- Set `COMPLEXITY_FLAG = true`
- This flag is NOT acted on here — carry it forward to the self-assessment in step 6f.

Path B is advisory only. Synthesis proceeds regardless.

---

# 6. Synthesize Convergence Report

Analyze all 9 results and produce a convergence report. This is YOUR analysis — not a summary of agent outputs.

**6a. Build the Score Matrix**

Present the full 3x3 grid with numerical scores, grouped by cell type so readers can see solo vs combo vs alt at a glance:

```
## Idea Matrix — {PROBLEM}

| Cell | Type | Option | Feas. | Risk | Synergy | Cost | Avg | Dealbreaker | Verdict |
|------|------|--------|-------|------|---------|------|-----|-------------|---------|
| 1 | solo | A alone | 4 | 5 | 3 | 4 | 4.0 | -- | ... |
| 2 | solo | B alone | 3 | 3 | 3 | 3 | 3.0 | -- | ... |
| 3 | solo | C alone | ... | ... | ... | ... | ... | ... | ... |
| 4 | combo | A+B | ... | ... | ... | ... | ... | ... | ... |
| 5 | combo | A+C | ... | ... | ... | ... | ... | ... | ... |
| 6 | combo | B+C | ... | ... | ... | ... | ... | ... | ... |
| 7 | combo | A+B+C | ... | ... | ... | ... | ... | ... | ... |
| 8 | alt | Remix | ... | ... | ... | ... | ... | ... | ... |
| 9 | alt | Contrarian | ... | ... | ... | ... | ... | ... | ... |
```

**Avg** = mean of the 4 scores. Cells with `dealbreaker: true` are flagged regardless of scores. Remember: only **solo** cells compete for the authoritative winner — combo and alt avgs are design insight (see §6c).

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

**6c. Identify Convergence (separated rankings by cell type)**

**Why separated rankings:** Null-model validation on a deliberately flat synthetic control (D0, 2026-04-16) found that combo cells won 14/16 valid reruns with p = 2.95e-05 — driven by the `synergy_potential` dimension tautologically favoring wider options. Full report: `docs/null-model-validation-abort.md`. To prevent structural bias from picking the winner, composites are now ranked **within each cell type separately**, and the authoritative winner comes from the solo pool only.

**Compute three separate rankings:**

1. **Solo ranking** (cells where `type == "solo"`, i.e., cells 1-3): the authoritative pool. The solo winner feeds `convergence.winner`, `recommendation`, brief-mode output, and devil's advocate.
2. **Combo ranking** (cells where `type == "combo"`, i.e., cells 4-7): design insight only. Surface the top combo as "the strongest hybrid" — never as the winner.
3. **Alt ranking** (cells where `type == "alt"`, i.e., cells 8-9): design insight only. Surface the top alt as "the strongest alternative" — never as the winner.

Compute the **solo confidence margin** = solo winner composite − solo runner-up composite.

- **solo margin ≥ 0.5** → clear winner, proceed normally
- **0.3 ≤ solo margin < 0.5** → moderate confidence — note it in the report
- **solo margin < 0.3** → **narrow solo win** — do NOT declare a single winner. Present the top 2 solos as tied candidates with the note: "Margin too small to distinguish — consider running the matrix with sharper option differentiation or additional constraints." Set `verdict_type: "narrow_win"`.

Then analyze:
- **Solo winner**: the highest-composite solo cell, after dealbreaker filter. This is the authoritative recommendation.
- **Dealbreaker filter (solo)**: eliminate any solo cells flagged as dealbreakers. If all 3 solos have dealbreakers, set `verdict_type: "no_clear_winner"` and recommend revisiting options.
- **Score band distribution (solo pool)**: count solo cells by band — strong (4-5 avg), neutral (3 avg), weak (1-2 avg).
- **Combination insight**: if the top combo's composite exceeds the solo winner's composite, report this as evidence that the options compose better than they stand alone. If the top combo includes the solo winner (e.g., solo winner A, top combo A+B), label it a **natural extension** — implement solo first, layer the combination after. If not (e.g., solo winner A, top combo B+C), label it an **alternative angle** worth documenting but not automatically pursued.
- **Alternative insight**: if the top alt's composite exceeds the solo winner's composite, report this as a framing challenge — the alt surfaced a reframing worth considering. Surface the alt's thesis verbatim so the user can judge whether to pivot.
- **Top insights**: cherry-pick the 3-5 most impactful surprises across **all 9 cells** (all types). These feed design thinking regardless of which ranking they came from.
- **Risk patterns**: are there risks that appear across multiple cells (any type)?

**§6c-i — Poor-Differentiation Protocol**

Scope: this check applies to the **solo pool only** (cells 1-3). Combo and alt cells serve as design insight — their flat distribution is expected when the base options already cover the design space.

If all 3 solo cells land in the neutral band (avg 2.5–3.5), the matrix has failed to differentiate the authoritative options. **Do not fabricate a winner.** Instead:

| Diagnosis | Signal | Recovery Action |
|-----------|--------|-----------------|
| Options are too similar | All 3 solos score nearly identically | Stop. Ask the user to replace 1-2 options with genuinely different approaches. |
| Problem statement is too vague | Agents score based on different assumptions | Stop. Ask the user to clarify the specific decision constraint (e.g., "optimize for X given constraint Y"). |
| Agent score collapse | Solo cells return 3 across all 4 dimensions | Re-run solo cells with stricter differentiation instruction. |

When this protocol triggers:
- Set `verdict_type: "no_clear_winner"` in the JSON output.
- Write the Recommended Design section as: "**No winner emerged.** [Diagnosis]. [Recovery action]."
- Do NOT rank solos from 1–3 as if a winner exists — this misleads the user.
- Combo and alt rankings may still be reported as insight, clearly labeled as "no authoritative solo winner was identified."

**6d. Recommended Design**

```
### Recommended Design

**Winner (solo):** {solo_label} — {one-line summary} (composite: {avg}/5)
**Verdict:** Go | Go with conditions | No clear winner

**Why it emerged:** {2-3 sentences citing specific scores within the solo pool}

**Conditions** (if "Go with conditions" — these must be true for the recommended design to succeed):
1. {specific condition from risk scores or dealbreaker analysis}
2. {specific condition from surprise insights}

**Dealbreakers avoided (solo pool):** {solo cells eliminated and why}

### Combination insight (non-authoritative)
**Top combo:** {combo_label} (composite: {avg}/5)
{IF top combo composite > solo winner composite:}
  The combination outscores the solo winner by {diff}.
  {IF combo contains solo winner: "Natural extension — implement the solo winner first, layer this combination after."}
  {IF combo does NOT contain solo winner: "Alternative angle — documented as a separate path, not auto-pursued."}
{ELSE:}
  Solo dominance confirmed — no combination surpassed the standalone recommendation.

### Alternative insight (non-authoritative)
**Top alt:** {alt_label} (composite: {avg}/5)
{IF top alt composite > solo winner composite:}
  The alternative surfaces a framing challenge: {alt thesis verbatim}.
  Consider whether the problem should be reframed before committing to the solo winner.
{ELSE:}
  No alternative outperformed the solo winner — the problem framing holds up.

**Top insights across all 9 cells (all types):**
- {most impactful surprise from any cell}
- {second most impactful}
- {third}

**First step:** {recommendation field from the solo winner cell}

**Required mitigations** (blocking — must address before proceeding):
- {risk or conflict from non-winning cells that applies to the solo winner}

**Recommended improvements** (non-blocking — worth carrying forward):
- {high-scoring aspect from non-winning cells that would strengthen the solo winner}
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

**6d.7. Post-Matrix Falsification Test (NEW — addresses #104 L11)**

Skip this step if the solo winner's `mechanism_novelty` is null or if `verdict_type` is `no_clear_winner` or `narrow_win`.

The matrix-original Cell 8 (remix) and Cell 9 (contrarian) prompts may have nudged agents toward a specific mechanism via framing cues ("UserPromptSubmit hook", "blackboard"). Falsification re-dispatches those two cells with **neutral prompts stripped of mechanism hints** and compares the re-proposed mechanism against the original. This takes ~$0.10 and returns one of three verdicts — `strong`, `framing_dependent`, or `falsified` — that qualify the winner's claim (addresses #104 L5a vs L5b split).

**Procedure:**

1. Construct neutral prompts for Cell 8 and Cell 9 that:
   - Use the same `BRIEF` and `ENV_BLOCK` as the original run.
   - REMOVE any mechanism-specific vocabulary from the Cell 8 and Cell 9 assignment text (e.g., if the original Cell 8 said "combine via UserPromptSubmit hook auto-inject", rewrite as "propose a hybrid that outperforms all three options; describe its mechanism in one sentence without naming any specific implementation primitive").
   - Cell 9 neutral: "challenge the framing; propose a fundamentally different approach; describe your mechanism in one sentence without reusing vocabulary from the original options."
2. Dispatch the two neutral cells (Haiku, `allowed-tools: []`). Collect each cell's `mechanism_novelty` string.
3. **Classify the relationship** between the original winner mechanism and the neutral probes, using your judgment (synthesis-side, not delegated):
   - **`strong`** — both probes converge on the same mechanism CATEGORY AND the same SPECIFIC implementation as the original winner. The winner's mechanism survives framing strip.
   - **`framing_dependent`** — probes converge on the same CATEGORY (e.g., both still propose "hook-based injection") but a DIFFERENT SPECIFIC implementation (e.g., PostToolUse + sentinel file instead of UserPromptSubmit auto-inject). The winner's category is robust; the specific implementation was nudged by framing.
   - **`falsified`** — probes converge on a DIFFERENT CATEGORY entirely (e.g., both propose passive-pull / blackboard instead of hook-based). The original winner was likely a framing artifact.
4. Record as `post_matrix_falsification` in the convergence report and structured JSON:
   ```json
   "post_matrix_falsification": {
     "verdict": "strong | framing_dependent | falsified",
     "probe_a_mechanism": "<one-line mechanism from Cell 8 neutral>",
     "probe_b_mechanism": "<one-line mechanism from Cell 9 neutral>",
     "original_winner_mechanism": "<original winner mechanism_novelty>"
   }
   ```
5. **Consequence for the winner's standing:**
   - `strong` → ship with full confidence.
   - `framing_dependent` → ship the mechanism CATEGORY; treat the specific as one implementation choice. Flag in the `conditions` section of the recommended design that other specifics within the category are viable.
   - `falsified` → downgrade `verdict_type` to `no_clear_winner`. Surface the probes' alternative category as the likely correct direction. Do NOT ship the original winner without re-running the matrix with revised options.

Mark: `TodoWrite([{id: "falsification", status: "completed"}])`.

**6d.6. Brief Mode Output (`--brief`)**

If `brief_mode` is true, replace the full report (6a–6d) with this compact block and skip 6e:

```
## Idea Matrix — {PROBLEM}

Winner (solo): {SOLO_WINNER_LABEL} — {SOLO_WINNER_DESCRIPTION}  (composite: {solo_winner_composite}/5)
Confidence: {clear|moderate|narrow}  (solo margin: {solo_confidence_margin:.2f})
Why it won: {2 sentences from synthesis — cite specific score patterns within solo pool}
Key risk: {devil_advocate.challenge or "none identified"}
{If conditions: "Conditions: {list}"}
Top combo: {TOP_COMBO_LABEL} ({top_combo_composite}/5){" — beats solo winner" if top_combo > solo_winner else ""}
Top alt: {TOP_ALT_LABEL} ({top_alt_composite}/5){" — beats solo winner" if top_alt > solo_winner else ""}
First step: {recommendation from solo winner cell}
```

**Narrow solo win exception:** if `verdict_type == "narrow_win"`, also include:
```
Solo runner-up: {SOLO_RUNNER_UP_LABEL} — {SOLO_RUNNER_UP_DESCRIPTION}  (solo margin: {margin:.2f} — too close to dismiss)
```

This format is optimized for pipeline handoff (e.g., to `/adversarial-review`): the reviewer gets the winner, the pre-identified risk, and the confidence level without wading through 9 cells of scores.

**6e. Output Structured JSON**

After the human-readable report, output the full structured data:

```json
{
  "problem": "<problem statement>",
  "options": [<OPTIONS array>],
  "cells": [<RESULTS array, all 9 with scores AND "type" field: "solo"|"combo"|"alt">],
  "rankings": {
    "solo": [{ "cell": <N>, "label": "<label>", "composite": <avg>, "dealbreaker": <bool> }],
    "combo": [{ "cell": <N>, "label": "<label>", "composite": <avg>, "dealbreaker": <bool> }],
    "alt": [{ "cell": <N>, "label": "<label>", "composite": <avg>, "dealbreaker": <bool> }]
  },
  "by_score_band_solo": {
    "strong": <count of solo cells with avg >= 4>,
    "neutral": <count of solo cells with avg >= 3 and < 4>,
    "weak": <count of solo cells with avg < 3>
  },
  "dimension_aggregates": {
    "feasibility": { "avg": <N>, "min": <N>, "max": <N> },
    "risk": { "avg": <N>, "min": <N>, "max": <N> },
    "synergy_potential": { "avg": <N>, "min": <N>, "max": <N> },
    "implementation_cost": { "avg": <N>, "min": <N>, "max": <N> }
  },
  "convergence": {
    "winner": "<solo winner label>",
    "winner_cell": <solo winner cell number>,
    "winner_composite": <solo winner composite>,
    "winner_type": "solo",
    "top_combo": {
      "cell": <N>,
      "label": "<label>",
      "composite": <avg>,
      "beats_solo": <bool>,
      "relation": "natural_extension | alternative_angle | below_solo",
      "thesis": "<combo's thesis>"
    },
    "top_alt": {
      "cell": <N>,
      "label": "<label>",
      "composite": <avg>,
      "beats_solo": <bool>,
      "relation": "framing_challenge | below_solo",
      "thesis": "<alt's thesis>"
    },
    "verdict_type": "go | conditional | no_clear_winner | narrow_win",
    "conditions": ["<what must be true for the solo winner to succeed>"],
    "reasoning": "<why the solo winner emerged — cite scores within solo pool>",
    "dealbreakers_solo": [{ "cell": <N>, "reason": "<why>" }],
    "top_insights": ["<most impactful surprises across all 9 cells, max 5>"],
    "risks": ["<key risks from matrix (any cell type)>"],
    "required_mitigations": ["<blocking risks/conflicts applying to the solo winner>"],
    "recommended_improvements": ["<non-blocking insights worth carrying forward>"]
  },
  "errors": <count of malformed agent outputs>,
  "schema_conformance_rate": <(9 - schema_violations) / 9>,
  "confidence_margin": <solo winner composite - solo runner-up composite>,
  "post_matrix_falsification": {
    "verdict": "<strong | framing_dependent | falsified>",
    "probe_a_mechanism": "<Cell 8 neutral mechanism>",
    "probe_b_mechanism": "<Cell 9 neutral mechanism>",
    "original_winner_mechanism": "<winner's mechanism_novelty>"
  },
  "devil_advocate": {
    "challenge": "<failure mode of the solo winner>",
    "evidence": "<specific detail>",
    "mitigation": "<first step>"
  }
}
```

**Schema note:** the `winner` field is always the solo winner. Consumers (adversarial-review, brief handoff, etc.) should read `winner` and `winner_composite` for the authoritative recommendation, and `top_combo`/`top_alt` for design insight only. The legacy single `ranking` array was removed — downstream code should migrate to the three separated `rankings`.

---

# 6f. Self-Assessment

```
## Self-Assessment
- Model used: haiku (9 cells) + haiku (devil's advocate)
- Codebase complexity: [1=trivial config, 3=moderate, 5=complex multi-subsystem]
- Could synthesis (step 6) have used a cheaper model? [yes/no + one sentence]
- Error rate: {N}/9 cells had malformed or sparse output
{IF COMPLEXITY_FLAG == true: "- High-complexity problem — Sonnet synthesis recommended for deeper cross-cutting analysis (BRIEF > 500 chars AND option count > 3)"}
```

Populate honestly — this data feeds model-selection calibration.

`COMPLEXITY_FLAG` is set in step 5.5 Path B. If it was not set (simple problem or ≤ 3 options), omit the complexity line.

---

# 7. Visual Digest (optional)

After the convergence report, offer a visual digest:

```
Visual digest? [Y/n]
```

If yes (or Enter), build the DATA object and open a self-contained HTML dashboard:

**DATA object** — assembled from results already in memory:

```javascript
const DATA = {
  problem:           "<PROBLEM>",
  verdict_type:      "<clear|moderate|narrow_win|no_clear_winner>",
  confidence_margin: <solo_winner_composite - solo_runner_up_composite>,
  winner: { cell: <N>, label: "<label>", avg: <score>, type: "solo" },  // always solo
  runner_up: { cell: <N>, label: "<label>", avg: <score>, type: "solo" },  // only for narrow_win, always solo
  top_combo: { cell: <N>, label: "<label>", avg: <score>, beats_solo: <bool> },
  top_alt:   { cell: <N>, label: "<label>", avg: <score>, beats_solo: <bool> },

  cells: [
    {
      cell:        <1-9>,
      type:        "solo|combo|alt",            // NEW — used by the digest to group cells visually
      label:       "<plain-language label>",    // the intention-first label from TodoWrite
      avg:         <composite avg>,
      scores: {
        feasibility:         <1-5>,
        risk:                <1-5>,
        synergy_potential:   <1-5>,
        implementation_cost: <1-5>
      },
      dealbreaker: <true|false>,
      thesis:      "<one-sentence thesis from agent>",
      verdict:     "<agent's one-sentence verdict>",
      recommendation: "<first implementation step if this wins>"
    },
    ...  // all 9 cells
  ],

  devil_advocate: {
    failure_mode: "<one-sentence failure mode>",
    scenario:     "<2-3 sentence scenario>",
    probability:  "<low|medium|high>",
    mitigations:  ["<mitigation 1>", "<mitigation 2>"],
    verdict:      "<still_recommend|reconsider|reject>"
  },

  top_insights: ["<insight 1>", "<insight 2>", "<insight 3>"]  // from 6d top insights
};
```

**Generate and open:**

1. Read `skills/idea-matrix/digest-template.html` (path relative to the plugin root, or use absolute path).
2. Replace `__DATA_PLACEHOLDER__` with `JSON.stringify(DATA)`.
3. Write result to a temp file: `/tmp/idea-matrix-<timestamp>.html`.
4. Run: `open /tmp/idea-matrix-<timestamp>.html`

Skip this step entirely if the user declines or if `--brief` mode is active (brief mode is for pipeline handoff, not interactive review).

## Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  {id: "cell-1", status: "completed"},
  {id: "cell-2", status: "completed"},
  {id: "cell-3", status: "completed"},
  {id: "cell-4", status: "completed"},
  {id: "cell-5", status: "completed"},
  {id: "cell-6", status: "completed"},
  {id: "cell-7", status: "completed"},
  {id: "cell-8", status: "completed"},
  {id: "cell-9", status: "completed"},
  {id: "devil", status: "completed"}
])
```

---

# 8. Write Telemetry

Persistence is the audit trail — without it there is no post-mortem, no cross-matrix pattern analysis, no null-model calibration. Telemetry writes are non-fatal (a single failed file skips to the next), but the full absence of the `~/.autoimprove/matrix-runs/<RUN_ID>/` directory is a process failure.

**Inline dispatchers (running the matrix via ad-hoc Agent calls instead of this skill) MUST also write here.** Empirical evidence (2026-04-15): agent:magi ran 4 matrices inline with zero persistence; post-hoc reconstruction required dumping from session scroll and was lossy. Every inline dispatcher should close with the same telemetry block below.

**Generate RUN_ID:** `YYYYMMDD-HHMMSS-<problem-slug>` where the problem slug is the `PROBLEM` string lowercased, non-alphanumeric characters replaced with `-`, truncated to 40 characters, and trailing `-` stripped.

```bash
mkdir -p ~/.autoimprove/matrix-runs/<RUN_ID>
```

Store: `MATRIX_RUN_DIR=~/.autoimprove/matrix-runs/<RUN_ID>`.

**Write `$MATRIX_RUN_DIR/meta.json`:**
```json
{
  "run_id": "<RUN_ID>",
  "problem": "<PROBLEM>",
  "options": [<OPTIONS array>],
  "date": "<ISO 8601 datetime>",
  "model": "haiku",
  "brief_mode": <true|false>,
  "cell_count": 9,
  "errors": <errors field from structured JSON>
}
```

**Write `$MATRIX_RUN_DIR/cells.json`:**
Full `RESULTS` array — all 9 cell outputs as collected in step 5 (including any `error` fields for malformed/sparse cells).

**Write `$MATRIX_RUN_DIR/convergence.json`:**
The `convergence` object from the structured JSON output (step 6e), plus `devil_advocate` and `confidence_margin`:
```json
{
  "winner": "<cell label>",
  "winner_cell": <N>,
  "winner_composite": <score>,
  "verdict_type": "<go|conditional|no_clear_winner|narrow_win>",
  "confidence_margin": <value>,
  "devil_advocate": { <devil_advocate object or null> },
  "post_matrix_falsification": { <falsification object or null> },
  "schema_conformance_rate": <rate>,
  "conditions": [...],
  "reasoning": "...",
  "top_insights": [...],
  "risks": [...],
  "required_mitigations": [...],
  "recommended_improvements": [...]
}
```

**Write `$MATRIX_RUN_DIR/report.md`:**
```markdown
# Idea Matrix Run — <RUN_ID>

**Problem:** <PROBLEM>
**Date:** <ISO date>
**Winner:** <winner label> (score: <winner_composite>/5)
**Verdict type:** <verdict_type>
**Confidence margin:** <confidence_margin>

## Score Table

| Cell | Label | Feas. | Risk | Synergy | Cost | Avg | Dealbreaker |
|------|-------|-------|------|---------|------|-----|-------------|
| 1A | Approach Name | 4/5 | 3/5 | 4/5 | 2/5 | 3.25 | none |
<one row per remaining cell from RESULTS>

## Devil's Advocate

<devil_advocate.challenge or "Not run (narrow win or no clear winner)">

## Top Insights

<numbered list of top_insights>
```

After all writes complete (or are skipped on error), print:

`Run saved: ~/.autoimprove/matrix-runs/<RUN_ID>/`

---

# 9. Notes

- **9 agents is the fixed grid.** The 3x3 structure (3 solo + 3 pairs + 1 trio + 2 wild) is the core design.
- **Haiku only, no tools.** Agents reason about pre-digested context. The orchestrator does the codebase research.
- **Scores enable objective comparison.** Numerical rubric eliminates ambiguity in prose-based assessments.
- **Solo cells determine the winner.** Combo and alt cells provide design insight only — see §6c for the null-model rationale. Do NOT collapse the three rankings back into a single composite ranking.
- **The convergence report is the deliverable.** Lead with the synthesis and recommendation, not the raw scores.
- **Works standalone or during brainstorming.** Can be invoked via `/idea-matrix` at any point — enriches design discussions or produces standalone analysis.
- **Visual digest is skipped in --brief mode.** Brief mode is a pipeline handoff — no interactive UI needed.
