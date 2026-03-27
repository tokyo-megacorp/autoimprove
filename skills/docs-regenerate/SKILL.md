---
name: docs-regenerate
description: "Regenerate docs after code changes. Use when the user says 'regenerate docs', 'update docs', 'docs are stale', 'sync docs', '/docs-regenerate', or after a milestone commit. Detects which source files changed, maps them to affected doc files, and delegates updates to subagents."
argument-hint: "[--range <git-range>] [--all] [--dry-run]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent]
---

<SKILL-GUARD>
You are NOW executing the docs-regenerate skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Detect changed source files, map them to affected docs, and regenerate stale documentation.

---

# 1. Parse Arguments

From the user's input, extract:
- **range**: git range for detecting changes (default: `HEAD~1..HEAD`)
- **all**: if true, regenerate all docs regardless of changes
- **dry_run**: if true, report what would change without writing

If `--all` was passed, skip step 2 (change detection) and proceed to step 3 with all artifact types.

If a specific range was given (e.g., `HEAD~5..HEAD`, `main..feature`), use that for change detection.

---

# 2. Detect Changed Files

Run change detection over the specified range:

```bash
git diff --name-only --diff-filter=ACMR <RANGE>
```

Store the list as `CHANGED_FILES`. If the list is empty and `--all` was not passed, tell the user: "No changes detected in the specified range. Use `--all` to regenerate all docs, or specify a broader range with `--range`."

---

# 3. Read Structure Spec

Read `~/.claude/docs-structure-spec.md` to get the canonical documentation structure rules.

If the file does not exist, use these defaults:
- Flat files for artifact types with count <= 10
- Subtree directories for count > 10
- README.md in every directory
- User perspective, not implementation details

Store as `SPEC`.

---

# 4. Inventory Current State

Scan the repository to count artifacts and determine the current docs structure:

**4a. Count artifacts:**

```bash
# Skills
ls skills/*/SKILL.md 2>/dev/null | wc -l

# Commands
ls commands/*.md 2>/dev/null | wc -l

# Agents
ls agents/*.md 2>/dev/null | wc -l

# Hooks (check both locations)
ls hooks/*.ts hooks/*.js hooks/*.sh 2>/dev/null | wc -l

# MCP tools (check plugin.json or .mcp.json)
# CLI subcommands (check if repo has a CLI binary)
```

Store counts as `ARTIFACT_COUNTS`.

**4b. Check existing docs:**

```bash
ls docs/*.md docs/*/*.md 2>/dev/null
```

Store as `EXISTING_DOCS`.

**4c. Determine structure mode for each type:**

Apply the spec's scale rule:
- count <= 10 → flat file (e.g., `docs/skills.md`)
- count > 10 → subtree (e.g., `docs/skills/README.md` + per-skill files)
- count == 0 → no doc file (do not create empty docs)

Store as `STRUCTURE_MODE` (map of type → "flat" | "subtree" | "none").

---

# 5. Map Changes to Affected Docs

For each file in `CHANGED_FILES`, classify it and determine which doc(s) need updating:

| Changed file pattern | Affected doc | Action |
|---------------------|-------------|--------|
| `skills/<name>/SKILL.md` | `docs/skills.md` or `docs/skills/<name>.md` | Update skill entry |
| `agents/<name>.md` | `docs/agents.md` or `docs/agents/<name>.md` | Update agent entry |
| `commands/<name>.md` | `docs/commands.md` or `docs/commands/<name>.md` | Update command entry |
| `hooks/<name>.*` | `docs/hooks.md` or `docs/hooks/<name>.md` | Update hook entry |
| `*.yaml`, `*.json` (config) | `docs/configuration.md` | Update config reference |
| `plugin.json` | `docs/getting-started.md`, `docs/README.md` | Check if version/name changed |
| New file in any category | Flag as "new — doc may not exist" | Create doc entry |
| Deleted file in any category | Flag as "removed — doc may be stale" | Remove doc entry |

Build `AFFECTED_DOCS` — a list of `{ doc_path, action, source_files, reason }`.

If `--all` was passed, include ALL doc files as affected.

If `--dry-run` was passed, print the `AFFECTED_DOCS` list and stop here:

```
Docs regeneration plan:
  UPDATE docs/skills.md — skills/idea-matrix/SKILL.md changed
  UPDATE docs/commands.md — commands/idea-matrix.md added
  UPDATE docs/agents.md — agents/idea-explorer.md added
  UPDATE docs/README.md — new skills/commands detected
  SKIP docs/configuration.md — no config changes
  SKIP docs/architecture.md — no structural changes
```

---

# 6. Read Source Files for Context

For each affected doc, read the source files that inform it:

- For skill docs: read the SKILL.md file (the skill definition IS the source of truth)
- For agent docs: read the agent .md file (frontmatter + system prompt)
- For command docs: read the command .md file
- For hook docs: read the hook source file
- For config docs: read the config file(s)

Build `DOC_CONTEXT` — a map of `doc_path → { current_doc_content, source_content[] }`.

---

# 7. Delegate Regeneration to Subagents

For each affected doc, spawn a subagent to regenerate or update it.

**Model selection:**
- **haiku** — for simple updates (adding a new entry to an existing flat file, updating a field)
- **sonnet** — for new doc creation, structural changes (flat → subtree migration), or architecture.md updates

**Subagent prompt template:**

```
You are a documentation writer. Update the following doc file based on changed source files.

## Structure Spec Rules
{relevant rules from SPEC for this doc type}

## Current Doc
{current content of the doc file, or "NEW FILE — create from scratch"}

## Source Files That Changed
{for each source file: path + full content}

## Instructions
- Write from the user perspective (behavior flows, not implementation details)
- Match the existing style and format of the doc
- For flat files: maintain alphabetical or logical ordering of entries
- For new entries: follow the same structure as existing entries
- Do not remove entries for items that still exist (only remove if the source file was deleted)
- Output the COMPLETE updated doc file content — not a diff, not a partial update

Output ONLY the file content. No preamble, no explanation.
```

**Dispatch strategy:**
- If only 1-2 docs need updating → run sequentially (low overhead)
- If 3+ docs need updating → dispatch in parallel using the Agent tool

Collect all regenerated doc content as `REGENERATED[doc_path] = content`.

---

# 8. Check for Structure Changes

After regeneration, verify that the docs structure still matches the spec:

**8a. Flat → subtree migration:**
If an artifact count crossed the > 10 threshold since docs were last written:
- Create the subtree directory
- Split the flat file into per-item files + README.md
- Delete the flat file
- Log: `"Migrated docs/skills.md → docs/skills/ (count exceeded 10)"`

**8b. Subtree → flat migration:**
If an artifact count dropped to <= 10:
- Merge per-item files into a single flat file
- Delete the subtree directory
- Log: `"Consolidated docs/skills/ → docs/skills.md (count dropped to 10 or below)"`

**8c. New artifact type:**
If a new artifact type was detected (e.g., first hook added) and no doc exists:
- Create the doc file
- Log: `"Created docs/hooks.md (first hook detected)"`

---

# 9. Update docs/README.md

If any new doc files were created or the structure changed, regenerate the `docs/README.md` TOC.

Read the current `docs/README.md`. Check if all doc files are linked. Add missing links, remove links to deleted files.

---

# 10. Write Files and Commit

**10a. Write all regenerated docs:**

For each `doc_path` in `REGENERATED`:
- If the file exists and content changed → write with Edit tool
- If the file is new → write with Write tool
- If the file should be deleted (source was removed, no entries remain) → delete

**10b. Stage and commit:**

```bash
git add docs/
git commit -m "docs: regenerate after $(echo <RANGE> | tr '..' ' ')"
```

If no docs actually changed (all regenerated content matches current content), skip the commit and report: "All docs are up to date — no changes needed."

---

# 11. Report

Print a summary:

```
Docs regeneration complete.

  Updated:  docs/skills.md (added idea-matrix)
  Updated:  docs/commands.md (added idea-matrix, prompt-testing)
  Updated:  docs/agents.md (added idea-explorer)
  Updated:  docs/README.md (TOC refreshed)
  Skipped:  docs/configuration.md (no changes)
  Skipped:  docs/architecture.md (no changes)

Commit: <SHA> — "docs: regenerate after HEAD~1 HEAD"
```

---

# Notes

- **Self-contained**: reads the structure spec at runtime so it stays current
- **Scale-aware**: checks artifact counts to decide flat vs subtree, migrates automatically
- **Non-destructive**: never removes doc entries for items that still exist in the source
- **Dry-run safe**: `--dry-run` shows the plan without writing anything
- **Incremental by default**: only regenerates docs affected by changed files
- **Full regeneration**: `--all` forces a complete docs refresh
