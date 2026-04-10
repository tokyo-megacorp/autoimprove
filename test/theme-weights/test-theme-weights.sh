#!/usr/bin/env bash
# test/theme-weights/test-theme-weights.sh — Tests for skills/_shared/theme-weights.sh
#
# Covers the weight formula:
#   adjusted = base × (0.5 + keep_rate)   [cold start: base × 1.0]
#   floor     = base × 0.25               [prevents starvation]
#   cold start = < 3 samples → factor 1.0 (neutral)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THEME_WEIGHTS="$SCRIPT_DIR/../../skills/_shared/theme-weights.sh"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
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

assert_json_field() {
  local desc="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d$field)" 2>/dev/null || echo "ERROR")
  assert_eq "$desc" "$expected" "$actual"
}

# Helper: write a minimal autoimprove.yaml with given priorities
write_yaml() {
  local path="$1"
  shift
  # Each argument is "theme:priority" e.g. "foo:1" "bar:3"
  printf 'themes:\n  auto:\n    strategy: weighted_random\n    priorities:\n' > "$path"
  for pair in "$@"; do
    local theme="${pair%%:*}"
    local prio="${pair##*:}"
    printf '      %s: %s\n' "$theme" "$prio" >> "$path"
  done
}

# Helper: write a TSV with header and rows
# write_tsv <path> <"theme verdict" ...>
write_tsv() {
  local path="$1"
  shift
  printf 'id\ttheme\tverdict\ttimestamp\n' > "$path"
  local n=1
  for row in "$@"; do
    local theme="${row%% *}"
    local verdict="${row##* }"
    printf 'exp-%03d\t%s\t%s\t2026-01-01T00:00:00Z\n' "$n" "$theme" "$verdict" >> "$path"
    n=$(( n + 1 ))
  done
}

echo "=== theme-weights.sh — Missing file guards ==="

# Test: missing YAML → exit 1
echo "--- Test: missing YAML exits with error ---"
set +e
out=$(bash "$THEME_WEIGHTS" /nonexistent/path.yaml /dev/null 2>&1)
exit_code=$?
set -e
assert_eq "missing YAML: exit code 1" "1" "$exit_code"
if echo "$out" | grep -qi "FATAL\|not found\|error"; then
  echo "  PASS: missing YAML: stderr contains error message"
  ((PASS++)) || true
else
  echo "  FAIL: missing YAML: stderr should mention FATAL/not found"
  echo "    actual: $out"
  ((FAIL++)) || true
fi

echo ""
echo "=== theme-weights.sh — Cold-start (< 3 samples) ==="

# Test: cold start — 0 experiments for a theme → factor=1.0
echo "--- Test: cold start (0 runs) → weight = base × 1.0 ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "alpha:2"
write_tsv "$tsv"  # empty TSV (no rows)
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
# alpha has base=2, 0 runs → cold start → factor=1.0 → weight=2.0
assert_json_field "cold-start(0 runs): alpha weight = 2.0" "$result" '["alpha"]' "2.0"
rm -f "$yaml" "$tsv"

# Test: cold start — 1 experiment → still cold start
echo "--- Test: cold start (1 run) → weight = base × 1.0 ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "alpha:2"
write_tsv "$tsv" "alpha keep"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
assert_json_field "cold-start(1 run): alpha weight = 2.0" "$result" '["alpha"]' "2.0"
rm -f "$yaml" "$tsv"

# Test: cold start — 2 experiments → still cold start
echo "--- Test: cold start (2 runs) → weight = base × 1.0 ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "alpha:2"
write_tsv "$tsv" "alpha keep" "alpha neutral"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
assert_json_field "cold-start(2 runs): alpha weight = 2.0" "$result" '["alpha"]' "2.0"
rm -f "$yaml" "$tsv"

echo ""
echo "=== theme-weights.sh — Active formula (>= 3 samples) ==="

# Test: 3 runs, 0 keeps → keep_rate=0 → factor=0.5 → weight = base × 0.5
echo "--- Test: 3 runs, 0 keeps → factor=0.5 (keep_rate=0) ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "alpha:2"
write_tsv "$tsv" "alpha neutral" "alpha neutral" "alpha neutral"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
# 2 * 0.5 = 1.0
assert_json_field "0% keep-rate: alpha weight = 1.0" "$result" '["alpha"]' "1.0"
rm -f "$yaml" "$tsv"

# Test: 3 runs, 3 keeps → keep_rate=1.0 → factor=1.5 → weight = base × 1.5
echo "--- Test: 3 runs, 3 keeps → factor=1.5 (keep_rate=1.0) ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "alpha:2"
write_tsv "$tsv" "alpha keep" "alpha keep" "alpha keep"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
# 2 * 1.5 = 3.0
assert_json_field "100% keep-rate: alpha weight = 3.0" "$result" '["alpha"]' "3.0"
rm -f "$yaml" "$tsv"

# Test: 4 runs, 2 keeps → keep_rate=0.5 → factor=1.0 → weight = base × 1.0
echo "--- Test: 4 runs, 2 keeps → factor=1.0 (keep_rate=0.5) ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "alpha:4"
write_tsv "$tsv" "alpha keep" "alpha neutral" "alpha keep" "alpha neutral"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
# 4 * 1.0 = 4.0
assert_json_field "50% keep-rate: alpha weight = 4.0" "$result" '["alpha"]' "4.0"
rm -f "$yaml" "$tsv"

# Test: 3 runs, 1 keep → keep_rate=1/3 → factor=0.5+0.333...=0.8333 → weight=base×0.8333
echo "--- Test: 3 runs, 1 keep → factor=0.8333 (keep_rate=1/3) ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "alpha:3"
write_tsv "$tsv" "alpha keep" "alpha neutral" "alpha neutral"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
# 3 * (0.5 + 1/3) = 3 * 0.8333 = 2.4999 → rounded to 4 dp = 2.5
assert_json_field "33% keep-rate: alpha weight = 2.5" "$result" '["alpha"]' "2.5"
rm -f "$yaml" "$tsv"

echo ""
echo "=== theme-weights.sh — Third run unlocks the formula ==="

# Test: transition from cold-start to active at exactly 3 runs
# With 2 runs: cold-start → weight = base
# With 3 runs: active → weight = base * (0.5 + keep_rate)
# This verifies the boundary: 2 runs = cold, 3 runs = active
echo "--- Test: exactly 3 runs (boundary) — formula activates ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "alpha:2"
# 3 runs, all neutral → keep_rate=0, factor=0.5 → weight=1.0
write_tsv "$tsv" "alpha neutral" "alpha neutral" "alpha neutral"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
assert_json_field "at 3 runs formula applies: alpha weight = 1.0 (not 2.0)" "$result" '["alpha"]' "1.0"
rm -f "$yaml" "$tsv"

echo ""
echo "=== theme-weights.sh — Multiple themes with independent histories ==="

# Test: two themes with different histories should compute independently
echo "--- Test: two themes — high keep-rate vs zero keep-rate ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "hot:2" "cold:2"
# hot: 3 runs, 3 keeps → keep_rate=1.0 → factor=1.5 → weight=3.0
# cold: 3 runs, 0 keeps → keep_rate=0 → factor=0.5 → weight=1.0
write_tsv "$tsv" \
  "hot keep" "hot keep" "hot keep" \
  "cold neutral" "cold neutral" "cold neutral"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
assert_json_field "multi-theme: hot weight = 3.0" "$result" '["hot"]' "3.0"
assert_json_field "multi-theme: cold weight = 1.0" "$result" '["cold"]' "1.0"
rm -f "$yaml" "$tsv"

# Test: a theme in YAML but not in TSV (no history) stays cold-start
echo "--- Test: theme in YAML but absent from TSV → cold-start weight ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "new_theme:3" "old_theme:3"
# Only old_theme has history; new_theme has none
write_tsv "$tsv" "old_theme keep" "old_theme keep" "old_theme keep"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
# new_theme: 0 runs → cold start → factor=1.0 → weight=3.0
assert_json_field "absent-from-TSV theme: weight = base (cold-start)" "$result" '["new_theme"]' "3.0"
# old_theme: 3 keeps out of 3 → factor=1.5 → weight=4.5
assert_json_field "TSV theme (all keeps): weight = 4.5" "$result" '["old_theme"]' "4.5"
rm -f "$yaml" "$tsv"

echo ""
echo "=== theme-weights.sh — TSV rows for other themes don't contaminate ==="

# Test: TSV contains rows for a theme not in YAML — they are ignored
echo "--- Test: TSV rows for unknown theme do not affect results ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "alpha:2"
# TSV has many rows for "beta" (not in YAML) and 3 neutral for "alpha"
write_tsv "$tsv" \
  "beta keep" "beta keep" "beta keep" "beta keep" "beta keep" \
  "alpha neutral" "alpha neutral" "alpha neutral"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
# alpha: 3 runs, 0 keeps → factor=0.5 → weight=1.0
assert_json_field "unknown-theme rows ignored: alpha weight = 1.0" "$result" '["alpha"]' "1.0"
# beta must NOT appear in output (it's not in YAML)
beta_present=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print('beta' in d)" 2>/dev/null || echo "ERROR")
assert_eq "unknown theme 'beta' not in output" "False" "$beta_present"
rm -f "$yaml" "$tsv"

echo ""
echo "=== theme-weights.sh — Missing TSV (fresh project) ==="

# Test: TSV file doesn't exist at all → all themes get cold-start weight
echo "--- Test: missing TSV → all themes get cold-start weight (base × 1.0) ---"
yaml=$(mktemp)
write_yaml "$yaml" "foo:3" "bar:1"
result=$(bash "$THEME_WEIGHTS" "$yaml" /nonexistent/experiments.tsv 2>/dev/null)
assert_json_field "missing TSV: foo weight = 3.0 (cold-start)" "$result" '["foo"]' "3.0"
assert_json_field "missing TSV: bar weight = 1.0 (cold-start)" "$result" '["bar"]' "1.0"
rm -f "$yaml"

echo ""
echo "=== theme-weights.sh — Output is valid JSON with all YAML themes ==="

# Test: output is valid JSON and contains exactly the themes from YAML
echo "--- Test: output is valid JSON containing all YAML themes ---"
yaml=$(mktemp)
tsv=$(mktemp)
write_yaml "$yaml" "theme_a:1" "theme_b:2" "theme_c:3"
write_tsv "$tsv"
result=$(bash "$THEME_WEIGHTS" "$yaml" "$tsv" 2>/dev/null)
set +e
valid=$(echo "$result" | python3 -c "import json,sys; json.load(sys.stdin); print('ok')" 2>/dev/null)
set -e
assert_eq "output is valid JSON" "ok" "$valid"
count=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")
assert_eq "output has exactly 3 themes" "3" "$count"
rm -f "$yaml" "$tsv"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
