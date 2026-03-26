#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"

# test_count: number of test cases in the evaluate.sh test suite
# Marker format: echo "--- Test: <name> ---"
test_count=$(grep -c -- "--- Test:" "$DIR/test/evaluate/test-evaluate.sh" 2>/dev/null || echo 0)

# broken_constraints: load-bearing invariant phrases must remain in experimenter agent
broken_constraints=0
for phrase in "forbidden_paths" "additive only" "reverse-engineer" "worktree"; do
  grep -q "$phrase" "$DIR/agents/experimenter.md" 2>/dev/null || broken_constraints=$((broken_constraints + 1))
done
# Line-count floor: catches wholesale file gutting
lines=$(wc -l < "$DIR/agents/experimenter.md" 2>/dev/null || echo 0)
[ "$lines" -lt 20 ] && broken_constraints=$((broken_constraints + 1))

# broken_refs: critical files referenced by the orchestrator must exist
broken_refs=0
for f in \
  "$DIR/skills/run/references/loop.md" \
  "$DIR/agents/experimenter.md" \
  "$DIR/scripts/evaluate.sh"; do
  [ -f "$f" ] || broken_refs=$((broken_refs + 1))
done

echo "{\"test_count\": $test_count, \"broken_constraints\": $broken_constraints, \"broken_refs\": $broken_refs}"
