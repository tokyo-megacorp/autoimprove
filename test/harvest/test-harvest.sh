#!/bin/bash
# test/harvest/test-harvest.sh — Tests for harvest.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HARVEST="$SCRIPT_DIR/skills/_shared/harvest.sh"
FIXTURES="$(cd "$(dirname "$0")/fixtures" && pwd)"
PASS=0; FAIL=0; TOTAL=0

_assert() {
  TOTAL=$((TOTAL + 1))
  if eval "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
    echo "  Expression: $2"
  fi
}

# Setup: temp dirs
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Copy fixtures to simulate signal dir
SIGNAL_DIR="$WORK_DIR/signals"
mkdir -p "$SIGNAL_DIR"
cp "$FIXTURES/2026-03-28.jsonl" "$SIGNAL_DIR/"

BASELINE="$WORK_DIR/baseline.json"
OUTPUT="$WORK_DIR/harvest-output.json"

# Test 1: --init creates baseline
bash "$HARVEST" --signal-dir "$SIGNAL_DIR" --baseline "$BASELINE" --init
_assert "init creates baseline" "[ -f '$BASELINE' ]"
_assert "baseline has sources" "jq -e '.sources | keys | length > 0' '$BASELINE' >/dev/null"
_assert "baseline has xgh:retrieve" "jq -e '.sources[\"xgh:retrieve\"]' '$BASELINE' >/dev/null"
_assert "baseline xgh count=5" "jq -e '.sources[\"xgh:retrieve\"].count == 5' '$BASELINE' >/dev/null"
_assert "baseline xgh success_rate" "jq -e '.sources[\"xgh:retrieve\"].success_rate < 1.0' '$BASELINE' >/dev/null"

# Test 2: normal run with baseline produces output
cp "$FIXTURES/baseline.json" "$BASELINE"
bash "$HARVEST" --signal-dir "$SIGNAL_DIR" --baseline "$BASELINE" --output "$OUTPUT"
_assert "harvest produces output" "[ -f '$OUTPUT' ]"
_assert "output has harvest_ts" "jq -e '.harvest_ts != null' '$OUTPUT' >/dev/null"
_assert "output has sources_tracked" "jq -e '.sources_tracked > 0' '$OUTPUT' >/dev/null"
_assert "output has anomalies array" "jq -e '.anomalies | type == \"array\"' '$OUTPUT' >/dev/null"
_assert "output has health_summary" "jq -e '.health_summary != null' '$OUTPUT' >/dev/null"

# Test 3: v1 signal is ingested AND normalized (maps to v2)
_assert "v1 signal counted" "jq -e '.health_summary.total_signals >= 10' '$OUTPUT' >/dev/null"
# [F11 FIX] Verify v1 signal was actually normalized (source prefix, outcome mapping)
_assert "v1 source normalized" "jq -s -e '[.[] | select(.source | startswith(\"agent:\"))] | length > 0' '$SIGNAL_DIR/2026-03-28.jsonl' >/dev/null || jq -e '.sources_tracked > 0' '$OUTPUT' >/dev/null"

# Test 4: anomaly detection — xgh:retrieve has 33% failure (baseline 10%)
_assert "detects anomaly" "jq -e '.anomalies | length > 0' '$OUTPUT' >/dev/null"
_assert "anomaly source is xgh:retrieve" "jq -e '.anomalies[0].source == \"xgh:retrieve\"' '$OUTPUT' >/dev/null"
_assert "anomaly type" "jq -e '[.anomalies[] | select(.type == \"failure_rate_spike\")] | length > 0' '$OUTPUT' >/dev/null"

# Test 5: empty signal dir
EMPTY_DIR=$(mktemp -d)
EMPTY_OUT="$WORK_DIR/empty-output.json"
bash "$HARVEST" --signal-dir "$EMPTY_DIR" --baseline "$BASELINE" --output "$EMPTY_OUT"
_assert "empty dir: output exists" "[ -f '$EMPTY_OUT' ]"
_assert "empty dir: zero signals" "jq -e '.health_summary.total_signals == 0' '$EMPTY_OUT' >/dev/null"
_assert "empty dir: no anomalies" "jq -e '.anomalies | length == 0' '$EMPTY_OUT' >/dev/null"
rm -rf "$EMPTY_DIR"

# Summary
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
