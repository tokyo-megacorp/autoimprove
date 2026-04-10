#!/usr/bin/env bash
# test/harvest/test-harvest-themes.sh — Tests for skills/_shared/harvest-themes.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HARVEST_THEMES="$SCRIPT_DIR/skills/_shared/harvest-themes.sh"
PASS=0; FAIL=0; TOTAL=0

_assert() {
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

# Setup: single temp project root for all tests
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Scaffold directories
mkdir -p "$WORK_DIR/scripts"
mkdir -p "$WORK_DIR/skills/short-skill"
mkdir -p "$WORK_DIR/skills/long-skill"
mkdir -p "$WORK_DIR/agents"
mkdir -p "$WORK_DIR/commands"
mkdir -p "$WORK_DIR/test"

# ── Fixtures for test_coverage ──────────────────────────────────────────────
# A script with NO test file → should appear in output
echo "#!/bin/bash" > "$WORK_DIR/scripts/untested-script.sh"
echo "echo hello" >> "$WORK_DIR/scripts/untested-script.sh"

# A script WITH a matching test file → must NOT appear in output
echo "#!/bin/bash" > "$WORK_DIR/scripts/covered-script.sh"
echo "echo hello" >> "$WORK_DIR/scripts/covered-script.sh"
mkdir -p "$WORK_DIR/test/covered-script"
touch "$WORK_DIR/test/covered-script/test-covered-script.sh"

# ── Fixtures for skill_quality ───────────────────────────────────────────────
# Short skill (< 50 lines) → should appear
printf '%s\n' "---" "name: short-skill" "---" > "$WORK_DIR/skills/short-skill/SKILL.md"
echo "This skill is very brief." >> "$WORK_DIR/skills/short-skill/SKILL.md"

# Long skill (>= 50 lines) → must NOT appear
python3 -c "print('---\nname: long-skill\n---'); [print('line %d' % i) for i in range(60)]" \
  > "$WORK_DIR/skills/long-skill/SKILL.md"

# ── Fixtures for agent_prompts ───────────────────────────────────────────────
# Agent missing BOTH sections → should appear
cat > "$WORK_DIR/agents/bare-agent.md" <<'EOF'
# Bare Agent
This agent does something but says nothing useful about itself.
EOF

# Agent has description but no constraint/guardrail/important keywords → should appear
cat > "$WORK_DIR/agents/partial-agent.md" <<'EOF'
# Partial Agent
description: I have a description here.
But I have no safety info at all.
EOF

# Agent with both sections → must NOT appear
cat > "$WORK_DIR/agents/complete-agent.md" <<'EOF'
# Complete Agent
description: A fully documented agent.

## When to use
Use when you need full docs.

## Constraints
- Must not exceed 5 subagents.
EOF

# ── Fixtures for command_docs ────────────────────────────────────────────────
# Short command doc (< 20 lines) → should appear
printf 'Short doc\n%.0s' $(seq 1 5) > "$WORK_DIR/commands/short-cmd.md"

# Long command doc (>= 20 lines) → must NOT appear
python3 -c "[print('line %d' % i) for i in range(25)]" > "$WORK_DIR/commands/long-cmd.md"

# ============================================================================
echo "=== harvest-themes.sh: test_coverage ==="
OUT_FILE=$(mktemp)

echo "--- Test: untested script is reported ---"
bash "$HARVEST_THEMES" test_coverage "$WORK_DIR" > "$OUT_FILE" || true
_assert "untested-script.sh appears in output" "grep -q 'untested-script' '$OUT_FILE'"
_assert "output is valid JSON line" "python3 -c 'import sys,json; json.loads(open(\"$OUT_FILE\").read().strip())' 2>/dev/null"
_assert "reason field present" "python3 -c 'import sys,json; d=json.loads(open(\"$OUT_FILE\").read().strip()); assert \"reason\" in d' 2>/dev/null"

echo "--- Test: covered script is excluded ---"
_assert "covered-script.sh absent from output" "! grep -q 'covered-script' '$OUT_FILE'"

echo "--- Test: unknown theme emits no output ---"
bash "$HARVEST_THEMES" unknown_theme "$WORK_DIR" > "$OUT_FILE" || true
_assert "unknown theme: empty output" "[ ! -s '$OUT_FILE' ]"

# ============================================================================
echo ""
echo "=== harvest-themes.sh: skill_quality ==="

echo "--- Test: short SKILL.md is reported ---"
bash "$HARVEST_THEMES" skill_quality "$WORK_DIR" > "$OUT_FILE" || true
_assert "short-skill appears in output" "grep -q 'short-skill' '$OUT_FILE'"
_assert "reason mentions lines" "python3 -c 'import json; d=json.loads(open(\"$OUT_FILE\").read().strip()); assert \"lines\" in d[\"reason\"]' 2>/dev/null"

echo "--- Test: long SKILL.md is excluded ---"
_assert "long-skill absent from output" "! grep -q 'long-skill' '$OUT_FILE'"

# ============================================================================
echo ""
echo "=== harvest-themes.sh: agent_prompts ==="

echo "--- Test: bare agent is reported ---"
bash "$HARVEST_THEMES" agent_prompts "$WORK_DIR" > "$OUT_FILE" || true
_assert "bare-agent.md appears in output" "grep -q 'bare-agent' '$OUT_FILE'"

echo "--- Test: partial agent (missing constraints) is reported ---"
_assert "partial-agent.md appears in output" "grep -q 'partial-agent' '$OUT_FILE'"

echo "--- Test: complete agent is excluded ---"
_assert "complete-agent.md absent from output" "! grep -q 'complete-agent' '$OUT_FILE'"

echo "--- Test: JSON path field ends with agent filename ---"
_assert "bare-agent path field valid" "python3 -c 'import json; lines=[l for l in open(\"$OUT_FILE\") if \"bare-agent\" in l]; d=json.loads(lines[0]); assert d[\"path\"].endswith(\"bare-agent.md\")' 2>/dev/null"

# ============================================================================
echo ""
echo "=== harvest-themes.sh: command_docs ==="

echo "--- Test: short command doc is reported ---"
bash "$HARVEST_THEMES" command_docs "$WORK_DIR" > "$OUT_FILE" || true
_assert "short-cmd.md appears in output" "grep -q 'short-cmd' '$OUT_FILE'"

echo "--- Test: long command doc is excluded ---"
_assert "long-cmd.md absent from output" "! grep -q 'long-cmd' '$OUT_FILE'"

# ============================================================================
echo ""
echo "=== harvest-themes.sh: empty project root ==="
EMPTY_ROOT=$(mktemp -d)

echo "--- Test: test_coverage on empty project emits no output ---"
bash "$HARVEST_THEMES" test_coverage "$EMPTY_ROOT" > "$OUT_FILE" || true
_assert "empty project test_coverage: no output" "[ ! -s '$OUT_FILE' ]"

echo "--- Test: skill_quality on empty project emits no output ---"
bash "$HARVEST_THEMES" skill_quality "$EMPTY_ROOT" > "$OUT_FILE" || true
_assert "empty project skill_quality: no output" "[ ! -s '$OUT_FILE' ]"

echo "--- Test: agent_prompts on empty project emits no output ---"
bash "$HARVEST_THEMES" agent_prompts "$EMPTY_ROOT" > "$OUT_FILE" || true
_assert "empty project agent_prompts: no output" "[ ! -s '$OUT_FILE' ]"

echo "--- Test: command_docs on empty project emits no output ---"
bash "$HARVEST_THEMES" command_docs "$EMPTY_ROOT" > "$OUT_FILE" || true
_assert "empty project command_docs: no output" "[ ! -s '$OUT_FILE' ]"

rm -rf "$EMPTY_ROOT"
rm -f "$OUT_FILE"

# ============================================================================
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
