#!/usr/bin/env bash
# Validate skill authoring hygiene for skills/<name>/SKILL.md files.
# Deterministic checks only: suitable for local hooks and CI blockers.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_LIST"' EXIT

MODE="all"
ERRORS=0
CHECKED=0
EXPLICIT_INPUTS=0

usage() {
  cat <<'EOF'
Usage: scripts/validate-skill-authoring.sh [--staged] [path...]

Validates deterministic skill-authoring checks:
- skills/<name>/SKILL.md exists
- YAML frontmatter exists and parses
- name is present, kebab-case, <= 64 chars, matches directory
- name does not contain reserved platform words
- description is present and <= 1024 chars

Options:
  --staged   Validate only staged skill changes
  --help     Show this help
EOF
}

print_error() {
  local label="$1"
  local message="$2"
  echo "ERROR: ${label} — ${message}"
  ERRORS=$((ERRORS + 1))
}

append_candidate() {
  local input="$1"
  local candidate=""
  local skill_dir=""
  local dir_name=""

  [ -z "$input" ] && return 0

  if [ -d "$input" ]; then
    dir_name="$(basename "$input")"
    case "$dir_name" in
      _*) return 0 ;;
    esac
    if [ -f "$input/SKILL.md" ]; then
      candidate="$input/SKILL.md"
    fi
  elif [ -f "$input" ]; then
    if [ "$(basename "$input")" = "SKILL.md" ]; then
      dir_name="$(basename "$(dirname "$input")")"
      case "$dir_name" in
        _*) return 0 ;;
      esac
      candidate="$input"
    else
      skill_dir="$(dirname "$input")"
      dir_name="$(basename "$skill_dir")"
      case "$dir_name" in
        _*) return 0 ;;
      esac
      if [ -f "$skill_dir/SKILL.md" ]; then
        candidate="$skill_dir/SKILL.md"
      fi
    fi
  fi

  [ -n "$candidate" ] && printf '%s\n' "$candidate" >> "$TMP_LIST"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --staged)
      MODE="staged"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      EXPLICIT_INPUTS=1
      append_candidate "$1"
      shift
      ;;
  esac
done

if [ "$MODE" = "staged" ]; then
  while IFS= read -r path; do
    case "$path" in
      skills/*/SKILL.md)
        append_candidate "$ROOT/$path"
        ;;
      skills/*/*)
        skill_dir="$(printf '%s\n' "$path" | cut -d/ -f1-2)"
        if [ -f "$ROOT/$skill_dir/SKILL.md" ]; then
          append_candidate "$ROOT/$skill_dir/SKILL.md"
        fi
        ;;
    esac
  done <<EOF
$(git diff --cached --name-only --diff-filter=ACMR)
EOF
elif [ "$EXPLICIT_INPUTS" -eq 0 ] && [ ! -s "$TMP_LIST" ]; then
  while IFS= read -r path; do
    append_candidate "$path"
  done <<EOF
$(find "$ROOT/skills" -mindepth 2 -maxdepth 2 -name 'SKILL.md' 2>/dev/null | sort)
EOF
fi

if [ ! -s "$TMP_LIST" ]; then
  echo "No skill files to validate."
  exit 0
fi

sort -u "$TMP_LIST" -o "$TMP_LIST"

while IFS= read -r skill_file; do
  dir_name="$(basename "$(dirname "$skill_file")")"
  case "$dir_name" in
    _*) continue ;;
  esac

  CHECKED=$((CHECKED + 1))
  label="$skill_file"
  validation_path="$skill_file"
  temp_validation=""

  if [ "$MODE" = "staged" ] && [ -f "$skill_file" ]; then
    case "$skill_file" in
      "$ROOT"/*)
        rel_path="${skill_file#$ROOT/}"
        staged_copy="$(mktemp)"
        if git show ":${rel_path}" > "$staged_copy" 2>/dev/null; then
          validation_path="$staged_copy"
          temp_validation="$staged_copy"
        else
          rm -f "$staged_copy"
        fi
        ;;
    esac
  fi

  if [ ! -f "$validation_path" ]; then
    print_error "$label" "SKILL.md not found"
    [ -n "$temp_validation" ] && rm -f "$temp_validation"
    continue
  fi

  frontmatter_state=""
  yaml_error=""
  name=""
  description_len=""

  while IFS='=' read -r key value; do
    case "$key" in
      frontmatter) frontmatter_state="$value" ;;
      yaml_error) yaml_error="$value" ;;
      name) name="$value" ;;
      description_len) description_len="$value" ;;
    esac
  done <<EOF
$(ruby - "$validation_path" <<'RUBY'
require "yaml"

path = ARGV[0]
content = File.read(path)
match = content.match(/\A---\s*\n(.*?)\n---\s*(?:\n|\z)/m)

if match.nil?
  puts "frontmatter=missing"
  exit 0
end

begin
  data = YAML.safe_load(match[1], aliases: true)
rescue => error
  puts "frontmatter=invalid"
  puts "yaml_error=#{error.message.gsub("\n", " ")}"
  exit 0
end

unless data.is_a?(Hash)
  puts "frontmatter=invalid"
  puts "yaml_error=Frontmatter must parse to a mapping"
  exit 0
end

name = data["name"].nil? ? "" : data["name"].to_s
description = data["description"].nil? ? "" : data["description"].to_s

puts "frontmatter=ok"
puts "name=#{name.gsub("\n", " ")}"
puts "description_len=#{description.length}"
RUBY
)
EOF

  case "$frontmatter_state" in
    missing)
      print_error "$label" "missing YAML frontmatter"
      [ -n "$temp_validation" ] && rm -f "$temp_validation"
      continue
      ;;
    invalid)
      print_error "$label" "invalid YAML frontmatter (${yaml_error})"
      [ -n "$temp_validation" ] && rm -f "$temp_validation"
      continue
      ;;
  esac

  if [ -z "$name" ]; then
    print_error "$label" "missing required frontmatter field 'name'"
  fi

  if [ -n "$name" ] && ! printf '%s' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    print_error "$label" "name must be kebab-case"
  fi

  if [ "${#name}" -gt 64 ]; then
    print_error "$label" "name exceeds 64 characters"
  fi

  if [ -n "$name" ] && [ "$name" != "$dir_name" ]; then
    print_error "$label" "name '$name' does not match directory '$dir_name'"
  fi

  if [ -n "$name" ] && printf '%s' "$name" | grep -Eqi 'anthropic|claude'; then
    print_error "$label" "name contains reserved platform word"
  fi

  if [ -z "$description_len" ]; then
    print_error "$label" "missing required frontmatter field 'description'"
  elif [ "$description_len" -eq 0 ]; then
    print_error "$label" "description must not be empty"
  elif [ "$description_len" -gt 1024 ]; then
    print_error "$label" "description is ${description_len} chars (max 1024)"
  fi

  [ -n "$temp_validation" ] && rm -f "$temp_validation"
done < "$TMP_LIST"

if [ "$ERRORS" -gt 0 ]; then
  echo "BLOCKED: ${ERRORS} skill authoring error(s) across ${CHECKED} skill file(s)."
  exit 1
fi

echo "OK: skill authoring validation passed for ${CHECKED} skill file(s)."
