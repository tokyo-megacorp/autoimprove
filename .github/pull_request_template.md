## Summary

<!-- What changed? Be specific — Copilot uses this for review context. -->

## Motivation / Why

<!-- Why is this change needed? What problem does it solve? -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactoring (no behavior change)
- [ ] Chore / infra / config
- [ ] Documentation

## Testing done

<!-- Describe how you tested. Include: did polling trigger correctly? No double-processing? -->
[NO_TEST_SUITE: autoimprove — integration tested manually]

## Related issues

<!-- Closes #N -->

## Copilot review focus areas

> This repo is a self-improvement loop with polling trigger scripts and prompt engineering.
> Please pay extra attention to:

- **Trigger idempotency**: Can the same event be processed twice? What prevents double-processing?
- **Polling safety**: Does the polling loop have a minimum interval? No tight retry loops?
- **Prompt quality**: Are instructions specific and unambiguous? No vague directives like "do better"?
- **GitHub API calls**: Are rate limit errors handled? Is pagination handled for list endpoints?
- **Bash 3.2 compatibility**: No `declare -A` associative arrays, no `mapfile`/`readarray`, no `&>>` append-redirect?
- **Shell safety**: `set -euo pipefail`? No unquoted variables? Proper quoting of paths?
- **State files**: Are lock files or state markers cleaned up on exit/failure?

## Checklist

- [ ] `set -euo pipefail` at top of every new shell script
- [ ] Bash 3.2 compatible (no bash 4+ features)
- [ ] Polling trigger cannot double-process the same event
- [ ] GitHub API calls handle 429 rate limit responses
- [ ] No tight retry loops — minimum 5-minute interval for recurring tasks
- [ ] Prompt instructions are specific, not vague
- [ ] Manual test run documented above
