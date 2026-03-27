# Copilot Review Instructions — autoimprove

This repo implements a self-improvement feedback loop: polling triggers that watch for Claude session output, extract learnings, and write them back as prompts or memory entries.

## Primary concerns

### Trigger idempotency (highest priority)
- Polling scripts must not process the same event twice. Look for lock files, processed-ID tracking, or state markers.
- Flag any loop that reads a file/directory and processes entries without marking them as done.
- `flock` or a `.processed` sentinel file are acceptable patterns.

### Polling interval safety
- No polling loop should run faster than every 5 minutes. Flag `sleep` values under 300 seconds in recurring loops.
- Tight retry loops on API failures are a bug — they will exhaust rate limits. Flag `while true; do ... done` without a minimum sleep.

### GitHub API correctness
- All `gh api` or `curl` calls to GitHub must handle HTTP 429 (rate limited). Look for `x-ratelimit-remaining` checks or exponential backoff.
- List endpoints return paginated results — flag any code that only reads the first page when completeness matters.

### Prompt quality
- Flag prompts that use vague instructions: "improve this", "make it better", "do good work". Prompts must be specific about the desired transformation.
- Prompts should include context about what the input is, what the output format should be, and any constraints.

### Bash 3.2 compatibility (macOS default shell)
- No `declare -A` associative arrays (bash 4+).
- No `mapfile` or `readarray` (bash 4+).
- No `&>>` redirect syntax (bash 4+).
- No `[[` with `=~` regex and capture groups via `BASH_REMATCH` — test compatibility.
- Use `#!/usr/bin/env bash` not `#!/bin/bash`.

### Shell safety
- `set -euo pipefail` at the top of every script.
- All `$variables` quoted in commands.
- Temp files use `mktemp` and are cleaned up in a `trap ... EXIT`.

## What to skip
- Don't flag missing unit tests — integration testing is the norm here.
- Don't flag `.yaml` indentation unless it's structurally invalid.
