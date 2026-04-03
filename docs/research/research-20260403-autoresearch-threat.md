# Competitive Threat Assessment: uditgoenka/autoresearch (v1.9.0)

**Date:** 2026-04-03
**Author:** Claude (research agent)
**Issue:** tokyo-megacorp/claudinho#219
**Subject:** https://github.com/uditgoenka/autoresearch — 3K stars, v1.9.0

---

## 1. Architecture Comparison

| Dimension | uditgoenka/autoresearch | autoimprove |
|---|---|---|
| **Loop design** | Single-agent loop: Claude reads, changes, verifies, reverts or keeps — all in one session | Two-agent: Orchestrator (scoring/gates) + isolated Experimenter (blind to metrics) |
| **Rollback** | `git revert` — failed experiments stay in history with `experiment:` prefix | `git worktree` delete — failed candidates never touch main; no revert noise |
| **Metric approach** | Human-defined mechanical metric (any measurable number) + optional Guard command | Composite weighted score from multiple benchmarks; dual baseline (epoch + rolling) |
| **Orchestration** | Stateless: single Claude session iterates indefinitely | Stateful: `experiments.tsv`, `context.json`, trust ratchet tier, phase transitions |
| **Isolation** | None — changes happen in the working tree; Guard prevents regressions but doesn't isolate | Full worktree isolation; state hashing before/after; `clean_between_experiments` commands |
| **Scope control** | Human specifies files/globs; Guard files are never modified | Trust ratchet (Tier 0–3); forbidden_paths; additive-only test modification |
| **Phase model** | Flat: one loop, many commands (`/autoresearch`, `:plan`, `:ship`, `:debug`, `:fix`, `:reason`) | Three phases: Grind → Propose → Research, with stagnation-triggered transitions |
| **Session memory** | `git log` is the memory; TSV log per session | `experiments.tsv` + per-experiment `context.json` (model SHA, prompt, seed) |
| **Goodhart defense** | None — single agent knows the metric it is optimizing | Experimenter is blind to benchmark definitions, weights, and scores |

---

## 2. Differentiation — What autoimprove Does Better

- **Worktree isolation beats `git revert`.** autoresearch's revert-on-fail leaves noise in git history and touches the main working tree during experiments. autoimprove candidates live in disposable worktrees; main is never mutated until a keep.

- **Goodhart defense.** autoresearch's single agent knows the exact metric and can (intentionally or not) Goodhart it. autoimprove's two-agent split removes the numerical optimization gradient from the agent making changes.

- **Compound safety.** Dual baseline prevents cumulative drift. Epoch drift halt (>5%) stops a session before it erodes the baseline. autoresearch has no equivalent — a session of 100 "keep" iterations could compound small regressions invisibly.

- **Trust ratchet is a differentiator.** Scope earns automatically through demonstrated success. autoresearch has no trust model — the human sets scope once.

- **Phase intelligence.** Stagnation detection, Propose phase, and Research phase give autoimprove structure for long-running campaigns. autoresearch exits when you interrupt or hit N iterations.

- **Reproducibility.** `context.json` per experiment captures model version, SHA, and prompt for replay. autoresearch's only record is the git log.

---

## 3. Integration Opportunity

autoresearch's `:plan` wizard is a polished goal-to-config UX that autoimprove currently lacks in `autoimprove init`. The `/autoresearch:reason` adversarial judge panel maps directly to autoimprove's Research phase — it could be called as a subprocess when autoimprove transitions to Research mode.

Concretely: autoimprove Orchestrator could dispatch to an autoresearch-compatible skill for (a) goal definition/planning (`:plan`), (b) adversarial quality refinement (`:reason`) in Research phase, or (c) security audits (`:security`) as a specialized benchmark. The two systems compose well because autoimprove owns the keep/discard decision while autoresearch skills handle domain-specific investigation.

---

## 4. Verdict — Complement, Not Threat

**Not a threat.** autoresearch targets a different user segment: anyone with a measurable goal, no infrastructure required, walk away and come back. It's a single-agent power tool. autoimprove targets teams running sustained improvement campaigns with provable safety guarantees, audit trails, and scope escalation.

**A complement.** autoresearch's breadth of specialized commands (`:debug`, `:fix`, `:ship`, `:reason`, `:security`) fills gaps autoimprove doesn't address (shipping workflows, adversarial refinement, bug hunting). Both share the same mental model from Karpathy's autoresearch, so they can be chained.

**Recommended action:** Track the `:reason` blind-judge pattern — it solves the v2 LLM-as-judge problem autoimprove deferred. If autoimprove ever adds soft-quality scoring, adopting `:reason`'s cold-start fresh-invocation panel is the right architecture.
