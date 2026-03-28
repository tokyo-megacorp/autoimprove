# Skill Observability Contract

**Version:** 1.0
**Canonical location:** `~/Developer/autoimprove/docs/skill-observability-contract.md`
**Changes require:** adversarial review

---

## Purpose

Every skill in the org MUST include an `observability` block in its SKILL.md frontmatter. This contract defines how autoimprove measures skill quality.

---

## 1. Extended Frontmatter Schema

```yaml
---
name: skill-name
description: "One-line description with trigger phrases"
version: 0.1.0
observability:
  emit: lcm                          # where metrics go: lcm | stdout | both
  tags:                              # standard tags for every invocation
    - "skill:<skill-name>"
    - "type:workflow"                 # workflow | gate | capture | dispatch
  success_criteria:                  # human-readable prose (Phase 1); machine DSL (Phase 2 goal)
    - "lcm_store called with skill tag"
    - "output contains RESULT:"
  metrics:                           # what autoimprove tracks (names only)
    - name: duration_ms
      type: gauge
    - name: items_processed
      type: counter
---
```

### Field Reference

| Field | Required | Values | Description |
|-------|----------|--------|-------------|
| `emit` | Yes | `lcm`, `stdout`, `both` | Where telemetry is sent |
| `tags` | Yes | string array | Must include `skill:<name>` and `type:<type>` |
| `success_criteria` | Yes | string array | Human prose in Phase 1. Machine DSL is a future goal. |
| `metrics` | Yes | array of {name, type} | `gauge` for point-in-time, `counter` for cumulative |

### Skill Types

| Type | Description | Example |
|------|-------------|---------|
| `workflow` | Multi-step procedure | `/triage`, `/factory-mode` |
| `gate` | Pass/fail validation | `/test-gate`, `/merge-gate` |
| `capture` | Record information | `/lcm-capture`, `/tangent-capture` |
| `dispatch` | Orchestrate other skills/agents | `/spawn-teammate` |

---

## 2. Mandatory Output Block

Every skill invocation MUST end with an `lcm_store()` call:

```
lcm_store(
  text: "<skill-name> completed: <1-line result summary>",
  tags: ["skill:<skill-name>", "sprint:<spN>", "type:<workflow|gate|capture>"],
  metadata: { duration_ms: N, success: true|false, items: N }
)
```

### Examples

**Workflow skill (`/triage`):**
```
lcm_store(
  text: "triage completed: 12 issues triaged, 3 batches created, top priority: claudinho#14",
  tags: ["skill:triage", "sprint:sp3", "type:workflow"],
  metadata: { duration_ms: 45000, success: true, items: 12 }
)
```

**Gate skill (`/test-gate`):**
```
lcm_store(
  text: "test-gate completed: 47/47 tests passed in lcm repo",
  tags: ["skill:test-gate", "sprint:sp3", "type:gate"],
  metadata: { duration_ms: 12000, success: true, items: 47 }
)
```

**Gate skill (`/test-gate`) — failure:**
```
lcm_store(
  text: "test-gate completed: 3/47 tests FAILED in lcm repo — blocking commit",
  tags: ["skill:test-gate", "sprint:sp3", "type:gate"],
  metadata: { duration_ms: 12000, success: false, items: 47 }
)
```

**Capture skill (`/tangent-capture`):**
```
lcm_store(
  text: "tangent-capture completed: created issue #42 for Pedro's voice mode idea",
  tags: ["skill:tangent-capture", "sprint:sp3", "type:capture"],
  metadata: { duration_ms: 3000, success: true, items: 1 }
)
```

**Dispatch skill (`/spawn-teammate`):**
```
lcm_store(
  text: "spawn-teammate completed: spawned lcm teammate for issues #12, #15",
  tags: ["skill:spawn-teammate", "sprint:sp3", "type:dispatch"],
  metadata: { duration_ms: 5000, success: true, items: 2 }
)
```

---

## 3. Telemetry Agent Interface

A dedicated `telemetry-agent` handles run lifecycle for skills that produce multi-round output (e.g., adversarial-review). The interface:

### start_run

```
Agent(telemetry-agent, "start_run",
  skill="adversarial-review",
  repo="claudinho",              # defaults to basename($PWD)
  target="diff"                  # human-readable target description
) -> { run_id: "20260328-143022-a3f9c1-diff", run_dir: ".autoimprove/runs/adversarial-review/claudinho/20260328-143022-a3f9c1-diff/" }
```

**Payload schema:**
| Field | Type | Required | Default |
|-------|------|----------|---------|
| `skill` | string | Yes | — |
| `repo` | string | No | `basename($PWD)` |
| `target` | string | Yes | — |

**Returns:** `{ run_id: string, run_dir: string }`

**Error codes:**
| Code | Meaning | Recovery |
|------|---------|----------|
| `DIR_CREATE_FAILED` | Cannot create run directory | Skill proceeds without telemetry |
| `INVALID_SKILL` | Skill name empty or contains path separators | Skill proceeds without telemetry |

**Idempotency:** Each call creates a new run. Run IDs are unique by construction (timestamp + random hex).

### write_round

```
Agent(telemetry-agent, "write_round",
  run_id="20260328-143022-a3f9c1-diff",
  round_data={ round: 1, confirmed: [...], advisory: [...], debunked: [...], converged: false }
)
```

**Payload:** `round_data` is an opaque JSON object — the telemetry agent writes it as `round-N.json` without validation.

**Idempotency:** Writing the same round number overwrites the previous file (last-write-wins).

### finalize_run

```
Agent(telemetry-agent, "finalize_run",
  run_id="20260328-143022-a3f9c1-diff",
  confirmed=2,
  debunked=7,
  advisory=1
)
```

**Payload schema:**
| Field | Type | Required | Default |
|-------|------|----------|---------|
| `run_id` | string | Yes | — |
| `confirmed` | integer | Yes | — |
| `debunked` | integer | Yes | — |
| `advisory` | integer | No | `0` |

> **Note:** `advisory` extends the spec's original two-parameter interface. Added in Phase 0 to capture split/partially-valid findings separately from confirmed findings.

**Side effects:**
1. Writes/updates `run.json` with final summary
2. Updates `meta.json` with `status: "complete"`, `converged_at_round`, severity counts

**Idempotency:** Finalizing an already-finalized run overwrites with new values.

### Error Handling

**All telemetry agent calls are fail-open.** If the agent fails, the calling skill MUST continue execution. Pattern:

```
# Pseudocode — skill wraps telemetry calls
try:
  run = Agent(telemetry-agent, "start_run", ...)
except:
  run = null  # proceed without telemetry

# ... skill does its work ...

if run:
  try:
    Agent(telemetry-agent, "finalize_run", run_id=run.run_id, ...)
  except:
    pass  # telemetry loss is acceptable; skill result is not
```

---

## 4. Run ID Format

Format: `YYYYMMDD-HHMMSS-<6-char-random-hex>-<target-slug>`

Examples:
- `20260328-143022-a3f9c1-diff`
- `20260329-091500-b7e2a4-retrieve-sh`
- `20260328-220306-c1d5f8-claude-md-skills-migration-design`

**Collision prevention:** The 6-character random hex suffix (16^6 = 16.7M possibilities) prevents same-second collisions. Combined with the timestamp, practical collision probability is negligible.

**Target slug:** Derived from the target argument, lowercased, non-alphanumeric replaced with `-`, truncated to 50 chars.

---

## 5. Run Path Structure

```
.autoimprove/runs/
  <skill-name>/
    <repo-name>/
      <run-id>/
        meta.json       <- run metadata (created by start_run)
        round-1.json    <- per-round data (created by write_round)
        round-2.json
        run.json        <- final summary (created by finalize_run)
```

**Location:** Repo-local `./.autoimprove/` directory. Portable — moves with the repo.

**Commit vs gitignore:** User choice. Committing shares telemetry across team. Gitignoring keeps it local. Default: gitignored (autoimprove adds `.autoimprove/` to `.gitignore` on first run).

---

## 6. Source Priority

When skill content conflicts with other sources, resolve using this priority (highest first):

1. `UNBREAKABLE_RULES.md` — hard safety rails, never overridden
2. Global `CLAUDE.md` (`~/.claude/CLAUDE.md`) — behavioral directives
3. Project `CLAUDE.md` (`.claude/CLAUDE.md` in repo) — repo-specific rules
4. Skill-local content (`SKILL.md`) — skill's own instructions

---

## 7. Enforcement Gate (Phase 5 Audit)

For each of the 15 skills in the org:

1. Trigger the skill once (with minimal valid input)
2. Run `lcm_search(tags: ["skill:<skill-name>"])`
3. Verify ≥1 entry returned
4. No entry = skill is broken — fix the `lcm_store()` call

This audit runs at the end of the migration (Phase 5) and should be re-run after any skill modification.
