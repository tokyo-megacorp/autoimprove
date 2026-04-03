#!/usr/bin/env bash
# Xavier School — Polish Skill Tests
source "$(dirname "$0")/test-helpers.sh"

echo "========================================="
echo " Test Suite: polish skill"
echo "========================================="

# --- Triggering Tests ---

echo ""
echo "--- Triggering Tests ---"

LOG=$(run_with_plugin "Polish my skill and improve its quality")
assert_skill_triggered "$LOG" "polish" "explicit polish request"

LOG=$(run_with_plugin "Review my skill for quality issues")
assert_skill_triggered "$LOG" "polish" "review quality triggers polish"

LOG=$(run_with_plugin "I just created a new skill, can you check it?")
assert_skill_triggered "$LOG" "polish" "new skill check triggers polish"

# --- Negative Tests ---

echo ""
echo "--- Negative Tests ---"

LOG=$(run_with_plugin "Create a new skill for code review")
assert_skill_not_triggered "$LOG" "polish" "skill creation does not trigger polish"

LOG=$(run_with_plugin "Fix the bug in my Python code")
assert_skill_not_triggered "$LOG" "polish" "general coding does not trigger polish"

# --- Explicit Request Tests ---

echo ""
echo "--- Explicit Request Tests ---"

LOG=$(run_with_plugin "xavier-school:polish")
assert_skill_triggered "$LOG" "polish" "explicit skill name triggers"

# Check no premature work
FIRST_SKILL_LINE=$(grep -n '"name":"Skill"' "$LOG" | head -1 | cut -d: -f1)
if [ -n "$FIRST_SKILL_LINE" ]; then
  PREMATURE=$(head -n "$FIRST_SKILL_LINE" "$LOG" | \
    grep '"type":"tool_use"' | \
    grep -v '"name":"Skill"' | \
    grep -v '"name":"TodoWrite"')
  if [ -n "$PREMATURE" ]; then
    echo "  [FAIL] premature work before skill load"
    ((FAIL_COUNT++))
  else
    echo "  [PASS] no premature tool use before skill load"
    ((PASS_COUNT++))
  fi
fi

report
