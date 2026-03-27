---
name: autoimprove-test
description: Run the autoimprove test suites — scoring unit tests, integration tests, and evaluate tests.
argument-hint: "[challenge|integration|evaluate|all]"
---

Run the autoimprove test suites. Arguments: $ARGUMENTS

If no argument or "all", run all three suites:
```bash
bash test/challenge/test-score-challenge.sh
bash test/challenge/test-integration.sh
bash test/evaluate/test-evaluate.sh
```

If argument is "challenge", run only `test/challenge/test-score-challenge.sh`.
If argument is "integration", run only `test/challenge/test-integration.sh`.
If argument is "evaluate", run only `test/evaluate/test-evaluate.sh`.

Report total pass/fail counts across all suites run.
