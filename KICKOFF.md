# autoimprove — Session Kickoff Prompt

Copy-paste the block below to start implementation.

---

Read CLAUDE.md, DESIGN.md, and TELEMETRY.md in this repo. These are the complete specs for autoimprove — an autonomous codebase improvement loop inspired by karpathy/autoresearch.

The design has been stress-tested through 2 rounds of adversarial FOR/AGAINST review, a 4-perspective spike on constraint philosophy (autoresearch, evolutionary algorithms, pragmatic engineer, open source maintainer), and a full telemetry audit against Claude Code APIs.

Build Phase 1: the MVP Grind loop. Follow the implementation priorities in CLAUDE.md. Specifically:

1. Scaffold the Claude Code plugin (plugin.json, directory structure)
2. Build the autoimprove.yaml parser + validator
3. Build the orchestrator skill (the main loop)
4. Build the experimenter agent (runs in worktree via Agent tool with isolation: "worktree")
5. Build hard gates runner (test suite, typecheck, coverage gate)
6. Build benchmark runner + metric extractor (support `type: script` first, defer `type: task`)
7. Build scoring system (dual baseline — epoch frozen + rolling updated, composite score)
8. Build keep/discard logic (worktree merge or delete, trust ratchet tier tracking)
9. Build experiment logger (experiments.tsv + per-experiment context.json with full metric breakdown)
10. Build /autoimprove run command
11. Build /autoimprove report command (morning report)
12. Build /autoimprove init command (scaffold autoimprove.yaml for a project)

Before writing any code, run a telemetry smoke test: verify that Agent(isolation="worktree"), AssistantMessage.usage, TaskProgressMessage, and max_budget_usd work as documented in TELEMETRY.md. Flag any API that doesn't match the spec.

Start with a plan. Then build iteratively — get the loop skeleton working end-to-end first (orchestrator → spawn experimenter in worktree → run gates → score → keep/discard → log), even if scoring is a stub. Then fill in each component.

The first real test: run autoimprove on the test-project/ directory described in CLAUDE.md. Create that test fixture as part of implementation.
