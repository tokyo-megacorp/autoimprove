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
| discipline-enforcing | pressure-resistant, procedural-completeness, anti-rationalization, verification-gates, progress-transparency |
| reference | procedural-completeness, examples, failure-modes |
| technique | procedural-completeness, examples, decision-diagrams, progress-transparency |
| pattern | procedural-completeness, examples, failure-modes |

Load rubric files from this directory: `skills/rubrics/<rubric-name>.md`

Each rubric is versioned (semver). Breaking changes increment major. Deprecated rubrics remain readable for 2 major versions.
