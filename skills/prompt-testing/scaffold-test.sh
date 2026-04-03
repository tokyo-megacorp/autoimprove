#!/usr/bin/env bash
# Scaffold a test file for an autoimprove skill or agent.
# Usage: ./scaffold-test.sh skill <skill-name>
#        ./scaffold-test.sh agent <agent-name>
#
# Creates:
#   tests/skills/test-<name>.sh       (for skills)
#   tests/agents/test-<name>.sh       (for agents)
#
# Helpers live in tests/skills/test-helpers.sh and tests/agents/test-helpers.sh
# (already present in the repo — scaffold does NOT overwrite them).
#
# After running: fill in the assertions. The scaffold contains
# placeholder tests that FAIL until you complete them.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TYPE="${1:-}"
NAME="${2:-}"

if [ -z "$TYPE" ] || [ -z "$NAME" ]; then
    echo "Usage: $0 skill <skill-name>"
    echo "       $0 agent <agent-name>"
    exit 1
fi

if [ "$TYPE" != "skill" ] && [ "$TYPE" != "agent" ]; then
    echo "Error: type must be 'skill' or 'agent'"
    exit 1
fi

# ── Paths ──────────────────────────────────────────────────────────────────
TEST_DIR="$REPO_ROOT/tests/${TYPE}s"
TEST_FILE="$TEST_DIR/test-${NAME}.sh"
HELPERS_FILE="$TEST_DIR/test-helpers.sh"

if [ ! -f "$HELPERS_FILE" ]; then
    echo "Error: helpers not found at $HELPERS_FILE"
    echo "Expected tests/ layout: tests/skills/test-helpers.sh and tests/agents/test-helpers.sh"
    exit 1
fi

# ── Refuse to overwrite ─────────────────────────────────────────────────────
if [ -f "$TEST_FILE" ]; then
    echo "Already exists: $TEST_FILE (skipping — delete to regenerate)"
    exit 0
fi

# ── Write test skeleton ─────────────────────────────────────────────────────
if [ "$TYPE" = "skill" ]; then

SOURCE_FILE="\$PLUGIN_DIR/skills/${NAME}/SKILL.md"

cat > "$TEST_FILE" << SKELETON_EOF
#!/usr/bin/env bash
# Tests for the ${NAME} skill.
#
# Unit tests:   grep directly on SKILL_FILE — fast, deterministic, no LLM.
# Triggering:   run_with_plugin — natural language prompt, stream-json.
# Negative:     assert_skill_not_triggered — prompt that must NOT trigger this skill.
#
# Run: bash tests/skills/test-${NAME}.sh
set -uo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
source "\$SCRIPT_DIR/test-helpers.sh"

SKILL_FILE="${SOURCE_FILE}"
SKILL_NAME="${NAME}"
passed=0; failed=0

record() {
    if [ "\$1" = "pass" ]; then passed=\$((passed+1)); else failed=\$((failed+1)); fi
}

echo ""
echo "=== ${NAME} skill — Unit Tests (doc content) ==="

# ── Unit tests: grep on SKILL_FILE ─────────────────────────────────────────
# TODO: Replace each grep with a real pattern from skills/${NAME}/SKILL.md.
# Pattern: grep -q "keyword or phrase" "\$SKILL_FILE" && record pass || record fail

# Test 1: [describe the behavioral claim]
if grep -q "TODO_REPLACE_WITH_KEYWORD" "\$SKILL_FILE"; then
    echo "  [PASS] [claim description]"; record pass
else
    echo "  [FAIL] [claim description] — expected keyword not found"; record fail
fi

# Test 2: [describe another claim]
if grep -q "TODO_REPLACE_WITH_KEYWORD_2" "\$SKILL_FILE"; then
    echo "  [PASS] [claim description]"; record pass
else
    echo "  [FAIL] [claim description] — expected keyword not found"; record fail
fi

# Test 3: Do NOT use example — skill should have a negative constraint
if grep -qiE "Do NOT|NOT use|never" "\$SKILL_FILE"; then
    echo "  [PASS] negative constraints documented"; record pass
else
    echo "  [FAIL] no negative constraints found"; record fail
fi

echo ""
echo "=== ${NAME} skill — Triggering Tests ==="

# ── Triggering test: natural language — NO skill name in prompt ─────────────
# CHEAT MODE: "use the ${NAME} skill"      ← do not use
# REAL TEST:  "[intent that triggers skill without naming it]"

log=\$(run_with_plugin "TODO_REPLACE_WITH_NATURAL_LANGUAGE_PROMPT")
assert_skill_triggered "\$log" "\$SKILL_NAME" "triggers on natural language"
result=\$?; rm -f "\$log"
[ "\$result" -eq 0 ] && record pass || record fail

echo ""
echo "=== ${NAME} skill — Negative Tests ==="

# ── Negative test: must NOT trigger on unrelated prompt ────────────────────
log=\$(run_with_plugin "what is a binary search tree?")
assert_skill_not_triggered "\$log" "\$SKILL_NAME" "no trigger on unrelated query"
result=\$?; rm -f "\$log"
[ "\$result" -eq 0 ] && record pass || record fail

echo ""
echo "Results: \$passed passed, \$failed failed"
[ "\$failed" -eq 0 ] || exit 1
SKELETON_EOF

else
# Agent skeleton

SOURCE_FILE="\$PLUGIN_DIR/agents/${NAME}.md"

cat > "$TEST_FILE" << SKELETON_EOF
#!/usr/bin/env bash
# Tests for the ${NAME} agent.
# Agent tests inject system prompt + scenario, assert on JSON output.
# Run: bash tests/agents/test-${NAME}.sh
set -uo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
source "\$SCRIPT_DIR/test-helpers.sh"

AGENT_FILE="${SOURCE_FILE}"
passed=0; failed=0

record() {
    if [ "\$1" = "pass" ]; then passed=\$((passed+1)); else failed=\$((failed+1)); fi
}

echo ""
echo "=== ${NAME} agent ==="

# ── Agent test: inject system prompt + concrete scenario ────────────────────
# run_as_agent strips YAML frontmatter and runs agent with scenario as user message.

output=\$(run_as_agent "\$AGENT_FILE" "
TODO: Replace with a concrete input scenario.
Be specific enough to force deterministic output.
Respond with only the JSON object.
")

# TODO: Replace with real field assertions
if echo "\$output" | grep -q '"TODO_field"'; then
    echo "  [PASS] expected field present"; record pass
else
    echo "  [FAIL] expected field missing"
    echo "  Output: \$(echo "\$output" | head -5)"; record fail
fi

echo ""
echo "Results: \$passed passed, \$failed failed"
[ "\$failed" -eq 0 ] || exit 1
SKELETON_EOF

fi

chmod +x "$TEST_FILE"
echo "Wrote: $TEST_FILE"
echo ""
echo "Next: fill in the TODO patterns — read $([ "$TYPE" = "skill" ] && echo "skills/$NAME/SKILL.md" || echo "agents/$NAME.md") first"
