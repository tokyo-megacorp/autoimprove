#!/usr/bin/env bash
# ar-write-round.sh — Write per-round AR telemetry files
#
# Usage:
#   bash scripts/ar-write-round.sh <run_dir> <round> <enthusiast_json_path> <adversary_json_path> <judge_json_path>
#
# Writes:
#   $run_dir/round-N.json  — structured round record
#   $run_dir/meta.json     — updated incrementally (rounds_completed++)
#
# Optional env vars:
#   AR_ROUND_MODEL   — model used this round (default: "haiku")
#   AR_ROUND_ERRORS  — JSON array of error strings (default: [])
#
# Exit codes:
#   0 — success
#   1 — bad arguments or missing files
#
# Requires: bash 4+, jq

set -uo pipefail

RUN_DIR="${1:-}"
ROUND="${2:-}"
ENTHUSIAST_PATH="${3:-}"
ADVERSARY_PATH="${4:-}"
JUDGE_PATH="${5:-}"

# ── Argument validation ────────────────────────────────────────────────────────

if [ -z "$RUN_DIR" ] || [ -z "$ROUND" ] || [ -z "$ENTHUSIAST_PATH" ] || [ -z "$ADVERSARY_PATH" ] || [ -z "$JUDGE_PATH" ]; then
  echo "usage: ar-write-round.sh <run_dir> <round> <enthusiast_json_path> <adversary_json_path> <judge_json_path>" >&2
  exit 1
fi

if [ ! -d "$RUN_DIR" ]; then
  echo "ar-write-round: run_dir not found: $RUN_DIR" >&2
  exit 1
fi

for f in "$ENTHUSIAST_PATH" "$ADVERSARY_PATH" "$JUDGE_PATH"; do
  if [ ! -f "$f" ]; then
    echo "ar-write-round: agent output file not found: $f" >&2
    exit 1
  fi
done

# ── Derived values ─────────────────────────────────────────────────────────────

RUN_ID="$(basename "$RUN_DIR")"
MODEL="${AR_ROUND_MODEL:-haiku}"
ERRORS_JSON="${AR_ROUND_ERRORS:-[]}"

# Extract converged flag from judge output (default false if missing/invalid)
CONVERGED=$(jq -r '.convergence // false' "$JUDGE_PATH" 2>/dev/null || echo "false")
# Normalise to lowercase boolean literal
case "$CONVERGED" in
  true|True|TRUE) CONVERGED="true" ;;
  *)              CONVERGED="false" ;;
esac

# ── Write round-N.json ─────────────────────────────────────────────────────────

ROUND_FILE="$RUN_DIR/round-${ROUND}.json"

ENTHUSIAST_JSON=$(cat "$ENTHUSIAST_PATH")
ADVERSARY_JSON=$(cat "$ADVERSARY_PATH")
JUDGE_JSON=$(cat "$JUDGE_PATH")

# Build the round record; omit "errors" key when array is empty
ROUND_JSON=$(jq -n \
  --argjson round "$ROUND" \
  --arg run_id "$RUN_ID" \
  --arg model "$MODEL" \
  --argjson enthusiast "$ENTHUSIAST_JSON" \
  --argjson adversary "$ADVERSARY_JSON" \
  --argjson judge "$JUDGE_JSON" \
  --argjson errors "$ERRORS_JSON" \
  --argjson converged "$CONVERGED" \
  '
  {round: $round, run_id: $run_id, model: $model,
   enthusiast: $enthusiast, adversary: $adversary, judge: $judge,
   converged: $converged}
  + (if ($errors | length) > 0 then {errors: $errors} else {} end)
  ') || { echo "ar-write-round: failed to build round-${ROUND}.json (malformed agent JSON)" >&2; exit 1; }
echo "$ROUND_JSON" > "$ROUND_FILE"

# ── Update meta.json incrementally ────────────────────────────────────────────

META_FILE="$RUN_DIR/meta.json"

if [ -f "$META_FILE" ]; then
  UPDATED_META=$(jq \
    --argjson round "$ROUND" \
    '.rounds_completed = $round' \
    "$META_FILE" 2>/dev/null) || UPDATED_META=""

  if [ -n "$UPDATED_META" ]; then
    echo "$UPDATED_META" > "$META_FILE"
  else
    echo "ar-write-round: warning — could not update meta.json (jq parse error)" >&2
  fi
else
  echo "ar-write-round: warning — meta.json not found at $META_FILE, skipping update" >&2
fi
