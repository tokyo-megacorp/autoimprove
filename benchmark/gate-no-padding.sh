#!/usr/bin/env bash
# Hard gate: fail if any skill was inflated without new code blocks.
# Exit 0 = pass. Exit 1 = discard experiment.
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"

alarm=$(bash "$DIR/benchmark/self-metrics.sh" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('padding_alarm', 0))
")

if [ "$alarm" -gt 0 ]; then
    echo "GATE FAIL: padding_alarm=$alarm — $alarm skill(s) grew >50% without new examples" >&2
    exit 1
fi
exit 0
