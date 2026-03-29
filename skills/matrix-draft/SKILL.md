---
name: matrix-draft
description: "Use when the user says 'draft idea matrix', 'help me set up idea-matrix', 'prepare for idea-matrix', 'matrix prep', or wants help formulating a crisp problem statement and well-differentiated options before running idea-matrix. Asks clarifying questions, sharpens the problem statement to one sentence, surfaces 3-5 truly distinct options, and outputs a ready-to-paste block for /idea-matrix."
argument-hint: "<rough problem description or topic>"
allowed-tools: []
---

<SKILL-GUARD>
You are NOW executing the matrix-draft skill. Do NOT invoke this skill again.
</SKILL-GUARD>

Pre-process a fuzzy problem into a crisp `/idea-matrix` input. No tools — all reasoning from conversation context.

---

# 1. Sharpen the Problem Statement

Ask ONE clarifying question if the problem is vague:
- Symptom ("things are slow") → "What decision does fixing this require?"
- Goal ("make it faster") → "What are you choosing between to get there?"
- Solution ("use caching") → "What problem does this solve, and are there alternatives?"

Write the problem as one sentence: **"How should we [verb] [object] given [constraint]?"**

Confirm: "Is this the decision you're trying to make?"

---

# 2. Surface 3–5 Distinct Options

**Differentiation test:** Each option must take a meaningfully different approach — not just vary a parameter. If two options differ only in degree ("same thing but faster/simpler"), merge them or replace one.

If fewer than 3 distinct options exist, ask: "What would you do if your first choice was impossible?" This reliably surfaces a third path.

```
A: <short label> — <what it does and what it bets on>
B: <short label> — <what it does and what it bets on>
C: <short label> — <what it does and what it bets on>
```

---

# 3. Quick Feasibility Check

For each option, flag obvious blockers before spawning 9 haiku agents:
- Technically impossible given the current stack? → `[BLOCKED: reason]`
- Depends on something that doesn't exist yet? → `[BLOCKED: reason]`

Replace or remove blocked options. If all pass: "All options are feasible — ready to run the matrix."

---

# 4. Output Ready-to-Paste Block

```
Problem: <one-sentence problem statement>

Options:
A: <label> — <description>
B: <label> — <description>
C: <label> — <description>
```

Then: "Run `/idea-matrix` with the block above, or adjust any option before proceeding."

---

# Notes

- **Stay under 5 exchanges.** If clarification takes more than 2 back-and-forths, tell the user to narrow scope first.
- **Don't pre-score options.** Evaluation is idea-matrix's job — this skill only frames the question well.

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
