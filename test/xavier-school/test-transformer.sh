#!/usr/bin/env bash
# Xavier School — Transformer Agent Tests
source "$(dirname "$0")/test-helpers.sh"

echo "========================================="
echo " Test Suite: transformer agent"
echo "========================================="

echo ""
echo "--- Schema Tests ---"

# Test: transformer produces valid JSON with required fields
OUTPUT=$(run_as_agent "transformer.md" "
Transform this skill based on reviewer feedback:

Original skill at /tmp/test-skill/SKILL.md:
---
name: example
description: An example skill
---
# Example
You should consider following these steps.
Try to check the code. Maybe run the tests.

Reviewer output:
{
  \"scores\": {\"pressure-resistant\": 3, \"procedural-completeness\": 4},
  \"gaps\": [
    {\"rubric\": \"pressure-resistant\", \"score\": 3, \"suggestion\": \"Replace soft language\"},
    {\"rubric\": \"procedural-completeness\", \"score\": 4, \"suggestion\": \"Add concrete steps\"}
  ]
}

Rubric transform rules for pressure-resistant:
- Replace 'should' with 'MUST'
- Replace 'try to' with direct command
- Replace 'maybe' with 'ALWAYS'
- Add red flags table

Do NOT actually write files. Instead, output the JSON report describing what you would do.
" 120)

JSON=$(extract_json "$OUTPUT")

assert_json_has_key "$JSON" "changes_summary" "changes_summary key present"
assert_json_has_key "$JSON" "rules_applied" "rules_applied key present"

# Test: changes_summary mentions the transforms
echo ""
echo "--- Transform Content Tests ---"

SUMMARY=$(echo "$JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('changes_summary',''))" 2>/dev/null)

if echo "$SUMMARY" | grep -qi "soft language\|replace.*should\|pressure"; then
  echo "  [PASS] changes_summary references pressure-resistant transforms"
  ((PASS_COUNT++))
else
  echo "  [FAIL] changes_summary does not mention expected transforms"
  ((FAIL_COUNT++))
fi

report
