#!/usr/bin/env bash
set -euo pipefail

# harvest-themes.sh — Goodhart-safe file targeting for theme-aware experiments
#
# Outputs JSON lines: {"path":"...","reason":"..."}
# NEVER outputs metric names — experimenter must remain blind to scoring.
#
# Usage: bash scripts/harvest-themes.sh <theme> [project_root]

THEME="${1:-}"
PROJECT_ROOT="${2:-.}"

# Read focus_paths from autoimprove.yaml for the given theme and expand globs.
# Returns newline-separated absolute file paths, or empty if not found/configured.
get_focus_files() {
  local theme="$1"
  local root="$2"
  local yaml_file="$root/autoimprove.yaml"
  [ -f "$yaml_file" ] || return 0
  python3 - "$yaml_file" "$theme" "$root" <<'PYEOF'
import sys, os, glob as globmod

yaml_file, theme, root = sys.argv[1], sys.argv[2], sys.argv[3]

with open(yaml_file) as f:
    content = f.read()

in_focus_paths = False
in_theme = False
indent_focus = None
indent_theme = None
patterns = []

for line in content.splitlines():
    stripped = line.lstrip()
    if not stripped or stripped.startswith("#"):
        continue
    indent = len(line) - len(stripped)

    if stripped == "focus_paths:":
        in_focus_paths = True
        indent_focus = indent
        in_theme = False
        continue

    if in_focus_paths:
        if indent_focus is not None and indent <= indent_focus:
            in_focus_paths = False
            in_theme = False
            continue
        if stripped == theme + ":":
            in_theme = True
            indent_theme = indent
            continue
        if in_theme:
            if indent_theme is not None and indent <= indent_theme and not stripped.startswith("-"):
                in_theme = False
                continue
            if stripped.startswith("- "):
                patterns.append(stripped[2:].strip().strip('"'))

if not patterns:
    sys.exit(0)

seen = set()
for pat in patterns:
    full_pat = os.path.join(root, pat)
    for match in sorted(globmod.glob(full_pat, recursive=True)):
        if os.path.isfile(match) and match not in seen:
            seen.add(match)
            print(match)
PYEOF
}

# candidate_files — emit focus files if configured, else fall back to find commands.
# Usage: candidate_files [find_cmd...]
# Any additional arguments are passed as separate find commands (eval'd).
candidate_files() {
  if [ -n "$FOCUS_FILES" ]; then
    echo "$FOCUS_FILES"
  else
    for find_cmd in "$@"; do
      eval "$find_cmd" 2>/dev/null
    done
  fi
}

FOCUS_FILES=$(get_focus_files "$THEME" "$PROJECT_ROOT")

case "$THEME" in
  test_coverage)
    # Find source shell scripts with no corresponding test file
    candidate_files \
      "find \"$PROJECT_ROOT/scripts\" -name '*.sh'" \
      "find \"$PROJECT_ROOT/skills\" -name '*.sh'" \
    | grep '\.sh$' | grep -v '/test/' \
    | while read -r f; do
      [ -z "$f" ] && continue
      basename=$(basename "$f" .sh)
      if ! find "$PROJECT_ROOT/test" -name "*${basename}*" 2>/dev/null | grep -q .; then
        printf '{"path":"%s","reason":"no test file found for this script"}\n' "$f"
      fi
    done
    ;;

  skill_quality)
    # Find SKILL.md files that are short (less thorough)
    candidate_files "find \"$PROJECT_ROOT/skills\" -name 'SKILL.md'" \
    | while read -r f; do
      [ -z "$f" ] && continue
      lines=$(wc -l < "$f" | tr -d ' ')
      if [ "$lines" -lt 50 ]; then
        printf '{"path":"%s","reason":"skill file is only %s lines — could be more thorough"}\n' "$f" "$lines"
      fi
    done
    ;;

  agent_prompts)
    # Find agent markdown files missing key structural sections
    candidate_files "find \"$PROJECT_ROOT/agents\" -name '*.md'" \
    | while read -r f; do
      [ -z "$f" ] && continue
      missing=""
      grep -qi "when to use\|description:" "$f" || missing="${missing}description,"
      grep -qi "constraints\|guardrails\|important" "$f" || missing="${missing}constraints,"
      if [ -n "$missing" ]; then
        printf '{"path":"%s","reason":"missing sections: %s"}\n' "$f" "${missing%,}"
      fi
    done
    ;;

  command_docs)
    # Find command docs that are very short
    candidate_files "find \"$PROJECT_ROOT/commands\" -name '*.md'" \
    | while read -r f; do
      [ -z "$f" ] && continue
      lines=$(wc -l < "$f" | tr -d ' ')
      if [ "$lines" -lt 20 ]; then
        printf '{"path":"%s","reason":"command doc is only %s lines"}\n' "$f" "$lines"
      fi
    done
    ;;

  refactoring)
    # Find files for refactoring from focus_paths or default to scripts/
    candidate_files "find \"$PROJECT_ROOT/scripts\" -name '*.sh'" \
    | while read -r f; do
      [ -z "$f" ] && continue
      printf '{"path":"%s","reason":"candidate for refactoring"}\n' "$f"
    done
    ;;

  *)
    # Unknown theme — no focus files (experimenter gets full autonomy)
    ;;
esac
