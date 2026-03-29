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

echo "{\"test_count\": $test_count, \"broken_constraints\": $broken_constraints, \"broken_refs\": $broken_refs, \"skill_doc_coverage\": $skill_doc_coverage, \"agent_completeness\": $agent_completeness, \"skill_depth\": $skill_depth, \"agent_sections\": $agent_sections}"
