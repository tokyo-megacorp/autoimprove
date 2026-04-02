---
name: docs-regenerate
description: |
  Update docs after code changes using only the git diff. Triggers: 'regenerate docs', 'update docs', 'docs are stale', 'sync docs', '/docs-regenerate', 'docs after milestone'.

  <example>
  user: "regenerate docs after the last commit"
  assistant: I'll use docs-regenerate to patch only affected doc sections.
  <commentary>Post-commit doc patch — docs-regenerate.</commentary>
  </example>

  <example>
  user: "docs are stale — we added a new skill"
  assistant: I'll use docs-regenerate to add the new skill entry from the diff.
  <commentary>New file in diff — docs-regenerate adds the doc entry.</commentary>
  </example>

  <example>
  user: "/docs-regenerate --dry-run"
  assistant: I'll run docs-regenerate in dry-run mode to preview without writing.
  <commentary>Preview mode — pass --dry-run.</commentary>
  </example>

  Do NOT regenerate all docs from scratch (no --all — token trap). Do NOT use without commits (needs a diff). Do NOT use for decisions/ideas (use idea-archive).
argument-hint: "[--range <git-range>] [--dry-run]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent]
---

<SKILL-GUARD>
You are NOW executing the docs-regenerate skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Update documentation using ONLY the git diff as context. Never read full source files. Never regenerate entire docs.

Initialize progress tracking:

```
TodoWrite([
  { id: "args",      content: "📋 Parse arguments",          status: "in_progress" },
  { id: "detect",    content: "🔍 Detect changed files",     status: "todo" },
  { id: "map",       content: "📊 Map changes to docs",      status: "todo" },
  { id: "read",      content: "📋 Read affected doc sections", status: "todo" },
  { id: "patch",     content: "📝 Patch docs via subagents", status: "todo" },
  { id: "structure", content: "🔍 Check structure changes",  status: "todo" },
  { id: "readme",    content: "📝 Update docs/README.md",    status: "todo" },
  { id: "commit",    content: "✅ Write files and commit",   status: "todo" },
  { id: "report",    content: "📋 Report",                   status: "todo" }
])
```

---

# 1. 📋 Parse Arguments

From the user's input, extract:
- **range**: git range for detecting changes (default: `HEAD~1..HEAD`)
- **dry_run**: if true, report what would change without writing

If a specific range was given (e.g., `HEAD~5..HEAD`, `main..feature`), use that for change detection.

```
TodoWrite([
  { id: "args",    content: "📋 Parse arguments",       status: "completed" },
  { id: "detect",  content: "🔍 Detect changed files",  status: "in_progress" }
])
```

---

# 2. 🔍 Detect Changed Files and Get Diffs

**2a. Get the list of changed files:**

```bash
git diff --name-only --diff-filter=ACMRD <RANGE>
```

Store as `CHANGED_FILES`. If empty, tell the user: "No changes detected in the specified range. Specify a broader range with `--range`."

**2b. Get the actual diffs for those files:**

```bash
git diff <RANGE> -- <file1> <file2> ...
```

Store as `DIFFS`. This is the ONLY context subagents will receive — no full file reads.

**2c. Identify new vs modified vs deleted files:**

From the diff filter flags:
- `A` = new file (doc entry needs to be created)
- `M`/`C`/`R` = modified (doc entry needs to be updated)
- `D` = deleted (doc entry needs to be removed)

```
TodoWrite([
  { id: "detect",  content: "🔍 Detect changed files",    status: "completed" },
  { id: "map",     content: "📊 Map changes to docs",     status: "in_progress" }
])
```

---

# 3. 📊 Map Changes to Affected Docs

For each file in `CHANGED_FILES`, classify it and determine which doc(s) need updating:

| Changed file pattern | Affected doc | Action |
|---------------------|-------------|--------|
| `skills/<name>/SKILL.md` | `docs/skills.md` or `docs/skills/<name>.md` | Update/create/remove skill entry |
| `agents/<name>.md` | `docs/agents.md` or `docs/agents/<name>.md` | Update/create/remove agent entry |
| `commands/<name>.md` | `docs/commands.md` or `docs/commands/<name>.md` | Update/create/remove command entry |
| `hooks/<name>.*` | `docs/hooks.md` or `docs/hooks/<name>.md` | Update/create/remove hook entry |
| `*.yaml`, `*.json` (config) | `docs/configuration.md` | Update config reference |
| `plugin.json` | `docs/getting-started.md`, `docs/README.md` | Check if version/name changed |
| `docs/*.md` | Self — no action needed | Skip (docs editing themselves) |

Build `AFFECTED_DOCS` — a list of `{ doc_path, action, changed_files[], reason }`.

If `--dry-run` was passed, print the `AFFECTED_DOCS` list and stop here:

```
Docs update plan (diff-only):
  UPDATE docs/skills.md — skills/idea-matrix/SKILL.md changed (section patch)
  CREATE entry in docs/commands.md — commands/idea-matrix.md added
  REMOVE entry in docs/agents.md — agents/old-agent.md deleted
  UPDATE docs/README.md — new skills/commands detected
  SKIP docs/configuration.md — no config changes
```

```
TodoWrite([
  { id: "map",   content: "📊 Map changes to docs — N docs affected",  status: "completed" },
  { id: "read",  content: "📋 Read affected doc sections",              status: "in_progress" }
])
```

---

# 4. 📋 Read ONLY Affected Doc Sections

For each affected doc, read the doc file that needs updating:

```
Read docs/skills.md
```

Do NOT read source files (skills/*.md, agents/*.md, commands/*.md, hooks/*). The git diff from step 2b contains everything needed.

```
TodoWrite([
  { id: "read",   content: "📋 Read affected doc sections",  status: "completed" },
  { id: "patch",  content: "📝 Patch docs via subagents",    status: "in_progress" }
])
```

---

# 5. 📝 Delegate Patching to Subagents

For each affected doc, spawn a subagent to patch it using ONLY the diff.

**Model selection:**
- **haiku** — for updating existing entries, removing entries, small patches
- **sonnet** — for creating new doc entries from a diff (needs to infer structure from diff context)

**Subagent prompt template:**

```
You are a documentation patcher. Update ONLY the relevant section(s) of this doc file based on the git diff below.

## Rules
- Do NOT rewrite the entire file — patch only the section affected by the diff
- Write from the user perspective (behavior flows, not implementation details)
- Match the existing style and format of the doc
- For new entries: follow the same structure as existing entries in the doc
- For deleted files: remove the entry entirely
- For modified files: update only what the diff changes

## Current Doc Content
{content of the doc file}

## Git Diff (this is your ONLY source of truth)
{relevant portions of DIFFS for the files that map to this doc}

## Action
{action from AFFECTED_DOCS — UPDATE/CREATE/REMOVE}

## Changed Files
{list of changed file paths that affect this doc}

Output the COMPLETE updated doc file content.
```

**Dispatch strategy:**
- If only 1-2 docs need updating → run sequentially
- If 3+ docs need updating → dispatch in parallel using the Agent tool

Collect all patched doc content as `PATCHED[doc_path] = content`.

```
TodoWrite([
  { id: "patch",     content: "📝 Patch docs via subagents",   status: "completed" },
  { id: "structure", content: "🔍 Check structure changes",    status: "in_progress" }
])
```

---

# 6. 🔍 Check for Structure Changes

Only if the diff includes NEW or DELETED files in a category, check whether counts crossed the scale threshold:

```bash
# Only run for affected categories
ls skills/*/SKILL.md 2>/dev/null | wc -l   # only if a skill was added/removed
ls commands/*.md 2>/dev/null | wc -l        # only if a command was added/removed
```

Apply the spec's scale rule (from `~/.claude/docs-structure-spec.md` if it exists):
- count crossed above 10 → migrate flat file to subtree
- count crossed below 11 → migrate subtree to flat file

Log any migrations performed.

```
TodoWrite([
  { id: "structure",  content: "🔍 Check structure changes",  status: "completed" },
  { id: "readme",     content: "📝 Update docs/README.md",    status: "in_progress" }
])
```

---

# 7. 📝 Update docs/README.md

Only if new doc files were created or the structure changed.

Read the current `docs/README.md`. Add missing links, remove links to deleted files. Do not rewrite sections unrelated to the change.

```
TodoWrite([
  { id: "readme",  content: "📝 Update docs/README.md",  status: "completed" },
  { id: "commit",  content: "✅ Write files and commit",  status: "in_progress" }
])
```

---

# 8. ✅ Write Files and Commit

**8a. Write patched docs:**

For each `doc_path` in `PATCHED`:
- If content changed → write with Edit tool (preferred) or Write tool
- If a doc should be deleted (all entries removed) → delete

**8b. Stage and commit:**

```bash
git add docs/
git commit -m "docs: update after $(echo <RANGE> | tr '..' ' ')"
```

If no docs actually changed, skip the commit and report: "All docs are up to date — no changes needed."

```
TodoWrite([
  { id: "commit",  content: "✅ Write files and commit",  status: "completed" },
  { id: "report",  content: "📋 Report",                  status: "in_progress" }
])
```

---

# 9. 📋 Report

Print a summary:

```
Docs update complete (diff-only).

  Patched:  docs/skills.md (updated idea-matrix section)
  Patched:  docs/commands.md (added idea-matrix entry)
  Patched:  docs/README.md (TOC refreshed)
  Skipped:  docs/configuration.md (no config changes)

Commit: <SHA> — "docs: update after HEAD~1 HEAD"
```

```
TodoWrite([
  { id: "report",  content: "📋 Report",  status: "completed" }
])
```

---

# ❌ Common Failure Patterns

- **Subagent reads full source files despite diff-only constraint:** If a patching subagent reads the entire source to "understand context", it defeats the diff-only design and floods the context window. Instruct subagents explicitly: "Your only source of truth is the diff. Do not read source files."
- **Commit message references the wrong SHAs:** The skill constructs `"docs: update after <from> <to>"` from the git arguments. If `--from` and `--to` are omitted, it defaults to `HEAD~1 HEAD`. Verify the resulting commit message matches the diff range you intended.
- **Docs drift silently after multiple keeps:** The docs-regenerate skill only runs when explicitly invoked (or via hook). If kept experiments are not followed by a docs run, documentation drifts. Consider adding it to the post-keep hook or the `/autoimprove run` completion flow.
- **All docs show "no changes needed" despite major changes:** This happens when the diff was from a merge commit or a branch that doesn't touch doc-relevant paths. Confirm the diff range with `git diff <from>..<to> --stat` before running the skill.

---

# 📋 Constraints

- **Diff-only**: NEVER read full source files. The git diff is the only input to subagents.
- **Patch, don't regenerate**: Update affected sections, not entire documents.
- **Minimal reads**: Only read doc files that need updating. Never inventory the whole repo.
- **No --all flag**: Full regeneration is intentionally unsupported — it's a token trap.
- **Scale checks only on add/delete**: Don't count artifacts unless the diff added or removed a file.

---

# 📝 Notes

- This skill is designed for the post-commit hook: `git commit` → autoimprove detects it → docs-regenerate runs automatically. If the hook is not wired, run the skill manually after each milestone.
- The diff-only constraint exists to prevent context flooding. A single source file diff is usually under 100 lines; the corresponding doc patch is under 50. Reading full source files for a doc update is a 10x token waste with no quality benefit.
- When multiple skills or commands change in one commit, each subagent handles one doc file — they work in parallel where possible.
- If `docs/` does not yet exist, the skill creates it with `mkdir -p docs` before writing. This is safe on first use.
- The skill is stateless — it does not track which docs it has previously updated. Every run is based solely on the provided diff range.
- For large refactors that touch many files, pass a focused diff range (e.g., `--from feature-branch --to HEAD`) rather than defaulting to `HEAD~1 HEAD` to avoid processing an overwhelming change set.
- The skill never deletes doc sections — it only patches or appends. Removing stale documentation must be done manually.
- Skills, commands, and agents all map to distinct doc sections. The mapping is determined by file path prefix (`skills/`, `commands/`, `agents/`).
- If `docs/skills.md` does not have a section for a skill yet, the subagent creates it rather than skipping the update.
