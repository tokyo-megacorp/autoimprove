#!/usr/bin/env bash
# theme-weights.sh — Compute adjusted theme weights from historical experiment data.
#
# Reads experiments.tsv and autoimprove.yaml; outputs adjusted weights as JSON.
# Used by the autoimprove orchestrator BEFORE theme selection.
#
# ╔══════════════════════════════════════════════════════════════════╗
# ║  GOODHART BOUNDARY — ORCHESTRATOR TOOL ONLY                     ║
# ║  Output is used for weighted theme selection only.               ║
# ║  NEVER pass this output to the experimenter agent.              ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Formula: adjusted = base_priority × (0.5 + keep_rate)
#   keep_rate = 0%   →  0.5× base  (penalised)
#   keep_rate = 100% →  1.5× base  (boosted)
#   floor             →  0.25× base (prevents starvation)
#   cold start        →  factor 1.0 (< 3 samples — new themes get base priority)
#
# Usage:
#   bash scripts/theme-weights.sh [YAML_PATH] [TSV_PATH]
#   bash scripts/theme-weights.sh autoimprove.yaml experiments/experiments.tsv
#
# Outputs JSON to stdout:
#   {"test_coverage": 0.75, "refactoring": 1.5, ...}
#
# Exit codes:
#   0  success
#   1  missing required file or tool

set -euo pipefail

YAML_PATH="${1:-autoimprove.yaml}"
TSV_PATH="${2:-experiments/experiments.tsv}"

if [[ ! -f "$YAML_PATH" ]]; then
  echo "FATAL: $YAML_PATH not found" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL: python3 is required" >&2
  exit 1
fi

python3 - "$YAML_PATH" "$TSV_PATH" <<'PYTHON'
import sys, json, csv, os

yaml_path = sys.argv[1]
tsv_path  = sys.argv[2]

# --- Parse base priorities from autoimprove.yaml ---
try:
    import yaml
    with open(yaml_path) as f:
        config = yaml.safe_load(f)
    base_priorities = config["themes"]["auto"]["priorities"]
except ImportError:
    # Fallback: minimal regex parser (no PyYAML)
    import re
    base_priorities = {}
    with open(yaml_path) as f:
        content = f.read()
    m = re.search(r'priorities:\s*\n((?:[ \t]+\w[^\n]*\n)+)', content)
    if m:
        for line in m.group(1).splitlines():
            km = re.match(r'\s+(\w+):\s*(\d+(?:\.\d+)?)', line)
            if km:
                base_priorities[km.group(1)] = float(km.group(2))

if not base_priorities:
    sys.stderr.write("FATAL: no themes.auto.priorities found in " + yaml_path + "\n")
    sys.exit(1)

# --- Read experiments.tsv to compute per-theme keep rates ---
theme_runs  = {}  # theme -> total experiments
theme_keeps = {}  # theme -> keep count

if os.path.isfile(tsv_path):
    with open(tsv_path, newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            theme   = row.get("theme",   "").strip()
            verdict = row.get("verdict", "").strip()
            if not theme:
                continue
            theme_runs[theme]  = theme_runs.get(theme, 0) + 1
            if verdict == "keep":
                theme_keeps[theme] = theme_keeps.get(theme, 0) + 1

# --- Apply weight formula ---
COLD_START_MIN    = 3
COLD_START_FACTOR = 1.0
FLOOR_FACTOR      = 0.25

adjusted = {}
for theme, base in base_priorities.items():
    base = float(base)
    runs  = theme_runs.get(theme, 0)
    keeps = theme_keeps.get(theme, 0)

    if runs < COLD_START_MIN:
        factor = COLD_START_FACTOR          # new theme: no penalty, no boost
    else:
        keep_rate = keeps / runs            # 0.0 – 1.0
        factor = 0.5 + keep_rate           # 0.5 – 1.5

    raw_weight   = base * factor
    floor_weight = base * FLOOR_FACTOR
    adjusted[theme] = round(max(raw_weight, floor_weight), 4)

print(json.dumps(adjusted, indent=2))
PYTHON
