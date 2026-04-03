---
name: polish
description: Review and improve a skill or plugin component to superpowers quality. Use after creating or modifying a skill, agent, hook, or plugin component. Orchestrates diagnose, review, and optional transformation.
---

# Polish

Entry point for skill quality review. Orchestrates diagnose, review, and optional transformation.

## Process

### Step 1: Identify Target

Ask the user which skill/component to review, or detect from recent context:
- If user specifies a path: use it
- If hook just suggested review: use the path from hook context
- If unclear: ask "Which skill would you like to polish?"

### Step 2: Diagnose (inline)

Read the target file. Classify it using the diagnose skill's classification process:

1. Read the file content
2. Identify type: discipline-enforcing, reference, technique, pattern
3. Select REQUIRED rubrics for that type from `skills/rubrics/SKILL.md` routing table
4. Quick-score each dimension (0-10) from a single read-through

Present to user:
```
Xavier School Diagnosis:
  Type: [type] (confidence: [high/medium/low])
  Quick scores: [dimension]: [score]/10, ...
  REQUIRED rubrics below 7: [list]
```

If all scores >= 7: "This skill looks solid. Want a deep review anyway?"

### Step 3: Review (Level 2)

Dispatch the `autoimprove:reviewer` agent with:
- `skill_path`: target file path
- `skill_type`: from diagnose
- `rubric_paths`: paths to REQUIRED rubric files for this type

Present reviewer output to user:
```
Xavier School Review:
  [rubric]: [score]/10 — [one-line evidence]
  ...

  Gaps requiring attention:
  - [rubric] (score [N]): [suggestion]
  ...

  Overall: [assessment]
```

Ask: "Want to fix these manually, or should Xavier School transform the skill? (transform / manual / done)"

### Step 4: Transform (Level 3, optional)

If user requests transform:

1. Dispatch `autoimprove:transformer` agent with reviewer output + rubric paths
2. Transformer writes rewritten skill + tests to temp path
3. Run generated tests: `bash /tmp/xavier-transform-.../tests/test-*.sh`
4. If tests fail: transformer revises (max 2 rounds). If still failing after 2 rounds: show partial results, suggest manual fixes, stop.
5. If tests pass: dispatch reviewer again on the REWRITTEN skill (re-score)
6. If any REQUIRED rubric < 7 after re-score: warn user "Score below threshold on [rubrics]. Accept anyway?"
7. Show diff between original and rewritten skill
8. User approves → apply diff to original. User rejects → discard temp files.

### Error Handling

| Situation | Action |
|---|---|
| Diagnose can't classify | Default to "technique", note low confidence |
| Reviewer agent fails | Show error, suggest manual review using rubrics directly |
| Transformer fails | Show error, skill unchanged, suggest manual fixes from reviewer output |
| Tests fail after 2 rounds | Show partial results + reviewer feedback, skill unchanged |
| Token budget concern | Warn user before dispatching transformer (~8-15K tokens) |
