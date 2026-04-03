#!/usr/bin/env bash
# Scan the repo for untested skills/agents and scaffold test files for them.
# Prioritizes by recency of last git change — most recently modified first.
#
# Usage:
#   ./scan-and-scaffold.sh              # scaffold all gaps
#   ./scan-and-scaffold.sh --dry-run    # show gaps without writing files
#   ./scan-and-scaffold.sh --skills     # skills only
#   ./scan-and-scaffold.sh --agents     # agents only
#
# After running: fill in the TODO placeholders in each generated test file.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCAFFOLD="$SCRIPT_DIR/scaffold-test.sh"

DRY_RUN=0
INCLUDE_SKILLS=1
INCLUDE_AGENTS=1

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --skills)  INCLUDE_AGENTS=0 ;;
        --agents)  INCLUDE_SKILLS=0 ;;
    esac
done

# ── Collect components with last-modified timestamp ─────────────────────────

declare -a ITEMS  # "timestamp|type|name|source_path"

if [ "$INCLUDE_SKILLS" = "1" ]; then
    for skill_dir in "$REPO_ROOT/skills"/*/; do
        skill_file="$skill_dir/SKILL.md"
        [ -f "$skill_file" ] || continue
        name="$(basename "$skill_dir")"
        # Skip the prompt-testing skill itself
        [ "$name" = "prompt-testing" ] && continue
        test_file="$REPO_ROOT/tests/skills/test-${name}.sh"
        [ -f "$test_file" ] && continue  # already has a test
        ts=$(git -C "$REPO_ROOT" log -1 --format="%ct" -- "skills/${name}/SKILL.md" 2>/dev/null || echo "0")
        ITEMS+=("${ts}|skill|${name}|skills/${name}/SKILL.md")
    done
fi

if [ "$INCLUDE_AGENTS" = "1" ]; then
    for agent_file in "$REPO_ROOT/agents"/*.md; do
        [ -f "$agent_file" ] || continue
        name="$(basename "$agent_file" .md)"
        test_file="$REPO_ROOT/tests/agents/test-${name}.sh"
        [ -f "$test_file" ] && continue  # already has a test
        ts=$(git -C "$REPO_ROOT" log -1 --format="%ct" -- "agents/${name}.md" 2>/dev/null || echo "0")
        ITEMS+=("${ts}|agent|${name}|agents/${name}.md")
    done
fi

# ── Sort by timestamp descending (most recently changed first) ───────────────

IFS=$'\n' SORTED=($(printf '%s\n' "${ITEMS[@]}" | sort -t'|' -k1 -rn))
unset IFS

# ── Report ───────────────────────────────────────────────────────────────────

TOTAL="${#SORTED[@]}"

if [ "$TOTAL" -eq 0 ]; then
    echo "✓ All skills and agents have test coverage."
    exit 0
fi

echo "Found $TOTAL untested component(s) — ordered by recency of last change:"
echo ""

for item in "${SORTED[@]}"; do
    ts="${item%%|*}"
    rest="${item#*|}"
    type="${rest%%|*}"
    rest="${rest#*|}"
    name="${rest%%|*}"
    source="${rest#*|}"

    if [ "$ts" -gt 0 ] 2>/dev/null; then
        if date --version >/dev/null 2>&1; then
            # GNU date (Linux)
            human_date=$(date -d "@$ts" "+%Y-%m-%d" 2>/dev/null || echo "unknown")
        else
            # BSD date (macOS)
            human_date=$(date -r "$ts" "+%Y-%m-%d" 2>/dev/null || echo "unknown")
        fi
    else
        human_date="untracked"
    fi

    echo "  [$type] $name  (last changed: $human_date)  →  $source"
done

echo ""

if [ "$DRY_RUN" = "1" ]; then
    echo "(dry-run — no files written)"
    exit 0
fi

# ── Scaffold ─────────────────────────────────────────────────────────────────

SCAFFOLDED=0
for item in "${SORTED[@]}"; do
    rest="${item#*|}"
    type="${rest%%|*}"
    name="${rest#*|}"
    name="${name%%|*}"

    echo "Scaffolding $type '$name'..."
    bash "$SCAFFOLD" "$type" "$name"
    SCAFFOLDED=$((SCAFFOLDED + 1))
    echo ""
done

echo "─────────────────────────────────────────────"
echo "Scaffolded $SCAFFOLDED test file(s)."
echo ""
echo "Next steps:"
echo "  1. For each test file, read the source component"
echo "  2. Replace TODO placeholders with real behavioral claims"
echo "  3. Run: bash tests/skills/test-<name>.sh   (or tests/agents/)"
