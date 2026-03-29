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
