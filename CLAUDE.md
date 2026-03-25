# autoimprove

Autonomous codebase improvement loop for Claude Code. Inspired by [karpathy/autoresearch](https://github.com/karpathy/autoresearch).

## What This Is

A Claude Code plugin that runs an experiment loop: modify code, evaluate against benchmarks, keep or discard via git worktrees. The human programs the improvement strategy (`autoimprove.yaml`), the system does the rest.

Read `DESIGN.md` for the full spec — it was stress-tested through adversarial FOR/AGAINST review.

## Project Structure

```
DESIGN.md              — full design spec (read this first)
CLAUDE.md              — this file
.claude-plugin/        — Claude Code plugin (to be built)
  plugin.json
  skills/              — orchestrator, init, report skills
  agents/              — experimenter, proposer, researcher agents
  commands/            — user-facing slash commands
```

## Architecture

Two-agent design:
- **Orchestrator**: picks themes, manages worktrees, runs gates/benchmarks, scores, keeps/discards
- **Experimenter**: spawned per-experiment into a worktree, blind to benchmarks and scoring

Three phases:
- **Grind**: autonomous small improvements, auto-merged (the core loop)
- **Propose**: drafts larger changes for human approval (triggered by stagnation)
- **Research**: investigates codebase, writes reports, no code changes

Trust escalation: the system earns scope through demonstrated competence (0 regressions → bigger scope).

## Key Design Decisions

- **Constraints are verifiability-based, not scope-based.** The hard gate is "can the test suite verify this change?" not "how many lines changed." File/line limits are soft guidance that escalate with trust.
- **Dual baseline** (epoch + rolling) prevents compound regression drift.
- **No LLM judge in v1** — deterministic metrics only. LLM-as-judge is v2.
- **Experimenter is blind to scoring** — separation of concerns prevents Goodhart gaming.
- **Test modifications must be additive only** — can add tests, cannot delete or weaken assertions (equivalent of autoresearch's immutable `prepare.py`).

## Implementation Priorities

### Phase 1: MVP (Grind loop only)
1. Plugin scaffold (`plugin.json`, directory structure)
2. `autoimprove.yaml` parser + validator
3. Orchestrator skill (the main loop)
4. Experimenter agent (worktree-isolated)
5. Hard gates runner (test suite, typecheck)
6. Benchmark runner + metric extractor
7. Scoring system (dual baseline, composite score)
8. Keep/discard logic (worktree merge/delete)
9. Experiment logger (`experiments.tsv` + `context.json`)
10. `/autoimprove run` command
11. `/autoimprove report` command
12. `/autoimprove init` command (project scaffolding)

### Phase 2: Trust + Proposals
13. Trust ratchet (tier escalation/regression)
14. Propose phase (proposer agent, proposal queue)
15. `/autoimprove proposals` command
16. Phase transition detection

### Phase 3: Research
17. Research phase (researcher agent, report generation)
18. Phase transition orchestration

## Coding Conventions

- This is a Claude Code plugin — follow the [plugin development guide](https://docs.anthropic.com/en/docs/claude-code/plugins)
- Skills, agents, and commands are Markdown files with YAML frontmatter
- No runtime dependencies beyond Claude Code's built-in tools
- Shell scripts for gates/benchmarks are executed via Bash tool
- Git worktrees managed via `git worktree add/remove` commands
- All state in flat files (`experiments.tsv`, `context.json`, `epoch-baseline.json`) — no databases

## Testing Strategy

- The plugin itself should be testable via `/autoimprove run` on a sample project
- Create a `test-project/` directory with a minimal Node.js or Python project that has:
  - A test suite (some passing, some failing)
  - A benchmark script that outputs JSON metrics
  - Known TODOs and lint warnings for the experimenter to find
- Integration test: run 3 experiments on test-project, verify at least 1 keep and 1 discard

## Related Projects

- **autoresearch** (`~/Developer/autoresearch`): The inspiration. Study `program.md` and `train.py` for the mental model.
- **lossless-claude** (`~/Developer/lossless-claude`): First real target project. Has 79 tests, dogfood suite, compression benchmarks.
- **xgh** (`~/Developer/xgh`): Second target project. Has 43 bash tests, context tree scoring, provider validation.
