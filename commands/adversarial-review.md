---
name: adversarial-review
description: Run the adversarial Enthusiast→Adversary→Judge debate review on the current diff, a file, or a PR. Always runs in background.
argument-hint: "[file|diff|pr]"
---

This review MUST run in the background so the user is not blocked.

**Do this:**

1. Spawn a **background Agent** (using `run_in_background: true`) with:
   - The `adversarial-review` skill invoked via the Skill tool
   - Arguments: `$ARGUMENTS`
   - Name: `adversarial-review`

2. Tell the user: "Review dispatched in background. I'll notify you when it's done."

3. When the background agent completes, summarize the results to the user:
   - Number of confirmed vs debunked findings
   - Top confirmed findings (critical/high severity)
   - Run folder path

**Do NOT invoke the skill directly in the foreground.** The whole point is non-blocking execution.
