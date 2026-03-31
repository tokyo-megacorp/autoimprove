#!/usr/bin/env bash
# Test runner for autoimprove skill tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo " autoimprove Skill Test Suite"
echo "========================================"
echo ""
echo "Project: $(cd ../.. && pwd)"
echo "Time: $(date)"
echo ""

if ! command -v claude &>/dev/null; then echo "ERROR: claude CLI not found"; exit 1; fi

VERBOSE=false; SPECIFIC_TEST=""; TIMEOUT=300
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v) VERBOSE=true; shift ;;
        --test|-t) SPECIFIC_TEST="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

tests=("test-review.sh" "test-adversarial-review-sequencing.sh")
[ -n "$SPECIFIC_TEST" ] && tests=("$SPECIFIC_TEST")

passed=0; failed=0

for test in "${tests[@]}"; do
    echo "----------------------------------------"
    echo "Running: $test"
    echo "----------------------------------------"
    test_path="$SCRIPT_DIR/$test"
    [ -f "$test_path" ] || { echo "  [SKIP] not found"; continue; }
    chmod +x "$test_path"

    if output=$(timeout "$TIMEOUT" bash "$test_path" 2>&1); then
        echo "$output"
        passed=$((passed+1))
    else
        echo "$output"
        failed=$((failed+1))
    fi
    echo ""
done

echo "========================================"
echo " Results: passed=$passed failed=$failed"
echo "========================================"
[ $failed -eq 0 ] || exit 1
