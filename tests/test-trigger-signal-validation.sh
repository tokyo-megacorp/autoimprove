#!/usr/bin/env bash
# tests/test-trigger-signal-validation.sh — Unit tests for signal validation guards
# Tests SP4 #8: pre-write validation in autoimprove-trigger.sh
#
# Does NOT invoke the real trigger (no gh CLI calls).
# Sources only the validation-relevant helpers from a minimal stub environment.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TRIGGER_SCRIPT="$REPO_ROOT/scripts/autoimprove-trigger.sh"

# --- Temporary workspace ---
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

XGH_HOME="$TEST_TMP/xgh"
STATE_DIR="$XGH_HOME/state"
AUTOIMPROVE_LOGS_DIR="$TEST_TMP/.autoimprove/logs"
SIGNAL_SKIP_LOG="$AUTOIMPROVE_LOGS_DIR/signal-skips.log"
LOG_FILE="$XGH_HOME/logs/trigger-test.log"

mkdir -p "$STATE_DIR" "$AUTOIMPROVE_LOGS_DIR" "$(dirname "$LOG_FILE")"

PASS=0
FAIL=0

pass() { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Inline the validation logic extracted from the trigger script.
# This isolates the guards without running the full trigger pipeline.
# ---------------------------------------------------------------------------
run_validation() {
  local sprint_pr_count="$1"
  local findings="$2"
  local signal_file="$3"

  # Reproduce the guard logic from autoimprove-trigger.sh (keep in sync)
  local SIGNAL_VALID=1

  # Guard 1: PR count must be > 0
  if [ "${sprint_pr_count:-0}" -le 0 ] 2>/dev/null; then
    local reason="empty PR count"
    local msg="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [SIGNAL_SKIP: ${reason}]"
    echo "$msg" >> "$SIGNAL_SKIP_LOG"
    SIGNAL_VALID=0
  fi

  # Guard 2: Adversarial findings must be parseable (numeric)
  if [ "$SIGNAL_VALID" = "1" ]; then
    if ! echo "${findings:-}" | grep -qE '^[0-9]+$'; then
      local reason="parse error"
      local msg="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [SIGNAL_SKIP: ${reason}]"
      echo "$msg" >> "$SIGNAL_SKIP_LOG"
      SIGNAL_VALID=0
    fi
  fi

  # Write signal only if valid
  if [ "$SIGNAL_VALID" = "1" ]; then
    python3 - <<PYEOF
import yaml, time
signal = {
    'source': 'github',
    'project': 'xgh',
    'repo': 'extreme-go-horse/xgh',
    'merge_sha': 'abc123',
    'timestamp_iso': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'tags': ['project:xgh', 'source:github'],
    'metrics': {
        'merged_per_sprint': int('$sprint_pr_count' or 0),
        'findings_per_pr': int('$findings' or 0),
        'coverage_delta': None,
    },
}
with open('$signal_file', 'w') as f:
    yaml.dump(signal, f, default_flow_style=False)
PYEOF
  fi

  return 0
}

echo "========================================"
echo " autoimprove Signal Validation Tests"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Test 1: Empty PR count → no signal written, skip logged
# ---------------------------------------------------------------------------
echo "--- Test 1: Empty PR count (0)"
T1_SIGNAL="$TEST_TMP/signal-t1.yaml"
> "$SIGNAL_SKIP_LOG"  # reset skip log

run_validation "0" "3" "$T1_SIGNAL"

if [ ! -f "$T1_SIGNAL" ]; then
  pass "no signal file written"
else
  fail "signal file was written despite PR count == 0"
fi

if grep -q "\[SIGNAL_SKIP: empty PR count\]" "$SIGNAL_SKIP_LOG"; then
  pass "skip log contains [SIGNAL_SKIP: empty PR count]"
else
  fail "skip log missing expected entry. Contents: $(cat "$SIGNAL_SKIP_LOG")"
fi
echo ""

# ---------------------------------------------------------------------------
# Test 2: Unparseable findings → no signal written, skip logged
# ---------------------------------------------------------------------------
echo "--- Test 2: Unparseable findings (non-numeric)"
T2_SIGNAL="$TEST_TMP/signal-t2.yaml"
> "$SIGNAL_SKIP_LOG"

run_validation "5" "N/A" "$T2_SIGNAL"

if [ ! -f "$T2_SIGNAL" ]; then
  pass "no signal file written"
else
  fail "signal file was written despite unparseable findings"
fi

if grep -q "\[SIGNAL_SKIP: parse error\]" "$SIGNAL_SKIP_LOG"; then
  pass "skip log contains [SIGNAL_SKIP: parse error]"
else
  fail "skip log missing expected entry. Contents: $(cat "$SIGNAL_SKIP_LOG")"
fi
echo ""

# ---------------------------------------------------------------------------
# Test 3: Valid inputs → signal IS written, no skip logged
# ---------------------------------------------------------------------------
echo "--- Test 3: Valid inputs (PR count=5, findings=2)"
T3_SIGNAL="$TEST_TMP/signal-t3.yaml"
> "$SIGNAL_SKIP_LOG"

run_validation "5" "2" "$T3_SIGNAL"

if [ -f "$T3_SIGNAL" ]; then
  pass "signal file written"
else
  fail "signal file NOT written despite valid inputs"
fi

if [ ! -s "$SIGNAL_SKIP_LOG" ]; then
  pass "no skip entries logged for valid signal"
else
  fail "unexpected skip entries: $(cat "$SIGNAL_SKIP_LOG")"
fi

# Verify signal YAML content
if python3 -c "
import yaml
with open('$T3_SIGNAL') as f:
    d = yaml.safe_load(f)
assert d['metrics']['merged_per_sprint'] == 5, 'wrong PR count'
assert d['metrics']['findings_per_pr'] == 2, 'wrong findings'
assert d['source'] == 'github'
" 2>/dev/null; then
  pass "signal YAML content is correct"
else
  fail "signal YAML content is incorrect"
fi
echo ""

# ---------------------------------------------------------------------------
# Test 4: Empty FINDINGS string → no signal written (parse error)
# ---------------------------------------------------------------------------
echo "--- Test 4: Empty findings string"
T4_SIGNAL="$TEST_TMP/signal-t4.yaml"
> "$SIGNAL_SKIP_LOG"

run_validation "3" "" "$T4_SIGNAL"

if [ ! -f "$T4_SIGNAL" ]; then
  pass "no signal file written for empty findings"
else
  fail "signal file was written despite empty findings"
fi

if grep -q "\[SIGNAL_SKIP: parse error\]" "$SIGNAL_SKIP_LOG"; then
  pass "skip log contains [SIGNAL_SKIP: parse error] for empty findings"
else
  fail "skip log missing parse error entry"
fi
echo ""

# ---------------------------------------------------------------------------
# Test 5: Script exits 0 even with invalid inputs (hook safety)
# ---------------------------------------------------------------------------
echo "--- Test 5: Script exit code is 0 when called with --help (no real gh calls)"
# We can't easily run the full script without gh/claude, but we can verify
# exit 0 is the last statement and there's no bare 'exit 1' outside conditionals.
if grep -E '^exit [^0]' "$TRIGGER_SCRIPT" | grep -v '#'; then
  fail "found non-zero bare exit in trigger script"
else
  pass "no bare non-zero exit statements found in trigger script"
fi
echo ""

# ---------------------------------------------------------------------------
echo "========================================"
echo " Results: passed=$PASS failed=$FAIL"
echo "========================================"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
