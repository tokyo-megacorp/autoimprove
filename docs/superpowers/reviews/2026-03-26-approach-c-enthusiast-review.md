# Approach C (Parallel Tracks) -- Enthusiast Review

> Reviewer role: The Enthusiast (Bug-finder). Aggressively flags every issue, gap, risk, contradiction, missing piece, and questionable assumption.

---

## Critical

1. **CRITICAL: Three new LLM agents obliterate the "No LLM judge in v1" design principle.** The entire DESIGN.md and adversarial analysis stress that v1 uses deterministic metrics only -- "No LLM Judge in v1" is literally a section heading. The Enthusiast, Adversary, and Judge are all LLM agents making subjective assessments. This is a direct contradiction of the core design philosophy. Either the v1 constraint needs to be formally amended or these agents cannot participate in keep/discard decisions.

2. **CRITICAL: Judge verdict in `review_gate:` creates a non-deterministic gate that breaks evaluate.sh's contract.** evaluate.sh is designed as the single deterministic evaluator (Key Invariant #2: "evaluate.sh is the single evaluator. All verdict computation happens inside it."). Wiring a debate verdict into the loop as a gate means an LLM opinion can veto a change that passes all deterministic checks. This violates the invariant and makes experiment outcomes non-reproducible -- the same code change could get different verdicts on different runs.

3. **CRITICAL: Budget explosion from 3x agent spawning per experiment.** Each experiment already spawns one Experimenter agent. Adding Enthusiast + Adversary + Judge (times N rounds) means a single experiment could spawn 1 + 3N agents. With `--rounds 3` that is 10 agent invocations per experiment. At `max_tokens_per_experiment: 100000`, debate agents alone could consume the entire token budget before benchmarks even run. There is no specification of how debate token costs are budgeted or capped.

4. **CRITICAL: Debate agents break experimenter blindness if wired into the loop.** The Enthusiast and Adversary will analyze the experimenter's diff and produce written reasoning about code quality, potential regressions, and improvement value. If this output feeds back into the orchestrator's keep/discard logic, the experimenter's changes are now being judged by subjective criteria it cannot observe or adapt to -- but worse, the Judge's reasoning will reference metric-adjacent concepts (performance concerns, test coverage opinions) that contaminate the separation of concerns. The design does not specify what the Judge verdict actually *does* in the loop flow.

5. **CRITICAL: No specification of where in the loop flow `review_gate:` executes.** The existing loop has a strict sequence: EXPERIMENT -> HARD GATES -> BENCHMARKS -> SCORING. Where does the debate gate run? Before hard gates (wastes tokens on code that would fail tests)? After scoring (can override a deterministic keep)? Between gates and benchmarks? Each placement has different failure modes and none is specified.

## High

6. **HIGH: GitHub-sourced case studies require network access and external API calls.** Claude Code plugins execute via Bash tool. Fetching real diffs from GitHub requires `curl`/`gh` commands, authentication tokens, and network availability. The design says "no runtime dependencies beyond Claude Code's built-in tools" but GitHub sourcing implies `gh` CLI, rate limiting, and a stored PAT. What happens when GitHub is unreachable during a challenge run?

7. **HIGH: No schema or format specified for challenge answer keys.** "Curated puzzles with planted bugs and answer keys" -- but what format? How does the system compare an agent's finding against the answer key? LLM comparison (violates v1 no-LLM-judge)? Exact string match (too brittle)? Regex (requires careful crafting)? This is the entire scoring mechanism for `/autoimprove challenge` and it is completely unspecified.

8. **HIGH: Multi-round debate has no convergence guarantee or termination condition.** "Configurable via `--review-rounds N`" but what if the Enthusiast and Adversary never converge? Round N could surface new issues that were not in round N-1. The Judge could flip verdicts between rounds. There is no specification of what happens when the Judge disagrees with itself across rounds, or what the final verdict aggregation logic is.

9. **HIGH: Debate agents need file/diff context but agent context passing is unspecified.** The existing experimenter agent receives theme, scope, constraints, and recent history via a structured prompt. The debate agents need the actual diff, surrounding file context, test results, and possibly benchmark output. How is this context assembled? Who constructs the prompt? The orchestrator skill? A new skill? The context budget for passing a full diff + surrounding code to three agents across multiple rounds could be enormous.

10. **HIGH: `/autoimprove review` as a standalone command has no connection to the worktree/scoring system.** If used outside the loop (e.g., on a PR or arbitrary file), there is no baseline, no metrics, no verdict integration. It is essentially a completely separate feature that happens to share a command namespace. The "standalone + loop integration" framing masks the fact that these are two different products with different architectures.

11. **HIGH: Challenge suite results have no defined effect on the system.** `/autoimprove challenge` benchmarks agents against ground truth -- but then what? Does a poor challenge score affect trust tier? Block loop integration? Trigger recalibration? Or is it purely informational? If informational, it is a vanity metric. If actionable, the action is unspecified.

12. **HIGH: The single-pass flow (Enthusiast -> Adversary -> Judge) has an order bias.** The Adversary always sees the Enthusiast's output, creating an anchoring effect. The Judge always sees both, but in a fixed sequence. Literature on LLM debate shows order effects are significant. There is no shuffling, no blind review, no mitigation of this bias.

## Medium

13. **MEDIUM: "review_gate:" in autoimprove.yaml adds a new top-level config section with no schema.** The existing YAML schema has `project`, `budget`, `gates`, `benchmarks`, `themes`, `constraints`, `phases`, `safety`. A new `review_gate:` section needs: round count, pass/fail criteria, which agents to enable, context scope, token budget for debate, and integration point. None of this is defined.

14. **MEDIUM: Challenge suites need curation, versioning, and maintenance.** Planted bugs must be crafted per-language, kept current, and versioned. GitHub case studies need to be vetted for quality and relevance. Who maintains these? How are they updated? This is an ongoing maintenance burden that is presented as a one-time implementation task.

15. **MEDIUM: Three new agent markdown files (enthusiast.md, adversary.md, judge.md) need tool access definitions.** The existing experimenter.md specifies tools: Read, Write, Edit, Glob, Grep, Bash. Debate agents need Read and Grep (to examine code) but probably should NOT have Write, Edit, or Bash (they should not modify code). This tool access matrix is unspecified and getting it wrong could let debate agents accidentally modify the worktree.

16. **MEDIUM: No specification of how debate output is structured or parsed.** The Judge needs to produce a verdict the orchestrator can act on. Is it JSON? A keyword? A score? Free text that the orchestrator LLM-interprets? If JSON, what schema? If free text, how is it parsed deterministically? This is the critical interface between debate and loop and it is undefined.

17. **MEDIUM: Debate agents in the loop multiply the blast radius of LLM failures.** If the Enthusiast hallucinates a bug that does not exist, and the Adversary fails to catch it, and the Judge acts on it -- a perfectly good change gets discarded. Three LLM agents in series means three chances for a hallucination to propagate. The system has no ground truth check for debate claims (unlike the deterministic gates).

18. **MEDIUM: `/autoimprove challenge` result format and storage are unspecified.** Is it TSV like experiments.tsv? JSON? Does it go in the experiments/ directory? How do you compare challenge performance over time? Is there a challenge-baseline equivalent? The entire data model for challenge results is missing.

19. **MEDIUM: Conflict between "standalone agents" and plugin architecture constraints.** The design says agents are "standalone" -- but Claude Code plugin agents are defined in `.claude-plugin/agents/` and invoked by the orchestrator skill or commands. "Standalone" in the plugin model means... a command that spawns them? A skill? How does a user invoke the Adversary agent by itself outside the loop? The invocation mechanism is unspecified.

20. **MEDIUM: The proposal implies the Judge makes binary keep/discard decisions, but the existing scoring system uses a 5-way decision matrix.** The loop has: fail, regress, neutral, keep, halt. The debate Judge produces... what? approve/reject? That maps to keep/discard but loses the nuance of regress vs. neutral vs. fail. Does the Judge need to understand the full decision matrix? That would require scoring knowledge, breaking its independence.

21. **MEDIUM: No fallback behavior when debate agents time out or error.** What if the Adversary agent crashes mid-review? Does the experiment auto-keep (dangerous)? Auto-discard (wasteful)? Retry (budget)? Skip debate and fall through to deterministic scoring (probably correct but unspecified)?

22. **MEDIUM: "Multi-language" code challenges require language-specific parsing and evaluation.** A planted bug in Python looks different from one in Rust or TypeScript. The challenge framework needs language detection, appropriate test harnesses per language, and language-aware answer key comparison. This is a significant implementation scope that is hand-waved as a feature bullet.

## Low

23. **LOW: Command namespace collision risk.** `/autoimprove review` and `/autoimprove challenge` add to an already long command list (run, status, report, history, proposals, init). Tab completion and discoverability suffer. The command surface area is growing without a coherent UX hierarchy.

24. **LOW: `--review-rounds N` default value is unspecified.** "Multi-round as default" -- but what is the default N? 2? 3? 5? Each additional round burns tokens. The default materially affects both cost and quality and it is unstated.

25. **LOW: No specification of whether debate agents share context between rounds.** In round 2, does the Enthusiast see its own round-1 output? The Judge's round-1 verdict? All of round 1? Or does it start fresh? Context sharing strategy dramatically affects behavior and cost, and is unspecified.

26. **LOW: "Curated puzzles" implies a static corpus that agents will memorize.** If the same planted bugs are used repeatedly for `/autoimprove challenge`, LLM agents may learn to pattern-match the specific puzzle format rather than develop genuine bug-finding capability. There is no rotation, randomization, or holdout set described.

27. **LOW: No metric for debate quality itself.** The challenge suite measures agent accuracy, but there is no way to measure whether the debate process (Enthusiast -> Adversary -> Judge) produces better verdicts than a single-agent review. Without this, there is no way to know if the multi-agent overhead is justified.

28. **LOW: The Enthusiast agent persona ("hyper-enthusiastically identify a massive list of both real and questionable issues") is optimized for recall at the expense of precision.** This is fine for standalone review but terrible for a gate -- a high false-positive Enthusiast will cause the Judge to see mostly noise, degrading verdict quality. The persona may need to differ between standalone and loop-integrated modes.

29. **LOW: No consideration of how debate interacts with trust ratchet.** If debate agents are conservative (high false-positive rate for issues), they will increase the discard rate, slowing trust tier escalation. If they are lenient, they add no value. The calibration of debate agent aggressiveness relative to the trust ratchet is unexplored.

30. **LOW: experiments.tsv schema has no column for debate verdict.** If debate is integrated into the loop, the experiment log should record what the debate agents said and whether the Judge agreed with the deterministic scoring. Without this, there is no way to audit debate quality post-hoc.

31. **LOW: No specification of how `/autoimprove review` selects what to review.** "Run debate on any file/diff/PR" -- but the user could point it at a 5000-line diff or an entire directory. There is no scope limiting, chunking strategy, or guidance on what constitutes a reviewable unit.

---

**Summary:** 5 Critical, 7 High, 10 Medium, 9 Low -- 31 total issues identified.

The most fundamental tension is that the proposal introduces LLM-as-judge into a system explicitly designed to avoid it in v1. Issues #1, #2, and #4 are architectural contradictions that need resolution before any implementation begins. The budget implications (#3) could make the feature impractical even if the architectural issues are resolved.
