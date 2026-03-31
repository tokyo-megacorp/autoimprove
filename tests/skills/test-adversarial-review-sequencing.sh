#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$ROOT/skills/adversarial-review/SKILL.md"
COMMAND="$ROOT/commands/adversarial-review.md"

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local name="$3"
    if grep -Fq "$pattern" "$file"; then
        echo "  [PASS] $name"
    else
        echo "  [FAIL] $name"
        echo "    pattern: $pattern"
        echo "    file: $file"
        return 1
    fi
}

echo "=== Test: adversarial-review sequential dispatch instructions ==="

assert_file_contains "$SKILL" "CRITICAL: sequential dispatch only" "skill documents sequential-only dispatch"
assert_file_contains "$SKILL" "Do not dispatch Enthusiast and Adversary in parallel" "skill forbids Enthusiast/Adversary parallelism"
assert_file_contains "$SKILL" "Pass the full Enthusiast JSON" "adversary receives full enthusiast output"
assert_file_contains "$SKILL" "Pass both full JSON payloads to the Judge" "judge receives both prior outputs"
assert_file_contains "$COMMAND" "sequentially, never in parallel" "command doc explains sequential execution"

echo "=== adversarial-review sequential dispatch instructions: passed ==="
