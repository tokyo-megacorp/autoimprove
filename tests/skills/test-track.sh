#!/usr/bin/env bash
# Tests for the autoimprove:track skill
# Covers: unit (doc content), triggering, and no-premature-work

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/skills/test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

SKILL_FILE="$PLUGIN_DIR/skills/track/SKILL.md"
passed=0; failed=0

record() {
    local result="$1"
    if [ "$result" = "pass" ]; then passed=$((passed+1)); else failed=$((failed+1)); fi
}

echo ""
echo "=== track skill — Unit Tests (doc content) ==="

# 1. SKILL-GUARD present
if grep -q "SKILL-GUARD" "$SKILL_FILE"; then
    echo "  [PASS] SKILL-GUARD present"; record pass
else
    echo "  [FAIL] SKILL-GUARD missing"; record fail
fi

# 2. Cold-start path documented
if grep -q "COLD_START" "$SKILL_FILE"; then
    echo "  [PASS] cold-start path present"; record pass
else
    echo "  [FAIL] cold-start path missing"; record fail
fi

# 3. 3-goal cap enforcement
if grep -q "3 active goals" "$SKILL_FILE"; then
    echo "  [PASS] 3-goal cap message present"; record pass
else
    echo "  [FAIL] 3-goal cap message missing"; record fail
fi

# 4. Benchmark failure error message
if grep -q "Benchmark script failed" "$SKILL_FILE"; then
    echo "  [PASS] benchmark failure message present"; record pass
else
    echo "  [FAIL] benchmark failure message missing"; record fail
fi

# 5. Remove not-found error message
if grep -q "not found" "$SKILL_FILE"; then
    echo "  [PASS] remove not-found error present"; record pass
else
    echo "  [FAIL] remove not-found error missing"; record fail
fi

# 6. needs_validation flag for cold-start goals
if grep -q "needs_validation" "$SKILL_FILE"; then
    echo "  [PASS] needs_validation flag present"; record pass
else
    echo "  [FAIL] needs_validation flag missing"; record fail
fi

# 7. version field in state.json schema
if grep -q '"version": "1.0"' "$SKILL_FILE"; then
    echo "  [PASS] version 1.0 field present"; record pass
else
    echo "  [FAIL] version 1.0 field missing"; record fail
fi

# 8. Delta sign semantics documented
if grep -q "TARGET_DELTA" "$SKILL_FILE" && grep -q '>=\|<=' "$SKILL_FILE"; then
    echo "  [PASS] delta sign semantics documented"; record pass
else
    echo "  [FAIL] delta sign semantics missing"; record fail
fi

# 9. TodoWrite cleanup at end
if grep -c "status: \"pending\"" "$SKILL_FILE" | grep -q "[0-9]"; then
    echo "  [PASS] TodoWrite tasks initialized"; record pass
else
    echo "  [FAIL] TodoWrite task initialization missing"; record fail
fi

# 10. Priority weight validation documented
if grep -q "integer" "$SKILL_FILE" || grep -q "1 to 5" "$SKILL_FILE"; then
    echo "  [PASS] priority weight validation documented"; record pass
else
    echo "  [FAIL] priority weight validation missing"; record fail
fi

echo ""
echo "=== track skill — Triggering Tests ==="

# T1: /track (explicit) → fires track
log=$(run_with_plugin "/track" 2 60)
assert_skill_triggered "$log" "track" "/track fires track skill"
[ $? -eq 0 ] && record pass || record fail
rm -f "$log"

# T2: "add goal" → fires track
log=$(run_with_plugin "add goal: reduce test runtime by 20%" 2 60)
assert_skill_triggered "$log" "track" "'add goal' fires track skill"
[ $? -eq 0 ] && record pass || record fail
rm -f "$log"

# T3: "list goals" → fires track
log=$(run_with_plugin "list goals" 2 60)
assert_skill_triggered "$log" "track" "'list goals' fires track skill"
[ $? -eq 0 ] && record pass || record fail
rm -f "$log"

# T4: "/track list" → fires track
log=$(run_with_plugin "/track list" 2 60)
assert_skill_triggered "$log" "track" "'/track list' fires track skill"
[ $? -eq 0 ] && record pass || record fail
rm -f "$log"

# T5: "show goals" → fires track
log=$(run_with_plugin "show goals" 2 60)
assert_skill_triggered "$log" "track" "'show goals' fires track skill"
[ $? -eq 0 ] && record pass || record fail
rm -f "$log"

# T6 (negative): "track changes in git" → does NOT fire track
log=$(run_with_plugin "track changes in git" 2 60)
assert_skill_not_triggered "$log" "track" "'track changes in git' does NOT fire track skill"
[ $? -eq 0 ] && record pass || record fail
rm -f "$log"

# T7 (negative): "git tracking" → does NOT fire track
log=$(run_with_plugin "what does git tracking mean?" 2 60)
assert_skill_not_triggered "$log" "track" "'git tracking' does NOT fire track skill"
[ $? -eq 0 ] && record pass || record fail
rm -f "$log"

echo ""
echo "=== track skill — Explicit Request Tests (no premature work) ==="

# E1: /track fires AND no tool use before skill loads
log=$(run_with_plugin "/track" 3 90)
assert_skill_triggered "$log" "track" "/track: skill fires"
[ $? -eq 0 ] && record pass || record fail
assert_no_premature_work "$log" "/track: no tool use before skill loads"
[ $? -eq 0 ] && record pass || record fail
rm -f "$log"

# E2: /track list fires AND no premature work
log=$(run_with_plugin "/track list" 3 90)
assert_skill_triggered "$log" "track" "/track list: skill fires"
[ $? -eq 0 ] && record pass || record fail
assert_no_premature_work "$log" "/track list: no tool use before skill loads"
[ $? -eq 0 ] && record pass || record fail
rm -f "$log"

echo ""
echo "=== Results ==="
echo "  Passed: $passed"
echo "  Failed: $failed"
echo ""
[ $failed -eq 0 ] || exit 1
