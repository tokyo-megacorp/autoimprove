---
name: rubrics
description: Reference skill — rubric catalog for skill quality assessment. Used by reviewer and transformer agents to score and improve skills. Not typically invoked directly by users.
---

# Xavier School Rubrics

Rubric index for skill quality assessment. Each rubric file contains score criteria (0-10), test generation prompts, and transform rules.

## Routing

Given a skill type from `diagnose`, load the applicable rubrics:

| Skill Type | REQUIRED Rubrics |
|---|---|
| discipline-enforcing | authoring-hygiene, pressure-resistant, procedural-completeness, anti-rationalization, verification-gates, progress-transparency |
| reference | authoring-hygiene, procedural-completeness, examples, failure-modes |
| technique | authoring-hygiene, procedural-completeness, examples, decision-diagrams, progress-transparency |
| pattern | authoring-hygiene, procedural-completeness, examples, failure-modes |

Load rubric files from this directory: `skills/rubrics/<rubric-name>.md`

Each rubric is versioned (semver). Breaking changes increment major. Deprecated rubrics remain readable for 2 major versions.

## Directives

- **Never load all rubric files.** Load only the REQUIRED rubrics for the diagnosed skill type. Loading extras wastes tokens and can introduce conflicting scoring criteria.
- **Always run diagnose before loading rubrics.** The skill type from diagnose determines which rubrics apply. Do not guess the type from the file name alone.
- **Do not invoke this skill directly to score a skill.** Use the `polish` skill instead — it orchestrates diagnose → review → optional transform in the correct order.
- **If the skill type is not in the routing table, default to `technique`.** Note the low-confidence classification in your output and apply the `technique` rubrics.
- **Never skip a REQUIRED rubric.** If a rubric file is missing from disk, stop and report the missing path — do not silently drop it from the assessment.
- **Prefer loading rubric files with `Read` over quoting them inline.** Rubric content changes across versions; always read from disk to get the current criteria.
- **Run `ls skills/rubrics/` before reporting a rubric as missing.** The file may exist under a slightly different name (e.g., `failure-modes.md` vs `failure_modes.md`).
