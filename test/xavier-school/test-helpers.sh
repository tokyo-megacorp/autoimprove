#!/usr/bin/env bash
# Xavier School — Agent Test Helpers
# Shared functions for agent output validation.

set -uo pipefail

TEST_MODEL="${TEST_MODEL:-haiku}"
PASS_COUNT=0
FAIL_COUNT=0

run_as_agent() {
  local agent_file="$1" scenario="$2" timeout="${3:-120}"
  local agent_dir
  agent_dir="$(cd "$(dirname "$0")/../.." && pwd)/agents"

  # Strip YAML frontmatter
  local system_prompt
  system_prompt=$(awk 'BEGIN{skip=0} /^---$/{skip++;next} skip<2{next} {print}' "$agent_dir/$agent_file")

  local prompt="$system_prompt

---

$scenario"

  timeout "$timeout" claude -p "$prompt" --model "$TEST_MODEL" --output-format text 2>/dev/null
}

extract_json() {
  # Extract first JSON object from mixed output
  local input="$1"
  echo "$input" | sed -n '/^{/,/^}/p' | head -1
  # Fallback: try to find JSON anywhere in output
  if [ $? -ne 0 ]; then
    echo "$input" | grep -o '{.*}' | head -1
  fi
}

assert_json_field() {
  local json="$1" field="$2" expected="$3" test_name="$4"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$field',''))" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    echo "  [PASS] $test_name"
    ((PASS_COUNT++))
  else
    echo "  [FAIL] $test_name (expected '$expected', got '$actual')"
    ((FAIL_COUNT++))
  fi
}

assert_json_has_key() {
  local json="$1" key="$2" test_name="$3"
  if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); assert '$key' in d" 2>/dev/null; then
    echo "  [PASS] $test_name"
    ((PASS_COUNT++))
  else
    echo "  [FAIL] $test_name (key '$key' not found)"
    ((FAIL_COUNT++))
  fi
}

report() {
  echo ""
  echo "========================================="
  echo " Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  echo "========================================="
  [ "$FAIL_COUNT" -eq 0 ]
}
