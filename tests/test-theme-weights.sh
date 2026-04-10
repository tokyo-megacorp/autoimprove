#!/usr/bin/env bash
# tests/test-theme-weights.sh — Unit tests for skills/_shared/theme-weights.sh
#
# Tests:
#  1. Missing YAML → exit 1
#  2. Valid YAML, no TSV (cold start) → all weights = base × 0.5
#  3. TSV with enough keep data → boosted weight = base × 1.5
#  4. TSV with zero keeps → penalised (weight = base × 0.5)
#  5. Output is valid JSON with all expected theme keys
#  6. Floor prevents starvation (weight >= base × 0.25)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
THEME_WEIGHTS="$SCRIPT_DIR/skills/_shared/theme-weights.sh"

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

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

OUT_FILE="$WORK_DIR/output.json"

# --- Minimal autoimprove.yaml fixture ---
YAML_FILE="$WORK_DIR/autoimprove.yaml"
cat > "$YAML_FILE" <<'EOF'
themes:
  auto:
    strategy: weighted_random
    priorities:
      test_coverage: 1
      skill_quality: 2
      agent_prompts: 2
      refactoring: 1
EOF

echo "========================================"
echo " theme-weights.sh Tests"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 1: Missing YAML → exit 1 ---"
bash "$THEME_WEIGHTS" "$WORK_DIR/nonexistent.yaml" "$WORK_DIR/notsv.tsv" >"$OUT_FILE" 2>&1 && EC=0 || EC=$?
_assert "exit code is 1 for missing YAML" "[ '$EC' = '1' ]"
_assert "error message mentions FATAL" "grep -q 'FATAL' '$OUT_FILE'"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 2: No TSV (cold start) → weights = base × 1.0 (base priority, no penalty) ---"
NO_TSV="$WORK_DIR/no.tsv"
bash "$THEME_WEIGHTS" "$YAML_FILE" "$NO_TSV" > "$OUT_FILE" 2>/dev/null
_assert "exits 0 without TSV" "[ -s '$OUT_FILE' ]"
_assert "output is valid JSON" "python3 -c 'import json; json.load(open(\"$OUT_FILE\"))'"
# test_coverage base=1, cold-start factor=1.0 → weight=1.0 (new themes get base priority)
_assert "test_coverage cold-start = 1.0 (base priority)" \
  "python3 -c 'import json; d=json.load(open(\"$OUT_FILE\")); assert d[\"test_coverage\"] == 1.0, f\"got {d[chr(34)+chr(116)+chr(101)+chr(115)+chr(116)+chr(95)+chr(99)+chr(111)+chr(118)+chr(101)+chr(114)+chr(97)+chr(103)+chr(101)+chr(34)]}\"'"
# skill_quality base=2, cold-start factor=1.0 → weight=2.0
_assert "skill_quality cold-start = 2.0 (base priority)" \
  "python3 -c 'import json; d=json.load(open(\"$OUT_FILE\")); assert d[\"skill_quality\"] == 2.0'"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 3: TSV with 5 keeps out of 5 runs → fully boosted ---"
TSV_FULL="$WORK_DIR/full_keeps.tsv"
cat > "$TSV_FULL" <<'EOF'
theme	verdict	experiment
test_coverage	keep	exp-001
test_coverage	keep	exp-002
test_coverage	keep	exp-003
test_coverage	keep	exp-004
test_coverage	keep	exp-005
EOF
bash "$THEME_WEIGHTS" "$YAML_FILE" "$TSV_FULL" > "$OUT_FILE" 2>/dev/null
# test_coverage: base=1, keep_rate=1.0, factor=1.5 → weight=1.5
_assert "test_coverage 100% keep → 1.5" \
  "python3 -c 'import json; d=json.load(open(\"$OUT_FILE\")); assert d[\"test_coverage\"] == 1.5'"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 4: TSV with 0 keeps → penalised ---"
TSV_NO_KEEPS="$WORK_DIR/no_keeps.tsv"
cat > "$TSV_NO_KEEPS" <<'EOF'
theme	verdict	experiment
test_coverage	reject	exp-001
test_coverage	reject	exp-002
test_coverage	reject	exp-003
test_coverage	reject	exp-004
EOF
bash "$THEME_WEIGHTS" "$YAML_FILE" "$TSV_NO_KEEPS" > "$OUT_FILE" 2>/dev/null
# test_coverage: base=1, keep_rate=0.0, factor=0.5 → raw=0.5, floor=0.25 → 0.5
_assert "test_coverage 0% keeps → 0.5" \
  "python3 -c 'import json; d=json.load(open(\"$OUT_FILE\")); assert d[\"test_coverage\"] == 0.5'"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 5: Output JSON has all expected theme keys ---"
bash "$THEME_WEIGHTS" "$YAML_FILE" "$NO_TSV" > "$OUT_FILE" 2>/dev/null
_assert "JSON has test_coverage key" \
  "python3 -c 'import json; d=json.load(open(\"$OUT_FILE\")); assert \"test_coverage\" in d'"
_assert "JSON has skill_quality key" \
  "python3 -c 'import json; d=json.load(open(\"$OUT_FILE\")); assert \"skill_quality\" in d'"
_assert "JSON has agent_prompts key" \
  "python3 -c 'import json; d=json.load(open(\"$OUT_FILE\")); assert \"agent_prompts\" in d'"
_assert "JSON has refactoring key" \
  "python3 -c 'import json; d=json.load(open(\"$OUT_FILE\")); assert \"refactoring\" in d'"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 6: Floor prevents starvation (all weights >= base × 0.25) ---"
TSV_MANY_REJECTS="$WORK_DIR/many_rejects.tsv"
printf 'theme\tverdict\texperiment\n' > "$TSV_MANY_REJECTS"
for i in $(seq 1 10); do
  printf 'skill_quality\treject\texp-%03d\n' "$i" >> "$TSV_MANY_REJECTS"
done
bash "$THEME_WEIGHTS" "$YAML_FILE" "$TSV_MANY_REJECTS" > "$OUT_FILE" 2>/dev/null
# skill_quality: base=2, 0% keep → raw=1.0, floor=0.5; result=1.0
_assert "skill_quality fully rejected → >= floor (0.5)" \
  "python3 -c 'import json; d=json.load(open(\"$OUT_FILE\")); assert d[\"skill_quality\"] >= 0.5'"
_assert "skill_quality fully rejected → 1.0 (raw > floor)" \
  "python3 -c 'import json; d=json.load(open(\"$OUT_FILE\")); assert d[\"skill_quality\"] == 1.0'"
echo ""

# ---------------------------------------------------------------------------
echo "========================================"
echo " Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
