#!/usr/bin/env bash
# tests/test-validate-skill-authoring.sh — unit tests for scripts/validate-skill-authoring.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$SCRIPT_DIR/scripts/validate-skill-authoring.sh"

PASS=0
FAIL=0
TOTAL=0

assert_expr() {
  local desc="$1"
  local expr="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$expr" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    Expression: $expr"
  fi
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/skills"

echo "========================================"
echo " validate-skill-authoring.sh Tests"
echo "========================================"
echo ""

echo "--- Test 1: Valid skill passes ---"
mkdir -p "$WORK_DIR/skills/good-skill"
cat > "$WORK_DIR/skills/good-skill/SKILL.md" <<'EOF'
---
name: good-skill
description: Use when validating a deterministic skill authoring gate.
---

# Good Skill

Minimal valid content.
EOF

VALID_OUTPUT=$(bash "$VALIDATOR" "$WORK_DIR/skills/good-skill" 2>&1)
VALID_EXIT=$?
assert_expr "valid skill exits 0" "[ '$VALID_EXIT' = '0' ]"
assert_expr "valid skill reports success" "echo \"$VALID_OUTPUT\" | grep -q 'OK: skill authoring validation passed'"
echo ""

echo "--- Test 2: Missing frontmatter fails ---"
mkdir -p "$WORK_DIR/skills/no-frontmatter"
cat > "$WORK_DIR/skills/no-frontmatter/SKILL.md" <<'EOF'
# Missing Frontmatter

This file should fail validation.
EOF

MISSING_OUTPUT=$(bash "$VALIDATOR" "$WORK_DIR/skills/no-frontmatter" 2>&1)
MISSING_EXIT=$?
assert_expr "missing frontmatter exits non-zero" "[ '$MISSING_EXIT' != '0' ]"
assert_expr "missing frontmatter error surfaced" "echo \"$MISSING_OUTPUT\" | grep -q 'missing YAML frontmatter'"
echo ""

echo "--- Test 3: Name mismatch fails ---"
mkdir -p "$WORK_DIR/skills/name-mismatch"
cat > "$WORK_DIR/skills/name-mismatch/SKILL.md" <<'EOF'
---
name: different-name
description: Use when checking name mismatch handling.
---

# Name Mismatch
EOF

MISMATCH_OUTPUT=$(bash "$VALIDATOR" "$WORK_DIR/skills/name-mismatch" 2>&1)
MISMATCH_EXIT=$?
assert_expr "name mismatch exits non-zero" "[ '$MISMATCH_EXIT' != '0' ]"
assert_expr "name mismatch error surfaced" "echo \"$MISMATCH_OUTPUT\" | grep -q \"does not match directory 'name-mismatch'\""
echo ""

echo "--- Test 4: Overlong description fails ---"
mkdir -p "$WORK_DIR/skills/long-description"
LONG_DESC="$(ruby -e 'print "a" * 1025')"
cat > "$WORK_DIR/skills/long-description/SKILL.md" <<EOF
---
name: long-description
description: ${LONG_DESC}
---

# Long Description
EOF

LONG_OUTPUT=$(bash "$VALIDATOR" "$WORK_DIR/skills/long-description" 2>&1)
LONG_EXIT=$?
assert_expr "overlong description exits non-zero" "[ '$LONG_EXIT' != '0' ]"
assert_expr "overlong description error surfaced" "echo \"$LONG_OUTPUT\" | grep -q 'description is 1025 chars'"
echo ""

echo "--- Test 5: Helper directories are skipped ---"
mkdir -p "$WORK_DIR/skills/_shared"
HELPER_OUTPUT=$(bash "$VALIDATOR" "$WORK_DIR/skills/_shared" 2>&1)
HELPER_EXIT=$?
assert_expr "helper directory exits 0" "[ '$HELPER_EXIT' = '0' ]"
assert_expr "helper directory is skipped cleanly" "echo \"$HELPER_OUTPUT\" | grep -q 'No skill files to validate.'"
echo ""

echo "--- Test 6: --staged validates index content, not unstaged edits ---"
GIT_DIR="$WORK_DIR/git-staged"
mkdir -p "$GIT_DIR/skills/staged-skill"
git -C "$GIT_DIR" init -q
cat > "$GIT_DIR/skills/staged-skill/SKILL.md" <<'EOF'
---
name: staged-skill
description: Use when validating staged-skill behavior.
---

# Staged Skill
EOF
git -C "$GIT_DIR" add skills/staged-skill/SKILL.md

# Make working tree invalid without staging the change.
cat > "$GIT_DIR/skills/staged-skill/SKILL.md" <<'EOF'
---
name: wrong-name
description: Use when validating staged-skill behavior.
---

# Staged Skill
EOF

STAGED_OUTPUT=$(cd "$GIT_DIR" && bash "$VALIDATOR" --staged 2>&1)
STAGED_EXIT=$?
assert_expr "staged mode exits 0 when staged blob is valid" "[ '$STAGED_EXIT' = '0' ]"
assert_expr "staged mode ignores unstaged invalid edits" "echo \"$STAGED_OUTPUT\" | grep -q 'OK: skill authoring validation passed'"
echo ""

echo "========================================"
echo " Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
