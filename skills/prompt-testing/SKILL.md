---
name: prompt-testing
description: "Use when writing tests for Claude Code skills or agents. Examples:

<example>
user: \"how do I test if my skill triggers correctly?\"
assistant: I'll use the prompt-testing skill to write triggering tests.
<commentary>Skill triggering tests — prompt-testing.</commentary>
</example>

<example>
user: \"write tests for the judge agent\"
assistant: I'll use the prompt-testing skill to write agent output tests.
<commentary>Agent output testing — prompt-testing.</commentary>
</example>

<example>
user: \"create a test suite for my plugin\"
assistant: I'll use the prompt-testing skill to scaffold the test suite.
<commentary>Plugin test scaffolding — prompt-testing.</commentary>
</example>

Do NOT use for testing regular code — only for plugin components. Do NOT use to run tests (use the test skill)."
argument-hint: "[<skill-name>|<agent-name>] [--type unit|agent|triggering|explicit|integration]"
allowed-tools: [Read, Write, Bash, Glob, Grep]
---

# Prompt Testing

## Overview

Claude Code skills and agents are tested by running `claude -p` in headless mode and asserting on the output. There are four test types — using the wrong one is the most common mistake.

**Core principles:**
1. Never use self-reported JSON (`{"invoke": true}`) to test triggering. Claude says "yes" even when the Skill tool wouldn't actually fire. Only `--output-format stream-json` tells you what actually happened.
2. Always use `--model haiku` for prompt tests. Triggering tests only verify tool dispatch, not output quality — haiku is ~60x cheaper than Opus and sufficient. Expose via `TEST_MODEL` env var for override.

---

## The Four Test Types

```dot
digraph test_types {
    "What do I want to verify?" [shape=diamond];
    "Skill content is correct" [shape=diamond];
    "Does the skill fire?" [shape=diamond];
    "Unit test\n(claude -p + text assert)" [shape=box];
    "Agent produces correct output?" [shape=diamond];
    "Agent test\n(inject system prompt + JSON assert)" [shape=box];
    "User names skill explicitly?" [shape=diamond];
    "Explicit request test\n(stream-json + premature-action check)" [shape=box];
    "Triggering test\n(stream-json + skill grep)" [shape=box];
    "Full workflow correct?" [shape=box, label="Integration test\n(run skill, check artifacts)"];

    "What do I want to verify?" -> "Skill content is correct";
    "What do I want to verify?" -> "Does the skill fire?";
    "What do I want to verify?" -> "Agent produces correct output?";
    "What do I want to verify?" -> "Full workflow correct?";

    "Skill content is correct" -> "Unit test\n(claude -p + text assert)";
    "Agent produces correct output?" -> "Agent test\n(inject system prompt + JSON assert)";
    "Does the skill fire?" -> "User names skill explicitly?";
    "User names skill explicitly?" -> "Explicit request test\n(stream-json + premature-action check)" [label="yes"];
    "User names skill explicitly?" -> "Triggering test\n(stream-json + skill grep)" [label="no, naive prompt"];
    "Full workflow correct?" -> "Integration test\n(run skill, check artifacts)";
}
```

| Type | Mechanism | Speed | Use when |
|------|-----------|-------|----------|
| **Unit** | `claude -p "question"` + text grep | 30–60s | Verifying skill content says the right things |
| **Agent** | inject system prompt + JSON assertions | 60–120s | Verifying agent output schema and correctness |
| **Triggering** | `stream-json` + `"name":"Skill"` grep | 60–180s | Verifying a naive prompt fires the right skill |
| **Explicit request** | `stream-json` + premature-action check | 60–180s | Verifying named invocation fires + no work before load |
| **Integration** | Run full skill, check artifacts | 10–30min | End-to-end workflow verification |

---

## File Structure

```
tests/
  agents/
    test-helpers.sh          ← shared assertion library
    run-tests.sh             ← test runner
    test-<agent-name>.sh     ← one file per agent
  skills/
    test-helpers.sh          ← shared helpers (stream-json version)
    run-tests.sh
    test-<skill-name>.sh     ← one file per skill
```

Always check if `test-helpers.sh` already exists before writing new helpers — follow the established pattern.

---

## Type 1: Unit Test

Tests that the skill document contains the right content and teaches the right behavior.

```bash
source ./test-helpers.sh

output=$(run_claude "In the review skill, what round count is used for a 50-line file?")

assert_contains "$output" "2 rounds\|two rounds" "50-line file → 2 rounds"
assert_contains "$output" "50.*199\|50-199" "references the correct range"
```

`run_claude` is `claude -p "$prompt" --model "$TEST_MODEL" --output-format text`.

---

## Type 2: Agent Test

Tests that an agent produces correct structured output for a given scenario. Inject the system prompt inline — do NOT rely on the plugin being loaded.

```bash
source ./test-helpers.sh

# run_as_agent strips frontmatter and injects system prompt + scenario
output=$(run_as_agent "judge.md" "
Round 1. No prior rulings.
<code>...</code>
<findings>...</findings>
<verdicts>...</verdicts>
Respond with only the JSON ruling object.
" 90)

assert_json_field "$output" "convergence" "False" "convergence=false on round 1"
assert_json_has_key "$output" "rulings" "rulings key present"
assert_json_array_length "$output" "rulings" "1" "one ruling per finding"
```

`run_as_agent` uses awk to strip YAML frontmatter, then calls `claude -p "system_prompt\n\n---\n\nscenario"`.

**Never use self-report JSON** (`{"would_you_trigger": true}`) — Claude answers based on what sounds correct, not what the Skill tool would actually do.

---

## Type 3: Triggering Test

Tests that a natural user prompt causes the correct skill to fire. Requires `--output-format stream-json` — this is the only reliable mechanism.

```bash
PLUGIN_DIR="/path/to/plugin"
SKILL_NAME="review"
PROMPT="run a review round on my code"

LOG=$(mktemp)
claude -p "$PROMPT" \
    --model "$TEST_MODEL" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --max-turns 3 \
    --verbose \
    --output-format stream-json \
    > "$LOG" 2>&1

# Check skill fired
SKILL_PATTERN='"skill":"([^"]*:)?'"${SKILL_NAME}"'"'
if grep -q '"name":"Skill"' "$LOG" && grep -qE "$SKILL_PATTERN" "$LOG"; then
    echo "  [PASS] skill triggered"
else
    echo "  [FAIL] skill NOT triggered"
    echo "  Skills that fired: $(grep -o '"skill":"[^"]*"' "$LOG" | sort -u)"
fi
```

**Why stream-json**: The JSONL output captures every tool invocation. `"name":"Skill"` appears when the Skill tool is called. The `skill` field contains the skill name. Text output alone cannot tell you whether the Skill tool fired.

**Negative tests matter**: Also test prompts that should NOT trigger the skill (`run the test suite`, `start the grind loop`) to verify the skill isn't over-eager.

---

## Type 4: Explicit Request Test

Tests that when a user names the skill directly, it fires AND no work happens before it loads. The premature-action check is the critical addition over a regular triggering test.

```bash
PROMPT="review, please"  # or "use the review skill", "review skill, please"

LOG=$(mktemp)
claude -p "$PROMPT" \
    --model "$TEST_MODEL" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --max-turns 3 \
    --verbose \
    --output-format stream-json \
    > "$LOG" 2>&1

# 1. Skill fired
if grep -q '"name":"Skill"' "$LOG" && grep -qE "$SKILL_PATTERN" "$LOG"; then
    echo "  [PASS] skill triggered"
else
    echo "  [FAIL] skill NOT triggered"; exit 1
fi

# 2. No premature work before skill load (the critical check)
FIRST_SKILL_LINE=$(grep -n '"name":"Skill"' "$LOG" | head -1 | cut -d: -f1)
PREMATURE=$(head -n "$FIRST_SKILL_LINE" "$LOG" | \
    grep '"type":"tool_use"' | \
    grep -v '"name":"Skill"' | \
    grep -v '"name":"TodoWrite"')

if [ -n "$PREMATURE" ]; then
    echo "  [FAIL] work happened BEFORE skill loaded:"
    echo "$PREMATURE" | head -3
else
    echo "  [PASS] no premature tool use"
fi
```

**Why premature-action detection matters**: The failure mode is Claude starts reading files or writing code before loading the skill. By the time it loads, it has already bypassed the skill's workflow instructions.

---

## Test Organization for Triggering Tests

Organize triggering tests into sections by prompt source and intent. This structure catches both known regressions and extrapolated edge cases:

| Section | Purpose | Example prompts |
|---------|---------|-----------------|
| **Real user queries** | Actual prompts from session history (lcm grep, git log) | "what do we have wip?", "what did we do last session?" |
| **Orientation variants** | Same intent, different wording — extrapolate from real patterns | "sitrep", "bring me up to speed", "fill me in" |
| **Continuation** | User resuming prior work | "pick up where we left off", "where were we?" |
| **Implementation context** | User needs prior decisions before starting work | "any decisions about the migration?" |
| **Terse/shorthand** | Power-user minimal prompts | "wip?", "status?", "updates?" |
| **Negatives** | Must NOT trigger — general knowledge, simple code gen | "what is a binary search tree?", "hello world in python" |
| **Explicit request** | Named invocation + premature-work check | "/skill-name", "use the X skill" |

**Source real test cases from actual usage.** Search lcm/git for the user's actual session-start messages. Extrapolate common wording patterns from those — don't invent test cases in a vacuum.

---

## Common Mistakes

| Mistake | Why it fails | Fix |
|---------|-------------|-----|
| `{"would_trigger": true}` for triggering tests | Claude self-reports based on reasoning, not actual tool dispatch | Use `--output-format stream-json` + `"name":"Skill"` grep |
| Missing `--plugin-dir` | Claude Code loads user's installed plugins, not the dev version | Always pass `--plugin-dir` for triggering/explicit tests |
| Missing `--dangerously-skip-permissions` | Claude Code prompts for permission confirmation in headless mode | Required for non-interactive test runs |
| Omitting `--output-format stream-json` | Text output has no record of which tools fired | Required for all triggering tests |
| Missing `--verbose` with `stream-json` | `--output-format stream-json` requires `--verbose` in print mode — silently produces empty output without it | Always pair `--verbose` with `--output-format stream-json` |
| Using `timeout` on macOS | GNU `timeout` is not available by default on macOS | Remove `timeout` or use Bash `SECONDS`-based guard; don't depend on coreutils |
| Using `set -e` in test runner | First failure kills the entire suite — you lose visibility into subsequent tests | Use `set -uo pipefail` without `-e`; collect results via `record()` |
| Skipping negative tests | Skill might trigger on everything | Test prompts that should NOT trigger |
| One giant test file | Slow and hard to debug | One test file per agent/skill |

---

## Quick Reference: Invocation Flags

```bash
# Unit / agent tests (no plugin loading needed)
claude -p "$PROMPT" --model "$TEST_MODEL" --output-format text

# Triggering / explicit request tests
claude -p "$PROMPT" \
    --model "$TEST_MODEL" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --max-turns 3 \
    --verbose \
    --output-format stream-json
```

`--max-turns 3` is enough for triggering tests — you only need to verify the skill fires, not complete the workflow.

`--model haiku` keeps costs low — triggering tests check tool dispatch, not output quality. Override with `TEST_MODEL=sonnet` when debugging failures.

---

## Real Examples

These are production tests for this plugin — read them as working reference:

- `tests/agents/test-judge.sh` — Type 2: JSON assertions on judge output (convergence, schema)
- `tests/agents/test-enthusiast.sh` — Type 2: JSON assertions on enthusiast output (schema, severity values, sequential IDs)
- `tests/agents/test-adversary.sh` — Type 2: JSON assertions on adversary output (verdict coverage)
- `tests/skills/test-review.sh` — Types 1+3+4: unit content, triggering, and explicit request tests for the review skill

Shared helpers:
- `tests/agents/test-helpers.sh` — `run_as_agent()`, `extract_json()`, `assert_json_*`
- `tests/skills/test-helpers.sh` — `run_with_plugin()`, `assert_skill_triggered()`, `assert_no_premature_work()`

---

## Debugging Failing Tests

### Triggering test fails: skill never fires

1. **Confirm the skill is loaded.** Dump all skills that fired during the test run:
   ```bash
   grep -o '"skill":"[^"]*"' "$LOG" | sort -u
   ```
   If the list is empty, the plugin directory is wrong or the skill has a syntax error in its frontmatter.

2. **Check the plugin is visible.** Run `claude --list-skills --plugin-dir "$PLUGIN_DIR"` to confirm the skill appears. If it doesn't, the `.claude-plugin/plugin.json` or the SKILL.md frontmatter is malformed.

3. **Check the description trigger text.** The skill fires based on its `description:` field in SKILL.md frontmatter. If the test prompt doesn't match the description's trigger examples, the LLM won't route to it. Add a trigger phrase that matches the test prompt.

4. **Try with a stronger model.** Haiku may not route correctly for ambiguous triggers. Run once with `TEST_MODEL=sonnet` to confirm the routing logic works before debugging the description.

5. **Inspect the full JSONL log.** The stream-json log captures every LLM decision — look for the assistant message before the failed Skill call to see what it reasoned:
   ```bash
   grep '"type":"assistant"' "$LOG" | head -3 | jq -r '.message.content[0].text // empty'
   ```

### Agent test fails: JSON assertion mismatch

1. **Print the raw output** before asserting:
   ```bash
   echo "RAW: $output"
   ```
   The most common cause is the agent produced a non-JSON preamble ("Sure, here is my verdict:") before the JSON block. Use `extract_json` from `test-helpers.sh` to strip it.

2. **Check frontmatter stripping.** `run_as_agent` strips YAML frontmatter with awk. If the agent file uses `---` inside the body (e.g., a markdown separator), awk may strip too much. Inspect what the helper actually sends as the system prompt.

3. **Verify the scenario is valid.** Agent tests inject a scenario as the user message. If the scenario is under-specified, the agent may produce valid JSON with different field values than expected. Make the scenario concrete enough to force a deterministic output.

### Test passes locally but fails in CI

- **Missing env vars.** `TEST_MODEL`, `PLUGIN_DIR`, and `ANTHROPIC_API_KEY` must be set. CI may not inherit your shell's env.
- **macOS vs Linux.** `grep -E` behavior and `awk` field separators differ. Test on both if possible; prefer POSIX constructs.
- **Flaky haiku routing.** Haiku's skill dispatch can be non-deterministic on borderline prompts. If a test is <80% reliable, either strengthen the trigger description or move the test to sonnet.

---

## When NOT to Use This Skill

- **Running tests** — use the `/autoimprove test` skill to execute existing test suites
- **Testing business logic, utilities, or regular application code** — this skill covers plugin components (skills, agents, commands) only; use your project's standard test framework for everything else
- **Benchmarking output quality** — the challenge skill measures agent accuracy with F1 scoring; prompt-testing checks behavioral correctness, not metric performance
- **Debugging a failing skill at runtime** — check `autoimprove status` and `autoimprove report` first; prompt-testing is for writing new tests, not diagnosing live session issues
