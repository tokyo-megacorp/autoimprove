# Plan: Cross-Model Calibration Phase 1 (issue #56)

**Date:** 2026-03-30
**Issue:** ipedro/autoimprove#56
**Approach:** B + C — Parallel Agent spawns + Calibrate Command skill
**Idea-matrix verdict:** Go with conditions (composite 3.5/5, only non-dealbreaker top scorer)

---

## Decision: Why B + C

The idea-matrix eliminated 6/9 options via dealbreakers:
- **D (Benchmark-integrated):** Goodhart violation — `calibration_gap_score` in autoimprove.yaml would be visible to the experimenter, creating perverse incentive to match format over reasoning quality. Hard no.
- **A (Manual Script):** Creates a parallel scoring system that conflicts with evaluate.sh's deterministic contract.
- **A+B, A+C, A+B+C:** Bash cannot natively await Agent tool calls; dual ownership of gap logic diverges.
- **B alone, C alone:** B has no clean synthesis point (violates §15); C breaks on arbitrary skill wrapping.

Surviving cells: **B+C (3.5)** > A+B+C (3.25) > E (3.0)

B+C wins on double Goodhart isolation:
1. Parallel Agent spawns (B) isolate models at execution layer — opus and haiku run independently
2. Calibrate skill (C) isolates gap report from experimenter at UX layer — skill returns findings, never scores

---

## Goodhart Boundary (mandatory)

- Calibration results = `lcm_store` signals with `tags: ['signal:calibration']`
- **NEVER** add `calibration_gap_score` to autoimprove.yaml benchmarks
- **NEVER** let gap scores influence theme selection weights
- Experimenter sees: "your prompt needs improvement at X because of Y structural reason"
- Experimenter does NOT see: "gap_score dropped from 7.2 to 4.1"

---

## Phase 1 Scope (this issue)

### Deliverable: `/calibrate adversarial-review <input>`

**Hardcoded to AR only.** Generic skill wrapping deferred to Phase 2.

**Flow:**
```
/calibrate adversarial-review <diff-or-file>
    ↓
Read target input
    ↓
Spawn two agents in PARALLEL:
  - Agent(model: opus, prompt: "Run AR on <input>") → opus_result
  - Agent(model: haiku, prompt: "Run AR on <input>") → haiku_result
    ↓
Spawn Sonnet evaluator agent:
  Input: opus_result + haiku_result
  Output: gap_report JSON
    {
      "gap_score": 0-10,
      "missed_by_haiku": [...],
      "false_positives_haiku": [...],
      "prompt_improvements": [
        { "target": "agents/enthusiast.md | agents/adversary.md | agents/judge.md",
          "improvement": "...",
          "reason": "..." }
      ]
    }
    ↓
Display gap report to user
    ↓
lcm_store signal (tags: ['signal:calibration', 'skill:adversarial-review'])
```

### Files to create/modify

1. **`skills/calibrate/SKILL.md`** — new skill
   - Frontmatter: `name: calibrate`, `model: sonnet`, `allowed-tools: [Read, Agent]`
   - Phase 1: hardcoded for adversarial-review only
   - Skill-guard to prevent re-invocation loop
   - Step 1: parse args (`<skill-name> <input>`)
   - Step 2: validate skill is `adversarial-review` (Phase 1 gate)
   - Step 3: load target input
   - Step 4: spawn opus + haiku agents in parallel (both run AR steps directly, not via Skill tool — to avoid nested skill invocation)
   - Step 5: spawn Sonnet evaluator with both outputs
   - Step 6: render gap report + lcm_store signal

2. **`skills/calibrate/plugin.json`** — skill registration
   - name, description, triggers (`/calibrate`)

3. **`docs/calibration.md`** — calibration protocol documentation
   - Phase 1 scope, gap_score interpretation, Goodhart boundary, Phase 2 roadmap

### Sonnet evaluator prompt (inline in skill)

```
You are a calibration evaluator comparing Opus (gold standard) and Haiku (cheap) outputs for the adversarial-review skill.

## Opus Output
{OPUS_RESULT}

## Haiku Output
{HAIKU_RESULT}

Evaluate:
1. What findings did Opus confirm that Haiku MISSED?
2. What findings did Haiku flag that Opus dismissed (false positives)?
3. What specific prompt changes would close the gap?

Output JSON only:
{
  "gap_score": <0-10, where 0=identical quality, 10=completely different>,
  "missed_by_haiku": [{ "finding": "...", "severity": "critical|high|medium|low" }],
  "false_positives_haiku": [{ "finding": "...", "reason": "..." }],
  "prompt_improvements": [
    {
      "target": "agents/enthusiast.md",
      "improvement": "...",
      "reason": "..."
    }
  ],
  "summary": "<one sentence: overall quality gap>"
}
```

---

## Phase 2 Boundary (out of scope for #56)

- Generic skill wrapping (`/calibrate idea-matrix`, `/calibrate introspection`, etc.)
- `xgh:dispatch` adapter for weekly cron automation
- Calibration trend tracking over time
- Automatic grind loop theme injection from calibration signals

**Acceptance criterion for Phase 2 start:** gap_score for adversarial-review must be measured at least 3 times manually before automation.

---

## Success Criteria (Phase 1)

- [ ] `/calibrate adversarial-review <diff>` runs end-to-end
- [ ] Gap report JSON includes at least one actionable `prompt_improvements` entry
- [ ] lcm signal stored with correct tags
- [ ] Goodhart boundary intact: gap_score never appears in autoimprove.yaml
- [ ] AR runs with Opus find ≥1 finding that Haiku misses (baseline measurement)

---

## Implementation Steps

1. Create `skills/calibrate/` directory with `SKILL.md` and `plugin.json`
2. Implement the three-stage flow (parallel spawns → Sonnet evaluator → display + lcm)
3. Test on a recent PR diff as canonical input
4. Store first gap report as Phase 1 baseline
5. Create `docs/calibration.md`
6. PR with AR + introspection

---

## Risk: Nested Skill Invocation

The calibrate skill MUST NOT call `Skill('autoimprove:adversarial-review')` internally — this would create a nested skill invocation that doesn't support model override. Instead, the skill spawns agents with the AR steps inlined in the agent prompt. This is by design: model calibration requires controlling the model parameter, which only Agent tool supports directly.
