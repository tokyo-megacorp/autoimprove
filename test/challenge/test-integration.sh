#!/usr/bin/env bash
# Integration test: verify score-challenge.sh works end-to-end with a real challenge.
# This tests the scoring pipeline, not the debate agents (which require Claude).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
SCORE="$ROOT/scripts/score-challenge.sh"
PASS=0
FAIL=0

assert_json_field() {
  local desc="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | jq -r "$field")
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++)) || true
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    ((FAIL++)) || true
  fi
}

echo "=== Integration Tests ==="

echo "--- Test: manifest is valid JSON ---"
if jq empty "$ROOT/challenges/manifest.json" 2>/dev/null; then
  echo "  PASS: manifest.json is valid JSON"
  ((PASS++)) || true
else
  echo "  FAIL: manifest.json is invalid JSON"
  ((FAIL++)) || true
fi

echo "--- Test: all answer keys are valid JSON ---"
ALL_VALID=true
for key in $(find "$ROOT/challenges" -name "answer-key.json"); do
  if ! jq empty "$key" 2>/dev/null; then
    echo "  FAIL: invalid JSON: $key"
    ALL_VALID=false
    ((FAIL++)) || true
  fi
done
if $ALL_VALID; then
  echo "  PASS: all answer-key.json files are valid JSON"
  ((PASS++)) || true
fi

echo "--- Test: all manifested challenges have files ---"
ALL_EXIST=true
while IFS= read -r id; do
  dir="$ROOT/challenges/$id"
  if [ ! -d "$dir" ]; then
    echo "  FAIL: directory missing: $dir"
    ALL_EXIST=false
    ((FAIL++)) || true
  fi
  if [ ! -f "$dir/answer-key.json" ]; then
    echo "  FAIL: answer-key.json missing: $dir"
    ALL_EXIST=false
    ((FAIL++)) || true
  fi
done < <(jq -r '.challenges[].id' "$ROOT/challenges/manifest.json")
if $ALL_EXIST; then
  echo "  PASS: all manifested challenges have files"
  ((PASS++)) || true
fi

echo "--- Test: scoring script handles each real answer key ---"
for key in $(find "$ROOT/challenges" -name "answer-key.json"); do
  # Score with empty findings (should get F1=0, pass=false)
  EMPTY='{"rulings":[],"findings":[]}'
  tmpfile=$(mktemp)
  echo "$EMPTY" > "$tmpfile"
  result=$("$SCORE" "$key" "$tmpfile" 2>/dev/null)
  rm "$tmpfile"

  challenge=$(jq -r '.challenge' "$key")
  assert_json_field "empty findings on $challenge: f1=0" "$result" '.f1' '0'
  assert_json_field "empty findings on $challenge: pass=false" "$result" '.pass' 'false'
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
