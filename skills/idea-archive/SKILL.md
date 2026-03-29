---
name: idea-archive
description: "Use when the user wants to save, archive, or persist an idea-matrix convergence report. Triggers on: 'archive this', 'save the convergence report', 'store idea matrix results', '/idea-archive', 'save this decision'. Takes the structured JSON output from a prior idea-matrix run (pasted inline or from the current conversation) and writes it to decisions/YYYY-MM-DD-<slug>.md for future reference.

<example>
Context: User just ran idea-matrix and wants to save the result.
user: \"archive this convergence report\"
assistant: I'll use idea-archive to save the report to decisions/.
<commentary>Saving a convergence report — idea-archive skill.</commentary>
</example>

<example>
Context: User wants to persist a specific decision.
user: \"/idea-archive\"
assistant: I'll use idea-archive to write the report from context to decisions/.
<commentary>Explicit skill invocation — idea-archive.</commentary>
</example>"
argument-hint: "[<problem-slug>] [--json <convergence-json>]"
allowed-tools: [Read, Write, Bash, Glob]
---

<SKILL-GUARD>
You are NOW executing the idea-archive skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Archive an idea-matrix convergence report to `decisions/` as a timestamped markdown file.

---

# 1. Locate the Convergence Report

From the user's input or recent conversation context, find the structured JSON produced by the idea-matrix skill. It has shape:

```json
{
  "problem": "...",
  "convergence": { "winner": "...", "verdict_type": "...", "winner_composite": ... },
  ...
}
```

If the user pasted JSON inline, use that. If not, search the conversation for the most recent idea-matrix output block. If none is found, ask: "Please paste the convergence JSON from your idea-matrix run, or run `/idea-matrix` first."

Store as `REPORT`.

---

# 2. Generate Filename

From `REPORT.problem`, derive a slug:
- Lowercase, strip punctuation, replace spaces/special chars with `-`, max 50 chars, trim trailing `-`

Get today's date:
```bash
date +%Y-%m-%d
```

Assemble: `decisions/YYYY-MM-DD-<slug>.md`

Store as `OUTFILE`.

---

# 3. Ensure Directory Exists

```bash
mkdir -p decisions
```

---

# 4. Write Archive File

Write `OUTFILE` with this structure:

```markdown
---
date: <YYYY-MM-DD>
problem: "<REPORT.problem>"
winner: "<REPORT.convergence.winner>"
verdict_type: "<REPORT.convergence.verdict_type>"
composite_score: <REPORT.convergence.winner_composite>
---

# Decision: <REPORT.problem>

**Winner:** <winner label>
**Verdict:** <verdict_type> (score: <composite_score>/5)
**Date:** <YYYY-MM-DD>

## Reasoning

<REPORT.convergence.reasoning>

## Conditions

<If REPORT.convergence.conditions is non-empty, list each as a bullet. Otherwise: "None.">

## Top Insights

<List REPORT.convergence.top_insights as bullets. If empty: "None recorded.">

## Required Mitigations

<List REPORT.convergence.required_mitigations as bullets. If empty: "None.">

## Full Convergence Data

```json
<REPORT as pretty-printed JSON>
```
```

---

# 5. Confirm

Print:

```
Archived to <OUTFILE>
Winner: <winner> (<verdict_type>, score: <composite_score>/5)
```

---

# Usage Examples

## Example 1 — Archive immediately after idea-matrix

```
user: /idea-matrix "which caching strategy to adopt"
... idea-matrix produces convergence JSON ...
user: /idea-archive caching-strategy
```

The skill reads the convergence JSON from context, derives the slug `caching-strategy`, writes `decisions/2026-03-29-caching-strategy.md`.

## Example 2 — Paste JSON explicitly

```
user: /idea-archive --json '{"problem":"auth approach","convergence":{"winner":"JWT","verdict_type":"clear","winner_composite":4.2},...}'
```

Useful when archiving a result from a prior session or a different conversation.

## Example 3 — Archive without a custom slug

```
user: archive this convergence report
```

The slug is auto-derived from `REPORT.problem`. If the problem text is "Which database should we use for user sessions?", the slug becomes `which-database-should-we-use-for-user-se` (50-char truncation).

---

# Edge Cases and Pitfalls

- **No convergence JSON in context**: If the user invokes this skill without a prior idea-matrix run and without pasting JSON, stop and ask. Do NOT invent or hallucinate a convergence report.
- **Slug collisions**: If `decisions/YYYY-MM-DD-<slug>.md` already exists, append `-2`, `-3`, etc. rather than overwriting. Silently incrementing preserves the original archive.
- **Malformed JSON**: If the pasted JSON is missing required fields (`problem`, `convergence.winner`), print which fields are missing and stop. Do not write a partial file.
- **No `decisions/` directory**: `mkdir -p decisions` is always safe — it is idempotent and will not fail if the directory already exists.
- **Long problem statements**: Slugs are capped at 50 chars to keep filenames readable. The full problem statement is preserved inside the file's frontmatter.

---

# Integration Points

- **idea-matrix** → idea-archive: the canonical pipeline. Run idea-matrix first, then archive the winner.
- **decisions skill**: After archiving, run `/decisions` to list all archived decisions and find this one by date or slug.
- **adversarial-review**: Major architectural decisions should go through adversarial-review before being idea-archived. The AR verdict can be included in `Top Insights`.
- **LCM / lcm-capture**: For cross-project memory, also run `lcm_store` with the decision summary after archiving. idea-archive is local-only (files in `decisions/`); LCM persists across repos.

---

# When NOT to Use

- **Do not use** to archive adversarial-review verdicts directly — those have their own output format. Use the report skill for AR summaries.
- **Do not use** to record informal notes or todo items — this skill is specifically for structured convergence JSON from idea-matrix.
- **Do not use** as a replacement for `lcm_store` when cross-project memory is needed — file-based archives are repo-scoped only.
