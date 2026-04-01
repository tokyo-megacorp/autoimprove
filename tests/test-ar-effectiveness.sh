#!/usr/bin/env bash
# tests/test-ar-effectiveness.sh — Smoke tests for benchmark/ar-effectiveness.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BENCHMARK="$SCRIPT_DIR/benchmark/ar-effectiveness.sh"

PASS=0
FAIL=0
TOTAL=0

assert_expr() {
  local desc="$1"
  local expr="$2"

  TOTAL=$((TOTAL + 1))
  if eval "$expr"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    Expression: $expr"
  fi
}

assert_json_field() {
  local desc="$1"
  local json="$2"
  local filter="$3"
  local expected="$4"
  local actual

  actual="$(printf '%s' "$json" | jq -r "$filter")"
  assert_expr "$desc" "[ \"$actual\" = \"$expected\" ]"
}

assert_valid_json() {
  local desc="$1"
  local json="$2"

  TOTAL=$((TOTAL + 1))
  if printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
  fi
}

assert_json_expr() {
  local desc="$1"
  local json="$2"
  local filter="$3"

  TOTAL=$((TOTAL + 1))
  if printf '%s' "$json" | jq -e "$filter" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    jq filter: $filter"
  fi
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "========================================"
echo " ar-effectiveness.sh Tests"
echo "========================================"
echo ""

echo "--- Test 1: missing Claude CLI returns sentinel JSON ---"
missing_output="$(CLAUDE_BIN=definitely-not-installed PATH="/usr/bin:/bin" bash "$BENCHMARK")"
assert_valid_json "missing CLI output is valid JSON" "$missing_output"
assert_json_field "missing CLI precision sentinel" "$missing_output" '.ar_precision' '-1'
assert_json_field "missing CLI quality sentinel" "$missing_output" '.ar_quality_score' '-1'
assert_json_field "missing CLI error message" "$missing_output" '.error' 'claude CLI not found'
echo ""

echo "--- Test 2: stubbed Claude CLI produces benchmark metrics ---"
cat > "$WORK_DIR/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

prompt=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p)
      prompt="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if printf '%s' "$prompt" | grep -qi 'code review quality judge\|return json only'; then
  echo '{"depth": 8, "accuracy": 8, "actionability": 8, "total": 24, "notes": "stub"}'
  exit 0
fi

cat <<'OUT'
high:security:stub
high:error-handling:stub
high:correctness:stub
medium:observability:stub
medium:process:stub
low:docs:stub
low:style:stub
OUT
EOF
chmod +x "$WORK_DIR/claude"

stubbed_output="$(PATH="$WORK_DIR:/usr/bin:/bin:$PATH" CLAUDE_BIN=claude TMPDIR="$WORK_DIR" bash "$BENCHMARK")"
assert_valid_json "stubbed CLI output is valid JSON" "$stubbed_output"
assert_json_field "stubbed run processes golden cases" "$stubbed_output" '.cases_run' '3'
assert_json_field "stubbed run passes all golden cases" "$stubbed_output" '.cases_passed' '3'
assert_json_expr "stubbed run yields perfect precision" "$stubbed_output" '.ar_precision == 1'
assert_json_field "stubbed run extracts judge score" "$stubbed_output" '.ar_quality_score' '24'
echo ""

echo "========================================"
echo " Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

[ "$FAIL" -eq 0 ]