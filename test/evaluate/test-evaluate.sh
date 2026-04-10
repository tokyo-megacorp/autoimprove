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
echo "=== Gate Fail Output Structure Tests ==="

# Test: gate_fail output has metrics={}, improved=[], regressed=[]
# evaluate.sh hardcodes these in the gate_fail JSON — verify the structure is correct.
echo "--- Test: gate_fail output has empty metrics, improved, and regressed ---"
gf_struct_config=$(mktemp)
echo '{"gates":[{"name":"structural-fail","command":"false"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}' > "$gf_struct_config"
result=$("$EVALUATE" "$gf_struct_config" /dev/null 2>/dev/null)
assert_json_field "gf-struct: metrics is empty object" "$result" '.metrics | length' '0'
assert_json_field "gf-struct: improved is empty array" "$result" '.improved | length' '0'
assert_json_field "gf-struct: regressed is empty array" "$result" '.regressed | length' '0'
assert_json_field "gf-struct: verdict is gate_fail" "$result" '.verdict' 'gate_fail'
rm -f "$gf_struct_config"

# Test: gate_fail reason string contains the failed gate name
# evaluate.sh sets reason="gate '$failed_gate' failed" — verify the name appears verbatim.
echo "--- Test: gate_fail reason string contains the failed gate name ---"
gf_reason_config=$(mktemp)
echo '{"gates":[{"name":"my-named-gate","command":"false"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}' > "$gf_reason_config"
result=$("$EVALUATE" "$gf_reason_config" /dev/null 2>/dev/null)
gf_reason=$(echo "$result" | jq -r '.reason')
if echo "$gf_reason" | grep -q "my-named-gate"; then
  echo "  PASS: gate_fail reason contains gate name (got: $gf_reason)"
  ((PASS++)) || true
else
  echo "  FAIL: gate_fail reason should contain gate name 'my-named-gate' (got: $gf_reason)"
  ((FAIL++)) || true
fi
rm -f "$gf_reason_config"

# Test: neutral reason string is exactly "no metrics improved beyond significance threshold"
# evaluate.sh hardcodes this exact string — verify it hasn't drifted.
echo "--- Test: neutral verdict reason is exact string 'no metrics improved beyond significance threshold' ---"
neutral_reason_config=$(mktemp)
cat > "$neutral_reason_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "stable-bench",
      "command": "echo '{\"val\": 100}'",
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
neutral_reason_baseline=$(mktemp)
echo '{"metrics":{"val":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$neutral_reason_baseline"
result=$("$EVALUATE" "$neutral_reason_config" "$neutral_reason_baseline" 2>/dev/null)
assert_json_field "neutral-reason: verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "neutral-reason: reason is exact text" "$result" '.reason' 'no metrics improved beyond significance threshold'
rm -f "$neutral_reason_config" "$neutral_reason_baseline"

# Test: delta_pct is exactly 0 when baseline equals candidate
# When baseline==candidate, delta=(c-b)/b=0, so delta_pct=0*100=0.
echo "--- Test: delta_pct is exactly 0 when baseline equals candidate ---"
zero_delta_config=$(mktemp)
cat > "$zero_delta_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "zero-delta-bench",
      "command": "echo '{\"score\": 42}'",
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
zero_delta_baseline=$(mktemp)
echo '{"metrics":{"score":42},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$zero_delta_baseline"
result=$("$EVALUATE" "$zero_delta_config" "$zero_delta_baseline" 2>/dev/null)
assert_json_field "zero-delta: verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "zero-delta: delta_pct is 0" "$result" '.metrics.score.delta_pct' '0'
assert_json_field "zero-delta: baseline value stored correctly" "$result" '.metrics.score.baseline' '42'
assert_json_field "zero-delta: candidate value stored correctly" "$result" '.metrics.score.candidate' '42'
rm -f "$zero_delta_config" "$zero_delta_baseline"

echo ""
echo "=== Multi-Bench Cross-Benchmark Regression Tests ==="

# Test: first benchmark improves a metric, second benchmark regresses a different metric → overall regress
# bench-improve: metric_p baseline=100, candidate=130 (+30%, improved)
# bench-regress: metric_q baseline=100, candidate=60 (-40%, regressed)
# regressed_count > 0 → verdict is regress, despite the improvement
echo "--- Test: first bench improves, second bench regresses → overall regress verdict ---"
cross_bench_improve_regress_config=$(mktemp)
cat > "$cross_bench_improve_regress_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "bench-improve",
      "command": "echo '{\"metric_p\": 130}'",
      "metrics": [
        {
          "name": "metric_p",
          "extract": "json:.metric_p",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "bench-regress",
      "command": "echo '{\"metric_q\": 60}'",
      "metrics": [
        {
          "name": "metric_q",
          "extract": "json:.metric_q",
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
cross_bench_baseline=$(mktemp)
echo '{"metrics":{"metric_p":100,"metric_q":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$cross_bench_baseline"
result=$("$EVALUATE" "$cross_bench_improve_regress_config" "$cross_bench_baseline" 2>/dev/null)
assert_json_field "cross-bench: verdict is regress (regression overrides improvement)" "$result" '.verdict' 'regress'
assert_json_field "cross-bench: metric_q in regressed (from second bench)" "$result" '.regressed | contains(["metric_q"])' 'true'
assert_json_field "cross-bench: metric_p in improved (from first bench)" "$result" '.improved | contains(["metric_p"])' 'true'
assert_json_field "cross-bench: verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
rm -f "$cross_bench_improve_regress_config" "$cross_bench_baseline"

# Test: exact delta_pct value for a known regression
# score: baseline=100, candidate=80 → delta=(80-100)/100 = -0.20 → delta_pct = -20.0
echo "--- Test: delta_pct exact value for a known regression (100→80 = -20.0%) ---"
delta_regress_config=$(mktemp)
cat > "$delta_regress_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "delta-regress-bench",
      "command": "echo '{\"score\": 80}'",
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
delta_regress_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$delta_regress_baseline"
result=$("$EVALUATE" "$delta_regress_config" "$delta_regress_baseline" 2>/dev/null)
assert_json_field "delta-regress: verdict is regress" "$result" '.verdict' 'regress'
delta_val=$(echo "$result" | jq '.metrics.score.delta_pct')
is_neg=$(echo "$delta_val < 0" | bc -l)
assert_eq "delta-regress: delta_pct is negative (-20%)" "1" "$is_neg"
expected_check=$(echo "$delta_val == -20" | bc -l)
assert_eq "delta-regress: delta_pct is exactly -20.0" "1" "$expected_check"
rm -f "$delta_regress_config" "$delta_regress_baseline"

# Test: regress reason string starts with the expected prefix "metric(s) regressed: "
echo "--- Test: regress reason starts with 'metric(s) regressed: ' prefix ---"
regress_prefix_config=$(mktemp)
cat > "$regress_prefix_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "prefix-bench",
      "command": "echo '{\"val\": 50}'",
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
regress_prefix_baseline=$(mktemp)
echo '{"metrics":{"val":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$regress_prefix_baseline"
result=$("$EVALUATE" "$regress_prefix_config" "$regress_prefix_baseline" 2>/dev/null)
assert_json_field "regress-prefix: verdict is regress" "$result" '.verdict' 'regress'
regress_reason=$(echo "$result" | jq -r '.reason')
if echo "$regress_reason" | grep -q "^metric(s) regressed: "; then
  echo "  PASS: regress reason has correct prefix (got: $regress_reason)"
  ((PASS++)) || true
else
  echo "  FAIL: regress reason should start with 'metric(s) regressed: ' (got: $regress_reason)"
  ((FAIL++)) || true
fi
rm -f "$regress_prefix_config" "$regress_prefix_baseline"

# Test: keep reason string starts with the expected prefix "improvement in: "
echo "--- Test: keep reason starts with 'improvement in: ' prefix ---"
keep_prefix_config=$(mktemp)
cat > "$keep_prefix_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "keep-prefix-bench",
      "command": "echo '{\"val\": 120}'",
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
keep_prefix_baseline=$(mktemp)
echo '{"metrics":{"val":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$keep_prefix_baseline"
result=$("$EVALUATE" "$keep_prefix_config" "$keep_prefix_baseline" 2>/dev/null)
assert_json_field "keep-prefix: verdict is keep" "$result" '.verdict' 'keep'
keep_reason=$(echo "$result" | jq -r '.reason')
if echo "$keep_reason" | grep -q "^improvement in: "; then
  echo "  PASS: keep reason has correct prefix (got: $keep_reason)"
  ((PASS++)) || true
else
  echo "  FAIL: keep reason should start with 'improvement in: ' (got: $keep_reason)"
  ((FAIL++)) || true
fi
rm -f "$keep_prefix_config" "$keep_prefix_baseline"

echo ""
echo "=== Init Mode Absent Fields Tests ==="

# Test: init mode output does NOT include improved, regressed, or verdict_logic fields
# evaluate.sh emits only {mode, gates, metrics} in init mode. None of the scoring fields
# (improved, regressed, verdict, verdict_logic) should be present.
echo "--- Test: init mode output has no improved, regressed, or verdict_logic fields ---"
init_absent_config=$(mktemp)
cat > "$init_absent_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "init-absent-bench",
      "command": "echo '{\"score\": 42}'",
      "metrics": [{"name": "score", "extract": "json:.score", "direction": "higher_is_better", "tolerance": 0.02, "significance": 0.01}]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$init_absent_config" /dev/null 2>/dev/null)
assert_eq "init-absent: no improved field" "false" "$(echo "$result" | jq 'has("improved")')"
assert_eq "init-absent: no regressed field" "false" "$(echo "$result" | jq 'has("regressed")')"
assert_eq "init-absent: no verdict_logic field" "false" "$(echo "$result" | jq 'has("verdict_logic")')"
assert_json_field "init-absent: mode is init" "$result" '.mode' 'init'
rm -f "$init_absent_config"

# Test: gate fail in init mode (no baseline) still produces gate_fail verdict, not init mode output
# evaluate.sh runs gates first, before checking INIT_MODE. A failing gate short-circuits to
# gate_fail output regardless of whether a baseline was supplied.
echo "--- Test: gate fail with no baseline → gate_fail verdict (not init mode) ---"
gate_fail_init_config=$(mktemp)
echo '{"gates":[{"name":"init-fail-gate","command":"false"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}' > "$gate_fail_init_config"
result=$("$EVALUATE" "$gate_fail_init_config" /dev/null 2>/dev/null)
assert_json_field "gate-fail-init: verdict is gate_fail (not init)" "$result" '.verdict' 'gate_fail'
assert_eq "gate-fail-init: no mode field (gate_fail preempts init)" "false" "$(echo "$result" | jq 'has("mode")')"
assert_json_field "gate-fail-init: verdict_logic is gate_fast_fail" "$result" '.verdict_logic' 'gate_fast_fail'
rm -f "$gate_fail_init_config"

# Test: no_benchmarks verdict_logic value is exactly "no_benchmarks" (distinct from "no_improvements")
# When benchmark_count=0 and a baseline is present, evaluate.sh emits verdict_logic: "no_benchmarks".
# This path is different from the scoring path that emits verdict_logic: "no_improvements".
echo "--- Test: zero benchmarks with baseline → verdict_logic is exactly 'no_benchmarks' (not 'no_improvements') ---"
no_bench_vl_config=$(mktemp)
echo '{"gates":[{"name":"pass","command":"true"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}' > "$no_bench_vl_config"
no_bench_vl_baseline=$(mktemp)
echo '{"metrics":{"score":42},"sha":"abc","timestamp":"2026-03-25T00:00:00Z"}' > "$no_bench_vl_baseline"
result=$("$EVALUATE" "$no_bench_vl_config" "$no_bench_vl_baseline" 2>/dev/null)
assert_json_field "no-bench-vl: verdict_logic is no_benchmarks" "$result" '.verdict_logic' 'no_benchmarks'
assert_json_field "no-bench-vl: verdict is neutral" "$result" '.verdict' 'neutral'
# Confirm it is NOT the scoring-path value
assert_eq "no-bench-vl: verdict_logic is not no_improvements" "false" "$([ "$(echo "$result" | jq -r '.verdict_logic')" = "no_improvements" ] && echo true || echo false)"
rm -f "$no_bench_vl_config" "$no_bench_vl_baseline"

# Test: three passing gates all appear in init mode output with passed=true
# Verifies that run_gates accumulates results for all gates (not just the last) when all pass.
echo "--- Test: three passing gates all appear in output ---"
three_gates_config=$(mktemp)
cat > "$three_gates_config" <<EOF
{
  "gates": [
    {"name": "gate-alpha", "command": "true"},
    {"name": "gate-beta",  "command": "true"},
    {"name": "gate-gamma", "command": "true"}
  ],
  "benchmarks": [],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$three_gates_config" /dev/null 2>/dev/null)
assert_json_field "three-gates: 3 gates in output" "$result" '.gates | length' '3'
assert_json_field "three-gates: gate-alpha passed" "$result" '.gates[0].passed' 'true'
assert_json_field "three-gates: gate-beta passed"  "$result" '.gates[1].passed' 'true'
assert_json_field "three-gates: gate-gamma passed" "$result" '.gates[2].passed' 'true'
assert_json_field "three-gates: gate-alpha name correct" "$result" '.gates[0].name' 'gate-alpha'
assert_json_field "three-gates: gate-gamma name correct" "$result" '.gates[2].name' 'gate-gamma'
rm -f "$three_gates_config"

echo ""
echo "=== Reason String Comma-Separator Tests ==="

# Test: multiple regressed metrics → reason string lists all with comma-space separator
# evaluate.sh builds reason via: jq -r 'join(", ")' on SCORE_REGRESSED array.
# With two regressed metrics (a, b), the reason should contain "a, b" (comma + space).
echo "--- Test: multiple regressions → reason lists all metric names comma-separated ---"
multi_regress_reason_config=$(mktemp)
cat > "$multi_regress_reason_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "multi-regress-reason-bench",
      "command": "echo '{\"alpha\": 50, \"beta\": 60}'",
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
multi_regress_reason_baseline=$(mktemp)
# alpha: 100→50 (-50%), beta: 100→60 (-40%) — both regress
echo '{"metrics":{"alpha":100,"beta":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$multi_regress_reason_baseline"
result=$("$EVALUATE" "$multi_regress_reason_config" "$multi_regress_reason_baseline" 2>/dev/null)
assert_json_field "multi-regress-reason: verdict is regress" "$result" '.verdict' 'regress'
mr_reason=$(echo "$result" | jq -r '.reason')
if echo "$mr_reason" | grep -q "alpha"; then
  echo "  PASS: multi-regress reason mentions 'alpha' (got: $mr_reason)"
  ((PASS++)) || true
else
  echo "  FAIL: multi-regress reason should mention 'alpha' (got: $mr_reason)"
  ((FAIL++)) || true
fi
if echo "$mr_reason" | grep -q "beta"; then
  echo "  PASS: multi-regress reason mentions 'beta' (got: $mr_reason)"
  ((PASS++)) || true
else
  echo "  FAIL: multi-regress reason should mention 'beta' (got: $mr_reason)"
  ((FAIL++)) || true
fi
# The join(", ") produces "alpha, beta" — verify comma-space separator is present
if echo "$mr_reason" | grep -q ", "; then
  echo "  PASS: multi-regress reason has comma-space separator (got: $mr_reason)"
  ((PASS++)) || true
else
  echo "  FAIL: multi-regress reason should use comma-space separator (got: $mr_reason)"
  ((FAIL++)) || true
fi
rm -f "$multi_regress_reason_config" "$multi_regress_reason_baseline"

# Test: multiple improved metrics → reason string lists all with comma-space separator
# evaluate.sh builds reason via: jq -r 'join(", ")' on SCORE_IMPROVED array.
echo "--- Test: multiple improvements → reason lists all metric names comma-separated ---"
multi_improve_reason_config=$(mktemp)
cat > "$multi_improve_reason_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "multi-improve-reason-bench",
      "command": "echo '{\"alpha\": 130, \"beta\": 150}'",
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
multi_improve_reason_baseline=$(mktemp)
# alpha: 100→130 (+30%), beta: 100→150 (+50%) — both improve
echo '{"metrics":{"alpha":100,"beta":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$multi_improve_reason_baseline"
result=$("$EVALUATE" "$multi_improve_reason_config" "$multi_improve_reason_baseline" 2>/dev/null)
assert_json_field "multi-improve-reason: verdict is keep" "$result" '.verdict' 'keep'
mi_reason=$(echo "$result" | jq -r '.reason')
if echo "$mi_reason" | grep -q "alpha"; then
  echo "  PASS: multi-improve reason mentions 'alpha' (got: $mi_reason)"
  ((PASS++)) || true
else
  echo "  FAIL: multi-improve reason should mention 'alpha' (got: $mi_reason)"
  ((FAIL++)) || true
fi
if echo "$mi_reason" | grep -q "beta"; then
  echo "  PASS: multi-improve reason mentions 'beta' (got: $mi_reason)"
  ((PASS++)) || true
else
  echo "  FAIL: multi-improve reason should mention 'beta' (got: $mi_reason)"
  ((FAIL++)) || true
fi
if echo "$mi_reason" | grep -q ", "; then
  echo "  PASS: multi-improve reason has comma-space separator (got: $mi_reason)"
  ((PASS++)) || true
else
  echo "  FAIL: multi-improve reason should use comma-space separator (got: $mi_reason)"
  ((FAIL++)) || true
fi
rm -f "$multi_improve_reason_config" "$multi_improve_reason_baseline"

echo ""
echo "=== Passing Gate exit_code=0 Test ==="

# Test: passing gate records exit_code=0 in output
# run_gates stores exit_code for every gate. For a command that returns 0,
# exit_code in the JSON should be 0 (not null, not absent).
echo "--- Test: passing gate has exit_code=0 in output ---"
pass_exit_config=$(mktemp)
cat > "$pass_exit_config" <<EOF
{
  "gates": [{"name": "pass-ec", "command": "true"}],
  "benchmarks": [],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$pass_exit_config" /dev/null 2>/dev/null)
assert_json_field "pass-exit: gate passed=true" "$result" '.gates[0].passed' 'true'
assert_json_field "pass-exit: exit_code is 0" "$result" '.gates[0].exit_code' '0'
assert_json_field "pass-exit: exit_code is number type" "$result" '.gates[0].exit_code | type' 'number'
rm -f "$pass_exit_config"

echo ""
echo "=== Negative Metric Value Tests ==="

# Test: benchmark outputs a negative number → stored as JSON number (not string)
# The run_benchmarks regex is ^-?[0-9]+(\.[0-9]+)?$ which matches negative integers and floats.
# A metric like "delta: -5" should be stored as the number -5, not the string "-5".
echo "--- Test: negative metric value stored as JSON number type ---"
neg_metric_config=$(mktemp)
cat > "$neg_metric_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "neg-metric-bench",
      "command": "echo '{\"delta\": -5}'",
      "metrics": [
        {
          "name": "delta",
          "extract": "json:.delta",
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
result=$("$EVALUATE" "$neg_metric_config" /dev/null 2>/dev/null)
assert_json_field "neg-metric: mode is init" "$result" '.mode' 'init'
assert_json_field "neg-metric: delta stored as number type" "$result" '.metrics.delta | type' 'number'
delta_neg=$(echo "$result" | jq '.metrics.delta')
if [ "$(echo "$delta_neg < 0" | bc -l)" = "1" ]; then
  echo "  PASS: neg-metric: delta value is negative (got $delta_neg)"
  ((PASS++)) || true
else
  echo "  FAIL: neg-metric: delta value should be negative (got $delta_neg)"
  ((FAIL++)) || true
fi
rm -f "$neg_metric_config"

echo ""
echo "=== Skipped Metric Absent from compare metrics Object ==="

# Test: when a metric is skipped (missing candidate), it is absent from .metrics in compare output
# The score_results loop only calls SCORE_METRICS_JSON += {k: v} when neither val is empty.
# A metric with no candidate value should NOT appear as a key in .metrics at all.
echo "--- Test: skipped metric (no candidate) is absent from .metrics object in compare output ---"
skip_absent_config=$(mktemp)
cat > "$skip_absent_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "skip-absent-bench",
      "command": "echo '{\"present\": 110}'",
      "metrics": [
        {
          "name": "present",
          "extract": "json:.present",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "absent",
          "extract": "json:.nonexistent_key",
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
skip_absent_baseline=$(mktemp)
# baseline has both; candidate only emits "present" → "absent" has no candidate → skipped
echo '{"metrics":{"present":100,"absent":50},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$skip_absent_baseline"
result=$("$EVALUATE" "$skip_absent_config" "$skip_absent_baseline" 2>/dev/null)
assert_json_field "skip-absent: verdict is keep (present improved)" "$result" '.verdict' 'keep'
assert_json_field "skip-absent: present IS in .metrics object" "$result" '.metrics | has("present")' 'true'
# Skipped metric must not appear in .metrics comparison object
absent_in_metrics=$(echo "$result" | jq '.metrics | has("absent")')
assert_eq "skip-absent: absent metric NOT in .metrics object (was skipped)" "false" "$absent_in_metrics"
assert_json_field "skip-absent: .metrics has exactly 1 key (only present)" "$result" '.metrics | keys | length' '1'
rm -f "$skip_absent_config" "$skip_absent_baseline"

echo ""
echo "=== Untested Path: direction field defaults, gate_fail with baseline, benchmark with empty metrics ==="

# Test: direction field omitted → defaults to higher_is_better
# evaluate.sh line 171: direction=$(jq -r ".benchmarks[$i].metrics[$j].direction // \"higher_is_better\"" "$CONFIG")
# When the direction key is absent, the jq // fallback returns "higher_is_better".
# An improvement (value goes up) should be scored as improved → keep.
echo "--- Test: omitted direction field defaults to higher_is_better ---"
no_dir_config=$(mktemp)
cat > "$no_dir_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "no-dir-bench",
      "command": "echo '{\"score\": 120}'",
      "metrics": [
        {
          "name": "score",
          "extract": "json:.score",
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
no_dir_baseline=$(mktemp)
# score: baseline=100, candidate=120 → +20%. Without direction, defaults to higher_is_better → improved → keep
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$no_dir_baseline"
result=$("$EVALUATE" "$no_dir_config" "$no_dir_baseline" 2>/dev/null)
assert_json_field "no-dir: verdict is keep (direction defaults to higher_is_better)" "$result" '.verdict' 'keep'
assert_json_field "no-dir: score in improved (higher value is better by default)" "$result" '.improved | contains(["score"])' 'true'
assert_json_field "no-dir: regressed is empty" "$result" '.regressed | length' '0'
# direction field in .metrics object should reflect the default value used
assert_json_field "no-dir: metrics.score.direction is higher_is_better" "$result" '.metrics.score.direction' 'higher_is_better'
rm -f "$no_dir_config" "$no_dir_baseline"

# Test: gate_fail output when a real baseline file IS present (compare mode entry blocked by gate)
# evaluate.sh runs gates before checking INIT_MODE: a gate fail short-circuits before compare scoring.
# The gate_fail output must be emitted even when BASELINE points to a real (valid) file.
echo "--- Test: gate_fail when real baseline file is present → gate_fail preempts compare mode ---"
gf_baseline_config=$(mktemp)
cat > "$gf_baseline_config" <<EOF
{
  "gates": [{"name": "blocking-gate", "command": "false"}],
  "benchmarks": [
    {
      "name": "should-not-run",
      "command": "echo '{\"score\": 999}'",
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
gf_real_baseline=$(mktemp)
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$gf_real_baseline"
result=$("$EVALUATE" "$gf_baseline_config" "$gf_real_baseline" 2>/dev/null)
# Gate fails → gate_fail verdict regardless of baseline presence
assert_json_field "gf-baseline: verdict is gate_fail (not regress/neutral)" "$result" '.verdict' 'gate_fail'
assert_json_field "gf-baseline: verdict_logic is gate_fast_fail" "$result" '.verdict_logic' 'gate_fast_fail'
assert_json_field "gf-baseline: no mode field (compare mode blocked)" "$result" 'has("mode")' 'false'
# benchmark must NOT have been scored — metrics object is empty
assert_json_field "gf-baseline: metrics is empty (benchmark never ran)" "$result" '.metrics | length' '0'
assert_json_field "gf-baseline: improved is empty" "$result" '.improved | length' '0'
rm -f "$gf_baseline_config" "$gf_real_baseline"

# Test: gate_fail reason string has exact format: "gate '<name>' failed" with single quotes
# evaluate.sh line 262: reason "gate '$failed_gate' failed"
# Earlier tests verify the name appears in the reason; this test checks the full format.
echo "--- Test: gate_fail reason has exact format with single quotes around gate name ---"
gf_fmt_config=$(mktemp)
echo '{"gates":[{"name":"exact-name","command":"false"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}' > "$gf_fmt_config"
result=$("$EVALUATE" "$gf_fmt_config" /dev/null 2>/dev/null)
gf_fmt_reason=$(echo "$result" | jq -r '.reason')
expected_reason="gate 'exact-name' failed"
assert_eq "gf-fmt: reason is exactly \"gate 'exact-name' failed\"" "$expected_reason" "$gf_fmt_reason"
rm -f "$gf_fmt_config"

# Test: benchmark with zero metrics in its metrics array — inner loop runs 0 times
# BENCH_METRICS accumulates nothing for this benchmark. The gate passes. In init mode,
# the output should be {mode: "init", gates: [...], metrics: {}} with an empty metrics object.
echo "--- Test: benchmark with empty metrics array → no metrics extracted → empty metrics object ---"
zero_metrics_bench_config=$(mktemp)
cat > "$zero_metrics_bench_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "zero-metrics-bench",
      "command": "echo '{\"score\": 42}'",
      "metrics": []
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$zero_metrics_bench_config" /dev/null 2>/dev/null)
assert_json_field "zero-metrics-bench: mode is init" "$result" '.mode' 'init'
assert_json_field "zero-metrics-bench: metrics is empty object (no metrics defined)" "$result" '.metrics | length' '0'
assert_json_field "zero-metrics-bench: gates ran (1 gate)" "$result" '.gates | length' '1'
rm -f "$zero_metrics_bench_config"

# Test: direction defaulting to higher_is_better causes a regression to be flagged correctly
# Without explicit direction, a drop in value (120→80) should be a regression (higher_is_better by default).
echo "--- Test: omitted direction field defaults to higher_is_better — regression detected on drop ---"
no_dir_regress_config=$(mktemp)
cat > "$no_dir_regress_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "no-dir-regress-bench",
      "command": "echo '{\"throughput\": 80}'",
      "metrics": [
        {
          "name": "throughput",
          "extract": "json:.throughput",
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
no_dir_regress_baseline=$(mktemp)
# throughput: baseline=120, candidate=80 → -33.3%, defaults to higher_is_better → regression
echo '{"metrics":{"throughput":120},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$no_dir_regress_baseline"
result=$("$EVALUATE" "$no_dir_regress_config" "$no_dir_regress_baseline" 2>/dev/null)
assert_json_field "no-dir-regress: verdict is regress (direction defaulted to higher_is_better)" "$result" '.verdict' 'regress'
assert_json_field "no-dir-regress: throughput in regressed" "$result" '.regressed | contains(["throughput"])' 'true'
assert_json_field "no-dir-regress: verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
rm -f "$no_dir_regress_config" "$no_dir_regress_baseline"

echo ""
echo "=== Compare Mode Gates Array Tests ==="

# Test: compare mode output includes a gates array with correct gate entries
# evaluate.sh emits GATE_RESULTS in both init and compare mode output.
# Verify that compare mode (with a real baseline) includes gates[] with correct names and passed flags.
echo "--- Test: compare mode output includes populated gates array ---"
compare_gates_config=$(mktemp)
cat > "$compare_gates_config" <<EOF
{
  "gates": [
    {"name": "g1-pass", "command": "true"},
    {"name": "g2-pass", "command": "true"}
  ],
  "benchmarks": [
    {
      "name": "cg-bench",
      "command": "echo '{\"val\": 110}'",
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
compare_gates_baseline=$(mktemp)
echo '{"metrics":{"val":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$compare_gates_baseline"
result=$("$EVALUATE" "$compare_gates_config" "$compare_gates_baseline" 2>/dev/null)
assert_json_field "compare-gates: verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "compare-gates: gates array has 2 entries" "$result" '.gates | length' '2'
assert_json_field "compare-gates: gates[0].name is g1-pass" "$result" '.gates[0].name' 'g1-pass'
assert_json_field "compare-gates: gates[0].passed is true" "$result" '.gates[0].passed' 'true'
assert_json_field "compare-gates: gates[1].name is g2-pass" "$result" '.gates[1].name' 'g2-pass'
assert_json_field "compare-gates: gates[1].passed is true" "$result" '.gates[1].passed' 'true'
assert_json_field "compare-gates: gates array present (has key)" "$result" 'has("gates")' 'true'
rm -f "$compare_gates_config" "$compare_gates_baseline"

# Test: compare mode with a single gate also emits gates array (not empty)
echo "--- Test: compare mode with single gate emits single-entry gates array ---"
compare_one_gate_config=$(mktemp)
cat > "$compare_one_gate_config" <<EOF
{
  "gates": [{"name": "solo-gate", "command": "true"}],
  "benchmarks": [
    {
      "name": "one-gate-bench",
      "command": "echo '{\"metric\": 50}'",
      "metrics": [
        {
          "name": "metric",
          "extract": "json:.metric",
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
compare_one_gate_baseline=$(mktemp)
echo '{"metrics":{"metric":50},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$compare_one_gate_baseline"
result=$("$EVALUATE" "$compare_one_gate_config" "$compare_one_gate_baseline" 2>/dev/null)
# metric is unchanged (neutral) — gates still populate
assert_json_field "compare-one-gate: verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "compare-one-gate: gates array length is 1" "$result" '.gates | length' '1'
assert_json_field "compare-one-gate: gate name is solo-gate" "$result" '.gates[0].name' 'solo-gate'
assert_json_field "compare-one-gate: gate passed is true" "$result" '.gates[0].passed' 'true'
assert_json_field "compare-one-gate: gate has exit_code key" "$result" '.gates[0] | has("exit_code")' 'true'
assert_json_field "compare-one-gate: gate has duration_ms key" "$result" '.gates[0] | has("duration_ms")' 'true'
rm -f "$compare_one_gate_config" "$compare_one_gate_baseline"

echo ""
echo "=== Three Separate Benchmarks All Regress Tests ==="

# Test: 3 separate benchmarks, each with 1 metric, all regress → all 3 in regressed[], verdict=regress
# bench-1: metric_a (100→10, -90%), bench-2: metric_b (100→20, -80%), bench-3: metric_c (100→30, -70%)
# All are separate benchmark objects — verifies that regression accumulates across benchmark boundaries.
echo "--- Test: 3 separate benchmarks all regress → all 3 in regressed[], reason lists all 3 ---"
three_bench_all_regress_config=$(mktemp)
cat > "$three_bench_all_regress_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "bench-1",
      "command": "echo '{\"metric_a\": 10}'",
      "metrics": [
        {
          "name": "metric_a",
          "extract": "json:.metric_a",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "bench-2",
      "command": "echo '{\"metric_b\": 20}'",
      "metrics": [
        {
          "name": "metric_b",
          "extract": "json:.metric_b",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "bench-3",
      "command": "echo '{\"metric_c\": 30}'",
      "metrics": [
        {
          "name": "metric_c",
          "extract": "json:.metric_c",
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
three_bench_all_regress_baseline=$(mktemp)
echo '{"metrics":{"metric_a":100,"metric_b":100,"metric_c":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$three_bench_all_regress_baseline"
result=$("$EVALUATE" "$three_bench_all_regress_config" "$three_bench_all_regress_baseline" 2>/dev/null)
assert_json_field "3-bench-regress: verdict is regress" "$result" '.verdict' 'regress'
assert_json_field "3-bench-regress: verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
regressed_len=$(echo "$result" | jq '.regressed | length')
assert_eq "3-bench-regress: regressed array has 3 entries" "3" "$regressed_len"
assert_json_field "3-bench-regress: metric_a in regressed" "$result" '.regressed | contains(["metric_a"])' 'true'
assert_json_field "3-bench-regress: metric_b in regressed" "$result" '.regressed | contains(["metric_b"])' 'true'
assert_json_field "3-bench-regress: metric_c in regressed" "$result" '.regressed | contains(["metric_c"])' 'true'
assert_json_field "3-bench-regress: improved is empty" "$result" '.improved | length' '0'
# reason lists all 3 metric names comma-separated
r3_reason=$(echo "$result" | jq -r '.reason')
if echo "$r3_reason" | grep -q "metric_a"; then
  echo "  PASS: 3-bench-regress reason mentions metric_a"
  ((PASS++)) || true
else
  echo "  FAIL: 3-bench-regress reason missing metric_a (got: $r3_reason)"
  ((FAIL++)) || true
fi
if echo "$r3_reason" | grep -q "metric_b"; then
  echo "  PASS: 3-bench-regress reason mentions metric_b"
  ((PASS++)) || true
else
  echo "  FAIL: 3-bench-regress reason missing metric_b (got: $r3_reason)"
  ((FAIL++)) || true
fi
if echo "$r3_reason" | grep -q "metric_c"; then
  echo "  PASS: 3-bench-regress reason mentions metric_c"
  ((PASS++)) || true
else
  echo "  FAIL: 3-bench-regress reason missing metric_c (got: $r3_reason)"
  ((FAIL++)) || true
fi
rm -f "$three_bench_all_regress_config" "$three_bench_all_regress_baseline"

echo ""
echo "=== Three-Benchmark Mixed Accumulation Tests ==="

# Test: bench-1 neutral, bench-2 improves, bench-3 regresses → regress wins
# metric_x: 100→100 (neutral), metric_y: 100→130 (+30%, improved), metric_z: 100→50 (-50%, regressed)
# regression_detected overrides the improvement — verdict is regress
echo "--- Test: 3 benchmarks neutral+improve+regress → regress verdict wins ---"
three_bench_mixed_config=$(mktemp)
cat > "$three_bench_mixed_config" <<EOF
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
      "name": "bench-improve",
      "command": "echo '{\"metric_y\": 130}'",
      "metrics": [
        {
          "name": "metric_y",
          "extract": "json:.metric_y",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "bench-regress",
      "command": "echo '{\"metric_z\": 50}'",
      "metrics": [
        {
          "name": "metric_z",
          "extract": "json:.metric_z",
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
three_bench_mixed_baseline=$(mktemp)
echo '{"metrics":{"metric_x":100,"metric_y":100,"metric_z":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$three_bench_mixed_baseline"
result=$("$EVALUATE" "$three_bench_mixed_config" "$three_bench_mixed_baseline" 2>/dev/null)
assert_json_field "3-bench-mixed: verdict is regress (regression wins over improvement)" "$result" '.verdict' 'regress'
assert_json_field "3-bench-mixed: metric_z in regressed" "$result" '.regressed | contains(["metric_z"])' 'true'
assert_json_field "3-bench-mixed: metric_y in improved" "$result" '.improved | contains(["metric_y"])' 'true'
assert_json_field "3-bench-mixed: metric_x not in improved (neutral)" "$result" '.improved | contains(["metric_x"])' 'false'
assert_json_field "3-bench-mixed: metric_x not in regressed (neutral)" "$result" '.regressed | contains(["metric_x"])' 'false'
assert_json_field "3-bench-mixed: verdict_logic is regression_detected" "$result" '.verdict_logic' 'regression_detected'
rm -f "$three_bench_mixed_config" "$three_bench_mixed_baseline"

# Test: bench-1 improves, bench-2 improves, bench-3 improves → keep, all 3 in improved[]
echo "--- Test: 3 separate benchmarks all improve → keep verdict, all 3 in improved[] ---"
three_bench_all_improve_config=$(mktemp)
cat > "$three_bench_all_improve_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "bench-a",
      "command": "echo '{\"alpha\": 120}'",
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
      "command": "echo '{\"beta\": 150}'",
      "metrics": [
        {
          "name": "beta",
          "extract": "json:.beta",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "bench-c",
      "command": "echo '{\"gamma\": 200}'",
      "metrics": [
        {
          "name": "gamma",
          "extract": "json:.gamma",
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
three_bench_all_improve_baseline=$(mktemp)
echo '{"metrics":{"alpha":100,"beta":100,"gamma":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$three_bench_all_improve_baseline"
result=$("$EVALUATE" "$three_bench_all_improve_config" "$three_bench_all_improve_baseline" 2>/dev/null)
assert_json_field "3-bench-improve: verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "3-bench-improve: alpha in improved" "$result" '.improved | contains(["alpha"])' 'true'
assert_json_field "3-bench-improve: beta in improved" "$result" '.improved | contains(["beta"])' 'true'
assert_json_field "3-bench-improve: gamma in improved" "$result" '.improved | contains(["gamma"])' 'true'
assert_json_field "3-bench-improve: improved length is 3" "$result" '.improved | length' '3'
assert_json_field "3-bench-improve: regressed is empty" "$result" '.regressed | length' '0'
assert_json_field "3-bench-improve: verdict_logic is no_regressions_and_at_least_one_improvement" "$result" '.verdict_logic' 'no_regressions_and_at_least_one_improvement'
rm -f "$three_bench_all_improve_config" "$three_bench_all_improve_baseline"

echo ""
echo "=== Shell Extractor Multi-Line Output Tests ==="

# Test: shell extractor with head -1 takes only the first line of multi-line output
# The benchmark command emits multiple lines; the extractor (head -1) reads only line 1.
# This verifies that shell extractors work correctly and are not broken by multi-line output.
echo "--- Test: shell extractor head -1 extracts only first line from multi-line output ---"
multiline_config=$(mktemp)
cat > "$multiline_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "multiline-bench",
      "command": "printf '42\n99\n77\n'",
      "metrics": [
        {
          "name": "first_line",
          "extract": "head -1",
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
result=$("$EVALUATE" "$multiline_config" /dev/null 2>/dev/null)
assert_json_field "multiline-extractor: mode is init" "$result" '.mode' 'init'
assert_json_field "multiline-extractor: first_line is 42 (only first line taken)" "$result" '.metrics.first_line' '42'
# Confirm second and third line values (99, 77) did not bleed into the metric
ml_val=$(echo "$result" | jq '.metrics.first_line')
assert_eq "multiline-extractor: value is exactly 42 (not 99 or 77)" "42" "$ml_val"
rm -f "$multiline_config"

# Test: shell extractor tail -1 extracts only the last line from multi-line output
echo "--- Test: shell extractor tail -1 extracts only last line from multi-line output ---"
tail_config=$(mktemp)
cat > "$tail_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "tail-bench",
      "command": "printf '10\n20\n30\n'",
      "metrics": [
        {
          "name": "last_line",
          "extract": "tail -1",
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
result=$("$EVALUATE" "$tail_config" /dev/null 2>/dev/null)
assert_json_field "tail-extractor: mode is init" "$result" '.mode' 'init'
assert_json_field "tail-extractor: last_line is 30 (tail -1 extracts last line)" "$result" '.metrics.last_line' '30'
rm -f "$tail_config"


echo ""
echo "=== Benchmark Non-Zero Exit with Output Tests ==="

# Test: benchmark command exits non-zero but still emits valid JSON to stdout → metric IS extracted
# evaluate.sh uses set+e / set-e guard around bench_cmd: the exit code is ignored for benchmarks.
# The output captured in bench_output is whatever the command wrote to stdout, regardless of exit code.
# This is different from the "exit 1 no output" case — here the benchmark fails AND produces metrics.
echo "--- Test: benchmark exits non-zero with valid output → metric extracted in init mode ---"
fail_output_init_config=$(mktemp)
cat > "$fail_output_init_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "partial-fail-bench",
      "command": "sh -c 'printf \"{\\\\\"score\\\\\": 77}\"; exit 1'",
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
result=$("$EVALUATE" "$fail_output_init_config" /dev/null 2>/dev/null)
assert_json_field "fail-output-init: mode is init (gates passed)" "$result" '.mode' 'init'
assert_json_field "fail-output-init: score extracted despite non-zero exit" "$result" '.metrics.score' '77'
assert_json_field "fail-output-init: score is number type" "$result" '.metrics.score | type' 'number'
rm -f "$fail_output_init_config"

# Test: benchmark exits non-zero but produces valid output in compare mode → scoring occurs normally
# The metric value extracted from the failing benchmark is used for comparison just like any other.
# This verifies that benchmark exit code has no bearing on scoring — only the output content matters.
echo "--- Test: benchmark exits non-zero with valid output → scoring occurs normally in compare mode ---"
fail_output_compare_config=$(mktemp)
cat > "$fail_output_compare_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "partial-fail-compare-bench",
      "command": "sh -c 'printf \"{\\\\\"throughput\\\\\": 110}\"; exit 2'",
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
fail_output_compare_baseline=$(mktemp)
echo '{"metrics":{"throughput":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$fail_output_compare_baseline"
result=$("$EVALUATE" "$fail_output_compare_config" "$fail_output_compare_baseline" 2>/dev/null)
# throughput 100→110 (+10%) → improved → keep (exit code of benchmark is irrelevant)
assert_json_field "fail-output-compare: verdict is keep (non-zero exit ignored for scoring)" "$result" '.verdict' 'keep'
assert_json_field "fail-output-compare: throughput in improved" "$result" '.improved | contains(["throughput"])' 'true'
assert_json_field "fail-output-compare: no regressions (exit code irrelevant)" "$result" '.regressed | length' '0'
assert_json_field "fail-output-compare: candidate is 110 (from failing benchmark output)" "$result" '.metrics.throughput.candidate' '110'
rm -f "$fail_output_compare_config" "$fail_output_compare_baseline"

# Test: shell extractor returning literal string "null" → metric is silently skipped
# run_benchmarks checks: if [ -n "$raw_value" ] && [ "$raw_value" != "null" ]
# A shell extractor that outputs the literal word "null" (not empty) hits the != "null" guard and is skipped.
# This is distinct from: (a) empty output (fails -n check), (b) json:. returning null (jq -r emits "null" string).
echo "--- Test: shell extractor returning literal 'null' string → metric silently skipped ---"
null_extractor_config=$(mktemp)
cat > "$null_extractor_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "null-string-bench",
      "command": "echo 'result: null'",
      "metrics": [
        {
          "name": "val",
          "extract": "grep -oE 'null'",
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
result=$("$EVALUATE" "$null_extractor_config" /dev/null 2>/dev/null)
assert_json_field "null-extractor: mode is init (gates passed)" "$result" '.mode' 'init'
assert_json_field "null-extractor: metrics is empty (null string skipped)" "$result" '.metrics | length' '0'
# 'val' must not appear in metrics — not stored as the string "null" or as null JSON
null_in_metrics=$(echo "$result" | jq '.metrics | has("val")')
assert_eq "null-extractor: val absent from metrics (not stored as null string)" "false" "$null_in_metrics"
rm -f "$null_extractor_config"

# Test: json:. extractor returning null (absent key) is also skipped in compare mode
# When `jq -r` is given a key that doesn't exist, it returns the string "null".
# The [ "$raw_value" != "null" ] guard skips it → metric not extracted → not regressed.
echo "--- Test: json: extractor returning 'null' string for absent key → metric skipped in compare mode ---"
json_null_config=$(mktemp)
cat > "$json_null_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "json-null-bench",
      "command": "echo '{\"existing\": 50}'",
      "metrics": [
        {
          "name": "existing",
          "extract": "json:.existing",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        },
        {
          "name": "ghost",
          "extract": "json:.ghost_key",
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
json_null_baseline=$(mktemp)
# baseline has both keys; candidate output only has "existing" — "ghost" returns null from jq
echo '{"metrics":{"existing":40,"ghost":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$json_null_baseline"
result=$("$EVALUATE" "$json_null_config" "$json_null_baseline" 2>/dev/null)
# existing: 40→50 (+25%) → improved; ghost: jq returns "null" → skipped (not regressed even with baseline=100)
assert_json_field "json-null: verdict is keep (existing improved, ghost skipped)" "$result" '.verdict' 'keep'
assert_json_field "json-null: existing in improved" "$result" '.improved | contains(["existing"])' 'true'
assert_json_field "json-null: ghost NOT in regressed (skipped by null guard)" "$result" '.regressed | contains(["ghost"])' 'false'
assert_json_field "json-null: ghost NOT in improved (skipped)" "$result" '.improved | contains(["ghost"])' 'false'
assert_json_field "json-null: ghost absent from .metrics (not scored)" "$result" '.metrics | has("ghost")' 'false'
rm -f "$json_null_config" "$json_null_baseline"

echo ""
echo "=== Baseline Structure Gap Tests ==="

# Test: baseline is valid JSON but has no .metrics key → jq returns empty for every metric →
# all metrics skipped (no candidate comparison possible) → neutral verdict
echo "--- Test: baseline missing .metrics key → all metrics skipped → neutral ---"
no_metrics_key_config=$(mktemp)
cat > "$no_metrics_key_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "no-metrics-key-bench",
      "command": "echo '{\"score\": 80}'",
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
# Baseline is valid JSON but has no .metrics key — jq .metrics["score"] // empty → empty → skip
no_metrics_key_baseline=$(mktemp)
echo '{"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$no_metrics_key_baseline"
result=$("$EVALUATE" "$no_metrics_key_config" "$no_metrics_key_baseline" 2>/dev/null)
assert_json_field "no-metrics-key: verdict is neutral (no baseline values to compare)" "$result" '.verdict' 'neutral'
assert_json_field "no-metrics-key: improved is empty (all metrics skipped)" "$result" '.improved | length' '0'
assert_json_field "no-metrics-key: regressed is empty (all metrics skipped)" "$result" '.regressed | length' '0'
assert_json_field "no-metrics-key: verdict_logic is no_improvements" "$result" '.verdict_logic' 'no_improvements'
rm -f "$no_metrics_key_config" "$no_metrics_key_baseline"

# Test: baseline has .metrics as empty object {} → no values for any metric → all skipped → neutral
# Different from missing .metrics key — here .metrics exists but has no entries.
echo "--- Test: baseline with empty .metrics object → all metrics skipped → neutral ---"
empty_metrics_baseline_config=$(mktemp)
cat > "$empty_metrics_baseline_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "empty-metrics-baseline-bench",
      "command": "echo '{\"count\": 42}'",
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
empty_metrics_obj_baseline=$(mktemp)
echo '{"metrics":{},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$empty_metrics_obj_baseline"
result=$("$EVALUATE" "$empty_metrics_baseline_config" "$empty_metrics_obj_baseline" 2>/dev/null)
assert_json_field "empty-metrics-obj: verdict is neutral (no baseline values)" "$result" '.verdict' 'neutral'
assert_json_field "empty-metrics-obj: improved is empty" "$result" '.improved | length' '0'
assert_json_field "empty-metrics-obj: regressed is empty" "$result" '.regressed | length' '0'
rm -f "$empty_metrics_baseline_config" "$empty_metrics_obj_baseline"

echo ""
echo "=== Regression Within Tolerance Tests ==="

# Test: regression within tolerance (not at boundary, not past it) → neutral
# score: baseline=100, candidate=99 → delta=-1%; tolerance=0.02 → -0.01 < -0.02 is FALSE → neutral
# This is distinct from the "at boundary" test (exactly -2%) and "just past" test (97.9).
echo "--- Test: regression within tolerance (not at boundary) → neutral ---"
within_tol_config=$(mktemp)
cat > "$within_tol_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "within-tol-bench",
      "command": "echo '{\"score\": 99}'",
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
within_tol_baseline=$(mktemp)
# score: 100→99, delta=-1%, tolerance=2% → within tolerance → NOT regressed → neutral
echo '{"metrics":{"score":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$within_tol_baseline"
result=$("$EVALUATE" "$within_tol_config" "$within_tol_baseline" 2>/dev/null)
assert_json_field "within-tol: verdict is neutral (-1% drop within 2% tolerance)" "$result" '.verdict' 'neutral'
assert_json_field "within-tol: score not in regressed (within tolerance)" "$result" '.regressed | contains(["score"])' 'false'
assert_json_field "within-tol: score not in improved (below significance)" "$result" '.improved | contains(["score"])' 'false'
assert_json_field "within-tol: verdict_logic is no_improvements" "$result" '.verdict_logic' 'no_improvements'
rm -f "$within_tol_config" "$within_tol_baseline"

# Test: lower_is_better regression within tolerance → neutral
# latency: baseline=100, candidate=103 → delta=+3% raw, normalized=-3%; tolerance=0.05 → -0.03 < -0.05 is FALSE → neutral
echo "--- Test: lower_is_better regression within tolerance → neutral ---"
lib_within_tol_config=$(mktemp)
cat > "$lib_within_tol_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "lib-within-tol-bench",
      "command": "echo '{\"latency\": 103}'",
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
lib_within_tol_baseline=$(mktemp)
# latency: 100→103, delta=+3% raw → normalized=-3% → -0.03 < -0.05 is FALSE → not regressed
# and -0.03 > +0.02 is also FALSE → not improved → neutral
echo '{"metrics":{"latency":100},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$lib_within_tol_baseline"
result=$("$EVALUATE" "$lib_within_tol_config" "$lib_within_tol_baseline" 2>/dev/null)
assert_json_field "lib-within-tol: verdict is neutral (3% increase within 5% tolerance)" "$result" '.verdict' 'neutral'
assert_json_field "lib-within-tol: latency not in regressed (within tolerance)" "$result" '.regressed | contains(["latency"])' 'false'
assert_json_field "lib-within-tol: latency not in improved" "$result" '.improved | contains(["latency"])' 'false'
assert_json_field "lib-within-tol: verdict_logic is no_improvements" "$result" '.verdict_logic' 'no_improvements'
rm -f "$lib_within_tol_config" "$lib_within_tol_baseline"

echo ""
echo "=== LLM-Judge Benchmark Type Tests ==="

# Test: llm-judge benchmark is skipped by default (no --include-llm-benchmarks flag)
# Without the flag, benchmarks typed "llm-judge" are silently skipped.
# In init mode this means the metric never appears in .metrics.
echo "--- Test: llm-judge benchmark skipped in default mode (no flag) ---"
llm_skip_config=$(mktemp)
cat > "$llm_skip_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "llm-bench",
      "type": "llm-judge",
      "command": "echo '{\"quality\": 99}'",
      "metrics": [
        {
          "name": "quality",
          "extract": "json:.quality",
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
result=$("$EVALUATE" "$llm_skip_config" /dev/null 2>/dev/null)
assert_json_field "llm-judge skipped: mode is init" "$result" '.mode' 'init'
# quality metric must NOT appear — llm-judge was skipped
quality_present=$(echo "$result" | jq 'has("metrics") and (.metrics | has("quality"))')
assert_eq "llm-judge skipped: quality not in metrics" "false" "$quality_present"
rm -f "$llm_skip_config"

# Test: llm-judge benchmark IS included when --include-llm-benchmarks is passed
echo "--- Test: llm-judge benchmark included with --include-llm-benchmarks flag ---"
llm_include_config=$(mktemp)
cat > "$llm_include_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "llm-bench",
      "type": "llm-judge",
      "command": "echo '{\"quality\": 88}'",
      "metrics": [
        {
          "name": "quality",
          "extract": "json:.quality",
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
result=$("$EVALUATE" "$llm_include_config" /dev/null --include-llm-benchmarks 2>/dev/null)
assert_json_field "llm-judge included: mode is init" "$result" '.mode' 'init'
assert_json_field "llm-judge included: quality metric extracted" "$result" '.metrics.quality' '88'
rm -f "$llm_include_config"

# Test: mixed benchmarks (one deterministic, one llm-judge) — without flag only deterministic runs
echo "--- Test: mixed deterministic+llm-judge — only deterministic runs without flag ---"
mixed_llm_config=$(mktemp)
cat > "$mixed_llm_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "fast-bench",
      "type": "deterministic",
      "command": "echo '{\"count\": 42}'",
      "metrics": [
        {
          "name": "count",
          "extract": "json:.count",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    },
    {
      "name": "slow-bench",
      "type": "llm-judge",
      "command": "echo '{\"score\": 99}'",
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
result=$("$EVALUATE" "$mixed_llm_config" /dev/null 2>/dev/null)
assert_json_field "mixed: count metric present (deterministic)" "$result" '.metrics.count' '42'
score_present=$(echo "$result" | jq 'has("metrics") and (.metrics | has("score"))')
assert_eq "mixed: score metric absent (llm-judge skipped)" "false" "$score_present"
rm -f "$mixed_llm_config"

# Test: llm-judge benchmark participates in scoring when flag is passed
# quality: baseline=80, candidate=88 → delta=+10% > significance=0.01 → improved → keep
echo "--- Test: llm-judge participates in scoring with --include-llm-benchmarks ---"
llm_score_config=$(mktemp)
cat > "$llm_score_config" <<EOF
{
  "gates": [{"name": "pass", "command": "true"}],
  "benchmarks": [
    {
      "name": "llm-score-bench",
      "type": "llm-judge",
      "command": "echo '{\"quality\": 88}'",
      "metrics": [
        {
          "name": "quality",
          "extract": "json:.quality",
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
llm_score_baseline=$(mktemp)
echo '{"metrics":{"quality":80},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$llm_score_baseline"
result=$("$EVALUATE" "$llm_score_config" "$llm_score_baseline" --include-llm-benchmarks 2>/dev/null)
assert_json_field "llm scoring: verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "llm scoring: quality in improved" "$result" '.improved | contains(["quality"])' 'true'
assert_json_field "llm scoring: no regressions" "$result" '.regressed | length' '0'
rm -f "$llm_score_config" "$llm_score_baseline"

echo ""
echo "=== cleanup-worktrees.sh Tests ==="

CLEANUP="$SCRIPT_DIR/../../scripts/cleanup-worktrees.sh"

# Helper: create a minimal git repo in a temp directory for cleanup tests.
# Prints the repo path. Caller must rm -rf it on exit.
_make_cleanup_repo() {
  local d
  d=$(mktemp -d)
  git init "$d" >/dev/null 2>&1
  git -C "$d" config user.email "test@test.com" 2>/dev/null
  git -C "$d" config user.name "Test" 2>/dev/null
  git -C "$d" commit --allow-empty -m "init" >/dev/null 2>&1
  echo "$d"
}

# Test: --help exits 0 and prints usage text containing key phrases
echo "--- Test: cleanup-worktrees --help exits 0 and prints usage ---"
set +e
help_out=$(bash "$CLEANUP" --help 2>&1)
help_exit=$?
set -e
if [ "$help_exit" -eq 0 ]; then
  echo "  PASS: --help exits 0"
  ((PASS++)) || true
else
  echo "  FAIL: --help should exit 0 (got $help_exit)"
  ((FAIL++)) || true
fi
if echo "$help_out" | grep -q "dry-run"; then
  echo "  PASS: --help output mentions --dry-run"
  ((PASS++)) || true
else
  echo "  FAIL: --help output should mention --dry-run"
  ((FAIL++)) || true
fi

# Test: unknown flag exits 2 with error message on stderr
echo "--- Test: cleanup-worktrees unknown flag exits 2 ---"
set +e
unknown_err=$(bash "$CLEANUP" --not-a-real-flag 2>&1 >/dev/null)
unknown_exit=$?
set -e
if [ "$unknown_exit" -eq 2 ]; then
  echo "  PASS: unknown flag exits 2"
  ((PASS++)) || true
else
  echo "  FAIL: unknown flag should exit 2 (got $unknown_exit)"
  ((FAIL++)) || true
fi
if echo "$unknown_err" | grep -q "unknown argument"; then
  echo "  PASS: unknown flag error message mentions 'unknown argument'"
  ((PASS++)) || true
else
  echo "  FAIL: unknown flag error message should mention 'unknown argument' (got: $unknown_err)"
  ((FAIL++)) || true
fi

# Test: clean repo (no orphan branches) → summary line shows 0 worktrees, 0 branches, exits 0
echo "--- Test: cleanup-worktrees clean repo → 0 removed, exits 0 ---"
clean_repo=$(_make_cleanup_repo)
trap "rm -rf '$clean_repo'" EXIT
set +e
clean_out=$(cd "$clean_repo" && bash "$CLEANUP" 2>/dev/null)
clean_exit=$?
set -e
if [ "$clean_exit" -eq 0 ]; then
  echo "  PASS: clean repo exits 0 (idempotent)"
  ((PASS++)) || true
else
  echo "  FAIL: clean repo should exit 0 (got $clean_exit)"
  ((FAIL++)) || true
fi
if echo "$clean_out" | grep -q "\[cleanup\] 0 worktrees, 0 branches removed"; then
  echo "  PASS: clean repo summary shows 0 worktrees, 0 branches"
  ((PASS++)) || true
else
  echo "  FAIL: clean repo summary should show '0 worktrees, 0 branches removed' (got: $clean_out)"
  ((FAIL++)) || true
fi
rm -rf "$clean_repo"
trap - EXIT

# Test: dry-run with autoimprove/* orphan branch → would-delete line, no real deletion
echo "--- Test: cleanup-worktrees dry-run autoimprove branch → would-delete, not deleted ---"
dr_repo=$(_make_cleanup_repo)
trap "rm -rf '$dr_repo'" EXIT
git -C "$dr_repo" checkout -b "autoimprove/exp-099-test" >/dev/null 2>&1
git -C "$dr_repo" checkout main >/dev/null 2>&1
set +e
dr_out=$(cd "$dr_repo" && bash "$CLEANUP" --dry-run 2>/dev/null)
set -e
if echo "$dr_out" | grep -q "would-delete: branch autoimprove/exp-099-test"; then
  echo "  PASS: dry-run shows would-delete for autoimprove/* branch"
  ((PASS++)) || true
else
  echo "  FAIL: dry-run should show would-delete for autoimprove/* branch (got: $dr_out)"
  ((FAIL++)) || true
fi
# Branch must still exist after dry-run
if git -C "$dr_repo" rev-parse --verify "autoimprove/exp-099-test" >/dev/null 2>&1; then
  echo "  PASS: dry-run did not delete the branch (branch still exists)"
  ((PASS++)) || true
else
  echo "  FAIL: dry-run should not delete the branch (branch was deleted)"
  ((FAIL++)) || true
fi
# Summary line must include (dry-run)
if echo "$dr_out" | grep -q "(dry-run)"; then
  echo "  PASS: dry-run summary line includes '(dry-run)' suffix"
  ((PASS++)) || true
else
  echo "  FAIL: dry-run summary should include '(dry-run)' suffix (got: $dr_out)"
  ((FAIL++)) || true
fi
rm -rf "$dr_repo"
trap - EXIT

# Test: real mode with autoimprove/* orphan branch → deleted line, branch actually removed
echo "--- Test: cleanup-worktrees real mode autoimprove branch → deleted, branch gone ---"
real_repo=$(_make_cleanup_repo)
trap "rm -rf '$real_repo'" EXIT
git -C "$real_repo" checkout -b "autoimprove/exp-100-test" >/dev/null 2>&1
git -C "$real_repo" checkout main >/dev/null 2>&1
set +e
real_out=$(cd "$real_repo" && bash "$CLEANUP" 2>/dev/null)
set -e
if echo "$real_out" | grep -q "deleted: branch autoimprove/exp-100-test"; then
  echo "  PASS: real mode shows deleted line for autoimprove/* branch"
  ((PASS++)) || true
else
  echo "  FAIL: real mode should show deleted line (got: $real_out)"
  ((FAIL++)) || true
fi
# Branch must be gone after real mode
if ! git -C "$real_repo" rev-parse --verify "autoimprove/exp-100-test" >/dev/null 2>&1; then
  echo "  PASS: real mode deleted the branch (branch no longer exists)"
  ((PASS++)) || true
else
  echo "  FAIL: real mode should have deleted the branch"
  ((FAIL++)) || true
fi
rm -rf "$real_repo"
trap - EXIT

# Test: worktree-agent-* namespace also cleaned up (not just autoimprove/*)
echo "--- Test: cleanup-worktrees picks up worktree-agent-* branches ---"
wa_repo=$(_make_cleanup_repo)
trap "rm -rf '$wa_repo'" EXIT
git -C "$wa_repo" checkout -b "worktree-agent-exp-042" >/dev/null 2>&1
git -C "$wa_repo" checkout main >/dev/null 2>&1
set +e
wa_out=$(cd "$wa_repo" && bash "$CLEANUP" --dry-run 2>/dev/null)
set -e
if echo "$wa_out" | grep -q "would-delete: branch worktree-agent-exp-042"; then
  echo "  PASS: worktree-agent-* branch appears in dry-run would-delete list"
  ((PASS++)) || true
else
  echo "  FAIL: worktree-agent-* branch should appear in dry-run list (got: $wa_out)"
  ((FAIL++)) || true
fi
if echo "$wa_out" | grep -q "\[cleanup\] 0 worktrees, 1 branches removed"; then
  echo "  PASS: summary shows 1 branch removed for worktree-agent-* match"
  ((PASS++)) || true
else
  echo "  FAIL: summary should show 1 branch removed (got: $wa_out)"
  ((FAIL++)) || true
fi
rm -rf "$wa_repo"
trap - EXIT

# Test: tagged exp-* branch is protected (Guard B) — not deleted even in real mode
echo "--- Test: cleanup-worktrees skips exp-* tagged autoimprove branch (Guard B) ---"
tag_repo=$(_make_cleanup_repo)
trap "rm -rf '$tag_repo'" EXIT
git -C "$tag_repo" checkout -b "autoimprove/exp-101-kept" >/dev/null 2>&1
git -C "$tag_repo" tag exp-101 >/dev/null 2>&1
git -C "$tag_repo" checkout main >/dev/null 2>&1
set +e
tag_out=$(cd "$tag_repo" && bash "$CLEANUP" 2>/dev/null)
set -e
# Tagged branch must still exist
if git -C "$tag_repo" rev-parse --verify "autoimprove/exp-101-kept" >/dev/null 2>&1; then
  echo "  PASS: tagged exp-* branch was protected (not deleted)"
  ((PASS++)) || true
else
  echo "  FAIL: tagged exp-* branch should be protected (was deleted)"
  ((FAIL++)) || true
fi
# Summary should show 0 branches removed
if echo "$tag_out" | grep -q "\[cleanup\] 0 worktrees, 0 branches removed"; then
  echo "  PASS: summary shows 0 branches removed (tagged branch skipped)"
  ((PASS++)) || true
else
  echo "  FAIL: tagged branch should not be counted as removed (got: $tag_out)"
  ((FAIL++)) || true
fi
rm -rf "$tag_repo"
trap - EXIT

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
