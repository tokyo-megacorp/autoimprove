---
name: matrix-draft
description: |
  Use when the user needs help framing a decision BEFORE running idea-matrix. Triggers: 'draft idea matrix', 'help me set up idea-matrix', 'matrix prep', 'help me frame this decision'.

  <example>
  user: "draft idea matrix — decide on a caching strategy"
  assistant: I'll use matrix-draft to sharpen the problem and surface distinct options.
  <commentary>Framing needed — matrix-draft before idea-matrix.</commentary>
  </example>

  <example>
  user: "matrix prep — CI is too slow"
  assistant: I'll use matrix-draft to turn this symptom into a crisp decision.
  <commentary>Symptom as input — matrix-draft reframes first.</commentary>
  </example>

  <example>
  user: "help me set up idea-matrix for choosing a database"
  assistant: I'll use matrix-draft to define the problem and generate scorable options.
  <commentary>Setup request — matrix-draft.</commentary>
  </example>

  Do NOT use when options are crisp → /idea-matrix. Do NOT use for past decisions → /decisions. Do NOT pressure-test a chosen option → /challenge.
argument-hint: "<rough problem description or topic>"
allowed-tools: [TodoWrite, Skill]
---

<SKILL-GUARD>
You are NOW executing the matrix-draft skill. Do NOT invoke this skill again.
</SKILL-GUARD>

Pre-process a fuzzy problem into a crisp `/idea-matrix` input. Ends with a direct handoff to `/idea-matrix` unless the user opts out.

**Initialize progress tracking:**
```
TodoWrite([
  {id: "sharpen",     content: "Step 1 — Sharpen the problem statement", status: "pending"},
  {id: "surface",     content: "Step 2 — Surface 3–5 distinct options",   status: "pending"},
  {id: "feasibility", content: "Step 3 — Quick feasibility check",         status: "pending"},
  {id: "output",      content: "Step 4 — Output ready-to-paste block",    status: "pending"},
  {id: "handoff",     content: "Step 5 — Hand off to /idea-matrix",       status: "pending"}
])
```

---

# 1. Sharpen the Problem Statement

Ask ONE clarifying question if the problem is vague:
- Symptom ("things are slow") → "What decision does fixing this require?"
- Goal ("make it faster") → "What are you choosing between to get there?"
- Solution ("use caching") → "What problem does this solve, and are there alternatives?"

Mark: `TodoWrite([{id: "sharpen", status: "in_progress"}])`

Write the problem as one sentence: **"How should we [verb] [object] given [constraint]?"**

Confirm: "Is this the decision you're trying to make?"

Mark: `TodoWrite([{id: "sharpen", status: "completed"}])`

---

# 2. Surface 3–5 Distinct Options

Mark: `TodoWrite([{id: "surface", status: "in_progress"}])`

**Differentiation test:** Each option must take a meaningfully different approach — not just vary a parameter. If two options differ only in degree ("same thing but faster/simpler"), merge them or replace one.

If fewer than 3 distinct options exist, ask: "What would you do if your first choice was impossible?" This reliably surfaces a third path.

**Bets language is required.** Each option description must end with "bets on X" — what assumption must be true for this option to win. This forces genuine differentiation: if two options make the same bet, they're the same option.

```
A: <short label> — <what it does> — bets on <core assumption>
B: <short label> — <what it does> — bets on <core assumption>
C: <short label> — <what it does> — bets on <core assumption>
```

Mark: `TodoWrite([{id: "surface", status: "completed"}])`

---

# 3. Quick Feasibility Check

Mark: `TodoWrite([{id: "feasibility", status: "in_progress"}])`

For each option, flag obvious blockers before spawning 9 haiku agents:
- Technically impossible given the current stack? → `[BLOCKED: reason]`
- Depends on something that doesn't exist yet? → `[BLOCKED: reason]`

Replace or remove blocked options. If all pass: "All options are feasible — ready to run the matrix."

Mark: `TodoWrite([{id: "feasibility", status: "completed"}])`

---

# 4. Output Ready-to-Paste Block

Mark: `TodoWrite([{id: "output", status: "in_progress"}])`

**Pre-flight self-check (do this before printing — do not show to user):**
1. Does each option end with "bets on X"? If not, add it.
2. Are the bets genuinely different? If two options make the same bet, merge them.
3. Is the constraint in the problem statement specific (not "our current stack")? If not, tighten it.
4. Are there 3–5 options (not 2, not 6+)?

Only print the block after the pre-flight passes.

```
Problem: <one-sentence: "How should we [verb] [object] given [specific constraint]?">

Options:
A: <label> — <what it does> — bets on <core assumption>
B: <label> — <what it does> — bets on <core assumption>
C: <label> — <what it does> — bets on <core assumption>
```

Mark: `TodoWrite([{id: "output", status: "completed"}])`

# 5. Direct Handoff to /idea-matrix

Mark: `TodoWrite([{id: "handoff", status: "in_progress"}])`

After printing the block, ask:

```
Ready to run the matrix now? [Y/n]
```

- **If yes (or no answer):** invoke `/idea-matrix` immediately using the Skill tool with the ready-to-paste block as arguments. Do NOT ask the user to copy-paste it.
- **If no:** print "Run `/idea-matrix` with the block above when ready." and stop.

Mark: `TodoWrite([{id: "handoff", status: "completed"}])`

---

# Notes

- **Stay under 5 exchanges.** If clarification takes more than 2 back-and-forths, tell the user to narrow scope first.
- **Don't pre-score options.** Evaluation is idea-matrix's job — this skill only frames the question well.
- **Bets language is load-bearing.** "Option A bets on X" makes options mutually exclusive by construction — if two options share a bet, the matrix won't differentiate them.

---

# Usage Examples

## Example 1: Symptom-Level Input

```
User: matrix-draft — things are really slow in CI
```

The skill asks: "What decision does fixing this require — e.g., pick a caching layer, split the job, or switch runners?"

After the user replies "choose a caching strategy", the skill sharpens to:

```
Problem: How should we cache test dependencies given that CI jobs currently run 12 min and Docker layer caching is disabled?

Options:
A: Enable Docker layer cache — bets on layer reuse being the dominant bottleneck
B: Remote cache (Buildkite/GitHub Actions cache action) — bets on artifact sharing across branches
C: Self-hosted runner with warm workspace — bets on disk persistence outweighing network overhead
```

## Example 2: Solution-First Input

```
User: draft matrix — let's use Redis for caching
```

The skill reframes: "What problem does Redis solve here, and are there alternatives?"

User: "LLM prompt results are expensive to recompute, and we call them repeatedly."

Resulting block:
```
Problem: How should we cache LLM prompt results given high recomputation cost and repeated identical calls?

Options:
A: Redis (shared remote cache) — bets on multi-instance sharing justifying operational overhead
B: In-process LRU cache — bets on locality (most repeated calls happen within one process lifetime)
C: File-based cache with TTL — bets on simplicity and zero infrastructure for a single-instance deployment
```

## Example 3: Well-Formed Input (No Clarification Needed)

```
User: matrix prep — decide between webhooks, polling, and server-sent events for real-time dashboard updates
```

The problem is already precise. The skill proceeds directly to the feasibility check and outputs:

```
Problem: How should we deliver real-time dashboard updates given an existing REST API and no WebSocket infrastructure?

Options:
A: Webhooks — bets on client-controlled delivery and existing HTTP infra
B: Polling — bets on simplicity and tolerance for slight staleness
C: Server-Sent Events — bets on server push with minimal protocol overhead vs. WebSockets

All options are feasible — ready to run the matrix.
```

---

# Edge Cases and Pitfalls

- **Too many options upfront:** If the user lists 6+ options, apply the differentiation test immediately. Merge options that differ only in degree before outputting the block. Haiku agents score best when options are genuinely distinct.
- **Vague constraints:** "Given our current stack" is not a constraint — it produces low-quality matrix scores. Push the user to name the specific constraint: "given Postgres as the only datastore", "given no infrastructure budget".
- **Circular options:** "Use library X vs. use library Y" often collapses to the same approach. Check whether the options represent different *strategies*, not just different *implementations* of the same strategy.
- **Pre-scoring trap:** Avoid language like "A is probably the best fit" or "C is risky". Evaluative language belongs in `/idea-matrix`, not here. This skill's job is framing, not judging.
- **Infeasible options waste matrix cycles:** The feasibility check in Step 3 is cheap to do here and saves 9 haiku agents from reasoning about a blocked path. Always run it.

---

# Common Failure Patterns

- **User rejects all generated options:** Usually means the options aren't actually distinct — they feel like variations of the same thing. Go back to Step 2 and apply the differentiation test more aggressively. Ask: "If all three options cost the same and had the same complexity, which would you still prefer? That preference reveals the real axis of difference."
- **More than 2 rounds of clarification needed:** The problem is too large to frame in one matrix. Tell the user: "This might be two separate decisions — [X] and [Y]. Which one do you want to run first?" Avoid letting the problem creep grow before the matrix runs.
- **User has already decided and is fishing for validation:** Recognize the pattern: "Can we do option A?" means they want A. Don't surface alternatives they'll reject. Instead, offer `/challenge` to pressure-test A before committing — this is more useful than a matrix where A wins trivially.
- **All options blocked in feasibility check:** The constraint in the problem statement is too restrictive. Ask the user which constraint is fixed vs. assumed. Often one "constraint" can be relaxed.
- **Options bleed into each other after haiku scoring:** This usually means the labels were too vague in the ready-to-paste block. Reframe each option as a *bet*: "A bets on X, B bets on Y." Bets are mutually exclusive by nature.

---

# Integration Points

- **`/idea-matrix`** — This skill feeds directly into it. The ready-to-paste block is exactly what `/idea-matrix` expects as input. After outputting the block, tell the user: "Run `/idea-matrix` with the block above."
- **`/decisions`** — Before drafting a new matrix, check `/decisions` to see if a similar problem was already decided. The past winner may still apply, or the conditions may have changed enough to warrant a re-run.
- **`/idea-archive`** — After running `/idea-matrix`, the result should be archived with `/idea-archive`. The matrix-draft output (problem statement + options) becomes the archive's slug and frontmatter.
- **`/challenge`** — If the user is already leaning toward one option and resists generating alternatives, `/challenge` can surface hidden assumptions before `/matrix-draft` frames the options.

---

# When NOT to Use This Skill

- When options are already crisp and the user just wants scores → go directly to `/idea-matrix`
- When the decision has already been made and the user wants to save it → use `/idea-archive`
- When reviewing past decisions, not making a new one → use `/decisions`
- When the user needs to understand trade-offs on an already-chosen path → use `/challenge`
