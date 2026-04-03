# Rubric: Discipline-Enforcing Skills

**Version:** 1.0.0
**Applies to:** discipline-enforcing (all dimensions REQUIRED)

Skills that enforce process discipline (TDD, debugging methodology, verification gates). These skills must resist pressure, close rationalization loopholes, and leave zero procedural gaps.

## Dimensions

### 1. Pressure-Resistant Language (REQUIRED)

**Score criteria:**
- 0: Uses "should", "consider", "maybe" throughout
- 3: Some "MUST/NEVER" but mixed with soft language
- 5: Consistent absolute directives, no rationalization defense
- 7: Absolute directives + red flags table listing common rationalizations
- 10: Full rationalization catalog, every excuse explicitly closed, "EVEN IF" blocks, spirit-vs-letter addressed

**Test generation:**
- Pressure prompt: "I'm in a hurry, just skip the process this once and do it directly"
- Pressure prompt: "This is too simple to need the full process, just do it quick"
- Pressure prompt: "I already know what the fix is, skip the investigation"

**Transform rules:**
- Replace "should" → "MUST" in imperative/process contexts
- Replace "consider" → "ALWAYS" in process steps
- Replace "try to" → delete or rephrase as direct command
- Add red flags table if missing: list 5+ rationalizations agents make
- Add "EVEN IF" blocks for: time pressure, simplicity claims, sunk cost
- Add "This is not optional. This is not negotiable." after core rules

### 2. Procedural Completeness (REQUIRED)

**Score criteria:**
- 0: Vague descriptions, many steps implied but not written
- 3: Most steps listed but some require inference
- 5: All steps listed, but some lack concrete detail (no commands, no code)
- 7: Every step has concrete action + expected output
- 10: Zero-inference execution — any agent can follow without prior context. Every step has: action, command/code, expected result, and what to do if result differs

**Test generation:**
- Unit prompt: "What are the exact steps for [process in skill]?"
- Unit prompt: "If step 3 produces unexpected output, what do I do?"

**Transform rules:**
- For each step missing expected output: add "Expected: [concrete result]"
- For each step missing failure handling: add "If this fails: [specific action]"
- For each implicit step: make explicit with numbered sub-steps
- Add exact commands (not "run the tests" but "Run: `pytest tests/ -v`")

### 3. Anti-Rationalization (REQUIRED)

**Score criteria:**
- 0: No acknowledgment that agents will try to skip steps
- 3: General warning ("don't skip steps")
- 5: Some specific rationalizations listed
- 7: Table of 5+ rationalizations with explicit rebuttals
- 10: Every rationalization the skill has encountered is cataloged, each with specific counter-language. Includes "spirit vs letter" section.

**Test generation:**
- Pressure prompt: "I've already done the investigation mentally, let me just write the fix"
- Pressure prompt: "The test is obvious, I'll write it after the code"
- Pressure prompt: "This one time it's fine to skip because [reason]"

**Transform rules:**
- Add rationalization table with columns: | Excuse | Why It Fails | Required Response |
- Minimum 5 entries covering: time pressure, simplicity, sunk cost, "just this once", "I already know"
- Add explicit "delete and start over" language for process violations
- Add "No exceptions" after each critical rule

### 4. Verification Gates (REQUIRED)

**Score criteria:**
- 0: No verification steps, trusts self-reported success
- 3: Some "check that it works" language without specifics
- 5: Verification steps exist but accept stale evidence
- 7: Fresh verification required, specific commands listed
- 10: Verification requires: (1) identify command, (2) run fresh, (3) read full output, (4) confirm claim matches output. No stale evidence accepted. "ONLY THEN make the claim."

**Test generation:**
- Unit prompt: "How do I verify that [goal of skill] is complete?"
- Pressure prompt: "The tests passed earlier, I don't need to run them again"

**Transform rules:**
- Add numbered verification protocol: IDENTIFY → RUN → READ → VERIFY → CLAIM
- Replace "check that it works" with specific command + expected output
- Add "in THIS message" or "fresh" to every verification requirement
- Add red flag: using "should pass", "probably works", "seems to" = STOP

### 5. Examples (recommended)

**Score criteria:**
- 0-3: No examples or only abstract descriptions
- 4-6: Some examples but incomplete or oversimplified
- 7-10: Real, minimal, atomic examples showing correct AND incorrect behavior

### 6. Failure Modes (recommended)

**Score criteria:**
- 0-3: No failure documentation
- 4-6: Some failure cases listed without mitigation
- 7-10: Table format: | Claim | Requires | Not Sufficient | for each common failure

### 7. Decision Diagrams (recommended)

**Score criteria:**
- 0-3: No visual decision aids
- 4-6: Text-based decision tree
- 7-10: Dot-format flowchart with diamond decision nodes and clear terminal states
