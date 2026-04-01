#!/usr/bin/env bash
# tests/test-diff-skill.sh — Regression test for aggregate diff range guidance
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="$SCRIPT_DIR/skills/diff/SKILL.md"

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

echo "========================================"
echo " diff skill aggregate-range tests"
echo "========================================"
echo ""

echo "--- Test 1: obsolete tail-based range is absent ---"
assert_expr "aggregate mode no longer uses git log ... tail -1" "! grep -q 'git log --oneline <hash_1> <hash_2> ... | tail -1' '$SKILL_FILE'"
echo ""

echo "--- Test 2: aggregate mode uses selected experiment endpoints ---"
assert_expr "aggregate mode defines oldest selected hash" "grep -q 'FIRST_COMMIT=<oldest_selected_hash>' '$SKILL_FILE'"
assert_expr "aggregate mode defines newest selected hash" "grep -q 'LAST_COMMIT=<newest_selected_hash>' '$SKILL_FILE'"
assert_expr "aggregate mode warns against tail-based history walk" "grep -q 'repository.s initial commit\|repository\x27s initial commit' '$SKILL_FILE'"
echo ""

echo "========================================"
echo " Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

[ "$FAIL" -eq 0 ]