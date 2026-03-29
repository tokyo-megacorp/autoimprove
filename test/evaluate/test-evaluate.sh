#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVALUATE="$SCRIPT_DIR/../../scripts/evaluate.sh"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++)) || true
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    ((FAIL++)) || true
  fi
}

assert_json_field() {
  local desc="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | jq -r "$field")
  assert_eq "$desc" "$expected" "$actual"
}

echo "=== Gate Runner Tests ==="

echo "--- Test: all gates pass ---"
result=$("$EVALUATE" "$FIXTURES/config-gates-only.json" /dev/null 2>/dev/null)
assert_json_field "gates[0] passed" "$result" '.gates[0].passed' 'true'
assert_json_field "gates[1] passed" "$result" '.gates[1].passed' 'true'
assert_json_field "gates[0] name" "$result" '.gates[0].name' 'true-gate'

echo "--- Test: gate failure fast-fails ---"
fail_config='{"gates":[{"name":"fail-gate","command":"false"},{"name":"never-reached","command":"true"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}'
tmpconfig=$(mktemp)
echo "$fail_config" > "$tmpconfig"
result=$("$EVALUATE" "$tmpconfig" /dev/null 2>/dev/null)
assert_json_field "verdict is gate_fail" "$result" '.verdict' 'gate_fail'
assert_json_field "failed gate name" "$result" '.gates[0].name' 'fail-gate'
assert_json_field "failed gate passed=false" "$result" '.gates[0].passed' 'false'
second_gate=$(echo "$result" | jq '.gates | length')
assert_eq "only one gate ran (fast-fail)" "1" "$second_gate"
rm -f "$tmpconfig"

echo ""
echo "=== Benchmark Runner Tests ==="

bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"

echo "--- Test: init mode extracts metrics ---"
result=$("$EVALUATE" "$bench_config" /dev/null 2>/dev/null)
assert_json_field "mode is init" "$result" '.mode' 'init'
assert_json_field "score extracted" "$result" '.metrics.score' '42'
assert_json_field "speed_ms extracted" "$result" '.metrics.speed_ms' '150'

echo "--- Test: json: extractor works ---"
assert_json_field "score is number" "$result" '.metrics.score | type' 'number'

rm -f "$bench_config"

echo ""
echo "=== Scoring Tests ==="

# Test: keep verdict — both metrics improved
echo "--- Test: keep verdict (both metrics improved) ---"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
# baseline: score=40, speed_ms=160 → candidate: score=42 (+5%), speed_ms=150 (+6.25% normalized)
result=$("$EVALUATE" "$bench_config" "$FIXTURES/baseline-basic.json" 2>/dev/null)
assert_json_field "verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "score in improved" "$result" '.improved | contains(["score"])' 'true'
assert_json_field "speed_ms in improved" "$result" '.improved | contains(["speed_ms"])' 'true'
assert_json_field "regressed is empty" "$result" '.regressed | length' '0'
assert_json_field "score baseline" "$result" '.metrics.score.baseline' '40'
assert_json_field "score candidate" "$result" '.metrics.score.candidate' '42'
rm -f "$bench_config"

# Test: regress verdict — baseline score=50, candidate=42 → -16% regression
echo "--- Test: regress verdict (score regressed) ---"
regress_baseline=$(mktemp)
echo '{"metrics":{"score":50,"speed_ms":160},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$regress_baseline"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
result=$("$EVALUATE" "$bench_config" "$regress_baseline" 2>/dev/null)
assert_json_field "verdict is regress" "$result" '.verdict' 'regress'
assert_json_field "score in regressed" "$result" '.regressed | contains(["score"])' 'true'
rm -f "$bench_config" "$regress_baseline"

# Test: neutral verdict — baseline matches candidate exactly
echo "--- Test: neutral verdict (no change) ---"
neutral_baseline=$(mktemp)
echo '{"metrics":{"score":42,"speed_ms":150},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$neutral_baseline"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
result=$("$EVALUATE" "$bench_config" "$neutral_baseline" 2>/dev/null)
assert_json_field "verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "improved is empty" "$result" '.improved | length' '0'
assert_json_field "regressed is empty" "$result" '.regressed | length' '0'
rm -f "$bench_config" "$neutral_baseline"

echo ""
echo "=== Integration Tests (test-project) ==="

TEST_PROJECT="$SCRIPT_DIR/../../test-project"

# Test 1: Gate failure with real test-project (has a failing test)
echo "--- Test: gate fail with real test-project ---"
tp_gate_config=$(mktemp)
cat > "$tp_gate_config" <<EOF
{
  "gates": [
    {"name": "node-tests", "command": "cd $TEST_PROJECT && node --test test/*.test.js"}
  ],
  "benchmarks": [],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$tp_gate_config" /dev/null 2>/dev/null)
assert_json_field "tp gate_fail verdict" "$result" '.verdict' 'gate_fail'
assert_json_field "tp failing gate name" "$result" '.gates[0].name' 'node-tests'
assert_json_field "tp failing gate passed=false" "$result" '.gates[0].passed' 'false'
rm -f "$tp_gate_config"

# Test 2: Init mode with real benchmarks
echo "--- Test: init mode with real benchmark ---"
tp_bench_config=$(mktemp)
cat > "$tp_bench_config" <<EOF
{
  "gates": [
    {"name": "always-pass", "command": "true"}
  ],
  "benchmarks": [
    {
      "name": "real-metrics",
      "command": "bash $TEST_PROJECT/benchmark/metrics.sh",
      "metrics": [
        {
          "name": "test_count",
          "extract": "json:.test_count",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$tp_bench_config" /dev/null 2>/dev/null)
assert_json_field "tp init mode" "$result" '.mode' 'init'
actual_test_count=$(echo "$result" | jq -r '.metrics.test_count')
if [ "$actual_test_count" -gt 0 ] 2>/dev/null; then
  echo "  PASS: test_count > 0 (got $actual_test_count)"
  ((PASS++)) || true
else
  echo "  FAIL: test_count > 0 (got $actual_test_count)"
  ((FAIL++)) || true
fi

# Test 3: Scoring against real baseline (neutral — no change)
echo "--- Test: neutral verdict against real baseline ---"
# Use the same bench config from test 2 — run init to capture current metrics
init_result=$("$EVALUATE" "$tp_bench_config" /dev/null 2>/dev/null)
raw_test_count=$(echo "$init_result" | jq -r '.metrics.test_count')
tp_baseline=$(mktemp)
cat > "$tp_baseline" <<EOF
{"metrics":{"test_count":$raw_test_count},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}
EOF
result=$("$EVALUATE" "$tp_bench_config" "$tp_baseline" 2>/dev/null)
assert_json_field "tp neutral verdict" "$result" '.verdict' 'neutral'
assert_json_field "tp no regressions" "$result" '.regressed | length' '0'
rm -f "$tp_bench_config" "$tp_baseline"

echo ""
echo "=== Edge Case Tests ==="

# Test: no benchmarks configured with a real baseline — should produce neutral with verdict_logic=no_benchmarks
echo "--- Test: no benchmarks with baseline produces neutral ---"
no_bench_baseline=$(mktemp)
echo '{"metrics":{"score":42},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$no_bench_baseline"
no_bench_config='{"gates":[{"name":"pass","command":"true"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}'
tmpconfig=$(mktemp)
echo "$no_bench_config" > "$tmpconfig"
result=$("$EVALUATE" "$tmpconfig" "$no_bench_baseline" 2>/dev/null)
assert_json_field "no-bench verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "no-bench verdict_logic is no_benchmarks" "$result" '.verdict_logic' 'no_benchmarks'
assert_json_field "no-bench reason mentions no benchmarks" "$result" '.reason' 'no benchmarks configured'
rm -f "$tmpconfig" "$no_bench_baseline"

# Test: second gate fails — fast-fail stops at gate 2, not gate 1
echo "--- Test: second gate fails (fast-fail at gate 2) ---"
second_fail_config=$(mktemp)
cat > "$second_fail_config" <<EOF
{
  "gates": [
    {"name": "first-pass", "command": "true"},
    {"name": "second-fail", "command": "false"},
    {"name": "third-never", "command": "true"}
  ],
  "benchmarks": [],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$second_fail_config" /dev/null 2>/dev/null)
assert_json_field "second-gate verdict is gate_fail" "$result" '.verdict' 'gate_fail'
assert_json_field "second-gate failed gate name" "$result" '.gates[-1].name' 'second-fail'
assert_json_field "second-gate first gate passed" "$result" '.gates[0].passed' 'true'
gate_count=$(echo "$result" | jq '.gates | length')
assert_eq "two gates ran before fast-fail" "2" "$gate_count"
rm -f "$second_fail_config"

# Test: shell extractor pattern (non json:) — uses grep+sed to extract a value
echo "--- Test: shell extractor pattern ---"
shell_bench_config=$(mktemp)
cat > "$shell_bench_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "shell-bench",
      "command": "echo 'lines_of_code: 99'",
      "metrics": [
        {
          "name": "loc",
          "extract": "grep -oE '[0-9]+'",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$shell_bench_config" /dev/null 2>/dev/null)
assert_json_field "shell extractor init mode" "$result" '.mode' 'init'
assert_json_field "shell extractor value extracted" "$result" '.metrics.loc' '99'
rm -f "$shell_bench_config"

# Test: lower_is_better regression — speed_ms went up significantly
echo "--- Test: lower_is_better regression (speed_ms increased) ---"
lower_regress_baseline=$(mktemp)
echo '{"metrics":{"score":42,"speed_ms":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lower_regress_baseline"
bench_config=$(mktemp)
# mock-benchmark.sh emits speed_ms=150 — that is +50% vs baseline=100, which is a regression for lower_is_better
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
result=$("$EVALUATE" "$bench_config" "$lower_regress_baseline" 2>/dev/null)
assert_json_field "lower_is_better regress verdict" "$result" '.verdict' 'regress'
assert_json_field "speed_ms in regressed list" "$result" '.regressed | contains(["speed_ms"])' 'true'
rm -f "$bench_config" "$lower_regress_baseline"

# Test: regression wins over improvement — one metric improved, another regressed
echo "--- Test: mixed metrics — regress verdict wins over improvement ---"
mixed_baseline=$(mktemp)
# score baseline=30 → candidate=42 (+40%, improved); speed_ms baseline=100 → candidate=150 (+50%, regressed for lower_is_better)
echo '{"metrics":{"score":30,"speed_ms":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$mixed_baseline"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
result=$("$EVALUATE" "$bench_config" "$mixed_baseline" 2>/dev/null)
assert_json_field "mixed verdict is regress" "$result" '.verdict' 'regress'
assert_json_field "score still appears in improved" "$result" '.improved | contains(["score"])' 'true'
assert_json_field "speed_ms in regressed" "$result" '.regressed | contains(["speed_ms"])' 'true'
assert_json_field "verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
rm -f "$bench_config" "$mixed_baseline"

# Test: gate duration is recorded and non-negative
echo "--- Test: gate duration_ms is recorded ---"
result=$("$EVALUATE" "$FIXTURES/config-gates-only.json" /dev/null 2>/dev/null)
duration=$(echo "$result" | jq -r '.gates[0].duration_ms')
if [ "$duration" -ge 0 ] 2>/dev/null; then
  echo "  PASS: gate duration_ms is non-negative (got $duration)"
  ((PASS++)) || true
else
  echo "  FAIL: gate duration_ms is non-negative (got $duration)"
  ((FAIL++)) || true
fi

echo ""
echo "=== Tolerance & Significance Boundary Tests ==="

# Test: improvement exactly at significance threshold → neutral (> not >=)
echo "--- Test: improvement at significance boundary is neutral ---"
# score: baseline=100, candidate=101 → delta=0.01 = significance=0.01 → not > 0.01 → neutral
sig_boundary_config=$(mktemp)
cat > "$sig_boundary_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "sig-bench",
      "command": "echo '{\"val\": 101}'",
      "metrics": [
        {
          "name": "val",
          "extract": "json:.val",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
sig_boundary_baseline=$(mktemp)
echo '{"metrics":{"val":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$sig_boundary_baseline"
result=$("$EVALUATE" "$sig_boundary_config" "$sig_boundary_baseline" 2>/dev/null)
assert_json_field "sig boundary: verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "sig boundary: val not in improved" "$result" '.improved | length' '0'
assert_json_field "sig boundary: val not in regressed" "$result" '.regressed | length' '0'
assert_json_field "sig boundary: verdict_logic is no_improvements" "$result" '.verdict_logic' 'no_improvements'
rm -f "$sig_boundary_config" "$sig_boundary_baseline"

# Test: lower_is_better improvement — score decreased = good
echo "--- Test: lower_is_better improvement (value decreased is good) ---"
# speed_ms baseline=200, candidate=150 → delta=(150-200)/200=-0.25, normalized=+0.25 > significance → improved
lib_improve_config=$(mktemp)
cat > "$lib_improve_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "latency-bench",
      "command": "echo '{\"latency\": 150}'",
      "metrics": [
        {
          "name": "latency",
          "extract": "json:.latency",
          "direction": "lower_is_better",
          "tolerance": 0.05,
          "significance": 0.02
        }
      ]
    }
  ],
  "regression_tolerance": 0.05,
  "significance_threshold": 0.02
}
EOF
lib_improve_baseline=$(mktemp)
echo '{"metrics":{"latency":200},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lib_improve_baseline"
result=$("$EVALUATE" "$lib_improve_config" "$lib_improve_baseline" 2>/dev/null)
assert_json_field "lib improve: verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "lib improve: latency in improved" "$result" '.improved | contains(["latency"])' 'true'
assert_json_field "lib improve: regressed is empty" "$result" '.regressed | length' '0'
rm -f "$lib_improve_config" "$lib_improve_baseline"

# Test: config with no gates (empty gates array) — benchmarks still score correctly
echo "--- Test: config with no gates scores benchmarks normally ---"
no_gates_config=$(mktemp)
cat > "$no_gates_config" <<EOF
{
  "gates": [],
  "benchmarks": [
    {
      "name": "no-gate-bench",
      "command": "echo '{\"count\": 55}'",
      "metrics": [
        {
          "name": "count",
          "extract": "json:.count",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
no_gates_baseline=$(mktemp)
echo '{"metrics":{"count":50},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$no_gates_baseline"
result=$("$EVALUATE" "$no_gates_config" "$no_gates_baseline" 2>/dev/null)
assert_json_field "no-gates: verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "no-gates: count in improved" "$result" '.improved | contains(["count"])' 'true'
assert_json_field "no-gates: gates array is empty" "$result" '.gates | length' '0'
rm -f "$no_gates_config" "$no_gates_baseline"

# Test: all metrics within tolerance → verdict neutral, verdict_logic no_improvements
echo "--- Test: all metrics neutral (within tolerance and significance) ---"
all_neutral_config=$(mktemp)
cat > "$all_neutral_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "stable-bench",
      "command": "echo '{\"a\": 100, \"b\": 200}'",
      "metrics": [
        {
          "name": "a",
          "extract": "json:.a",
          "direction": "higher_is_better",
          "tolerance": 0.05,
          "significance": 0.03
        },
        {
          "name": "b",
          "extract": "json:.b",
          "direction": "lower_is_better",
          "tolerance": 0.05,
          "significance": 0.03
        }
      ]
    }
  ],
  "regression_tolerance": 0.05,
  "significance_threshold": 0.03
}
EOF
all_neutral_baseline=$(mktemp)
# a: baseline=100, candidate=100 → 0 change → neutral
# b: baseline=200, candidate=200 → 0 change → neutral
echo '{"metrics":{"a":100,"b":200},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$all_neutral_baseline"
result=$("$EVALUATE" "$all_neutral_config" "$all_neutral_baseline" 2>/dev/null)
assert_json_field "all-neutral: verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "all-neutral: improved is empty" "$result" '.improved | length' '0'
assert_json_field "all-neutral: regressed is empty" "$result" '.regressed | length' '0'
assert_json_field "all-neutral: verdict_logic is no_improvements" "$result" '.verdict_logic' 'no_improvements'
rm -f "$all_neutral_config" "$all_neutral_baseline"

# Test: tolerance boundary — delta exactly equals -tolerance → not regressed (strict <)
echo "--- Test: regression at tolerance boundary is neutral (not regressed) ---"
# val: baseline=~42.857, candidate=42 → delta = (42-42.857)/42.857 = -0.02 = -tolerance
# Check: -0.02 < -0.02 is false → not regressed; 0 > significance(0.01) is false → not improved → neutral
tol_boundary_config=$(mktemp)
cat > "$tol_boundary_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "tol-bench",
      "command": "echo '{\"val\": 42}'",
      "metrics": [
        {
          "name": "val",
          "extract": "json:.val",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
# baseline chosen so delta = exactly -0.02: baseline = 42 / 0.98 = 42.857142...
tol_boundary_baseline=$(mktemp)
echo '{"metrics":{"val":42.857142857142},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$tol_boundary_baseline"
result=$("$EVALUATE" "$tol_boundary_config" "$tol_boundary_baseline" 2>/dev/null)
assert_json_field "tol boundary: verdict is neutral (not regressed)" "$result" '.verdict' 'neutral'
assert_json_field "tol boundary: val not in regressed" "$result" '.regressed | length' '0'
rm -f "$tol_boundary_config" "$tol_boundary_baseline"

echo ""
echo "=== Array Exactness & reason Field Tests ==="

# Test: improved array has exactly the right entries (length + membership, not just contains)
echo "--- Test: improved array contains exactly the right entries ---"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
# baseline: score=40, speed_ms=160 → candidate: score=42, speed_ms=150 → both improve
result=$("$EVALUATE" "$bench_config" "$FIXTURES/baseline-basic.json" 2>/dev/null)
improved_len=$(echo "$result" | jq '.improved | length')
assert_eq "improved has exactly 2 entries" "2" "$improved_len"
assert_json_field "improved[0] is score" "$result" '.improved[0]' 'score'
assert_json_field "improved[1] is speed_ms" "$result" '.improved[1]' 'speed_ms'
rm -f "$bench_config"

# Test: regressed array is populated with exactly the right entry on regress verdict
echo "--- Test: regressed array contains exactly the right entry ---"
regress_baseline=$(mktemp)
echo '{"metrics":{"score":50,"speed_ms":150},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$regress_baseline"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
# score 50→42 = -16%, well below -2% tolerance → regressed; speed_ms baseline=150, candidate=150 → no change
result=$("$EVALUATE" "$bench_config" "$regress_baseline" 2>/dev/null)
regressed_len=$(echo "$result" | jq '.regressed | length')
assert_eq "regressed has exactly 1 entry" "1" "$regressed_len"
assert_json_field "regressed[0] is score" "$result" '.regressed[0]' 'score'
assert_json_field "regressed: improved is empty" "$result" '.improved | length' '0'
rm -f "$bench_config" "$regress_baseline"

# Test: delta_pct sign is negative for lower_is_better improvement (value decreased)
echo "--- Test: delta_pct is negative when lower_is_better value decreases ---"
lib_delta_config=$(mktemp)
cat > "$lib_delta_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "latency-bench",
      "command": "echo '{\"ms\": 80}'",
      "metrics": [
        {
          "name": "ms",
          "extract": "json:.ms",
          "direction": "lower_is_better",
          "tolerance": 0.05,
          "significance": 0.02
        }
      ]
    }
  ],
  "regression_tolerance": 0.05,
  "significance_threshold": 0.02
}
EOF
lib_delta_baseline=$(mktemp)
echo '{"metrics":{"ms":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lib_delta_baseline"
# ms 100→80 = -20% raw delta → displayed as negative delta_pct
result=$("$EVALUATE" "$lib_delta_config" "$lib_delta_baseline" 2>/dev/null)
delta=$(echo "$result" | jq '.metrics.ms.delta_pct')
is_negative=$(echo "$delta < 0" | bc -l)
assert_eq "delta_pct is negative for lower_is_better improvement" "1" "$is_negative"
assert_json_field "verdict is keep (it was an improvement)" "$result" '.verdict' 'keep'
rm -f "$lib_delta_config" "$lib_delta_baseline"

# Test: reason field is a non-empty string on all verdict types
echo "--- Test: reason field is non-empty string on all verdict types ---"
# gate_fail reason
fail_config=$(mktemp)
echo '{"gates":[{"name":"fail","command":"false"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}' > "$fail_config"
reason_gate_fail=$(echo "$("$EVALUATE" "$fail_config" /dev/null 2>/dev/null)" | jq -r '.reason')
if [ -n "$reason_gate_fail" ] && [ "$reason_gate_fail" != "null" ]; then
  echo "  PASS: gate_fail has non-empty reason (got: $reason_gate_fail)"
  ((PASS++)) || true
else
  echo "  FAIL: gate_fail reason is empty or null"
  ((FAIL++)) || true
fi
rm -f "$fail_config"
# keep reason
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
reason_keep=$(echo "$("$EVALUATE" "$bench_config" "$FIXTURES/baseline-basic.json" 2>/dev/null)" | jq -r '.reason')
if [ -n "$reason_keep" ] && [ "$reason_keep" != "null" ]; then
  echo "  PASS: keep has non-empty reason (got: $reason_keep)"
  ((PASS++)) || true
else
  echo "  FAIL: keep reason is empty or null"
  ((FAIL++)) || true
fi
rm -f "$bench_config"
# neutral reason
neutral_baseline=$(mktemp)
echo '{"metrics":{"score":42,"speed_ms":150},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$neutral_baseline"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
reason_neutral=$(echo "$("$EVALUATE" "$bench_config" "$neutral_baseline" 2>/dev/null)" | jq -r '.reason')
if [ -n "$reason_neutral" ] && [ "$reason_neutral" != "null" ]; then
  echo "  PASS: neutral has non-empty reason (got: $reason_neutral)"
  ((PASS++)) || true
else
  echo "  FAIL: neutral reason is empty or null"
  ((FAIL++)) || true
fi
rm -f "$bench_config" "$neutral_baseline"
# regress reason
regress_baseline=$(mktemp)
echo '{"metrics":{"score":50,"speed_ms":160},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$regress_baseline"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
reason_regress=$(echo "$("$EVALUATE" "$bench_config" "$regress_baseline" 2>/dev/null)" | jq -r '.reason')
if [ -n "$reason_regress" ] && [ "$reason_regress" != "null" ]; then
  echo "  PASS: regress has non-empty reason (got: $reason_regress)"
  ((PASS++)) || true
else
  echo "  FAIL: regress reason is empty or null"
  ((FAIL++)) || true
fi
rm -f "$bench_config" "$regress_baseline"

echo ""
echo "=== New Metric / Benchmark Failure / Compare Mode / All-Regress Tests ==="

# Test: new metric in candidate not present in baseline → skipped (not counted as improvement)
# The scoring loop does: if [ -z "$baseline_val" ]; then continue — so new metrics are ignored.
echo "--- Test: new metric in candidate absent from baseline is skipped ---"
new_metric_config=$(mktemp)
cat > "$new_metric_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "new-metric-bench",
      "command": "echo '{\"old\": 110, \"new_metric\": 99}'",
      "metrics": [
        {
          "name": "old",
          "extract": "json:.old",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "new_metric",
          "extract": "json:.new_metric",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
# baseline only has "old"; "new_metric" is absent → new_metric should be skipped entirely
new_metric_baseline=$(mktemp)
echo '{"metrics":{"old":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$new_metric_baseline"
result=$("$EVALUATE" "$new_metric_config" "$new_metric_baseline" 2>/dev/null)
# old improved (100→110, +10%), new_metric has no baseline so skipped
assert_json_field "new-metric: old is in improved" "$result" '.improved | contains(["old"])' 'true'
assert_json_field "new-metric: new_metric NOT in improved" "$result" '.improved | contains(["new_metric"])' 'false'
assert_json_field "new-metric: new_metric NOT in regressed" "$result" '.regressed | contains(["new_metric"])' 'false'
assert_json_field "new-metric: verdict is keep (old improved)" "$result" '.verdict' 'keep'
# new_metric should not appear in scored metrics (no baseline to compare against)
has_new_metric=$(echo "$result" | jq 'has("new_metric")')
assert_eq "new-metric: new_metric absent from top-level result keys" "false" "$has_new_metric"
rm -f "$new_metric_config" "$new_metric_baseline"

# Test: benchmark command exits non-zero → metric extraction produces no output → metric skipped → neutral
echo "--- Test: benchmark command exits non-zero → metric skipped → neutral ---"
fail_bench_config=$(mktemp)
cat > "$fail_bench_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "failing-bench",
      "command": "exit 1",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
fail_bench_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$fail_bench_baseline"
result=$("$EVALUATE" "$fail_bench_config" "$fail_bench_baseline" 2>/dev/null)
# Gates pass, benchmark exits non-zero → no metric output → candidate_val empty → skip → neutral
assert_json_field "failing-bench: verdict is neutral (metric skipped)" "$result" '.verdict' 'neutral'
assert_json_field "failing-bench: improved is empty" "$result" '.improved | length' '0'
assert_json_field "failing-bench: regressed is empty" "$result" '.regressed | length' '0'
rm -f "$fail_bench_config" "$fail_bench_baseline"

# Test: compare mode output does NOT include a "mode" field (mode only appears in init output)
echo "--- Test: compare mode output has no mode field ---"
compare_bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$compare_bench_config"
result=$("$EVALUATE" "$compare_bench_config" "$FIXTURES/baseline-basic.json" 2>/dev/null)
mode_field=$(echo "$result" | jq 'has("mode")')
assert_eq "compare output has no mode field" "false" "$mode_field"
assert_json_field "compare output has verdict field" "$result" '.verdict' 'keep'
assert_json_field "compare output has verdict_logic field" "$result" '.verdict_logic' 'no_regressions_and_at_least_one_improvement'
rm -f "$compare_bench_config"

# Test: ALL metrics regress → regress verdict with full regressed array
echo "--- Test: all metrics regress → regress verdict with full regressed array ---"
all_regress_config=$(mktemp)
cat > "$all_regress_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "all-regress-bench",
      "command": "echo '{\"a\": 50, \"b\": 60, \"c\": 70}'",
      "metrics": [
        {
          "name": "a",
          "extract": "json:.a",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "b",
          "extract": "json:.b",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "c",
          "extract": "json:.c",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
# baseline: a=100, b=100, c=100 → candidate: a=50(-50%), b=60(-40%), c=70(-30%) — all regress
all_regress_baseline=$(mktemp)
echo '{"metrics":{"a":100,"b":100,"c":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$all_regress_baseline"
result=$("$EVALUATE" "$all_regress_config" "$all_regress_baseline" 2>/dev/null)
assert_json_field "all-regress: verdict is regress" "$result" '.verdict' 'regress'
assert_json_field "all-regress: verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
regressed_len=$(echo "$result" | jq '.regressed | length')
assert_eq "all-regress: regressed array has 3 entries" "3" "$regressed_len"
assert_json_field "all-regress: a in regressed" "$result" '.regressed | contains(["a"])' 'true'
assert_json_field "all-regress: b in regressed" "$result" '.regressed | contains(["b"])' 'true'
assert_json_field "all-regress: c in regressed" "$result" '.regressed | contains(["c"])' 'true'
assert_json_field "all-regress: improved is empty" "$result" '.improved | length' '0'
rm -f "$all_regress_config" "$all_regress_baseline"

echo ""
echo "=== verdict_logic, exit_code, and duration_ms Type Tests ==="

# Test: gate_fail verdict_logic is "gate_fast_fail" (not "gate_fail")
echo "--- Test: gate_fail has verdict_logic=gate_fast_fail ---"
gf_vl_config=$(mktemp)
echo '{"gates":[{"name":"fail-vl","command":"false"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}' > "$gf_vl_config"
result=$("$EVALUATE" "$gf_vl_config" /dev/null 2>/dev/null)
assert_json_field "gate_fail verdict_logic is gate_fast_fail" "$result" '.verdict_logic' 'gate_fast_fail'
assert_json_field "gate_fail verdict is gate_fail" "$result" '.verdict' 'gate_fail'
rm -f "$gf_vl_config"

# Test: gate exit_code stores the actual non-zero exit code from the command
echo "--- Test: failing gate stores actual exit_code value ---"
ec_config=$(mktemp)
# 'exit 42' should record exit_code=42 in gate output
cat > "$ec_config" <<EOF
{
  "gates": [{"name": "exit-42-gate", "command": "bash -c 'exit 42'"}],
  "benchmarks": [],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$ec_config" /dev/null 2>/dev/null)
assert_json_field "exit_code is 42" "$result" '.gates[0].exit_code' '42'
assert_json_field "gate with exit 42 is not passed" "$result" '.gates[0].passed' 'false'
rm -f "$ec_config"

# Test: gates[].duration_ms is a JSON number type (not a string)
echo "--- Test: gate duration_ms is JSON number type ---"
result=$("$EVALUATE" "$FIXTURES/config-gates-only.json" /dev/null 2>/dev/null)
assert_json_field "duration_ms is number type" "$result" '.gates[0].duration_ms | type' 'number'
assert_json_field "exit_code is number type" "$result" '.gates[0].exit_code | type' 'number'

echo ""
echo "=== Zero-Baseline, Zero-Significance, and Multi-Bench Accumulation Tests ==="

# Test: baseline = 0, candidate > 0 → delta_pct clamped to 1 (100%) → keep when significance < 1
echo "--- Test: baseline=0, candidate>0 → delta_pct=100% → verdict keep ---"
zero_base_config=$(mktemp)
cat > "$zero_base_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "zero-base-bench",
      "command": "echo '{\"score\": 5}'",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
zero_base_baseline=$(mktemp)
echo '{"metrics":{"score":0},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$zero_base_baseline"
result=$("$EVALUATE" "$zero_base_config" "$zero_base_baseline" 2>/dev/null)
assert_json_field "zero-base: verdict is keep (0→5 is improvement)" "$result" '.verdict' 'keep'
assert_json_field "zero-base: score in improved" "$result" '.improved | contains(["score"])' 'true'
assert_json_field "zero-base: score not in regressed" "$result" '.regressed | contains(["score"])' 'false'
assert_json_field "zero-base: delta_pct is 100 (1*100)" "$result" '.metrics.score.delta_pct' '100'
rm -f "$zero_base_config" "$zero_base_baseline"

# Test: significance: 0 → any positive change triggers keep (even tiny improvement)
echo "--- Test: significance=0 → any positive change is significant → keep ---"
zero_sig_config=$(mktemp)
cat > "$zero_sig_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "zero-sig-bench",
      "command": "echo '{\"score\": 100.001}'",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0
}
EOF
zero_sig_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$zero_sig_baseline"
result=$("$EVALUATE" "$zero_sig_config" "$zero_sig_baseline" 2>/dev/null)
assert_json_field "zero-sig: verdict is keep (any positive change counts)" "$result" '.verdict' 'keep'
assert_json_field "zero-sig: score in improved" "$result" '.improved | contains(["score"])' 'true'
rm -f "$zero_sig_config" "$zero_sig_baseline"

# Test: third benchmark's improved metric is counted even when first two benchmarks are neutral
echo "--- Test: third benchmark improvement counted when first two are neutral ---"
multi_bench_config=$(mktemp)
cat > "$multi_bench_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "bench-neutral-1",
      "command": "echo '{\"a\": 100}'",
      "metrics": [
        {
          "name": "a",
          "extract": "json:.a",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "bench-neutral-2",
      "command": "echo '{\"b\": 100}'",
      "metrics": [
        {
          "name": "b",
          "extract": "json:.b",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "bench-improved-3",
      "command": "echo '{\"c\": 120}'",
      "metrics": [
        {
          "name": "c",
          "extract": "json:.c",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
multi_bench_baseline=$(mktemp)
# a and b are unchanged (neutral), c improves from 100 to 120 (+20%)
echo '{"metrics":{"a":100,"b":100,"c":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$multi_bench_baseline"
result=$("$EVALUATE" "$multi_bench_config" "$multi_bench_baseline" 2>/dev/null)
assert_json_field "multi-bench: verdict is keep (third bench improved)" "$result" '.verdict' 'keep'
assert_json_field "multi-bench: c in improved" "$result" '.improved | contains(["c"])' 'true'
assert_json_field "multi-bench: a not in improved (neutral)" "$result" '.improved | contains(["a"])' 'false'
assert_json_field "multi-bench: b not in improved (neutral)" "$result" '.improved | contains(["b"])' 'false'
assert_json_field "multi-bench: regressed is empty" "$result" '.regressed | length' '0'
rm -f "$multi_bench_config" "$multi_bench_baseline"

echo ""
echo "=== Edge Case: extract Pattern No-Match, Zero-Tolerance, Compare-Mode Keys, verdict_logic Completeness ==="

# Test: extract pattern yields no match in benchmark output → metric is skipped gracefully
# The json:.nonexistent key is absent from the output JSON; jq returns null → empty → metric skipped.
# With a baseline present for that metric, the comparison loop should simply skip it (no crash, no phantom regression).
echo "--- Test: extract pattern with no match in output → metric silently skipped ---"
no_match_config=$(mktemp)
cat > "$no_match_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "no-match-bench",
      "command": "echo '{\"present\": 50}'",
      "metrics": [
        {
          "name": "present",
          "extract": "json:.present",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "missing",
          "extract": "json:.nonexistent",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
# baseline has both metrics; candidate output lacks "nonexistent" key → extract returns null/empty → skip
no_match_baseline=$(mktemp)
echo '{"metrics":{"present":40,"missing":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$no_match_baseline"
result=$("$EVALUATE" "$no_match_config" "$no_match_baseline" 2>/dev/null)
# "present" improved (40→50, +25%), "missing" skipped gracefully → no crash, not in regressed
assert_json_field "no-match: verdict is keep (present improved, missing skipped)" "$result" '.verdict' 'keep'
assert_json_field "no-match: missing NOT in regressed (skipped, not regressed)" "$result" '.regressed | contains(["missing"])' 'false'
assert_json_field "no-match: missing NOT in improved (skipped)" "$result" '.improved | contains(["missing"])' 'false'
assert_json_field "no-match: present IS in improved" "$result" '.improved | contains(["present"])' 'true'
rm -f "$no_match_config" "$no_match_baseline"

# Test: compare mode output has both baseline and candidate keys for each metric
# The per-metric object must carry {baseline, candidate, delta_pct, direction} in compare mode.
echo "--- Test: compare mode metrics have baseline and candidate keys per metric ---"
compare_keys_config=$(mktemp)
cat > "$compare_keys_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "keys-bench",
      "command": "echo '{\"alpha\": 110, \"beta\": 90}'",
      "metrics": [
        {
          "name": "alpha",
          "extract": "json:.alpha",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "beta",
          "extract": "json:.beta",
          "direction": "lower_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
compare_keys_baseline=$(mktemp)
echo '{"metrics":{"alpha":100,"beta":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$compare_keys_baseline"
result=$("$EVALUATE" "$compare_keys_config" "$compare_keys_baseline" 2>/dev/null)
# alpha: 100→110 improved; beta: 100→90 improved (lower_is_better)
assert_json_field "compare-keys: alpha has baseline key" "$result" '.metrics.alpha | has("baseline")' 'true'
assert_json_field "compare-keys: alpha has candidate key" "$result" '.metrics.alpha | has("candidate")' 'true'
assert_json_field "compare-keys: alpha baseline value is 100" "$result" '.metrics.alpha.baseline' '100'
assert_json_field "compare-keys: alpha candidate value is 110" "$result" '.metrics.alpha.candidate' '110'
assert_json_field "compare-keys: beta has baseline key" "$result" '.metrics.beta | has("baseline")' 'true'
assert_json_field "compare-keys: beta has candidate key" "$result" '.metrics.beta | has("candidate")' 'true'
rm -f "$compare_keys_config" "$compare_keys_baseline"

# Test: regression_tolerance=0.0 → any decrease, however tiny, triggers regress immediately
# With tolerance=0, the condition normalized_delta < -0 is true for any negative delta.
echo "--- Test: regression_tolerance=0.0 → tiny decrease triggers regress ---"
zero_tol_config=$(mktemp)
cat > "$zero_tol_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "zero-tol-bench",
      "command": "echo '{\"score\": 99}'",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
          "direction": "higher_is_better",
          "tolerance": 0.0,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.0,
  "significance_threshold": 0.01
}
EOF
zero_tol_baseline=$(mktemp)
# candidate=99 < baseline=100 → delta=-1% → with tolerance=0, -0.01 < -0 is true → regress
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$zero_tol_baseline"
result=$("$EVALUATE" "$zero_tol_config" "$zero_tol_baseline" 2>/dev/null)
assert_json_field "zero-tol: verdict is regress (any decrease)" "$result" '.verdict' 'regress'
assert_json_field "zero-tol: score in regressed" "$result" '.regressed | contains(["score"])' 'true'
assert_json_field "zero-tol: verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
rm -f "$zero_tol_config" "$zero_tol_baseline"

# Test: verdict_logic is present and non-empty on ALL four verdict types
# (gate_fail → gate_fast_fail, keep → no_regressions_and_at_least_one_improvement,
#  regress → regression_detected, neutral → no_improvements or no_benchmarks)
echo "--- Test: verdict_logic is present and non-empty for all verdict types ---"
# gate_fail
vl_fail_config=$(mktemp)
echo '{"gates":[{"name":"fail","command":"false"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}' > "$vl_fail_config"
vl_gate=$(echo "$("$EVALUATE" "$vl_fail_config" /dev/null 2>/dev/null)" | jq -r '.verdict_logic // empty')
if [ -n "$vl_gate" ] && [ "$vl_gate" != "null" ]; then
  echo "  PASS: gate_fail has verdict_logic=$vl_gate"
  ((PASS++)) || true
else
  echo "  FAIL: gate_fail verdict_logic is empty or null"
  ((FAIL++)) || true
fi
rm -f "$vl_fail_config"
# keep
vl_keep_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$vl_keep_config"
vl_keep=$(echo "$("$EVALUATE" "$vl_keep_config" "$FIXTURES/baseline-basic.json" 2>/dev/null)" | jq -r '.verdict_logic // empty')
if [ -n "$vl_keep" ] && [ "$vl_keep" != "null" ]; then
  echo "  PASS: keep has verdict_logic=$vl_keep"
  ((PASS++)) || true
else
  echo "  FAIL: keep verdict_logic is empty or null"
  ((FAIL++)) || true
fi
rm -f "$vl_keep_config"
# regress
vl_regress_baseline=$(mktemp)
echo '{"metrics":{"score":50,"speed_ms":160},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$vl_regress_baseline"
vl_regress_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$vl_regress_config"
vl_regress=$(echo "$("$EVALUATE" "$vl_regress_config" "$vl_regress_baseline" 2>/dev/null)" | jq -r '.verdict_logic // empty')
if [ -n "$vl_regress" ] && [ "$vl_regress" != "null" ]; then
  echo "  PASS: regress has verdict_logic=$vl_regress"
  ((PASS++)) || true
else
  echo "  FAIL: regress verdict_logic is empty or null"
  ((FAIL++)) || true
fi
rm -f "$vl_regress_config" "$vl_regress_baseline"
# neutral
vl_neutral_baseline=$(mktemp)
echo '{"metrics":{"score":42,"speed_ms":150},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$vl_neutral_baseline"
vl_neutral_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$vl_neutral_config"
vl_neutral=$(echo "$("$EVALUATE" "$vl_neutral_config" "$vl_neutral_baseline" 2>/dev/null)" | jq -r '.verdict_logic // empty')
if [ -n "$vl_neutral" ] && [ "$vl_neutral" != "null" ]; then
  echo "  PASS: neutral has verdict_logic=$vl_neutral"
  ((PASS++)) || true
else
  echo "  FAIL: neutral verdict_logic is empty or null"
  ((FAIL++)) || true
fi
rm -f "$vl_neutral_config" "$vl_neutral_baseline"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
