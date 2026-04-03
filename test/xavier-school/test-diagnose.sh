#!/usr/bin/env bash
# Xavier School — Diagnose Skill Tests
source "$(dirname "$0")/test-helpers.sh"

echo "========================================="
echo " Test Suite: diagnose skill"
echo "========================================="

# --- Triggering Tests ---

echo ""
echo "--- Triggering Tests ---"

LOG=$(run_with_plugin "Classify this skill for me and tell me what type it is")
assert_skill_triggered "$LOG" "diagnose" "naive prompt triggers diagnose"

LOG=$(run_with_plugin "What type of skill is my TDD skill?")
assert_skill_triggered "$LOG" "diagnose" "skill type question triggers diagnose"

# --- Negative Tests ---

echo ""
echo "--- Negative Tests ---"

LOG=$(run_with_plugin "Write a hello world function in Python")
assert_skill_not_triggered "$LOG" "diagnose" "unrelated coding prompt does not trigger"

LOG=$(run_with_plugin "What is the capital of France?")
assert_skill_not_triggered "$LOG" "diagnose" "general knowledge does not trigger"

# --- Unit Tests ---

echo ""
echo "--- Unit Tests ---"

OUTPUT=$(run_claude "According to the Xavier School diagnose skill, what are the four skill types?")
assert_contains "$OUTPUT" "discipline" "mentions discipline-enforcing type"
assert_contains "$OUTPUT" "reference" "mentions reference type"
assert_contains "$OUTPUT" "technique" "mentions technique type"
assert_contains "$OUTPUT" "pattern" "mentions pattern type"

OUTPUT=$(run_claude "In the Xavier School diagnose skill, what language markers indicate a discipline-enforcing skill?")
assert_contains "$OUTPUT" "MUST\|NEVER\|ALWAYS" "mentions absolute directive markers"

report
