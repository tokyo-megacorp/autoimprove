# Agents Reference

autoimprove has 6 agents. None are user-invoked directly — they are all spawned by skills.

---

## experimenter

**Model:** sonnet | **Tools:** Read, Write, Edit, Glob, Grep, Bash | **Dispatched by:** [run](skills.md#run) skill

The experimenter runs inside an isolated git worktree to make code improvements. It is deliberately blind to benchmarks and scoring — it receives a theme, scope constraints, and recent experiment summaries, but never metric names, scoring logic, or current scores. This separation prevents Goodhart's Law gaming.

**What it receives:**
- Theme (e.g., `failing_tests`, `todo_comments`, `coverage_gaps`, `lint_warnings`)
- Scope constraints (max files, max lines, forbidden paths)
- Recent experiment summaries (what was tried, not how it scored)

**What it does:**
1. Explores the codebase within its scope
2. Identifies a specific improvement matching its theme
3. Implements the change (staying within constraints)
4. Verifies by running the test suite
5. Commits with a descriptive message: `<theme>: <what and why>`

**Rules:**
- Test modifications are additive only — can add tests, never delete or weaken assertions
- If no meaningful improvement is found within constraints, commits nothing
- Must not try to discover or reverse-engineer how changes are scored

---

## enthusiast

**Model:** sonnet | **Tools:** Read, Glob, Grep | **Dispatched by:** [adversarial-review](skills.md#adversarial-review), [challenge](skills.md#challenge)

The Enthusiast aggressively finds bugs and issues in code. High recall, low precision expected — it flags everything suspicious and lets the Judge sort out precision. Scored per-finding by severity (critical: +10, high: +5, medium: +2, low: +1).

**Output schema:**
```json
{
  "findings": [
    {
      "id": "F1",
      "severity": "critical|high|medium|low",
      "file": "path/to/file.ext",
      "line": 42,
      "description": "Brief description",
      "evidence": "Specific code reference",
      "prior_finding_id": null
    }
  ]
}
```

**What it looks for:** Logic errors, null/undefined issues, error handling gaps, resource leaks, race conditions, security vulnerabilities, type errors, dead code, performance issues.

**In round > 1:** Receives prior round findings and focuses on what was missed.

---

## adversary

**Model:** sonnet | **Tools:** Read, Glob, Grep | **Dispatched by:** [adversarial-review](skills.md#adversarial-review), [challenge](skills.md#challenge)

The Adversary challenges the Enthusiast's findings and debunks false positives. Asymmetric scoring creates a strong incentive against reckless debunks: correct debunk = +3 pts, wrong debunk = -9 pts (3x penalty), correct validation = +1 pt.

**Output schema:**
```json
{
  "verdicts": [
    {
      "finding_id": "F1",
      "verdict": "valid|debunked|partial",
      "severity_adjustment": "critical|high|medium|low|null",
      "reasoning": "Evidence-based reasoning citing specific code"
    }
  ]
}
```

**Verdict meanings:**
- `valid` — finding is correct as stated
- `debunked` — finding is wrong (nonexistent issue, wrong file/line, misunderstood code)
- `partial` — finding is real but severity or scope is overstated/understated

**Rules:** Must render a verdict for every finding. Reasoning must reference specific code (line numbers, variable names). "I disagree" is not reasoning.

---

## judge

**Model:** sonnet | **Tools:** Read, Glob, Grep | **Dispatched by:** [adversarial-review](skills.md#adversarial-review), [challenge](skills.md#challenge)

The Judge arbitrates between the Enthusiast and the Adversary. Symmetric scoring (+5 for correct ruling, -5 for incorrect) means bias in any direction costs equally. The only winning strategy is to be right.

**Output schema:**
```json
{
  "rulings": [
    {
      "finding_id": "F1",
      "final_severity": "critical|high|medium|low|dismissed",
      "winner": "enthusiast|adversary|split",
      "resolution": "Actionable one-liner"
    }
  ],
  "summary": "N confirmed, M debunked.",
  "convergence": false
}
```

**Winner meanings:**
- `enthusiast` — finding is real and confirmed
- `adversary` — finding is bogus or fabricated
- `split` — partially valid (real issue but wrong severity or scope)

**Convergence:** Always `false` in round 1. In round 2+, set `true` only if all ruling tuples match the prior round. The orchestrator performs an independent deterministic check that overrides this flag.

---

## challenge-runner

**Model:** sonnet | **Tools:** Read, Glob, Grep, Bash, Agent | **Dispatched by:** [challenge](skills.md#challenge)

Runs the full debate pipeline (Enthusiast → Adversary → Judge) on a single code challenge and scores it with F1 against the answer key.

**What it does:**
1. Loads the challenge source file and answer key from `challenges/<id>/`
2. Spawns a single-pass debate: Enthusiast → Adversary → Judge
3. Assembles debate output and calls `scripts/score-challenge.sh`
4. Returns structured JSON with debate stats (finding counts, confirmed/debunked) and F1 score (precision, recall, TP, FP, FN, pass/fail)

**Output:** Pure JSON — no prose, no commentary.

---

## idea-explorer

**Model:** haiku | **Tools:** none | **Dispatched by:** [idea-matrix](skills.md#idea-matrix)

A lightweight reasoning probe for one cell of the 3x3 idea exploration matrix. Receives a fully self-contained prompt (~800 tokens) with pre-digested project context and scores one design option or combination on a structured rubric.

**Output schema:**
```json
{
  "cell": 1,
  "label": "A alone",
  "thesis": "One sentence position before scoring",
  "scores": {
    "feasibility": 4,
    "risk": 5,
    "synergy_potential": 3,
    "implementation_cost": 4
  },
  "dealbreaker": { "flag": false },
  "surprise": "One non-obvious insight citing specific detail from the brief",
  "recommendation": "If this option wins, the first implementation step is...",
  "verdict": "One sentence: pursue or not, and why"
}
```

**Scoring guide:**

| Score | Meaning |
|-------|---------|
| **5** | Ideal — straightforward, lowest risk, synergistic, trivial cost |
| **4** | Good — minor unknowns, low risk, clear benefits, small cost |
| **3** | Adequate — needs design, moderate risk, neutral synergy, medium cost |
| **2** | Concerning — significant unknowns, high risk, partial conflict, large cost |
| **1** | Showstopper — may not be possible, critical risk, fundamental conflict, massive rewrite |

Risk scoring is inverted (5 = lowest risk) so all dimensions are directionally consistent — higher is always better.

**Why no tools:** The orchestrator pre-digests all codebase context. Haiku agents reason about what they're given — they never search or read files. This makes them faster, cheaper, and more focused.
