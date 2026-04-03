#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"

# test_count: number of test cases in the evaluate.sh test suite
# Marker format: echo "--- Test: <name> ---"
if [ -f "$DIR/test/evaluate/test-evaluate.sh" ]; then
  test_count=$(grep -c -- "--- Test:" "$DIR/test/evaluate/test-evaluate.sh" 2>/dev/null || true)
else
  test_count=0
fi

# broken_constraints: load-bearing invariant phrases must remain in experimenter agent
broken_constraints=0
for phrase in "forbidden_paths" "additive only" "how your changes are scored" "worktree"; do
  grep -q "$phrase" "$DIR/agents/experimenter.md" 2>/dev/null || broken_constraints=$((broken_constraints + 1)) || true
done
# Line-count floor: catches wholesale file gutting
if [ -f "$DIR/agents/experimenter.md" ]; then
  lines=$(wc -l < "$DIR/agents/experimenter.md")
else
  lines=0
fi
[ "$lines" -lt 20 ] && { broken_constraints=$((broken_constraints + 1)) || true; }

# broken_refs: critical files referenced by the orchestrator must exist
broken_refs=0
for f in \
  "$DIR/skills/run/references/loop.md" \
  "$DIR/agents/experimenter.md" \
  "$DIR/scripts/evaluate.sh"; do
  [ -f "$f" ] || broken_refs=$((broken_refs + 1)) || true
done

# skill_doc_coverage: number of skills with a non-empty description in SKILL.md
skill_doc_coverage=0
for skill_dir in "$DIR/skills"/*/; do
  if [ -f "$skill_dir/SKILL.md" ]; then
    grep -q "^description:" "$skill_dir/SKILL.md" 2>/dev/null && skill_doc_coverage=$((skill_doc_coverage + 1)) || true
  fi
done

# agent_completeness: number of agents with both name and description fields
agent_completeness=0
for agent_file in "$DIR/agents"/*.md; do
  [ -f "$agent_file" ] || continue
  if grep -q "^name:" "$agent_file" 2>/dev/null && grep -q "^description:" "$agent_file" 2>/dev/null; then
    agent_completeness=$((agent_completeness + 1))
  fi
done

# skill_depth: average line count across all SKILL.md files
skill_depth=0
skill_file_count=0
for skill_dir in "$DIR/skills"/*/; do
  if [ -f "$skill_dir/SKILL.md" ]; then
    lines=$(wc -l < "$skill_dir/SKILL.md")
    skill_depth=$((skill_depth + lines))
    skill_file_count=$((skill_file_count + 1))
  fi
done
if [ "$skill_file_count" -gt 0 ]; then
  skill_depth=$((skill_depth / skill_file_count))
fi

# agent_sections: count of agents with all required sections (description, when-to-use, constraints)
agent_sections=0
for agent_file in "$DIR/agents"/*.md; do
  [ -f "$agent_file" ] || continue
  has_desc=0
  has_when=0
  has_constraints=0
  grep -qi "^description:" "$agent_file" 2>/dev/null && has_desc=1 || true
  grep -qi "when.to.use\|when to use\|## when" "$agent_file" 2>/dev/null && has_when=1 || true
  grep -qi "constraint\|forbidden\|never\|must not" "$agent_file" 2>/dev/null && has_constraints=1 || true
  [ "$has_desc" -eq 1 ] && [ "$has_when" -eq 1 ] && [ "$has_constraints" -eq 1 ] && agent_sections=$((agent_sections + 1)) || true
done

# revert_rate: proportion of last 50 commits that are reverts (float 0.0-1.0)
# Missing data (no git history): output 0.0
revert_rate="0.0"
if git -C "$DIR" log --oneline -50 >/dev/null 2>&1; then
  revert_count=$(git -C "$DIR" log --oneline -50 2>/dev/null | grep -ic "revert" || true)
  total_commits=$(git -C "$DIR" log --oneline -50 2>/dev/null | wc -l | tr -d ' ')
  if [ "$total_commits" -gt 0 ]; then
    # Use awk for float division
    revert_rate=$(awk "BEGIN {printf \"%.4f\", $revert_count / $total_commits}")
  fi
fi

# bug_escape_rate: open bug issues / total open issues (float 0.0-1.0)
# Missing data (no gh auth, no issues): output 0.0
bug_escape_rate="0.0"
if command -v gh >/dev/null 2>&1; then
  total_open=$(gh issue list --state open --limit 200 --json number 2>/dev/null | grep -c '"number"' || true)
  bug_open=$(gh issue list --state open --label bug --limit 200 --json number 2>/dev/null | grep -c '"number"' || true)
  if [ "$total_open" -gt 0 ]; then
    bug_escape_rate=$(awk "BEGIN {printf \"%.4f\", $bug_open / $total_open}")
  fi
fi

# ar_severity_trend: count of "high" severity findings in last 3 AR telemetry runs
# Missing data (no runs dir, no runs): output 0
ar_severity_trend=0
AR_RUNS_DIR="${HOME}/.autoimprove/runs"
if [ -d "$AR_RUNS_DIR" ]; then
  # Get last 3 run directories sorted by name (timestamp-prefixed = chronological)
  last3_dirs=$(ls -1 "$AR_RUNS_DIR" 2>/dev/null | grep -E '^[0-9]{8}-' | sort | tail -3)
  for run_name in $last3_dirs; do
    run_file="$AR_RUNS_DIR/$run_name/run.json"
    if [ -f "$run_file" ]; then
      high_count=$(jq '[.. | objects | select(.severity == "high")] | length' "$run_file" 2>/dev/null || grep -c '"severity":[[:space:]]*"high"' "$run_file" 2>/dev/null || true)
      ar_severity_trend=$((ar_severity_trend + high_count))
    fi
  done
fi

# fix_durability: proportion of "keep" experiments with no subsequent "discard" within next 5 rows
# Missing data (<5 experiments total): output 1.0
# Reads experiments/experiments.tsv relative to project root
fix_durability="1.0"
TSV_PATH="$DIR/experiments/experiments.tsv"
if [ -f "$TSV_PATH" ]; then
  # Extract verdict column (col 4) skipping header; store as array
  verdicts=()
  while IFS= read -r line; do
    verdicts+=("$line")
  done < <(awk -F'\t' 'NR>1 && NF>=4 {print $4}' "$TSV_PATH" 2>/dev/null || true)
  total_verdicts=${#verdicts[@]}
  if [ "$total_verdicts" -ge 5 ]; then
    keep_total=0
    keep_durable=0
    for i in "${!verdicts[@]}"; do
      if [ "${verdicts[$i]}" = "keep" ]; then
        keep_total=$((keep_total + 1))
        # Check next 5 rows for a discard
        found_discard=0
        for j in 1 2 3 4 5; do
          next=$((i + j))
          if [ "$next" -lt "$total_verdicts" ] && [ "${verdicts[$next]}" = "discard" ]; then
            found_discard=1
            break
          fi
        done
        [ "$found_discard" -eq 0 ] && keep_durable=$((keep_durable + 1))
      fi
    done
    if [ "$keep_total" -gt 0 ]; then
      fix_durability=$(awk "BEGIN {printf \"%.4f\", $keep_durable / $keep_total}")
    fi
  fi
fi

echo "{\"test_count\": $test_count, \"broken_constraints\": $broken_constraints, \"broken_refs\": $broken_refs, \"skill_doc_coverage\": $skill_doc_coverage, \"agent_completeness\": $agent_completeness, \"skill_depth\": $skill_depth, \"agent_sections\": $agent_sections, \"revert_rate\": $revert_rate, \"bug_escape_rate\": $bug_escape_rate, \"ar_severity_trend\": $ar_severity_trend, \"fix_durability\": $fix_durability}"
