---
name: decisions
description: "Use when the user wants to browse, list, or review archived design decisions. Triggers on: 'show decisions', 'list decisions', 'review past decisions', 'what did we decide', 'decision archive'. Optionally filter by keyword slug. Can show summary or full content of specific decisions."
argument-hint: "[<keyword>] [--full]"
allowed-tools: [Read, Bash, Glob]
---

<SKILL-GUARD>
You are NOW executing the decisions skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Browse archived decisions from `decisions/`. Read-only — makes no changes.

Parse user input:
- `<keyword>` — filter filenames by substring (case-insensitive, matched against slug)
- `--full` — print full file content instead of summary line per decision

---

# 1. List Decision Files

```bash
ls decisions/ 2>/dev/null | sort -r
```

If the directory is missing or empty, print:
```
No decisions archived yet. Run /idea-matrix then /idea-archive to create one.
```
and stop.

---

# 2. Apply Keyword Filter

Keep only filenames containing `<keyword>` (case-insensitive). If no keyword, keep all.

If result is empty, print:
```
No decisions match "<keyword>". Try a broader term or omit the keyword to list all.
```
and stop.

---

# 3. Display Results

For each matched file (newest-first — filenames are YYYY-MM-DD-prefixed):

**Summary mode (default):** Read YAML frontmatter and print:
```
<YYYY-MM-DD>  <slug>  |  Winner: <winner>  |  Verdict: <verdict_type>  (score: <composite_score>/5)
```
`<slug>` = filename minus `YYYY-MM-DD-` prefix and `.md` suffix.

If frontmatter is missing or malformed: `<YYYY-MM-DD>  <slug>  |  [unreadable]`

**Full mode (`--full`):** Print complete file content for each match, separated by `---`.

---

# 4. Summary Line

```
<N> decision(s) found — keyword: <keyword> | (no filter)
```

If archive has >50 files, suggest using a keyword to narrow results.
Files not matching `YYYY-MM-DD-*.md` pattern are listed separately under `Unrecognized files:`.

---

# Usage Examples

## Example 1: List All Decisions

```
User: show decisions
```

Output:
```
2026-03-28  cache-strategy  |  Winner: A+B hybrid  |  Verdict: go  (score: 4.1/5)
2026-03-15  auth-backend    |  Winner: JWT alone   |  Verdict: conditional  (score: 3.7/5)
2026-03-01  storage-layer   |  Winner: C alone     |  Verdict: go  (score: 4.3/5)

3 decision(s) found — (no filter)
```

## Example 2: Filter by Keyword

```
User: show decisions cache
```

Returns only files whose slug contains "cache" (case-insensitive). If the project accumulated decisions about "disk-cache", "cache-strategy", and "cache-eviction", all three are returned.

## Example 3: View Full Decision File

```
User: show decisions auth --full
```

Prints the entire markdown content of all decisions whose slug contains "auth", separated by `---`. Useful when you need the full reasoning, conditions, and top insights — not just the summary line.

## Example 4: Verify a Past Commitment

```
User: what did we decide about JWT vs session cookies?
```

The skill filters for a keyword like "jwt" or "session" and surfaces the YAML frontmatter summary, letting the user quickly confirm the past verdict without re-reading the full file.

---

# Edge Cases and Pitfalls

- **Missing `decisions/` directory:** The skill will print the onboarding message and stop. This is expected on a fresh project — run `/idea-matrix` then `/idea-archive` first.
- **Malformed frontmatter:** If a decision file is missing the YAML block or has invalid YAML, the skill prints `[unreadable]` for that entry and continues. It does NOT crash or stop.
- **Keyword too narrow:** A keyword like "v2" may match nothing even though related decisions exist under "auth-v2" or "storage-migration". Use broader terms when unsure.
- **Unrecognized files:** Any `.md` file in `decisions/` that doesn't follow the `YYYY-MM-DD-<slug>.md` naming pattern is listed separately under `Unrecognized files:`. These might be manually created notes or partial archives — they are displayed, not silently dropped.
- **Newest-first ordering:** Files are sorted reverse-chronologically by filename. If a file was renamed or its date prefix is wrong, it will appear out of order.

---

# Integration Points

- **`/idea-archive`** — Creates the `.md` files in `decisions/` that this skill reads. The archive skill writes the YAML frontmatter (`winner`, `verdict_type`, `composite_score`) that the summary mode depends on.
- **`/idea-matrix`** — Produces the convergence report that `/idea-archive` then persists. Running `/decisions` after an archived matrix session is the standard review workflow.
- **`/matrix-draft`** — When a user says "what options did we consider last time for X?", reviewing past decisions via this skill can seed the next matrix-draft session.
- **`/report`** — Complements this skill: `/report` shows experiment metrics and kept/discarded diffs; `/decisions` shows design-level rationale. Use both together for a full project retrospective.

---

# When NOT to Use This Skill

- To see experiment scores or kept/discarded code changes → use `/report`
- To browse in-progress brainstorming → use `/idea-matrix` or `/matrix-draft`
- To create or update a decision file → use `/idea-archive`
