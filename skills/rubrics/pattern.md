# Rubric: Pattern Skills

**Version:** 1.0.0
**Applies to:** pattern (ways of thinking, design patterns, architectural approaches)

Skills that teach patterns — reusable approaches to recurring problems. Less prescriptive than techniques, more about recognition and judgment.

## Dimensions

### 1. Procedural Completeness (REQUIRED)

**Score criteria:**
- 0: Pattern described abstractly with no structure
- 3: Pattern has some structure but unclear when to apply
- 5: Clear structure with application guidance
- 7: Pattern + when to use + when NOT to use + trade-offs
- 10: Full pattern documentation: name, context, problem, solution, consequences, related patterns

**Test generation:**
- Unit prompt: "When should I use [pattern]?"
- Unit prompt: "What are the trade-offs of [pattern]?"

**Transform rules:**
- Add "When to use" section with concrete trigger conditions
- Add "When NOT to use" section with counter-indicators
- Add "Trade-offs" section with honest pros/cons
- Structure as: Context → Problem → Solution → Consequences

### 2. Examples (REQUIRED)

**Score criteria:**
- 0-3: No examples or purely theoretical
- 4-6: One example, possibly abstract
- 7-10: Real-world before/after examples showing pattern application + counter-example

**Transform rules:**
- Add before/after code showing pattern application
- Add one counter-example (when the pattern was wrongly applied)
- Examples must be from real-world domains, not textbook abstractions

### 3. Failure Modes (recommended)

**Score criteria:**
- 0-3: No discussion of misapplication
- 4-6: Brief mention of common mistakes
- 7-10: Detailed anti-patterns with "looks like the pattern but isn't" examples

**Transform rules:**
- Add "Common Misapplications" section
- Each misapplication: what it looks like, why it's wrong, how to fix
