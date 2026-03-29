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

# Test: regression exactly at tolerance boundary — should be neutral (not regress)
# score tolerance=0.02; baseline=100, candidate=98 → delta=-0.02 (not < -0.02)
echo "--- Test: tolerance boundary — exact regression_tolerance is NOT a regress ---"
tol_boundary_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$tol_boundary_baseline"
tol_boundary_config=$(mktemp)
cat > "$tol_boundary_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "tol-bench",
      "command": "echo '{\"score\": 98}'",
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
result=$("$EVALUATE" "$tol_boundary_config" "$tol_boundary_baseline" 2>/dev/null)
assert_json_field "exact tolerance boundary verdict is NOT regress" "$result" '.verdict' 'neutral'
assert_json_field "score not in regressed list" "$result" '.regressed | length' '0'
rm -f "$tol_boundary_config" "$tol_boundary_baseline"

# Test: improvement exactly at significance threshold — should be neutral (not keep)
# score significance=0.01; baseline=100, candidate=101 → delta=0.01 (not > 0.01)
echo "--- Test: significance boundary — exact significance_threshold is NOT an improvement ---"
sig_boundary_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$sig_boundary_baseline"
sig_boundary_config=$(mktemp)
cat > "$sig_boundary_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "sig-bench",
      "command": "echo '{\"score\": 101}'",
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
result=$("$EVALUATE" "$sig_boundary_config" "$sig_boundary_baseline" 2>/dev/null)
assert_json_field "exact significance boundary verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "score not in improved list" "$result" '.improved | length' '0'
rm -f "$sig_boundary_config" "$sig_boundary_baseline"

# Test: multiple metrics — one improved, one neutral (at significance boundary) → keep verdict
# metric_a: baseline=100, candidate=115 (+15%, clearly improved)
# metric_b: baseline=100, candidate=101 (exactly at significance=0.01, not improved)
# No regressions + at least one improvement → keep
echo "--- Test: multiple metrics — one improved, one neutral → keep verdict ---"
multi_neutral_baseline=$(mktemp)
echo '{"metrics":{"metric_a":100,"metric_b":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$multi_neutral_baseline"
multi_neutral_config=$(mktemp)
cat > "$multi_neutral_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "multi-bench",
      "command": "echo '{\"metric_a\": 115, \"metric_b\": 101}'",
      "metrics": [
        {
          "name": "metric_a",
          "extract": "json:.metric_a",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "metric_b",
          "extract": "json:.metric_b",
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
result=$("$EVALUATE" "$multi_neutral_config" "$multi_neutral_baseline" 2>/dev/null)
assert_json_field "one-improved-one-neutral verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "metric_a appears in improved" "$result" '.improved | contains(["metric_a"])' 'true'
assert_json_field "metric_b not in improved" "$result" '.improved | contains(["metric_b"])' 'false'
assert_json_field "no regressions in multi-neutral test" "$result" '.regressed | length' '0'
rm -f "$multi_neutral_config" "$multi_neutral_baseline"

# Test: metric extraction failure (malformed JSON) — jq fails inside evaluate.sh causing non-zero exit
# When benchmark output is not valid JSON and extract pattern is json:, jq fails → evaluate.sh exits non-zero.
# This is a known behavior: malformed bench output causes evaluate.sh to exit with error.
echo "--- Test: malformed JSON output — evaluate exits non-zero on jq parse failure ---"
malformed_config=$(mktemp)
cat > "$malformed_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "bad-bench",
      "command": "echo 'this is not json'",
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
set +e
"$EVALUATE" "$malformed_config" /dev/null >/dev/null 2>/dev/null
malformed_exit=$?
set -e
if [ "$malformed_exit" -ne 0 ]; then
  echo "  PASS: malformed JSON causes non-zero exit (got $malformed_exit)"
  ((PASS++)) || true
else
  echo "  FAIL: malformed JSON should cause non-zero exit (got 0)"
  ((FAIL++)) || true
fi
rm -f "$malformed_config"

echo ""
echo "=== lower_is_better Improvement Tests ==="

# Test: lower_is_better improvement → keep
# latency_ms: baseline=200, candidate=150 → delta=-25%, normalized=+25% > significance=0.02 → improved → keep
echo "--- Test: lower_is_better improvement → keep ---"
lib_improve_baseline=$(mktemp)
echo '{"metrics":{"latency_ms":200},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lib_improve_baseline"
lib_improve_config=$(mktemp)
cat > "$lib_improve_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "lib-bench",
      "command": "echo '{\"latency_ms\": 150}'",
      "metrics": [
        {
          "name": "latency_ms",
          "extract": "json:.latency_ms",
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
result=$("$EVALUATE" "$lib_improve_config" "$lib_improve_baseline" 2>/dev/null)
assert_json_field "lower_is_better improvement verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "latency_ms in improved list" "$result" '.improved | contains(["latency_ms"])' 'true'
assert_json_field "no regressions for lower_is_better improvement" "$result" '.regressed | length' '0'
rm -f "$lib_improve_config" "$lib_improve_baseline"

# Test: lower_is_better exactly at significance boundary → neutral
# latency_ms: baseline=100, candidate=95 → delta=-5%, normalized=+5%; significance=0.05 → 0.05 > 0.05 is FALSE → neutral
echo "--- Test: lower_is_better at significance boundary → neutral ---"
lib_boundary_baseline=$(mktemp)
echo '{"metrics":{"latency_ms":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lib_boundary_baseline"
lib_boundary_config=$(mktemp)
cat > "$lib_boundary_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "lib-boundary-bench",
      "command": "echo '{\"latency_ms\": 95}'",
      "metrics": [
        {
          "name": "latency_ms",
          "extract": "json:.latency_ms",
          "direction": "lower_is_better",
          "tolerance": 0.10,
          "significance": 0.05
        }
      ]
    }
  ],
  "regression_tolerance": 0.10,
  "significance_threshold": 0.05
}
EOF
result=$("$EVALUATE" "$lib_boundary_config" "$lib_boundary_baseline" 2>/dev/null)
assert_json_field "lower_is_better at boundary verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "latency_ms not in improved at boundary" "$result" '.improved | length' '0'
assert_json_field "no regressions at boundary" "$result" '.regressed | length' '0'
rm -f "$lib_boundary_config" "$lib_boundary_baseline"

# Test: lower_is_better improvement with higher_is_better unchanged → keep
# score (higher_is_better): baseline=42, candidate=42 → neutral (0% change)
# latency_ms (lower_is_better): baseline=200, candidate=150 → normalized +25% > significance=0.02 → improved
# No regressions + latency_ms improved → keep
echo "--- Test: lower_is_better improves, higher_is_better unchanged → keep ---"
lib_mixed_baseline=$(mktemp)
echo '{"metrics":{"score":42,"latency_ms":200},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lib_mixed_baseline"
lib_mixed_config=$(mktemp)
cat > "$lib_mixed_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "lib-mixed-bench",
      "command": "echo '{\"score\": 42, \"latency_ms\": 150}'",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "latency_ms",
          "extract": "json:.latency_ms",
          "direction": "lower_is_better",
          "tolerance": 0.05,
          "significance": 0.02
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$lib_mixed_config" "$lib_mixed_baseline" 2>/dev/null)
assert_json_field "mixed types with lower_is_better improvement verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "latency_ms in improved for mixed test" "$result" '.improved | contains(["latency_ms"])' 'true'
assert_json_field "score not in improved (unchanged)" "$result" '.improved | contains(["score"])' 'false'
assert_json_field "no regressions in mixed lower_is_better test" "$result" '.regressed | length' '0'
rm -f "$lib_mixed_config" "$lib_mixed_baseline"

echo ""
echo "=== Multi-Metric Edge Case Tests ==="

# Test: two metrics both improve by >significance → both in .improved[], verdict is keep
# metric_a: baseline=100, candidate=120 (+20% > significance=0.01) → improved
# metric_b: baseline=200, candidate=250 (+25% > significance=0.01) → improved
# No regressions + two improvements → keep, and BOTH names appear in .improved[]
echo "--- Test: two metrics both improve → both in improved list ---"
two_improve_baseline=$(mktemp)
echo '{"metrics":{"metric_a":100,"metric_b":200},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$two_improve_baseline"
two_improve_config=$(mktemp)
cat > "$two_improve_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "two-improve-bench",
      "command": "echo '{\"metric_a\": 120, \"metric_b\": 250}'",
      "metrics": [
        {
          "name": "metric_a",
          "extract": "json:.metric_a",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "metric_b",
          "extract": "json:.metric_b",
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
result=$("$EVALUATE" "$two_improve_config" "$two_improve_baseline" 2>/dev/null)
assert_json_field "two-improve verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "metric_a in improved" "$result" '.improved | contains(["metric_a"])' 'true'
assert_json_field "metric_b in improved" "$result" '.improved | contains(["metric_b"])' 'true'
assert_json_field "improved list length is 2" "$result" '.improved | length' '2'
assert_json_field "no regressions when both improve" "$result" '.regressed | length' '0'
rm -f "$two_improve_config" "$two_improve_baseline"

# Test: all metrics regress simultaneously → all appear in .regressed[], verdict is regress
# metric_a: baseline=100, candidate=70 (-30% < -tolerance=0.02) → regressed
# metric_b: baseline=200, candidate=140 (-30% < -tolerance=0.02) → regressed
# Both regressed → verdict is regress and BOTH names appear in .regressed[]
echo "--- Test: all metrics regress → all in regressed list ---"
all_regress_baseline=$(mktemp)
echo '{"metrics":{"metric_a":100,"metric_b":200},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$all_regress_baseline"
all_regress_config=$(mktemp)
cat > "$all_regress_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "all-regress-bench",
      "command": "echo '{\"metric_a\": 70, \"metric_b\": 140}'",
      "metrics": [
        {
          "name": "metric_a",
          "extract": "json:.metric_a",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "metric_b",
          "extract": "json:.metric_b",
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
result=$("$EVALUATE" "$all_regress_config" "$all_regress_baseline" 2>/dev/null)
assert_json_field "all-regress verdict is regress" "$result" '.verdict' 'regress'
assert_json_field "metric_a in regressed" "$result" '.regressed | contains(["metric_a"])' 'true'
assert_json_field "metric_b in regressed" "$result" '.regressed | contains(["metric_b"])' 'true'
assert_json_field "regressed list length is 2" "$result" '.regressed | length' '2'
assert_json_field "improved is empty when all regress" "$result" '.improved | length' '0'
rm -f "$all_regress_config" "$all_regress_baseline"

# Test: second gate fails — verify gates[0].passed=true AND gates[1].passed=false AND verdict=gate_fail
# This closes gap 4+5: the combination of first-gate-passes + second-gate-fails + correct verdict field.
echo "--- Test: second gate fails — gates[0].passed=true, gates[1].passed=false, verdict=gate_fail ---"
second_gate_detail_config=$(mktemp)
cat > "$second_gate_detail_config" <<EOF
{
  "gates": [
    {"name": "first-pass", "command": "true"},
    {"name": "second-fail", "command": "false"}
  ],
  "benchmarks": [],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$second_gate_detail_config" /dev/null 2>/dev/null)
assert_json_field "verdict is gate_fail when second gate fails" "$result" '.verdict' 'gate_fail'
assert_json_field "first gate passed=true" "$result" '.gates[0].passed' 'true'
assert_json_field "first gate name correct" "$result" '.gates[0].name' 'first-pass'
assert_json_field "second gate passed=false" "$result" '.gates[1].passed' 'false'
assert_json_field "second gate name correct" "$result" '.gates[1].name' 'second-fail'
rm -f "$second_gate_detail_config"

echo ""
echo "=== Zero Baseline Edge Case Tests ==="

# Test: zero baseline, non-zero candidate — delta_pct hardcoded to 1 (100% gain)
# evaluate.sh special-cases baseline=0, candidate!=0 → delta_pct=1
# normalized_delta=1 > significance=0.01 → improved → keep
echo "--- Test: zero baseline, non-zero candidate → keep (100% improvement) ---"
zero_base_nonzero_cand_baseline=$(mktemp)
echo '{"metrics":{"score":0},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$zero_base_nonzero_cand_baseline"
zero_base_nonzero_cand_config=$(mktemp)
cat > "$zero_base_nonzero_cand_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "zero-base-bench",
      "command": "echo '{\"score\": 1}'",
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
result=$("$EVALUATE" "$zero_base_nonzero_cand_config" "$zero_base_nonzero_cand_baseline" 2>/dev/null)
assert_json_field "zero-baseline non-zero candidate verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "score in improved when baseline=0" "$result" '.improved | contains(["score"])' 'true'
assert_json_field "no regressions when baseline=0 candidate>0" "$result" '.regressed | length' '0'
rm -f "$zero_base_nonzero_cand_config" "$zero_base_nonzero_cand_baseline"

# Test: zero baseline, zero candidate — delta_pct hardcoded to 0 → normalized=0
# 0 > significance=0.01 is FALSE; 0 < -tolerance=0.02 is FALSE → neutral
echo "--- Test: zero baseline, zero candidate → neutral (no change) ---"
zero_zero_baseline=$(mktemp)
echo '{"metrics":{"score":0},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$zero_zero_baseline"
zero_zero_config=$(mktemp)
cat > "$zero_zero_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "zero-zero-bench",
      "command": "echo '{\"score\": 0}'",
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
result=$("$EVALUATE" "$zero_zero_config" "$zero_zero_baseline" 2>/dev/null)
assert_json_field "zero-baseline zero-candidate verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "score not in improved when both zero" "$result" '.improved | length' '0'
assert_json_field "score not in regressed when both zero" "$result" '.regressed | length' '0'
rm -f "$zero_zero_config" "$zero_zero_baseline"

# Test: significance threshold of 0.0 — any positive delta, however small, should produce keep
# score: baseline=100, candidate=100.001 → delta=0.00001% > significance=0.0 → improved → keep
echo "--- Test: significance=0.0 — any improvement produces keep ---"
sig_zero_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$sig_zero_baseline"
sig_zero_config=$(mktemp)
cat > "$sig_zero_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "sig-zero-bench",
      "command": "echo '{\"score\": 101}'",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.0
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.0
}
EOF
result=$("$EVALUATE" "$sig_zero_config" "$sig_zero_baseline" 2>/dev/null)
assert_json_field "significance=0.0 any improvement → keep" "$result" '.verdict' 'keep'
assert_json_field "score in improved with significance=0.0" "$result" '.improved | contains(["score"])' 'true'
assert_json_field "no regressions with significance=0.0" "$result" '.regressed | length' '0'
rm -f "$sig_zero_config" "$sig_zero_baseline"

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
echo "=== Direction Field, Multi-Bench Init Merge, Gate Stdout Isolation Tests ==="

# Test: compare mode per-metric object includes a "direction" field with the correct value
echo "--- Test: compare mode metric object includes direction field ---"
dir_field_config=$(mktemp)
cat > "$dir_field_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "dir-bench",
      "command": "echo '{\"latency\": 80, \"throughput\": 120}'",
      "metrics": [
        {
          "name": "latency",
          "extract": "json:.latency",
          "direction": "lower_is_better",
          "tolerance": 0.05,
          "significance": 0.02
        },
        {
          "name": "throughput",
          "extract": "json:.throughput",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.05,
  "significance_threshold": 0.02
}
EOF
dir_field_baseline=$(mktemp)
echo '{"metrics":{"latency":100,"throughput":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$dir_field_baseline"
result=$("$EVALUATE" "$dir_field_config" "$dir_field_baseline" 2>/dev/null)
assert_json_field "direction-field: latency.direction is lower_is_better" "$result" '.metrics.latency.direction' 'lower_is_better'
assert_json_field "direction-field: throughput.direction is higher_is_better" "$result" '.metrics.throughput.direction' 'higher_is_better'
assert_json_field "direction-field: latency has direction key" "$result" '.metrics.latency | has("direction")' 'true'
assert_json_field "direction-field: throughput has direction key" "$result" '.metrics.throughput | has("direction")' 'true'
rm -f "$dir_field_config" "$dir_field_baseline"

# Test: init mode with multiple benchmarks merges all metrics into a single flat object
echo "--- Test: init mode merges metrics from multiple benchmarks into flat object ---"
multi_init_config=$(mktemp)
cat > "$multi_init_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "bench-a",
      "command": "echo '{\"alpha\": 10}'",
      "metrics": [
        {
          "name": "alpha",
          "extract": "json:.alpha",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "bench-b",
      "command": "echo '{\"beta\": 20}'",
      "metrics": [
        {
          "name": "beta",
          "extract": "json:.beta",
          "direction": "lower_is_better",
          "tolerance": 0.05,
          "significance": 0.02
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$multi_init_config" /dev/null 2>/dev/null)
assert_json_field "multi-init: mode is init" "$result" '.mode' 'init'
assert_json_field "multi-init: alpha present with value 10" "$result" '.metrics.alpha' '10'
assert_json_field "multi-init: beta present with value 20" "$result" '.metrics.beta' '20'
assert_json_field "multi-init: metrics has exactly 2 keys" "$result" '.metrics | keys | length' '2'
rm -f "$multi_init_config"

# Test: gate command that emits stdout doesn't pollute the JSON output
echo "--- Test: gate stdout is suppressed — JSON output is valid ---"
noisy_gate_config=$(mktemp)
cat > "$noisy_gate_config" <<EOF
{
  "gates": [
    {"name": "noisy-pass", "command": "echo 'this is noisy stdout from gate'; true"}
  ],
  "benchmarks": [],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
# The gate emits stdout; evaluate.sh should suppress it. The result JSON must be valid.
raw_output=$("$EVALUATE" "$noisy_gate_config" /dev/null 2>/dev/null)
parsed=$(echo "$raw_output" | jq '.' 2>/dev/null)
if [ -n "$parsed" ]; then
  echo "  PASS: noisy gate stdout suppressed — output is valid JSON"
  ((PASS++)) || true
else
  echo "  FAIL: noisy gate stdout polluted output — not valid JSON"
  ((FAIL++)) || true
fi
# Also verify gate passed and no gate noise bleeds into the verdict
assert_json_field "noisy-gate: gate passed" "$raw_output" '.gates[0].passed' 'true'
assert_json_field "noisy-gate: mode is init (no baseline)" "$raw_output" '.mode' 'init'
rm -f "$noisy_gate_config"

echo ""
echo "=== Error Handling Tests ==="

# Test: no arguments → exits with code 1 (error emitted to stderr, not stdout)
echo "--- Test: no arguments → exit code 1 ---"
set +e
"$EVALUATE" 2>/dev/null
no_arg_exit=$?
set -e
if [ "$no_arg_exit" -eq 1 ]; then
  echo "  PASS: no-args exits with code 1 (got $no_arg_exit)"
  ((PASS++)) || true
else
  echo "  FAIL: no-args should exit 1 (got $no_arg_exit)"
  ((FAIL++)) || true
fi

# Test: no arguments → error message goes to stderr (stdout is empty)
echo "--- Test: no arguments → error message on stderr, stdout empty ---"
set +e
stdout_output=$("$EVALUATE" 2>/dev/null)
set -e
if [ -z "$stdout_output" ]; then
  echo "  PASS: no-args stdout is empty (error correctly on stderr)"
  ((PASS++)) || true
else
  echo "  FAIL: no-args stdout should be empty (got: $stdout_output)"
  ((FAIL++)) || true
fi

# Test: nonexistent config file → exits with code 1
echo "--- Test: nonexistent config file → exit code 1 ---"
set +e
"$EVALUATE" /tmp/definitely-nonexistent-evaluate-config-xyz.json 2>/dev/null
nonexistent_exit=$?
set -e
if [ "$nonexistent_exit" -eq 1 ]; then
  echo "  PASS: nonexistent config exits with code 1 (got $nonexistent_exit)"
  ((PASS++)) || true
else
  echo "  FAIL: nonexistent config should exit 1 (got $nonexistent_exit)"
  ((FAIL++)) || true
fi

# Test: nonexistent config file → error message on stderr, stdout empty
echo "--- Test: nonexistent config file → stderr only, stdout empty ---"
set +e
stdout_nonexistent=$("$EVALUATE" /tmp/definitely-nonexistent-evaluate-config-xyz.json 2>/dev/null)
set -e
if [ -z "$stdout_nonexistent" ]; then
  echo "  PASS: nonexistent config stdout is empty"
  ((PASS++)) || true
else
  echo "  FAIL: nonexistent config stdout should be empty (got: $stdout_nonexistent)"
  ((FAIL++)) || true
fi

echo ""
echo "=== Init Mode Structure Tests ==="

# Test: init mode output includes a gates array (not just metrics)
echo "--- Test: init mode output includes gates array ---"
init_gates_config=$(mktemp)
cat > "$init_gates_config" <<EOF
{
  "gates": [{"name": "init-gate", "command": "true"}],
  "benchmarks": [
    {
      "name": "g-bench",
      "command": "echo '{\"val\": 7}'",
      "metrics": [{"name": "val", "extract": "json:.val", "direction": "higher_is_better", "tolerance": 0.02, "significance": 0.01}]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$init_gates_config" /dev/null 2>/dev/null)
assert_json_field "init-gates: mode is init" "$result" '.mode' 'init'
assert_json_field "init-gates: gates array present" "$result" '.gates | length' '1'
assert_json_field "init-gates: gate name is init-gate" "$result" '.gates[0].name' 'init-gate'
assert_json_field "init-gates: gate passed=true" "$result" '.gates[0].passed' 'true'
rm -f "$init_gates_config"

# Test: nonexistent baseline path → treated as init mode (INIT_MODE=true when file not found)
echo "--- Test: nonexistent baseline path → init mode ---"
no_baseline_file_config=$(mktemp)
cat > "$no_baseline_file_config" <<EOF
{
  "gates": [],
  "benchmarks": [
    {
      "name": "no-bl-bench",
      "command": "echo '{\"count\": 10}'",
      "metrics": [{"name": "count", "extract": "json:.count", "direction": "higher_is_better", "tolerance": 0.02, "significance": 0.01}]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$no_baseline_file_config" /tmp/nonexistent-baseline-for-evaluate-test.json 2>/dev/null)
assert_json_field "no-baseline-file: mode is init (nonexistent file treated as init)" "$result" '.mode' 'init'
assert_json_field "no-baseline-file: count metric present in init output" "$result" '.metrics.count' '10'
rm -f "$no_baseline_file_config"

# Test: init mode with no benchmarks → metrics is empty object
echo "--- Test: init mode with no benchmarks → empty metrics object ---"
no_bench_init_config=$(mktemp)
echo '{"gates":[],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}' > "$no_bench_init_config"
result=$("$EVALUATE" "$no_bench_init_config" /dev/null 2>/dev/null)
assert_json_field "no-bench-init: mode is init" "$result" '.mode' 'init'
assert_json_field "no-bench-init: metrics is empty object" "$result" '.metrics | length' '0'
assert_json_field "no-bench-init: gates is empty array" "$result" '.gates | length' '0'
rm -f "$no_bench_init_config"

echo ""
echo "=== Metric Type Handling Tests ==="

# Test: string metric value stored as string type in init mode
# When benchmark output contains a non-numeric value, run_benchmarks stores it as a JSON string.
echo "--- Test: non-numeric metric stored as string type in init mode ---"
str_metric_config=$(mktemp)
cat > "$str_metric_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "str-metric-bench",
      "command": "echo '{\"version\": \"v2.1.0\"}'",
      "metrics": [
        {
          "name": "version",
          "extract": "json:.version",
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
result=$("$EVALUATE" "$str_metric_config" /dev/null 2>/dev/null)
assert_json_field "str-metric: mode is init" "$result" '.mode' 'init'
assert_json_field "str-metric: version value is v2.1.0" "$result" '.metrics.version' 'v2.1.0'
assert_json_field "str-metric: version stored as string type" "$result" '.metrics.version | type' 'string'
rm -f "$str_metric_config"

# Test: floating-point metric value stored as number type in init mode
echo "--- Test: fractional metric stored as number type in init mode ---"
float_metric_config=$(mktemp)
cat > "$float_metric_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "float-metric-bench",
      "command": "echo '{\"accuracy\": 0.9375}'",
      "metrics": [
        {
          "name": "accuracy",
          "extract": "json:.accuracy",
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
result=$("$EVALUATE" "$float_metric_config" /dev/null 2>/dev/null)
assert_json_field "float-metric: mode is init" "$result" '.mode' 'init'
assert_json_field "float-metric: accuracy stored as number type" "$result" '.metrics.accuracy | type' 'number'
accuracy_val=$(echo "$result" | jq -r '.metrics.accuracy')
if [ "$(echo "$accuracy_val == 0.9375" | bc -l)" = "1" ]; then
  echo "  PASS: float-metric: accuracy value is 0.9375 (got $accuracy_val)"
  ((PASS++)) || true
else
  echo "  FAIL: float-metric: accuracy value should be 0.9375 (got $accuracy_val)"
  ((FAIL++)) || true
fi
rm -f "$float_metric_config"

# Test: fractional metric scores correctly in compare mode
# accuracy: baseline=0.90, candidate=0.95 → delta=(0.95-0.90)/0.90 ≈ +5.56% > significance=0.01 → keep
echo "--- Test: fractional metric (0.90→0.95) scores as improvement in compare mode ---"
float_compare_config=$(mktemp)
cat > "$float_compare_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "float-compare-bench",
      "command": "echo '{\"accuracy\": 0.95}'",
      "metrics": [
        {
          "name": "accuracy",
          "extract": "json:.accuracy",
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
float_compare_baseline=$(mktemp)
echo '{"metrics":{"accuracy":0.90},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$float_compare_baseline"
result=$("$EVALUATE" "$float_compare_config" "$float_compare_baseline" 2>/dev/null)
assert_json_field "float-compare: verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "float-compare: accuracy in improved" "$result" '.improved | contains(["accuracy"])' 'true'
assert_json_field "float-compare: baseline stored correctly" "$result" '.metrics.accuracy.baseline' '0.90'
assert_json_field "float-compare: candidate stored correctly" "$result" '.metrics.accuracy.candidate' '0.95'
rm -f "$float_compare_config" "$float_compare_baseline"

echo ""
echo "=== lower_is_better Zero Baseline Tests ==="

# Test: lower_is_better, baseline=0, candidate>0 → delta=1, normalized=-1 → regress
# For lower_is_better: an increase from 0 is a regression (things got slower/larger).
# evaluate.sh sets delta_pct=1 when baseline=0 and candidate!=0, then negates for lower_is_better:
# normalized_delta = -1 → -1 < -tolerance → regression.
echo "--- Test: lower_is_better, baseline=0, candidate>0 → regress ---"
lib_zero_cand_nonzero_config=$(mktemp)
cat > "$lib_zero_cand_nonzero_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "lib-zero-nonzero-bench",
      "command": "echo '{\"latency\": 10}'",
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
lib_zero_cand_nonzero_baseline=$(mktemp)
echo '{"metrics":{"latency":0},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lib_zero_cand_nonzero_baseline"
result=$("$EVALUATE" "$lib_zero_cand_nonzero_config" "$lib_zero_cand_nonzero_baseline" 2>/dev/null)
assert_json_field "lib-zero-nonzero: verdict is regress (baseline=0, candidate>0 is worse for lower_is_better)" "$result" '.verdict' 'regress'
assert_json_field "lib-zero-nonzero: latency in regressed" "$result" '.regressed | contains(["latency"])' 'true'
assert_json_field "lib-zero-nonzero: improved is empty" "$result" '.improved | length' '0'
rm -f "$lib_zero_cand_nonzero_config" "$lib_zero_cand_nonzero_baseline"

# Test: lower_is_better, baseline=0, candidate=0 → normalized_delta=0 → neutral
echo "--- Test: lower_is_better, baseline=0, candidate=0 → neutral ---"
lib_zero_zero_config=$(mktemp)
cat > "$lib_zero_zero_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "lib-zero-zero-bench",
      "command": "echo '{\"latency\": 0}'",
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
lib_zero_zero_baseline=$(mktemp)
echo '{"metrics":{"latency":0},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lib_zero_zero_baseline"
result=$("$EVALUATE" "$lib_zero_zero_config" "$lib_zero_zero_baseline" 2>/dev/null)
assert_json_field "lib-zero-zero: verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "lib-zero-zero: improved is empty" "$result" '.improved | length' '0'
assert_json_field "lib-zero-zero: regressed is empty" "$result" '.regressed | length' '0'
rm -f "$lib_zero_zero_config" "$lib_zero_zero_baseline"

# Test: lower_is_better, tolerance=0.0, candidate slightly above baseline → regress immediately
echo "--- Test: lower_is_better, tolerance=0.0, any increase → regress ---"
lib_zero_tol_config=$(mktemp)
cat > "$lib_zero_tol_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "lib-zero-tol-bench",
      "command": "echo '{\"ms\": 101}'",
      "metrics": [
        {
          "name": "ms",
          "extract": "json:.ms",
          "direction": "lower_is_better",
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
lib_zero_tol_baseline=$(mktemp)
# baseline=100, candidate=101 → delta=+1%, normalized=-1% → -0.01 < -0 → regress
echo '{"metrics":{"ms":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lib_zero_tol_baseline"
result=$("$EVALUATE" "$lib_zero_tol_config" "$lib_zero_tol_baseline" 2>/dev/null)
assert_json_field "lib-zero-tol: verdict is regress (any increase in lower_is_better with tol=0)" "$result" '.verdict' 'regress'
assert_json_field "lib-zero-tol: ms in regressed" "$result" '.regressed | contains(["ms"])' 'true'
assert_json_field "lib-zero-tol: verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
rm -f "$lib_zero_tol_config" "$lib_zero_tol_baseline"

# Test: lower_is_better, tolerance boundary — candidate exactly at +tolerance → neutral (not regress)
# ms: baseline=100, candidate=105 → delta=5%, normalized=-5%; tolerance=0.05 → -0.05 < -0.05 is false → neutral
echo "--- Test: lower_is_better, exact +tolerance → not a regress (boundary is exclusive) ---"
lib_tol_boundary_config=$(mktemp)
cat > "$lib_tol_boundary_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "lib-tol-boundary-bench",
      "command": "echo '{\"ms\": 105}'",
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
lib_tol_boundary_baseline=$(mktemp)
echo '{"metrics":{"ms":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lib_tol_boundary_baseline"
result=$("$EVALUATE" "$lib_tol_boundary_config" "$lib_tol_boundary_baseline" 2>/dev/null)
assert_json_field "lib-tol-boundary: verdict is neutral (exact boundary not regress)" "$result" '.verdict' 'neutral'
assert_json_field "lib-tol-boundary: ms not in regressed" "$result" '.regressed | length' '0'
assert_json_field "lib-tol-boundary: ms not in improved" "$result" '.improved | length' '0'
rm -f "$lib_tol_boundary_config" "$lib_tol_boundary_baseline"

echo ""
echo "=== Benchmark Command Empty Output Tests ==="

# Test: benchmark command produces empty output → metric not extracted → skipped gracefully → neutral
echo "--- Test: benchmark command empty output → metric skipped → neutral in compare mode ---"
empty_output_config=$(mktemp)
cat > "$empty_output_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "empty-output-bench",
      "command": "true",
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
empty_output_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$empty_output_baseline"
result=$("$EVALUATE" "$empty_output_config" "$empty_output_baseline" 2>/dev/null)
assert_json_field "empty-output: verdict is neutral (empty output → metric skipped)" "$result" '.verdict' 'neutral'
assert_json_field "empty-output: improved is empty (no candidate extracted)" "$result" '.improved | length' '0'
assert_json_field "empty-output: regressed is empty (skipped, not regressed)" "$result" '.regressed | length' '0'
assert_json_field "empty-output: metrics object is empty (nothing extracted)" "$result" '.metrics | length' '0'
rm -f "$empty_output_config" "$empty_output_baseline"

# Test: benchmark command empty output in init mode → metrics is empty object
echo "--- Test: benchmark command empty output in init mode → empty metrics object ---"
empty_init_config=$(mktemp)
cat > "$empty_init_config" <<EOF
{
  "gates": [],
  "benchmarks": [
    {
      "name": "empty-init-bench",
      "command": "true",
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
result=$("$EVALUATE" "$empty_init_config" /dev/null 2>/dev/null)
assert_json_field "empty-init: mode is init" "$result" '.mode' 'init'
assert_json_field "empty-init: metrics is empty (command had no output)" "$result" '.metrics | length' '0'
rm -f "$empty_init_config"

echo ""
echo "=== Boundary Just-Past Tests ==="

# Test: regression just past tolerance boundary → regress (strict < triggers here)
# val: baseline=100, candidate=97.9 → delta=-2.1%, tolerance=0.02 → -0.021 < -0.02 is TRUE → regress
echo "--- Test: regression just past tolerance boundary → regress ---"
just_past_regress_config=$(mktemp)
cat > "$just_past_regress_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "just-past-regress-bench",
      "command": "echo '{\"val\": 97.9}'",
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
just_past_regress_baseline=$(mktemp)
echo '{"metrics":{"val":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$just_past_regress_baseline"
result=$("$EVALUATE" "$just_past_regress_config" "$just_past_regress_baseline" 2>/dev/null)
assert_json_field "just-past-tol: verdict is regress (delta=-2.1% past -2% tolerance)" "$result" '.verdict' 'regress'
assert_json_field "just-past-tol: val in regressed" "$result" '.regressed | contains(["val"])' 'true'
assert_json_field "just-past-tol: verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
rm -f "$just_past_regress_config" "$just_past_regress_baseline"

# Test: improvement just past significance threshold → keep (strict > triggers here)
# val: baseline=100, candidate=101.2 → delta=1.2% > significance=0.01 → improved → keep
echo "--- Test: improvement just past significance threshold → keep ---"
just_past_sig_config=$(mktemp)
cat > "$just_past_sig_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "just-past-sig-bench",
      "command": "echo '{\"val\": 101.2}'",
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
just_past_sig_baseline=$(mktemp)
echo '{"metrics":{"val":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$just_past_sig_baseline"
result=$("$EVALUATE" "$just_past_sig_config" "$just_past_sig_baseline" 2>/dev/null)
assert_json_field "just-past-sig: verdict is keep (delta=+1.2% past 1% significance)" "$result" '.verdict' 'keep'
assert_json_field "just-past-sig: val in improved" "$result" '.improved | contains(["val"])' 'true'
assert_json_field "just-past-sig: regressed is empty" "$result" '.regressed | length' '0'
rm -f "$just_past_sig_config" "$just_past_sig_baseline"

echo ""
echo "=== Init Mode Absent Field Tests ==="

# Test: init mode output has no verdict field (verdict only appears in compare mode)
echo "--- Test: init mode output has no verdict field ---"
no_verdict_init_config=$(mktemp)
cat > "$no_verdict_init_config" <<EOF
{
  "gates": [],
  "benchmarks": [
    {
      "name": "no-verdict-bench",
      "command": "echo '{\"x\": 5}'",
      "metrics": [{"name": "x", "extract": "json:.x", "direction": "higher_is_better", "tolerance": 0.02, "significance": 0.01}]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$no_verdict_init_config" /dev/null 2>/dev/null)
has_verdict=$(echo "$result" | jq 'has("verdict")')
assert_eq "init mode: no verdict field in output" "false" "$has_verdict"
has_vl=$(echo "$result" | jq 'has("verdict_logic")')
assert_eq "init mode: no verdict_logic field in output" "false" "$has_vl"
assert_json_field "init mode: mode field is init" "$result" '.mode' 'init'
rm -f "$no_verdict_init_config"

echo ""
echo "=== Reason Field Content Tests ==="

# Test: regress reason string contains the regressed metric name(s)
echo "--- Test: regress reason string mentions the regressed metric name ---"
reason_regress_named_config=$(mktemp)
cat > "$reason_regress_named_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "reason-bench",
      "command": "echo '{\"throughput\": 40}'",
      "metrics": [
        {
          "name": "throughput",
          "extract": "json:.throughput",
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
reason_regress_named_baseline=$(mktemp)
echo '{"metrics":{"throughput":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$reason_regress_named_baseline"
result=$("$EVALUATE" "$reason_regress_named_config" "$reason_regress_named_baseline" 2>/dev/null)
assert_json_field "reason-regress: verdict is regress" "$result" '.verdict' 'regress'
reason_str=$(echo "$result" | jq -r '.reason')
if echo "$reason_str" | grep -q "throughput"; then
  echo "  PASS: regress reason mentions 'throughput' (got: $reason_str)"
  ((PASS++)) || true
else
  echo "  FAIL: regress reason should mention 'throughput' (got: $reason_str)"
  ((FAIL++)) || true
fi
rm -f "$reason_regress_named_config" "$reason_regress_named_baseline"

# Test: keep reason string contains the improved metric name
echo "--- Test: keep reason string mentions the improved metric name ---"
reason_keep_named_config=$(mktemp)
cat > "$reason_keep_named_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "reason-keep-bench",
      "command": "echo '{\"coverage\": 85}'",
      "metrics": [
        {
          "name": "coverage",
          "extract": "json:.coverage",
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
reason_keep_named_baseline=$(mktemp)
echo '{"metrics":{"coverage":70},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$reason_keep_named_baseline"
result=$("$EVALUATE" "$reason_keep_named_config" "$reason_keep_named_baseline" 2>/dev/null)
assert_json_field "reason-keep: verdict is keep" "$result" '.verdict' 'keep'
reason_keep_str=$(echo "$result" | jq -r '.reason')
if echo "$reason_keep_str" | grep -q "coverage"; then
  echo "  PASS: keep reason mentions 'coverage' (got: $reason_keep_str)"
  ((PASS++)) || true
else
  echo "  FAIL: keep reason should mention 'coverage' (got: $reason_keep_str)"
  ((FAIL++)) || true
fi
rm -f "$reason_keep_named_config" "$reason_keep_named_baseline"

echo ""
echo "=== Multi-Bench Regression Accumulation Tests ==="

# Test: first benchmark neutral, second benchmark regresses → overall regress
# bench-1: metric_x baseline=100, candidate=100 → neutral
# bench-2: metric_y baseline=100, candidate=50 → -50% regression → regress
echo "--- Test: first bench neutral, second bench regresses → overall regress ---"
multi_bench_regress_config=$(mktemp)
cat > "$multi_bench_regress_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "bench-neutral",
      "command": "echo '{\"metric_x\": 100}'",
      "metrics": [
        {
          "name": "metric_x",
          "extract": "json:.metric_x",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "bench-regress",
      "command": "echo '{\"metric_y\": 50}'",
      "metrics": [
        {
          "name": "metric_y",
          "extract": "json:.metric_y",
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
multi_bench_regress_baseline=$(mktemp)
echo '{"metrics":{"metric_x":100,"metric_y":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$multi_bench_regress_baseline"
result=$("$EVALUATE" "$multi_bench_regress_config" "$multi_bench_regress_baseline" 2>/dev/null)
assert_json_field "multi-bench-regress: verdict is regress" "$result" '.verdict' 'regress'
assert_json_field "multi-bench-regress: metric_y in regressed" "$result" '.regressed | contains(["metric_y"])' 'true'
assert_json_field "multi-bench-regress: metric_x not in regressed (neutral)" "$result" '.regressed | contains(["metric_x"])' 'false'
assert_json_field "multi-bench-regress: verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
rm -f "$multi_bench_regress_config" "$multi_bench_regress_baseline"

# Test: very large regression (-90%) → still correctly flagged as regress
echo "--- Test: very large regression (-90%) → regress ---"
huge_regress_config=$(mktemp)
cat > "$huge_regress_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "huge-regress-bench",
      "command": "echo '{\"score\": 10}'",
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
huge_regress_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$huge_regress_baseline"
result=$("$EVALUATE" "$huge_regress_config" "$huge_regress_baseline" 2>/dev/null)
assert_json_field "huge-regress: verdict is regress (10% of original)" "$result" '.verdict' 'regress'
assert_json_field "huge-regress: score in regressed" "$result" '.regressed | contains(["score"])' 'true'
# delta_pct should be -90.0000
delta_val=$(echo "$result" | jq '.metrics.score.delta_pct')
is_neg=$(echo "$delta_val < 0" | bc -l)
assert_eq "huge-regress: delta_pct is negative" "1" "$is_neg"
rm -f "$huge_regress_config" "$huge_regress_baseline"

echo ""
echo "=== Global Tolerance/Significance Fallback Tests ==="

# Test: per-metric tolerance omitted → falls back to global regression_tolerance
# score: baseline=100, candidate=97 → delta=-3%, global regression_tolerance=0.02 → -0.03 < -0.02 → regress
echo "--- Test: per-metric tolerance absent → falls back to global regression_tolerance ---"
global_tol_config=$(mktemp)
cat > "$global_tol_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "global-tol-bench",
      "command": "echo '{\"score\": 97}'",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
          "direction": "higher_is_better",
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
global_tol_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$global_tol_baseline"
result=$("$EVALUATE" "$global_tol_config" "$global_tol_baseline" 2>/dev/null)
assert_json_field "global-tol: verdict is regress (global tolerance used)" "$result" '.verdict' 'regress'
assert_json_field "global-tol: score in regressed" "$result" '.regressed | contains(["score"])' 'true'
assert_json_field "global-tol: verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
rm -f "$global_tol_config" "$global_tol_baseline"

# Test: per-metric significance omitted → falls back to global significance_threshold
# score: baseline=100, candidate=102 → delta=2%, global significance_threshold=0.03 → 0.02 > 0.03 is FALSE → neutral
echo "--- Test: per-metric significance absent → falls back to global significance_threshold ---"
global_sig_config=$(mktemp)
cat > "$global_sig_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "global-sig-bench",
      "command": "echo '{\"score\": 102}'",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
          "direction": "higher_is_better",
          "tolerance": 0.10
        }
      ]
    }
  ],
  "regression_tolerance": 0.10,
  "significance_threshold": 0.03
}
EOF
global_sig_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$global_sig_baseline"
result=$("$EVALUATE" "$global_sig_config" "$global_sig_baseline" 2>/dev/null)
# delta=+2% but global significance_threshold=3% → 0.02 > 0.03 is false → neutral
assert_json_field "global-sig: verdict is neutral (global significance used, 2% < 3% threshold)" "$result" '.verdict' 'neutral'
assert_json_field "global-sig: score not in improved (below global threshold)" "$result" '.improved | length' '0'
assert_json_field "global-sig: score not in regressed (within tolerance)" "$result" '.regressed | length' '0'
rm -f "$global_sig_config" "$global_sig_baseline"

# Test: both tolerance and significance omitted → both fall back to global values → keep verdict
# score: baseline=100, candidate=110 → delta=+10%, global significance_threshold=0.05 → 0.10 > 0.05 → improved → keep
echo "--- Test: both tolerance and significance absent → both fall back to global → keep ---"
global_both_config=$(mktemp)
cat > "$global_both_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "global-both-bench",
      "command": "echo '{\"score\": 110}'",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
          "direction": "higher_is_better"
        }
      ]
    }
  ],
  "regression_tolerance": 0.05,
  "significance_threshold": 0.05
}
EOF
global_both_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$global_both_baseline"
result=$("$EVALUATE" "$global_both_config" "$global_both_baseline" 2>/dev/null)
# delta=+10%, global significance=5% → 0.10 > 0.05 → improved → keep
assert_json_field "global-both: verdict is keep (using global thresholds)" "$result" '.verdict' 'keep'
assert_json_field "global-both: score in improved" "$result" '.improved | contains(["score"])' 'true'
assert_json_field "global-both: no regressions" "$result" '.regressed | length' '0'
rm -f "$global_both_config" "$global_both_baseline"

# Test: same metric name defined in two benchmarks → second value overwrites first in BENCH_METRICS
# bench-first outputs score=50; bench-second outputs score=120.
# In compare mode, BENCH_METRICS ends with score=120. baseline=100 → delta=+20% → improved → keep.
echo "--- Test: same metric name in two benchmarks → second value used (overwrite) ---"
dup_metric_config=$(mktemp)
cat > "$dup_metric_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "bench-first",
      "command": "echo '{\"score\": 50}'",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "bench-second",
      "command": "echo '{\"score\": 120}'",
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
dup_metric_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$dup_metric_baseline"
result=$("$EVALUATE" "$dup_metric_config" "$dup_metric_baseline" 2>/dev/null)
# bench-second's score=120 overwrites bench-first's score=50 → candidate=120 vs baseline=100 → +20% → keep
assert_json_field "dup-metric: verdict is keep (second benchmark's value used)" "$result" '.verdict' 'keep'
assert_json_field "dup-metric: score in improved (120 > 100)" "$result" '.improved | contains(["score"])' 'true'
assert_json_field "dup-metric: candidate value reflects second benchmark (120)" "$result" '.metrics.score.candidate' '120'
rm -f "$dup_metric_config" "$dup_metric_baseline"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
