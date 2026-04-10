#!/usr/bin/env bash
# replay-pattern-layer.sh — replay candidate rubric signals against a past experiment
#
# Usage:
#   scripts/replay-pattern-layer.sh <commit_sha> [parent_sha]
#
# If parent_sha is omitted, <commit_sha>^ is used.
#
# Computes per-file rubric signals (presence + ratio deltas) for each skills/*/SKILL.md
# touched by the commit, and outputs a JSON document with the suspect_dimensions list.
#
# Exit codes:
#   0  — replay succeeded, suspect list computed (may be empty or non-empty)
#   1  — commit not found / invalid args / no SKILL.md files changed
#
# Validation contract:
#   This script is part of the Rubric Escalation Ladder design (idea-matrix 2026-04-10).
#   Before wiring the ladder into the grind loop, this script MUST be run against
#   experiments 075 (eeb8900) and 081 (39f18cb). Both must produce a non-empty
#   suspect_dimensions list or the design is inverted and must be redesigned to
#   use ratio-delta signals only (dropping presence-based patterns).

set -uo pipefail

COMMIT="${1:-}"
PARENT="${2:-}"

if [ -z "$COMMIT" ]; then
  echo '{"error":"usage: replay-pattern-layer.sh <commit_sha> [parent_sha]"}' >&2
  exit 1
fi

if ! git cat-file -e "$COMMIT" 2>/dev/null; then
  echo "{\"error\":\"commit not found: $COMMIT\"}" >&2
  exit 1
fi

if [ -z "$PARENT" ]; then
  PARENT="${COMMIT}^"
fi

# ── Signal definitions ──────────────────────────────────────────────────────
#
# Each signal is a (regex, dimension) pair. A signal contributes to flagging
# its dimension as suspect if:
#   (a) presence count decreases from before → after (pattern removed), OR
#   (b) the global ratio delta for that dimension drops below threshold.
#
# Dimensions mirror agents/reviewer.md rubric output fields.

# Count helpers — always return a single integer on stdout. grep -c returns
# exit code 1 when no matches, which combined with `|| echo 0` produces
# double-zero output and breaks downstream arithmetic. Use `|| true` + default.

count() {
  # Case-insensitive to match self-metrics.sh (grep -ciE) and to handle
  # markdown bullets like `- **Never ...` where the verb is capitalized.
  local n
  n=$(grep -ciE "$2" "$1" 2>/dev/null) || n=0
  printf '%s' "${n:-0}"
}

count_inv() {
  local n
  n=$(grep -cvE "$2" "$1" 2>/dev/null) || n=0
  printf '%s' "${n:-0}"
}

# Two directive counters:
#   bench_directive_lines — matches the regex benchmark/self-metrics.sh uses
#   (naive: only counts lines starting with the verb, no markdown bullet handling)
#
#   smart_directive_lines — bullet-aware: also counts markdown bullets with
#   bold-wrapped directives (`- **Never ...`, `- **Use ...`) which the benchmark
#   misses. This is what a human reader would call "a directive line".
#
# Disagreement between the two is the escalation signal: when a change adds
# real directive content but the benchmark can't see it, escalate to reviewer.md.

bench_directive_lines() {
  [ -f "$1" ] || { printf 0; return; }
  count "$1" '^(use|run|call|invoke|always|never|do not|avoid|set|add|pass|return|check|ensure|prefer|include|read|write|omit|skip|stop|dispatch|emit|load|store|create|delete|update|format|validate|parse|handle)'
}

smart_directive_lines() {
  [ -f "$1" ] || { printf 0; return; }
  # Accepts optional markdown bullet (`-` or `*`), optional bold wrappers (`**`),
  # optional leading whitespace. Then one of the imperative verbs.
  count "$1" '^[[:space:]]*[-*]?[[:space:]]*\**(use|run|call|invoke|always|never|do not|don.t|avoid|set|add|pass|return|check|ensure|prefer|include|read|write|omit|skip|stop|dispatch|emit|load|store|create|delete|update|format|validate|parse|handle)'
}

directive_lines() {
  # Default entry point used for primary directive_ratio computation — use smart.
  smart_directive_lines "$1"
}

non_blank_lines() {
  [ -f "$1" ] || { printf 0; return; }
  count_inv "$1" '^[[:space:]]*$'
}

header_count() {
  [ -f "$1" ] || { printf 0; return; }
  count "$1" '^#{1,6}[[:space:]]'
}

pattern_count() {
  [ -f "$1" ] || { printf 0; return; }
  count "$1" "$2"
}

# ── Replay a single file ────────────────────────────────────────────────────

replay_file() {
  local path="$1"
  local tmp_before tmp_after
  tmp_before=$(mktemp)
  tmp_after=$(mktemp)

  # Extract BEFORE and AFTER content from git. Empty file on error (new/deleted files).
  git show "$PARENT:$path" > "$tmp_before" 2>/dev/null || : > "$tmp_before"
  git show "$COMMIT:$path" > "$tmp_after" 2>/dev/null || : > "$tmp_after"

  local d_before d_after nb_before nb_after h_before h_after bench_before bench_after
  d_before=$(smart_directive_lines "$tmp_before")
  d_after=$(smart_directive_lines "$tmp_after")
  bench_before=$(bench_directive_lines "$tmp_before")
  bench_after=$(bench_directive_lines "$tmp_after")
  nb_before=$(non_blank_lines "$tmp_before")
  nb_after=$(non_blank_lines "$tmp_after")
  h_before=$(header_count "$tmp_before")
  h_after=$(header_count "$tmp_after")

  # Also compute total lines (including blanks) because the benchmark uses wc -l
  # (not non_blank) as its denominator — so we must do the same to predict it.
  local total_before total_after
  total_before=$(wc -l < "$tmp_before" | tr -d ' ')
  total_after=$(wc -l < "$tmp_after" | tr -d ' ')
  total_before=${total_before:-0}
  total_after=${total_after:-0}

  # Dimension-specific presence counts (select few — not exhaustive)
  local pr_before pr_after dg_before dg_after rf_before rf_after ex_before ex_after
  # pressure-resistant markers
  pr_before=$(pattern_count "$tmp_before" 'EVEN IF|MUST|NEVER|This is not optional|non-negotiable')
  pr_after=$(pattern_count  "$tmp_after"  'EVEN IF|MUST|NEVER|This is not optional|non-negotiable')
  # decision-diagrams
  dg_before=$(pattern_count "$tmp_before" 'digraph|```dot|flowchart|mermaid')
  dg_after=$(pattern_count  "$tmp_after"  'digraph|```dot|flowchart|mermaid')
  # anti-rationalization (red flags tables + rationalization blocks)
  rf_before=$(pattern_count "$tmp_before" '[Rr]ed [Ff]lag|[Rr]ationaliz|Don.t rationalize')
  rf_after=$(pattern_count  "$tmp_after"  '[Rr]ed [Ff]lag|[Rr]ationaliz|Don.t rationalize')
  # examples (code fences + <example> blocks)
  ex_before=$(pattern_count "$tmp_before" '^```|<example>')
  ex_after=$(pattern_count  "$tmp_after"  '^```|<example>')

  rm -f "$tmp_before" "$tmp_after"

  # Smart ratio (bullet-aware — what a human would call directive density)
  local ratio_before ratio_after ratio_delta
  if [ "$nb_before" -gt 0 ]; then
    ratio_before=$(awk "BEGIN{printf \"%.6f\", $d_before / $nb_before}")
  else
    ratio_before="0.000000"
  fi
  if [ "$nb_after" -gt 0 ]; then
    ratio_after=$(awk "BEGIN{printf \"%.6f\", $d_after / $nb_after}")
  else
    ratio_after="0.000000"
  fi
  ratio_delta=$(awk "BEGIN{printf \"%.6f\", $ratio_after - $ratio_before}")

  # Benchmark ratio (naive, matches self-metrics.sh exactly — for disagreement detection)
  local bench_ratio_before bench_ratio_after bench_ratio_delta
  if [ "$total_before" -gt 0 ]; then
    bench_ratio_before=$(awk "BEGIN{printf \"%.6f\", $bench_before / $total_before}")
  else
    bench_ratio_before="0.000000"
  fi
  if [ "$total_after" -gt 0 ]; then
    bench_ratio_after=$(awk "BEGIN{printf \"%.6f\", $bench_after / $total_after}")
  else
    bench_ratio_after="0.000000"
  fi
  bench_ratio_delta=$(awk "BEGIN{printf \"%.6f\", $bench_ratio_after - $bench_ratio_before}")

  # Decide suspect dimensions for this file.
  #
  # Core insight (devil's advocate resolution): the escalation signal is
  # DISAGREEMENT between the naive benchmark regex and the bullet-aware smart
  # regex. When a change adds real directive content via markdown bullets,
  # smart_ratio goes UP but bench_ratio goes DOWN — that's a false-positive
  # regression waiting to happen. Escalate to reviewer.md to break the tie.

  local suspects='[]'

  # Signal 1: benchmark ratio drops but smart ratio stays flat or rises →
  # "hidden regression" — the benchmark is about to punish a real improvement.
  local hidden_regression
  hidden_regression=$(awk "BEGIN{print ($bench_ratio_delta < -0.0005 && $ratio_delta >= -0.0005) ? 1 : 0}")
  if [ "$hidden_regression" = "1" ]; then
    suspects=$(echo "$suspects" | jq '. + ["pressure-resistant"]')
  fi

  # Signal 2: smart directive_ratio dropped significantly (real directive dilution)
  local real_regression
  real_regression=$(awk "BEGIN{print ($ratio_delta < -0.005) ? 1 : 0}")
  if [ "$real_regression" = "1" ]; then
    suspects=$(echo "$suspects" | jq 'if index("pressure-resistant") then . else . + ["pressure-resistant"] end')
  fi

  # Signal 3: headers added without proportional smart-directive growth
  local h_delta d_delta header_suspect
  h_delta=$(( h_after - h_before ))
  d_delta=$(( d_after - d_before ))
  header_suspect=$(awk "BEGIN{print ($h_delta > 0 && ($h_delta * 3) > $d_delta) ? 1 : 0}")
  if [ "$header_suspect" = "1" ]; then
    suspects=$(echo "$suspects" | jq 'if index("pressure-resistant") then . else . + ["pressure-resistant"] end')
  fi

  # Signal 3: presence count decreases for specific dimensions
  [ "$pr_after" -lt "$pr_before" ] && suspects=$(echo "$suspects" | jq 'if index("pressure-resistant") then . else . + ["pressure-resistant"] end')
  [ "$dg_after" -lt "$dg_before" ] && suspects=$(echo "$suspects" | jq 'if index("decision-diagrams") then . else . + ["decision-diagrams"] end')
  [ "$rf_after" -lt "$rf_before" ] && suspects=$(echo "$suspects" | jq 'if index("anti-rationalization") then . else . + ["anti-rationalization"] end')
  [ "$ex_after" -lt "$ex_before" ] && suspects=$(echo "$suspects" | jq 'if index("examples") then . else . + ["examples"] end')

  # Emit per-file JSON
  jq -n \
    --arg path "$path" \
    --argjson d_before "$d_before" --argjson d_after "$d_after" \
    --argjson bench_before "$bench_before" --argjson bench_after "$bench_after" \
    --argjson nb_before "$nb_before" --argjson nb_after "$nb_after" \
    --argjson total_before "$total_before" --argjson total_after "$total_after" \
    --argjson h_before "$h_before" --argjson h_after "$h_after" \
    --arg ratio_before "$ratio_before" --arg ratio_after "$ratio_after" --arg ratio_delta "$ratio_delta" \
    --arg bench_ratio_before "$bench_ratio_before" --arg bench_ratio_after "$bench_ratio_after" --arg bench_ratio_delta "$bench_ratio_delta" \
    --argjson pr_before "$pr_before" --argjson pr_after "$pr_after" \
    --argjson dg_before "$dg_before" --argjson dg_after "$dg_after" \
    --argjson rf_before "$rf_before" --argjson rf_after "$rf_after" \
    --argjson ex_before "$ex_before" --argjson ex_after "$ex_after" \
    --argjson suspects "$suspects" \
    '{
      path: $path,
      smart_directive_lines: { before: $d_before, after: $d_after },
      bench_directive_lines: { before: $bench_before, after: $bench_after },
      non_blank_lines: { before: $nb_before, after: $nb_after },
      total_lines: { before: $total_before, after: $total_after },
      headers: { before: $h_before, after: $h_after },
      smart_directive_ratio: {
        before: ($ratio_before | tonumber),
        after: ($ratio_after | tonumber),
        delta: ($ratio_delta | tonumber)
      },
      bench_directive_ratio: {
        before: ($bench_ratio_before | tonumber),
        after: ($bench_ratio_after | tonumber),
        delta: ($bench_ratio_delta | tonumber)
      },
      presence: {
        pressure_resistant: { before: $pr_before, after: $pr_after },
        decision_diagrams:  { before: $dg_before, after: $dg_after },
        anti_rationalization: { before: $rf_before, after: $rf_after },
        examples: { before: $ex_before, after: $ex_after }
      },
      suspect_dimensions: $suspects
    }'
}

# ── Main: replay all changed SKILL.md files ────────────────────────────────

CHANGED=$(git diff --name-only "$PARENT" "$COMMIT" 2>/dev/null | grep -E '^skills/.*/SKILL\.md$' || true)

if [ -z "$CHANGED" ]; then
  jq -n --arg commit "$COMMIT" --arg parent "$PARENT" \
    '{commit: $commit, parent: $parent, files: [], suspect_dimensions: [], note: "no SKILL.md files changed"}'
  exit 0
fi

ALL_FILES='[]'
ALL_SUSPECTS='[]'

while IFS= read -r path; do
  [ -z "$path" ] && continue
  file_json=$(replay_file "$path")
  ALL_FILES=$(echo "$ALL_FILES" | jq ". + [$file_json]")
  file_suspects=$(echo "$file_json" | jq '.suspect_dimensions')
  ALL_SUSPECTS=$(echo "$ALL_SUSPECTS $file_suspects" | jq -s 'add | unique')
done <<< "$CHANGED"

jq -n \
  --arg commit "$COMMIT" \
  --arg parent "$PARENT" \
  --argjson files "$ALL_FILES" \
  --argjson suspects "$ALL_SUSPECTS" \
  '{
    commit: $commit,
    parent: $parent,
    files: $files,
    suspect_dimensions: $suspects,
    non_empty: ($suspects | length > 0)
  }'
