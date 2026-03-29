---
name: autoimprove-idea-matrix
description: Run a 3x3 haiku idea exploration matrix on design options. Spawns 9 parallel agents to evaluate options, combinations, and alternatives, then synthesizes a convergence report.
argument-hint: "[problem statement + options, or invoke during brainstorming]"
---

Invoke the `idea-matrix` skill now. Do not do any work before the skill loads.

Arguments: $ARGUMENTS

---

## Arguments

| Argument | Description |
|----------|-------------|
| `problem statement` | Description of the design decision to explore. |
| `options` | Two to five labeled options to evaluate (e.g., `A: Redis, B: in-memory LRU, C: file cache`). Minimum 3 options required. |

Options can be provided inline or gathered from the current conversation context. If fewer than 3 options are available, the skill asks for more before proceeding.

## Usage Examples

```
# Inline options
/idea-matrix A: Redis, B: in-memory LRU, C: file cache

# Invoke mid-brainstorm (skill pulls options from conversation context)
/idea-matrix

# Natural language trigger
Run idea matrix on: JWT vs session cookies vs OAuth
```

## What It Does

1. Parses the problem and options from inline arguments or conversation context.
2. Researches the codebase (architecture, patterns, constraints) and produces a dense brief — haiku agents never touch the codebase directly.
3. Generates a 3x3 matrix of 9 cells: 3 solo options, 3 pairwise hybrids, 1 all-three combination, and 2 creative alternatives (best-of-breed remix + contrarian approach).
4. Dispatches all 9 haiku agents in parallel, each scoring their cell on feasibility, risk, synergy potential, and implementation cost.
5. Synthesizes a convergence report: ranked score matrix, per-dimension aggregates, winner recommendation, required mitigations, and top insights.

## Output

The convergence report contains:

- Full 3x3 score table (one row per cell, four scores + composite average)
- Dimension aggregates (average, min, max across all 9 cells)
- Ranked cell list with dealbreaker flags
- Recommended design with first implementation step and blocking mitigations
- Structured JSON at the end for programmatic use

## When to Use

- At any design decision point where 3+ options exist.
- During brainstorming sessions before committing to an architecture direction.
- When evaluating hybrid or combination approaches, not just solo options.
- When you want non-obvious insights surfaced before starting implementation.

## Notes

- Requires at least 3 options. The 3x3 structure (3 solo + 3 pairs + 1 trio + 2 creative) is fixed.
- Haiku agents have no tools — all codebase research is done by the orchestrator upfront.
- If 7 or more cells land in the neutral score band, the skill reports "no clear winner" and asks for better-differentiated options rather than fabricating a winner.

## Related Commands

- `/autoimprove run` — start the experiment loop after a design decision is made
- `/adversarial-review` — deeper review of a specific design after the matrix narrows options
