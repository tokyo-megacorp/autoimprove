#!/usr/bin/env bash
# Shared helpers for autoimprove skill tests

PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Model for tests — haiku is cheapest and sufficient for triggering checks.
# Override: TEST_MODEL=sonnet bash tests/skills/run-tests.sh
TEST_MODEL="${TEST_MODEL:-haiku}"

# Run claude headless, text output — for unit tests
run_claude() {
    local prompt="$1"
    local timeout="${2:-60}"
    claude -p "$prompt" --model "$TEST_MODEL" --output-format text 2>/dev/null
}

# Run claude with plugin loaded, stream-json — for triggering/explicit tests
# Usage: run_with_plugin "prompt" [max_turns] [timeout]
run_with_plugin() {
    local prompt="$1"
    local max_turns="${2:-3}"
    local timeout="${3:-120}"
    local log
    log=$(mktemp)

    claude -p "$prompt" \
        --model "$TEST_MODEL" \
        --plugin-dir "$PLUGIN_DIR" \
        --dangerously-skip-permissions \
        --max-turns "$max_turns" \
        --verbose \
        --output-format stream-json \
        > "$log" 2>&1 || true

    echo "$log"  # return path, caller reads and deletes
}

# Assert output contains pattern (case-insensitive)
assert_contains() {
    local output="$1" pattern="$2" test_name="${3:-test}"
    if echo "$output" | grep -qi "$pattern"; then
        echo "  [PASS] $test_name"; return 0
    else
        echo "  [FAIL] $test_name: '$pattern' not found"
        echo "  Output: $(echo "$output" | head -3)"; return 1
    fi
}

# Assert skill fired in a stream-json log
# Usage: assert_skill_triggered "$log_file" "skill-name" "test name"
assert_skill_triggered() {
    local log="$1" skill="$2" test_name="${3:-test}"
    local pattern='"skill":"([^"]*:)?'"${skill}"'"'
    if grep -q '"name":"Skill"' "$log" && grep -qE "$pattern" "$log"; then
        echo "  [PASS] $test_name"; return 0
    else
        echo "  [FAIL] $test_name: skill '$skill' not triggered"
        echo "  Skills fired: $(grep -o '"skill":"[^"]*"' "$log" 2>/dev/null | sort -u || echo none)"
        return 1
    fi
}

# Assert skill did NOT fire in a stream-json log
assert_skill_not_triggered() {
    local log="$1" skill="$2" test_name="${3:-test}"
    local pattern='"skill":"([^"]*:)?'"${skill}"'"'
    if grep -q '"name":"Skill"' "$log" && grep -qE "$pattern" "$log"; then
        echo "  [FAIL] $test_name: skill '$skill' triggered but should not have"
        return 1
    else
        echo "  [PASS] $test_name"; return 0
    fi
}

# Assert no tool use happened before the first Skill invocation
assert_no_premature_work() {
    local log="$1" test_name="${2:-no premature work}"
    local first_skill_line
    first_skill_line=$(grep -n '"name":"Skill"' "$log" | head -1 | cut -d: -f1)

    if [ -z "$first_skill_line" ]; then
        echo "  [SKIP] $test_name: no Skill invocation found"; return 0
    fi

    local premature
    premature=$(head -n "$first_skill_line" "$log" | \
        grep '"type":"tool_use"' | \
        grep -v '"name":"Skill"' | \
        grep -v '"name":"TodoWrite"' || true)

    if [ -n "$premature" ]; then
        echo "  [FAIL] $test_name: tool use before skill loaded:"
        echo "$premature" | head -3 | sed 's/^/    /'; return 1
    else
        echo "  [PASS] $test_name"; return 0
    fi
}

export -f run_claude run_with_plugin assert_contains assert_skill_triggered assert_skill_not_triggered assert_no_premature_work
export PLUGIN_DIR TEST_MODEL
