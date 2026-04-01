#!/usr/bin/env bash
# tests/test-autoimprove-entrypoint.sh — Regression test for the top-level autoimprove skill/command
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="$REPO_ROOT/skills/autoimprove/SKILL.md"
COMMAND_FILE="$REPO_ROOT/commands/autoimprove.md"
PLUGIN_COMMAND="$REPO_ROOT/.claude-plugin/commands/autoimprove.md"
DOCS_COMMANDS="$REPO_ROOT/docs/commands.md"
DOCS_SKILLS="$REPO_ROOT/docs/skills.md"

PASS=0
FAIL=0
TOTAL=0

pass_fail() {
  local desc="$1"
  local status="$2"

  TOTAL=$((TOTAL + 1))
  if [ "$status" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
  fi
}

assert_expr() {
  local desc="$1"
  local expr="$2"

  if eval "$expr"; then
    pass_fail "$desc" 0
  else
    pass_fail "$desc" 1
    echo "    Expression: $expr"
  fi
}

assert_contains_fixed() {
  local desc="$1"
  local needle="$2"
  local file="$3"

  if grep -Fq "$needle" "$file"; then
    pass_fail "$desc" 0
  else
    pass_fail "$desc" 1
    echo "    Missing text: $needle"
    echo "    File: $file"
  fi
}

assert_symlink_target() {
  local desc="$1"
  local link_path="$2"
  local expected_target="$3"
  local actual_target

  actual_target="$(readlink "$link_path")"
  if [ "$actual_target" = "$expected_target" ]; then
    pass_fail "$desc" 0
  else
    pass_fail "$desc" 1
    echo "    Expected: $expected_target"
    echo "    Actual:   $actual_target"
  fi
}

echo "========================================"
echo " autoimprove entrypoint tests"
echo "========================================"
echo ""

echo "--- Test 1: top-level skill exists and aliases run ---"
assert_expr "autoimprove skill file exists" "[ -f '$SKILL_FILE' ]"
assert_expr "autoimprove skill frontmatter is named autoimprove" "grep -q '^name: autoimprove$' '$SKILL_FILE'"
assert_expr "autoimprove skill loads run skill instructions" "grep -q 'skills/run/SKILL.md' '$SKILL_FILE'"
assert_expr "autoimprove skill documents Skill(autoimprove) compatibility" "grep -q 'Skill(autoimprove)' '$SKILL_FILE'"
echo ""

echo "--- Test 2: top-level command exists and invokes the top-level skill ---"
assert_expr "autoimprove command file exists" "[ -f '$COMMAND_FILE' ]"
assert_expr "autoimprove command frontmatter is named autoimprove" "grep -q '^name: autoimprove$' '$COMMAND_FILE'"
assert_contains_fixed "autoimprove command invokes autoimprove skill" 'Invoke the `autoimprove:autoimprove` skill now.' "$COMMAND_FILE"
assert_contains_fixed "autoimprove command documents /autoimprove run alias" "/autoimprove run" "$COMMAND_FILE"
echo ""

echo "--- Test 3: plugin exposes /autoimprove command and docs mention it ---"
assert_expr "plugin command link exists" "[ -L '$PLUGIN_COMMAND' ]"
assert_symlink_target "plugin command link points at commands/autoimprove.md" "$PLUGIN_COMMAND" "../../commands/autoimprove.md"
assert_contains_fixed "commands reference documents /autoimprove" '## `/autoimprove`' "$DOCS_COMMANDS"
assert_contains_fixed "skills reference documents autoimprove skill" "## autoimprove" "$DOCS_SKILLS"
echo ""

echo "========================================"
echo " Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

[ "$FAIL" -eq 0 ]
