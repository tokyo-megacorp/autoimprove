---
name: decisions
description: "Use when the user wants to browse, list, or review archived design decisions. Triggers on: 'show decisions', 'list decisions', 'review past decisions', 'what did we decide', 'decision archive'. Optionally filter by keyword (slug or body), date, or verdict type. Can show summary or full content of specific decisions."
argument-hint: "[<keyword>] [--full] [--since YYYY-MM-DD] [--verdict go|conditional|abort] [--search TEXT]"
allowed-tools: [Read, Bash, Glob]
---

<SKILL-GUARD>
You are NOW executing the decisions skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Browse archived decisions from `decisions/`. Read-only — makes no changes.

Parse user input:
- `<keyword>` — filter filenames by substring (case-insensitive, matched against slug)
- `--full` — print full file content instead of summary line per decision
- `--since YYYY-MM-DD` — only show decisions on or after this date (matches YAML `date:` field or filename prefix)
- `--verdict TYPE` — filter by verdict type (go, conditional, abort — matched case-insensitively)
- `--search TEXT` — search inside decision body text (problem statement, reasoning, insights), not just filenames

Initialize progress tracking:
```
TodoWrite([
  {id:"list",    content:"🗂️ List decision files",    status:"in_progress"},
  {id:"filter",  content:"🔍 Apply filters",           status:"pending"},
  {id:"display", content:"📋 Display results",         status:"pending"},
  {id:"summary", content:"📊 Print summary line",      status:"pending"}
])
```

---

# 1. 🗂️ List Decision Files

```bash
ls decisions/ 2>/dev/null | sort -r
```

If the directory is missing or empty, print:
```
No decisions archived yet. Run /idea-matrix then /idea-archive to create one.
```
and stop.

Mark `list` complete: `TodoWrite([{id:"list", content:"🗂️ List decision files", status:"completed"}, {id:"filter", content:"🔍 Apply filters", status:"in_progress"}])`

---

# 2. 🔍 Apply Filters

Keep only files that pass ALL of the following active filters. Apply in this order:

**2a. Keyword filter** (active when `<keyword>` is provided)

Keep filenames containing `<keyword>` (case-insensitive substring match against the slug — the filename minus the `YYYY-MM-DD-` prefix and `.md` suffix).

**2b. Since filter** (active when `--since YYYY-MM-DD` is provided)

Keep only files where the `YYYY-MM-DD` date prefix in the filename is >= the given date.
If the filename does not have a recognizable date prefix, keep it (don't silently drop it).

Example: `--since 2026-03-01` keeps `2026-03-15-auth-backend.md` but drops `2026-02-28-storage-layer.md`.

**2c. Verdict filter** (active when `--verdict TYPE` is provided)

Read the YAML frontmatter of each remaining file and keep only those where `verdict_type` matches `TYPE` (case-insensitive). If frontmatter is unreadable, keep the file (don't silently drop it — print `[unreadable]` for it later).

**2d. Body search** (active when `--search TEXT` is provided)

Read the body of each remaining file. Keep only those where `TEXT` appears (case-insensitive) anywhere in the file content — problem statement, reasoning, conditions, top insights, or required mitigations. This supplements `<keyword>`, which only matches filenames.

```bash
grep -li "<TEXT>" decisions/<file> 2>/dev/null
```

If result is empty after all filters, print:
```
No decisions match the given filters. Try a broader term or omit filters to list all.
```
and stop.

Mark `filter` complete: `TodoWrite([{id:"filter", content:"🔍 Apply filters", status:"completed"}, {id:"display", content:"📋 Display results", status:"in_progress"}])`

---

# 3. 📋 Display Results

For each matched file (newest-first — filenames are YYYY-MM-DD-prefixed):

**Summary mode (default):** Read YAML frontmatter and print:
```
<YYYY-MM-DD>  <slug>  |  Winner: <winner>  |  Verdict: <verdict_type>  (score: <composite_score>/5)
```
`<slug>` = filename minus `YYYY-MM-DD-` prefix and `.md` suffix.

If frontmatter is missing or malformed: `<YYYY-MM-DD>  <slug>  |  [unreadable]`

**Full mode (`--full`):** Print complete file content for each match, separated by `---`.

Mark `display` complete: `TodoWrite([{id:"display", content:"📋 Display results", status:"completed"}, {id:"summary", content:"📊 Print summary line", status:"in_progress"}])`

---

# 4. 📊 Summary Line

```
<N> decision(s) found — <active filters description>
```

Build the filter description from active filters, e.g.:
- `keyword: cache`
- `verdict: go`
- `since: 2026-03-01`
- `search: "JWT"`
- `keyword: auth, verdict: conditional`
- `(no filters)`

If the archive has >50 files and no filters were applied, suggest:
```
Archive has <N> files. Use --since or <keyword> to narrow results.
```

Files not matching `YYYY-MM-DD-*.md` pattern are listed separately under `Unrecognized files:`.

Mark `summary` complete: `TodoWrite([{id:"summary", content:"📊 <N> decision(s) found", status:"completed"}])`

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  {id:"list", status:"completed"},
  {id:"filter", status:"completed"},
  {id:"display", status:"completed"},
  {id:"summary", status:"completed"}
])
```

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

3 decision(s) found — (no filters)
```

## Example 2: Filter by Keyword (Filename)

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

## Example 5: Search Inside Decision Body

```
User: show decisions --search "session cookie"
```

The `--search` flag searches inside decision body text (not just filenames). This finds decisions where "session cookie" appears in the problem statement, reasoning, or insights — even if the filename slug is `auth-backend`. Use this when you don't know the slug but remember a phrase from the discussion.

## Example 6: Filter by Verdict Type

```
User: show decisions --verdict conditional
```

Returns all decisions where `verdict_type: conditional` — decisions that were approved with conditions attached. Useful for auditing which past commitments have outstanding obligations before planning new work.

## Example 7: Review Decisions Since a Date

```
User: show decisions --since 2026-03-01
```

Returns decisions made on or after March 1, 2026. Combine with `--verdict go` for a quick sprint retrospective of clean wins: `--since 2026-03-01 --verdict go`.

---

# Edge Cases and Pitfalls

- **Missing `decisions/` directory:** The skill will print the onboarding message and stop. This is expected on a fresh project — run `/idea-matrix` then `/idea-archive` first.
- **Malformed frontmatter:** If a decision file is missing the YAML block or has invalid YAML, the skill prints `[unreadable]` for that entry and continues. It does NOT crash or stop.
- **Keyword too narrow:** A keyword like "v2" may match nothing even though related decisions exist under "auth-v2" or "storage-migration". Use `--search` when the concept is in the body, not the slug.
- **`--search` vs `<keyword>`:** `<keyword>` matches the filename slug only (fast, no file reads). `--search TEXT` reads every file's body — it's slower on large archives but finds content anywhere in the document.
- **`--since` date format:** Must be ISO 8601 (`YYYY-MM-DD`). Formats like `03-29-2026` or `March 29` will not match correctly. Files without a date prefix are retained (not silently dropped).
- **Unrecognized files:** Any `.md` file in `decisions/` that doesn't follow the `YYYY-MM-DD-<slug>.md` naming pattern is listed separately under `Unrecognized files:`. These might be manually created notes or partial archives — they are displayed, not silently dropped.
- **Newest-first ordering:** Files are sorted reverse-chronologically by filename. If a file was renamed or its date prefix is wrong, it will appear out of order.
- **Verdict filter and unreadable frontmatter:** If a file cannot be read (e.g., binary, permissions), it is kept in the result set and shown as `[unreadable]` rather than dropped. The verdict filter only drops files where frontmatter is readable but `verdict_type` doesn't match.

---

# Common Failure Patterns

- **Keyword too specific, returns nothing:** Try the root concept instead of the exact phrase. `decisions auth` beats `decisions jwt-vs-session-cookies`. If still no result, use `--search jwt` to look inside bodies.
- **`[unreadable]` on every file:** The YAML frontmatter is likely using tabs or inconsistent indentation. Open the file with `--full` to inspect the raw content, then repair the frontmatter manually.
- **All files show `[unreadable]`:** The `/idea-archive` skill may have written files without YAML frontmatter (common if it was run in "quick mode"). These files contain the reasoning but no machine-readable summary — they are still displayed, just without the structured summary line.
- **`--since` filter returns fewer results than expected:** Verify the date format is `YYYY-MM-DD`. Also verify the filename prefix uses the same format — if a file was manually created with `MM-DD-YYYY`, the comparison will fail. Files with non-standard prefixes appear under `Unrecognized files:`.
- **`--verdict go` returns nothing despite many "go" decisions:** The `verdict_type` field in YAML frontmatter must be exactly `go`, `conditional`, or `abort`. If `/idea-archive` wrote `"clear"` or `"strong go"` instead, the exact-match will miss them. Use `--search go` as a fallback to catch non-standard values.
- **Newest decision not appearing first:** The sort is lexicographic by filename, so the date prefix must be ISO 8601 (`YYYY-MM-DD`). A `MM-DD-YYYY` prefix will sort incorrectly.

---

# Integration Points

- **`/idea-archive`** — Creates the `.md` files in `decisions/` that this skill reads. The archive skill writes the YAML frontmatter (`winner`, `verdict_type`, `composite_score`) that the summary mode depends on.
- **`/idea-matrix`** — Produces the convergence report that `/idea-archive` then persists. Running `/decisions` after an archived matrix session is the standard review workflow.
- **`/matrix-draft`** — When a user says "what options did we consider last time for X?", use `--search "X"` via this skill to find the relevant past decision and seed the next matrix-draft session with what was already tried.
- **`/report`** — Complements this skill: `/report` shows experiment metrics and kept/discarded diffs; `/decisions` shows design-level rationale. Use both together for a full project retrospective.
- **Periodic audits:** `--since YYYY-MM-DD --verdict conditional` lists all conditional decisions made since a date, letting you verify outstanding conditions have been met before closing a milestone.

---

# When NOT to Use This Skill

- To see experiment scores or kept/discarded code changes → use `/report`
- To browse in-progress brainstorming → use `/idea-matrix` or `/matrix-draft`
- To create or update a decision file → use `/idea-archive`
- To compare multiple decision options that haven't been decided yet → use `/matrix-draft` to frame and `/idea-matrix` to run the debate
