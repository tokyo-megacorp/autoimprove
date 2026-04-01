#!/usr/bin/env bash
# ar-effectiveness.sh — Benchmark adversarial-review skill effectiveness
# Emits: {"ar_precision": float, "ar_quality_score": int, "cases_run": int, "cases_passed": int}
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
GOLDEN_DIR="$DIR/benchmark/ar-golden"
JUDGE_PROMPT_FILE="$DIR/benchmark/judge-prompt.txt"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
TMP_AR_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/ar-output.XXXXXX")"
TMP_DIFF=""

cleanup() {
  rm -f "$TMP_AR_OUTPUT"
  if [ -n "$TMP_DIFF" ]; then
    rm -f "$TMP_DIFF"
  fi
}

run_claude() {
  "$CLAUDE_BIN" --print --model "$1" -p "$2" 2>/dev/null || true
}

trap cleanup EXIT

# --- Guard: claude CLI must be present ---
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  echo '{"ar_precision": -1, "ar_quality_score": -1, "error": "claude CLI not found"}'
  exit 0
fi

# ============================================================
# Measurement 1: AR Precision (golden test cases)
# ============================================================
total_cases=0
passed_cases=0
precision_sum=0

if [ -d "$GOLDEN_DIR" ]; then
  for case_dir in "$GOLDEN_DIR"/case-*/; do
    [ -d "$case_dir" ] || continue

    diff_file="$case_dir/diff.txt"
    expected_file="$case_dir/expected.txt"

    # Skip if either file is missing
    [ -f "$diff_file" ] || continue
    [ -f "$expected_file" ] || continue

    total_cases=$((total_cases + 1))

    # Run AR on this diff
    ar_output=$(run_claude haiku "Review this diff and list all bugs, issues, and improvements. Be thorough. Output one finding per line in format: severity:category:description

  $(cat "$diff_file")")

    # Fuzzy match: check how many expected category keywords appear in AR output
    total_expected=0
    found=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      total_expected=$((total_expected + 1))
      # Extract the category (second colon-delimited field, or full line if no colon)
      keyword=$(echo "$line" | cut -d: -f2 | tr '[:upper:]' '[:lower:]' | tr -d ' ')
      [ -z "$keyword" ] && keyword=$(echo "$line" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
      if echo "$ar_output" | tr '[:upper:]' '[:lower:]' | grep -qF "$keyword" 2>/dev/null; then
        found=$((found + 1))
      fi
    done < "$expected_file"

    if [ "$total_expected" -gt 0 ]; then
      # Use awk for float division
      case_rate=$(awk "BEGIN { printf \"%.4f\", $found / $total_expected }")
      precision_sum=$(awk "BEGIN { printf \"%.4f\", $precision_sum + $case_rate }")
      # A case is "passed" if match_rate >= 0.5
      is_passed=$(awk "BEGIN { print ($case_rate >= 0.5) ? 1 : 0 }")
      passed_cases=$((passed_cases + is_passed))
    fi
  done
fi

# Average precision across cases
if [ "$total_cases" -gt 0 ]; then
  ar_precision=$(awk "BEGIN { printf \"%.4f\", $precision_sum / $total_cases }")
else
  ar_precision="0"
fi

# ============================================================
# Measurement 2: AR Quality (LLM-as-judge)
# ============================================================
ar_quality_score=-1

# Use case-01 as canonical input; fall back to a trivial diff if not present
canonical_diff="$GOLDEN_DIR/case-01/diff.txt"
if [ ! -f "$canonical_diff" ]; then
  # No golden cases yet — create an ephemeral minimal diff for judge evaluation
  TMP_DIFF=$(mktemp "${TMPDIR:-/tmp}/ar-diff.XXXXXX")
  cat > "$TMP_DIFF" <<'EOF'
diff --git a/foo.py b/foo.py
index 0000000..1111111 100644
--- a/foo.py
+++ b/foo.py
@@ -1,3 +1,6 @@
 def divide(a, b):
-    return a / b
+    result = a / b  # potential division by zero
+    return result
+
+x = divide(10, 0)
EOF
  canonical_diff="$TMP_DIFF"
fi

run_claude haiku "Review this diff and list all bugs, issues, and improvements. Be thorough. Output one finding per line in format: severity:category:description

$(cat "$canonical_diff")" > "$TMP_AR_OUTPUT"

# Only run judge if we have a judge prompt and the AR produced output
if [ -f "$JUDGE_PROMPT_FILE" ] && [ -s "$TMP_AR_OUTPUT" ]; then
  JUDGE_PROMPT=$(cat "$JUDGE_PROMPT_FILE")
  AR_OUTPUT=$(cat "$TMP_AR_OUTPUT")

  judge_response=$(run_claude sonnet "${JUDGE_PROMPT}

${AR_OUTPUT}")

  # Extract "total" field from JSON response; tolerate non-JSON gracefully
    extracted=$(printf '%s' "$judge_response" | jq -r '.total // empty' 2>/dev/null || true)
    if [ -z "$extracted" ]; then
      extracted=$(printf '%s' "$judge_response" | grep -oE '"total"[[:space:]]*:[[:space:]]*[0-9]+' 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
    fi
    if [ -z "$extracted" ]; then
      extracted="-1"
    fi

  ar_quality_score="$extracted"
fi

# ============================================================
# Output JSON
# ============================================================
echo "{\"ar_precision\": $ar_precision, \"ar_quality_score\": $ar_quality_score, \"cases_run\": $total_cases, \"cases_passed\": $passed_cases}"
