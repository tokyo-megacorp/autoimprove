# Scout Report: ruflo (claude-flow v3.5) — Fault Tolerance + Specialized Agents

**Date:** 2026-04-03  
**Issue:** #97  
**Scope:** ruvnet/ruflo — 5,900+ commits, 60+ agents, TypeScript CLI

---

## 1. Fault-Tolerant Consensus

### What ruflo does

Ruflo's `hive-mind` command implements **Queen-led Byzantine fault-tolerant consensus** with four selectable consensus algorithms:

| Algorithm | Fault model | Tolerance |
|-----------|-------------|-----------|
| `byzantine` | BFT (arbitrary failures) | f < n/3 faulty |
| `raft` | Crash failures (default) | f < n/2 |
| `gossip` | Eventual consistency | partition-tolerant |
| `crdt` | Conflict-free merge | split-brain safe |

`SwarmCoordinator.reachConsensus()` collects votes and applies a >50% majority gate; BFT variants are higher-level policies around this. Agent health is tracked via `AgentMetrics { health, successRate, tasksFailed }` — failed tasks go unassigned with no built-in retry.

**Key finding:** BFT applies to swarm-voting scenarios (parallel agents vote on a shared decision). The serial chain has no native fault recovery in ruflo either — failures surface as errors to the caller.

### What we could adopt

**Actionable:** Add a **re-dispatch policy** in the AR orchestrator for the malformed-JSON fallback paths that already exist. Currently, when enthusiast/adversary/judge returns invalid JSON, we re-prompt once then fall back to empty output. We could instead re-dispatch to a fresh agent instance before falling back — this mirrors ruflo's "retry with a different worker" pattern without needing full BFT.

**Not applicable:** `raft`/`byzantine` requires parallel agents voting on a shared decision. Our E→A→J is a serial debate with asymmetric roles — majority voting doesn't map.

---

## 2. Specialized Agents Per Domain

### What ruflo does

Ruflo auto-selects a **task-complexity-based swarm template** with specialized roles per domain:

| Code N | Domain | Agents spawned |
|--------|--------|----------------|
| 7 | Performance | coordinator, perf-engineer, coder |
| 9 | Security | coordinator, security-architect, auditor |
| 11 | Memory | coordinator, memory-specialist, perf-engineer |

The agent *type* controls which tasks it `canExecute()`. A `security-architect` agent accepts `security` typed tasks; a `tester` accepts `test` typed tasks. This is **routing by task type**, not prompt specialization — each type has a YAML capability list (`capabilities: [code-review, quality-analysis]`).

**Key finding:** Ruflo's specialization is **agent-routing** (which agent type handles which task category), not prompt tuning. LLM instructions in the YAML configs are sparse — specialization is structural, not behavioral.

### What we could adopt

**Actionable:** Our `enthusiast-spec` / `adversary-spec` / `judge-spec` agent variants already implement this pattern for spec vs code targets. Extend this to a third track: a **security-focused track** where all three agents receive a security-biased system prompt (OWASP top-10 lens, privilege escalation, injection). Triggered when the diff or target contains `auth`, `token`, `crypto`, `password`, or `exec`.

**Not applicable:** Per-language specialization (mobile-dev, ml-developer, etc.) requires task routing infrastructure we don't have — complexity for marginal gain.

---

*Report based on: ruflo v3.5 source at ruvnet/ruflo (main branch, 2026-04-03). SwarmCoordinator.ts, Agent.ts, CLAUDE.md, agents/*.yaml inspected directly via GitHub API.*
