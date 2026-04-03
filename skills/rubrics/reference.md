# Rubric: Reference Skills

**Version:** 1.0.0
**Applies to:** reference (API docs, syntax guides, lookup tables)

Skills that serve as lookup references — users consult them for specific information, not process guidance.

## Dimensions

### 1. Procedural Completeness (REQUIRED)

**Score criteria:**
- 0: Information scattered, hard to find specific answers
- 3: Organized but missing common lookup scenarios
- 5: Covers common scenarios, some gaps in edge cases
- 7: Complete coverage with clear headings, searchable structure
- 10: Every common query answerable by scanning headings. Index/TOC present. Cross-references link related sections.

**Test generation:**
- Unit prompt: "How do I [common task in skill domain]?"
- Unit prompt: "What is the syntax for [specific feature]?"

**Transform rules:**
- Add table of contents if > 3 sections
- Convert prose paragraphs to structured tables where data is tabular
- Add cross-references between related sections
- Ensure every heading is scannable (noun phrase, not sentence)

### 2. Examples (REQUIRED)

**Score criteria:**
- 0: No code/usage examples
- 3: Abstract examples without real values
- 5: Real examples but only happy path
- 7: Real examples covering happy path + common errors
- 10: Minimal, copyable examples for every documented feature. Each example shows input, output, and one common mistake.

**Test generation:**
- Unit prompt: "Show me an example of [feature]"
- Unit prompt: "What happens if I use [feature] incorrectly?"

**Transform rules:**
- Add code block for every feature without one
- Each example: show correct usage + one common mistake
- Examples must be copyable (no placeholder values like "your-api-key")
- Add "Common mistake:" callout after examples where errors are likely

### 3. Failure Modes (REQUIRED)

**Score criteria:**
- 0: No error documentation
- 3: Some errors mentioned in passing
- 5: Error section exists but incomplete
- 7: Table: | Error | Cause | Fix | for common failures
- 10: Comprehensive error catalog with: error message, root cause, fix, and prevention

**Test generation:**
- Unit prompt: "What errors can [feature] produce?"
- Unit prompt: "I got error [X], what does it mean?"

**Transform rules:**
- Add error table: | Error | Cause | Fix |
- Minimum 3 entries for any documented feature
- Include exact error messages where possible
- Add "Prevention:" line for each fixable error
