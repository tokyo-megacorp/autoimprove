# Rubric: Authoring Hygiene

**Version:** 1.0.0
**Applies to:** discipline-enforcing, reference, technique, pattern

Skills are not only judged by the quality of their procedure or judgment. They also need to be discoverable, structurally valid, and maintainable as plugin assets.

## Dimensions

### 1. Discovery Contract (REQUIRED)

**Score criteria:**
- 0: Missing or invalid frontmatter; skill may not load at all
- 3: Frontmatter exists but core fields are malformed, misleading, or inconsistent with the directory name
- 5: `name` and `description` exist, but discovery cues are weak or ambiguous
- 7: `name` is stable and directory-aligned; description clearly states what the skill does and when to use it
- 10: Discovery is precise and low-ambiguity: name, directory, and description all align; trigger language avoids overlap and accidental misfires

**Test generation:**
- Unit prompt: "When should this skill activate?"
- Trigger prompt: "What request patterns should match this skill, and what should not?"

**Transform rules:**
- Repair or add YAML frontmatter before changing anything else
- Align `name` with the directory basename in kebab-case
- Rewrite `description` to include both capability and activation context
- Remove vague descriptions like "helps with X" unless followed by explicit trigger language

### 2. Structural Compatibility (REQUIRED)

**Score criteria:**
- 0: Authoring violates platform constraints or common discovery invariants
- 3: Mostly valid, but contains one or more footguns that can break installation or discovery
- 5: Structurally valid, but conventions are inconsistent or underspecified
- 7: File shape and references follow stable conventions; no obvious discovery or portability footguns
- 10: Structure is robust across platforms and installation modes; constraints and file-layout assumptions are explicit

**Test generation:**
- Unit prompt: "What structural assumptions does this skill rely on?"
- Pressure prompt: "If this skill is moved or installed elsewhere, what breaks?"

**Transform rules:**
- Replace brittle path assumptions with stable skill-local references where possible
- Make file-layout assumptions explicit in prerequisites or notes
- Remove discovery footguns such as conflicting names or unclear ownership of helper files

### 3. Progressive Disclosure Discipline (RECOMMENDED)

**Score criteria:**
- 0: Everything is inline; the skill is bloated and hard to scan
- 3: Some sectioning exists, but detail still overwhelms the main path
- 5: Large sections are present but loosely organized
- 7: Main path stays scannable; dense detail is pushed into sibling files, examples, or references
- 10: The skill is optimized for activation-time readability: concise main flow, clear quick links, and heavy detail only where needed

**Test generation:**
- Unit prompt: "Can I understand the main workflow by scanning the top-level sections only?"
- Unit prompt: "Where would I look for deeper examples or edge cases?"

**Transform rules:**
- Move bulky examples, schemas, and auxiliary detail into sibling files
- Add a "Quick Links" section when support files exist or should exist
- Compress repeated warnings into a single directive section instead of scattering them inline

### 4. Maintenance Signal (RECOMMENDED)

**Score criteria:**
- 0: No hints about how this skill should evolve or be validated
- 3: Mentions validation loosely, but no concrete maintenance signal
- 5: Some validation or review guidance exists
- 7: The skill tells future modifiers how to validate changes and what should stay stable
- 10: Maintenance boundaries are explicit: validation path, invariants, and likely failure modes are all easy to recover

**Test generation:**
- Unit prompt: "If I modify this skill, how do I know I didn't break it?"
- Unit prompt: "What invariants or boundaries should future editors preserve?"

**Transform rules:**
- Add a concise validation note or related command/test pointer
- Surface invariants that future modifiers should preserve
- Make likely failure modes explicit instead of relying on tribal knowledge
