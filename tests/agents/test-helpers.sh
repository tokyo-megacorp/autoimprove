#!/usr/bin/env bash
# Helper functions for autoimprove agent tests

AGENTS_DIR="$(cd "$(dirname "$0")/../../agents" && pwd)"

# Model for tests — haiku is cheapest and sufficient for structure/schema checks.
# Override: TEST_MODEL=sonnet bash tests/agents/run-tests.sh
TEST_MODEL="${TEST_MODEL:-haiku}"

# Extract system prompt from agent .md file (strips YAML frontmatter)
get_system_prompt() {
    local agent_file="$1"
    awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$agent_file"
}

# Run claude in headless mode with agent system prompt + scenario injected inline
# Usage: run_as_agent "agents/judge.md" "scenario text" [timeout_seconds]
run_as_agent() {
    local agent_file="$AGENTS_DIR/$1"
    local scenario="$2"
    local timeout="${3:-90}"

    local system_prompt
    system_prompt=$(get_system_prompt "$agent_file")

    local prompt="You must follow these instructions EXACTLY:

${system_prompt}

---

${scenario}"

    claude -p "$prompt" --model "$TEST_MODEL" --output-format text 2>/dev/null
}

# Extract first JSON object from output (handles prose around the JSON)
extract_json() {
    local output="$1"
    echo "$output" | python3 -c "
import sys, json, re
text = sys.stdin.read()
# find first {...} block
match = re.search(r'\{.*\}', text, re.DOTALL)
if match:
    try:
        obj = json.loads(match.group())
        print(json.dumps(obj))
    except json.JSONDecodeError:
        sys.exit(1)
else:
    sys.exit(1)
"
}

# Assert JSON field equals expected value
# Usage: assert_json_field "$output" "field" "expected_value" "test name"
assert_json_field() {
    local output="$1"
    local field="$2"
    local expected="$3"
    local test_name="${4:-test}"

    local json
    if ! json=$(extract_json "$output"); then
        echo "  [FAIL] $test_name: output is not valid JSON"
        echo "  Output: $(echo "$output" | head -5)"
        return 1
    fi

    local actual
    actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$field', '__MISSING__'))" 2>/dev/null)

    if [ "$actual" = "$expected" ]; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Field '$field': expected '$expected', got '$actual'"
        return 1
    fi
}

# Assert JSON output is valid and contains a key
# Usage: assert_json_has_key "$output" "key" "test name"
assert_json_has_key() {
    local output="$1"
    local key="$2"
    local test_name="${3:-test}"

    local json
    if ! json=$(extract_json "$output"); then
        echo "  [FAIL] $test_name: output is not valid JSON"
        return 1
    fi

    local val
    val=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print('present' if '$key' in d else 'missing')" 2>/dev/null)

    if [ "$val" = "present" ]; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name: key '$key' not found in JSON"
        return 1
    fi
}

# Assert a JSON array field has a specific length
# Usage: assert_json_array_length "$output" "field" expected_length "test name"
assert_json_array_length() {
    local output="$1"
    local field="$2"
    local expected="$3"
    local test_name="${4:-test}"

    local json
    if ! json=$(extract_json "$output"); then
        echo "  [FAIL] $test_name: output is not valid JSON"
        return 1
    fi

    local actual
    actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); arr=d.get('$field'); print(len(arr) if isinstance(arr,list) else -1)" 2>/dev/null)

    if [ "$actual" = "$expected" ]; then
        echo "  [PASS] $test_name (length=$actual)"
        return 0
    else
        echo "  [FAIL] $test_name: expected '$field' length $expected, got $actual"
        return 1
    fi
}

# Assert output contains a text pattern
assert_contains() {
    local output="$1"
    local pattern="$2"
    local test_name="${3:-test}"

    if echo "$output" | grep -qi "$pattern"; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name: pattern '$pattern' not found"
        echo "  Output: $(echo "$output" | head -5)"
        return 1
    fi
}

export -f get_system_prompt run_as_agent extract_json assert_json_field assert_json_has_key assert_json_array_length assert_contains
export AGENTS_DIR TEST_MODEL
