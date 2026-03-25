#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

test_count=$(grep -r "it(" "$PROJECT_DIR/test" --include="*.test.js" | wc -l | tr -d ' ')
todo_count=$(grep -rn "TODO" "$PROJECT_DIR/src" --include="*.js" | wc -l | tr -d ' ')
src_lines=$(find "$PROJECT_DIR/src" -name "*.js" -exec cat {} + | grep -c -v '^[[:space:]]*$' || echo 0)
test_lines=$(find "$PROJECT_DIR/test" -name "*.test.js" -exec cat {} + | grep -c -v '^[[:space:]]*$' || echo 0)

if [ "$src_lines" -gt 0 ]; then
  test_ratio=$(echo "scale=2; $test_lines / $src_lines" | bc)
else
  test_ratio="0"
fi

cat <<EOF
{
  "test_count": $test_count,
  "todo_count": $todo_count,
  "src_lines": $src_lines,
  "test_ratio": $test_ratio
}
EOF
