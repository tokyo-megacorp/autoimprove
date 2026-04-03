#!/usr/bin/env bash
# Scaffold a test file for an autoimprove skill or agent.
# Usage: ./scaffold-test.sh skill <skill-name>
#        ./scaffold-test.sh agent <agent-name>
#
# Creates:
#   test/skills/test-<name>.sh       (for skills)
#   test/agents/test-<name>.sh       (for agents)
#   test/skills/test-helpers.sh      (if not present)
#   test/agents/test-helpers.sh      (if not present)
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
TEST_DIR="$REPO_ROOT/test/${TYPE}s"
TEST_FILE="$TEST_DIR/test-${NAME}.sh"
HELPERS_FILE="$TEST_DIR/test-helpers.sh"

mkdir -p "$TEST_DIR"

# ── Write test-helpers.sh (if not present) ─────────────────────────────────
if [ ! -f "$HELPERS_FILE" ]; then
cat > "$HELPERS_FILE" << 'HELPERS_EOF'
#!/usr/bin/env bash
# Shared helpers for autoimprove skill/agent tests.
# Cross-platform (macOS + Linux) — no GNU timeout dependency.

TEST_MODEL="${TEST_MODEL:-haiku}"
PLUGIN_DIR="${PLUGIN_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Run claude with a natural language prompt, capture text output.
# Usage: run_claude "In the X skill, what is Y?" [max_turns]
run_claude() {
    local prompt="$1"
    local max_turns="${2:-3}"
    claude -p "$prompt" \
        --model "$TEST_MODEL" \
        --output-format text \
        --max-turns "$max_turns" \
        2>/dev/null
}

# Run triggering test — loads plugin, captures stream-json log file path.
# Usage: log=$(run_with_plugin "natural language prompt")
run_with_plugin() {
    local prompt="$1"
    local max_turns="${2:-3}"
    local log
    log=$(mktemp)
    claude -p "$prompt" \
        --model "$TEST_MODEL" \
        --plugin-dir "$PLUGIN_DIR" \
        --dangerously-skip-permissions \
        --max-turns "$max_turns" \
        --verbose \
        --output-format stream-json \
        > "$log" 2>&1
    echo "$log"
}

# Assert output contains pattern (case-insensitive regex).
assert_contains() {
    local output="$1"
    local pattern="$2"
    local name="${3:-test}"
    if echo "$output" | grep -qiE "$pattern"; then
        echo "  [PASS] $name"
        return 0
    else
        echo "  [FAIL] $name"
        echo "         expected: $pattern"
        echo "         got: $(echo "$output" | head -3)"
        return 1
    fi
}

# Assert output does NOT contain pattern.
assert_not_contains() {
    local output="$1"
    local pattern="$2"
    local name="${3:-test}"
    if echo "$output" | grep -qiE "$pattern"; then
        echo "  [FAIL] $name (pattern found but should not be)"
        echo "         found: $pattern"
        echo "         in: $(echo "$output" | grep -iE "$pattern" | head -1)"
        return 1
    else
        echo "  [PASS] $name"
        return 0
    fi
}

# Assert pattern_a appears before pattern_b in output.
assert_order() {
    local output="$1"
    local pattern_a="$2"
    local pattern_b="$3"
    local name="${4:-order test}"
    local line_a line_b
    line_a=$(echo "$output" | grep -niE "$pattern_a" | head -1 | cut -d: -f1)
    line_b=$(echo "$output" | grep -niE "$pattern_b" | head -1 | cut -d: -f1)
    if [ -n "$line_a" ] && [ -n "$line_b" ] && [ "$line_a" -lt "$line_b" ]; then
        echo "  [PASS] $name"
        return 0
    else
        echo "  [FAIL] $name"
        echo "         expected '$pattern_a' (line $line_a) before '$pattern_b' (line $line_b)"
        return 1
    fi
}

# Assert a skill was triggered in a stream-json log file.
assert_skill_triggered() {
    local log="$1"
    local skill="$2"
    local name="${3:-skill triggered}"
    local pattern='"skill":"([^"]*:)?'"$skill"'"'
    if grep -q '"name":"Skill"' "$log" && grep -qE "$pattern" "$log"; then
        echo "  [PASS] $name"
        return 0
    else
        echo "  [FAIL] $name"
        echo "         skills that fired: $(grep -o '"skill":"[^"]*"' "$log" | sort -u)"
        return 1
    fi
}

# Assert no tool use happened before the first Skill tool call.
assert_no_premature_work() {
    local log="$1"
    local name="${2:-no premature work}"
    local first_skill_line
    first_skill_line=$(grep -n '"name":"Skill"' "$log" | head -1 | cut -d: -f1)
    if [ -z "$first_skill_line" ]; then
        echo "  [FAIL] $name (skill never called)"
        return 1
    fi
    local premature
    premature=$(head -n "$first_skill_line" "$log" | \
        grep '"type":"tool_use"' | \
        grep -v '"name":"Skill"' | \
        grep -v '"name":"TodoWrite"')
    if [ -n "$premature" ]; then
        echo "  [FAIL] $name"
        echo "         tool use before skill load: $(echo "$premature" | head -1)"
        return 1
    else
        echo "  [PASS] $name"
        return 0
    fi
}

# Track pass/fail counts. Call record $? after each assertion block.
PASS=0; FAIL=0
record() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi; }

summary() {
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ]
}
HELPERS_EOF
chmod +x "$HELPERS_FILE"
echo "Wrote: $HELPERS_FILE"
fi

# ── Write test skeleton ─────────────────────────────────────────────────────
if [ -f "$TEST_FILE" ]; then
    echo "Already exists: $TEST_FILE (skipping — delete to regenerate)"
    exit 0
fi

if [ "$TYPE" = "skill" ]; then
cat > "$TEST_FILE" << SKELETON_EOF
#!/usr/bin/env bash
# Tests for the ${NAME} skill.
# Pattern: natural language questions about skill content + triggering tests.
# Run: bash $TEST_FILE
set -uo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
source "\$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: ${NAME} skill ==="
echo ""

# ── Unit tests (ask knowledge questions about skill content) ────────────────
# TODO: Replace these placeholders with real claims from skills/${NAME}/SKILL.md

echo "Test 1: [replace with a behavioral claim from the skill]"
output=\$(run_claude "In the ${NAME} skill, what is [specific behavior]?" 3)
assert_contains "\$output" "expected pattern" "claim description"
record \$?

echo ""
echo "Test 2: [replace with another behavioral claim]"
output=\$(run_claude "Does the ${NAME} skill require [X]? What should [Y] do?" 3)
assert_contains "\$output" "expected pattern" "claim description"
record \$?

echo ""
echo "Test 3: [replace with an ordering or sequencing claim]"
output=\$(run_claude "In ${NAME}, what comes first: [A] or [B]?" 3)
assert_order "\$output" "pattern_a" "pattern_b" "[A] before [B]"
record \$?

echo ""

# ── Triggering tests (natural language — NO skill name in prompt) ───────────
# TODO: Replace with real prompts a user would type without knowing the skill exists.
# CHEAT MODE: "use the ${NAME} skill" — do not use
# REAL TEST:  "[natural user intent that should trigger this skill]"

echo "Test 4: [natural language triggering prompt]"
log=\$(run_with_plugin "[replace: natural user query without skill name]")
assert_skill_triggered "\$log" "${NAME}" "triggers on natural query"
record \$?
rm -f "\$log"

echo ""
echo "Test 5: negative — unrelated prompt should NOT trigger"
log=\$(run_with_plugin "what is a binary search tree?")
# assert_not_skill_triggered "\$log" "${NAME}" "no trigger on unrelated prompt"
record 0  # TODO: implement negative assertion
rm -f "\$log"

echo ""

summary
SKELETON_EOF

else
# Agent skeleton
cat > "$TEST_FILE" << SKELETON_EOF
#!/usr/bin/env bash
# Tests for the ${NAME} agent.
# Pattern: inject system prompt + scenario, assert on JSON output.
# Run: bash $TEST_FILE
set -uo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
source "\$SCRIPT_DIR/test-helpers.sh"

AGENT_FILE="\$(cd "\$SCRIPT_DIR/../.." && pwd)/agents/${NAME}.md"

echo "=== Test: ${NAME} agent ==="
echo ""

# Helper: strip YAML frontmatter and run as agent with injected system prompt
run_as_agent() {
    local agent_file="\$1"
    local scenario="\$2"
    local system_prompt
    system_prompt=\$(awk '/^---/{found++; if(found==2){p=1; next}} p' "\$agent_file")
    claude -p "\$system_prompt

---

\$scenario" --model "\$TEST_MODEL" --output-format text 2>/dev/null
}

# TODO: Replace with real scenarios from the agent's expected inputs

echo "Test 1: [replace with a scenario description]"
output=\$(run_as_agent "\$AGENT_FILE" "
[Replace with a concrete input scenario that forces deterministic output.
Be specific enough that the agent has no ambiguity.]
Respond with only the JSON object.
")
assert_contains "\$output" '"[expected_field]"' "[field] present in output"
record \$?

echo ""

summary
SKELETON_EOF
fi

chmod +x "$TEST_FILE"
echo "Wrote: $TEST_FILE"
echo ""
echo "Next: fill in the TODO placeholders in $TEST_FILE"
echo "      Read the source at: $([ "$TYPE" = "skill" ] && echo "skills/$NAME/SKILL.md" || echo "agents/$NAME.md")"
