# Competitive Threat Assessment: uditgoenka/autoresearch (v1.9.0)

**Date:** 2026-04-03
**Author:** Claude (research agent)
**Issue:** tokyo-megacorp/claudinho#219
**Subject:** https://github.com/uditgoenka/autoresearch — 3K stars, v1.9.0

---

## 1. Architecture Comparison

| Dimension | uditgoenka/autoresearch | autoimprove |
|---|---|---|
| **Loop design** | Single-agent: reads, changes, verifies, keeps/reverts | Two-agent: Orchestrator (scoring) + Experimenter (blind to metrics) |
| **Rollback** | `git revert` — failed experiments stay in history | `git worktree` delete — failed candidates never touch main |
| **Metrics** | One human-defined metric + optional Guard command | Composite weighted score; dual baseline (epoch + rolling) |
| **Orchestration** | Stateless single session | Stateful: `experiments.tsv`, `context.json`, trust ratchet |
| **Isolation** | None — changes in working tree | Full worktree; state hashing before/after |
| **Scope control** | Human specifies globs; Guard files off-limits | Trust ratchet Tier 0–3; forbidden_paths; additive-only tests |
| **Phase model** | Flat: one loop with commands (`:plan`, `:ship`, `:reason`) | Three phases: Grind → Propose → Research |
| **Session memory** | git log | `experiments.tsv` + per-experiment `context.json` |
| **Goodhart defense** | None — agent knows the metric it optimizes | Experimenter blind to benchmark definitions and scores |

---

## 2. Differentiation — What autoimprove Does Better

- **Worktree isolation.** autoresearch candidates mutate the working tree and leave revert noise in git history. autoimprove candidates live in disposable worktrees; main is never touched until a keep.

- **Goodhart defense.** Single-agent designs let the optimizer know the exact metric — drift is predictable. The two-agent split removes the scoring gradient from the agent making changes.

- **Compound safety.** Dual baseline prevents cumulative drift. Epoch halt (>5% drift) stops a session before it erodes the baseline invisibly. autoresearch has no equivalent.

- **Trust ratchet + phase intelligence.** Scope earns through demonstrated success. Stagnation triggers Propose and Research phases. autoresearch exits when the user interrupts.

---

## 3. Integration Opportunity

autoresearch's `:reason` adversarial judge panel maps directly to autoimprove's Research phase and solves the v2 LLM-as-judge problem autoimprove deferred. Its `:plan` wizard offers a polished goal-to-config UX that `autoimprove init` currently lacks. The two systems compose cleanly: autoimprove owns keep/discard decisions while autoresearch skills handle specialized investigation.

---

## 4. Verdict — Complement, Not Threat

**Not a threat.** autoresearch targets a different segment: anyone with a measurable goal, no infrastructure needed, single session. autoimprove targets sustained campaigns with safety guarantees, audit trails, and scope escalation.

**A complement.** autoresearch's specialized commands (`:debug`, `:fix`, `:ship`, `:security`) fill gaps autoimprove doesn't address. Both share Karpathy's mental model and can be chained.

**Recommended action:** Track `:reason`'s blind-judge pattern — if autoimprove adds soft-quality scoring, that architecture is the right starting point.
