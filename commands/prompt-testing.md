---
name: autoimprove-prompt-testing
description: Write tests for Claude Code skills and agents — triggering tests, unit tests, agent output tests, and integration tests.
argument-hint: "[skill-name | agent-name | all]"
---

Invoke the `autoimprove:prompt-testing` skill now. Do not do any work before the skill loads.

Arguments: $ARGUMENTS

---

## Arguments

| Argument | Description |
|----------|-------------|
| `skill-name` | Name of a specific skill to write tests for (e.g., `run`, `report`, `idea-matrix`). |
| `agent-name` | Name of a specific agent to write tests for (e.g., `judge`, `enthusiast`, `adversary`). |
| `all` | Scaffold tests for every skill and agent in the project. |

Omitting the argument writes tests for the component most recently discussed in the conversation.

## Usage Examples

```
# Write tests for the 'run' skill
/prompt-testing run

# Write tests for the judge agent
/prompt-testing judge

# Scaffold tests for everything
/prompt-testing all

# Ask the skill what tests to write (infers from context)
/prompt-testing
```

## The Four Test Types

| Type | What it verifies | Speed |
|------|-----------------|-------|
| **Unit** | Skill doc contains correct content and teaches right behavior | 30–60s |
| **Agent** | Agent produces correct structured output for a given scenario | 60–120s |
| **Triggering** | A natural user prompt causes the correct skill to fire | 60–180s |
| **Explicit request** | Named invocation fires AND no work happens before the skill loads | 60–180s |

The skill selects the right test type(s) automatically. You can also request a specific type: "write a triggering test for the report skill".

## Output

Test files are written to:

```
tests/
  agents/
    test-helpers.sh          ← shared assertion helpers
    run-tests.sh             ← test runner
    test-<agent-name>.sh     ← one file per agent
  skills/
    test-helpers.sh
    run-tests.sh
    test-<skill-name>.sh     ← one file per skill
```

Existing `test-helpers.sh` files are reused — the skill checks before writing new helpers.

## Key Rules

- All triggering tests use `--output-format stream-json` — never self-reported JSON.
- All tests run with `--model haiku` by default (override with `TEST_MODEL=sonnet`).
- Negative tests (prompts that must NOT trigger the skill) are always included.
- `set -e` is never used in test runners — failures are collected via `record()`, not by aborting.
- `timeout` is not used on macOS (not available without GNU coreutils).

## When to Use

- After writing a new skill or agent, to verify it triggers correctly.
- After modifying triggering descriptions or examples in a skill's frontmatter.
- When a skill starts misfiring — use a triggering test to pin the regression.
- Before releasing a plugin version, to verify the full test suite passes.

## Related Commands

- `/docs-regenerate` — update docs after skills or agents change
- `/autoimprove run` — run the experiment loop that may change skills and agents being tested
