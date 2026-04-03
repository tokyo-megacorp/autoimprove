#!/usr/bin/env bash
# Xavier School — Reviewer Agent Tests
source "$(dirname "$0")/test-helpers.sh"

echo "========================================="
echo " Test Suite: reviewer agent"
echo "========================================="

# --- Agent Output Tests ---

echo ""
echo "--- Schema Tests ---"

# Test: reviewer produces valid JSON with required fields
OUTPUT=$(run_as_agent "reviewer.md" "
Review this skill for quality:

---
name: example-skill
description: A basic example skill
---

# Example

You should consider following these steps:
1. Try to check the code
2. Maybe run the tests
3. Consider committing

Skill type: discipline-enforcing
Rubrics to apply: pressure-resistant, procedural-completeness

Score each rubric 0-10 and output JSON.
" 90)

JSON=$(extract_json "$OUTPUT")

assert_json_has_key "$JSON" "scores" "scores key present"
assert_json_has_key "$JSON" "gaps" "gaps key present"
assert_json_has_key "$JSON" "skill_type" "skill_type key present"

# Test: scores are honest (weak skill should score low)
echo ""
echo "--- Score Accuracy Tests ---"

# The example skill above uses soft language ("should", "try to", "maybe")
# so pressure-resistant should score low
PRESSURE_SCORE=$(echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
scores = d.get('scores', {})
print(scores.get('pressure-resistant', scores.get('pressure_resistant', -1)))
" 2>/dev/null)

if [ "$PRESSURE_SCORE" != "-1" ] && [ "$PRESSURE_SCORE" -le 4 ] 2>/dev/null; then
  echo "  [PASS] pressure-resistant scored low ($PRESSURE_SCORE) for weak skill"
  ((PASS_COUNT++))
else
  echo "  [FAIL] pressure-resistant score ($PRESSURE_SCORE) too high for skill with 'should/try/maybe'"
  ((FAIL_COUNT++))
fi

report
