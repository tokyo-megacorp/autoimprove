# Rubric: Technique Skills

**Version:** 1.0.0
**Applies to:** technique (concrete multi-step processes like git worktrees, code review)

Skills that teach a specific technique — a repeatable process with concrete steps.

## Dimensions

### 1. Procedural Completeness (REQUIRED)

**Score criteria:**
- 0: Process described vaguely, many steps implied
- 3: Steps listed but gaps between them
- 5: Complete steps but some lack detail
- 7: Every step: action + command/code + expected result
- 10: Zero-inference: action, exact command, expected output, failure handling for each step

**Test generation:**
- Unit prompt: "Walk me through [technique] step by step"
- Unit prompt: "What do I do if step N produces [unexpected result]?"

**Transform rules:**
- Number all steps sequentially
- Each step gets: action verb, exact command, expected output
- Add "If this fails:" after steps that commonly fail
- Remove any "obvious" steps that skip detail

### 2. Examples (REQUIRED)

**Score criteria:**
- 0-3: No examples
- 4-6: One example, happy path only
- 7-10: Multiple examples: happy path, edge case, failure recovery

**Transform rules:**
- Add at least 2 worked examples (complete start-to-finish)
- One example must show error recovery
- Examples must use realistic values, not placeholders

### 3. Verification Gates (recommended)

**Score criteria:**
- 0-3: No checkpoints to verify progress
- 4-6: Some "make sure" language
- 7-10: Concrete verification command after each major step

### 4. Decision Diagrams (REQUIRED)

**Score criteria:**
- 0: No visual decision aids
- 3: Text-based decision list ("if X, do Y")
- 5: Partial flowchart or decision table
- 7: Complete dot-format flowchart with diamond decision nodes
- 10: Flowchart covering: happy path, all decision points, failure paths, terminal states

**Test generation:**
- Unit prompt: "When should I use [technique A] vs [technique B]?"
- Unit prompt: "What's the decision process for [ambiguous scenario]?"

**Transform rules:**
- Add dot-format flowchart for the main decision/process flow
- Include diamond nodes for every decision point
- Include terminal states (success, failure, abort)
- Add text fallback for environments that don't render dot
