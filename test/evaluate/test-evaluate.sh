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
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
