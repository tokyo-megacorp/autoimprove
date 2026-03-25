# autoimprove — Telemetry & Observability Reference

APIs and mechanisms available in Claude Code for tracking token usage, costs, timing, and session metadata. This informs how the orchestrator monitors experiments.

## 1. Agent SDK — Per-Turn Token Usage

The `AssistantMessage` includes per-turn `usage` data matching the Anthropic API shape:

```python
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage

total_input = 0
total_output = 0

async for message in query(prompt="...", options=ClaudeAgentOptions()):
    if isinstance(message, AssistantMessage) and message.usage:
        total_input += message.usage['input_tokens']
        total_output += message.usage['output_tokens']
        # Also available: cache_creation_input_tokens, cache_read_input_tokens
```

**Implication for autoimprove:** The orchestrator can track cumulative token usage per experimenter session by summing `AssistantMessage.usage` across turns.

## 2. Agent SDK — Budget Control

```python
ClaudeAgentOptions(
    max_budget_usd=1.50,     # hard cost cap per experiment
    max_turns=20,            # hard turn cap
)
```

**Implication:** `max_budget_usd` directly implements the `budget.max_cost_per_session` config. `max_turns` prevents runaway experiments.

## 3. Agent SDK — Session Metadata

Session ID is available from the init message:

```python
from claude_agent_sdk import query, ClaudeAgentOptions, SystemMessage

async for message in query(prompt="...", options=ClaudeAgentOptions()):
    if isinstance(message, SystemMessage) and message.subtype == "init":
        session_id = message.data.get("session_id")
```

Session history is available programmatically:

```python
from claude_agent_sdk import list_sessions, get_session_messages

sessions = list_sessions()  # sync, returns all past sessions
for s in sessions:
    print(f"{s.session_id}: {s.cwd}")

messages = get_session_messages(session_id="...")  # sync
```

Session mutations for tagging experiments:

```python
from claude_agent_sdk import rename_session, tag_session

rename_session(session_id="...", title="autoimprove-exp-003-test_coverage")
tag_session(session_id="...", tag="experiment")
```

**Implication:** The orchestrator can tag each experimenter session for later retrieval and analysis.

## 4. Agent SDK — Subagent Task Events

Typed message subclasses for tracking subagent (experimenter) progress:

- `TaskStartedMessage` — emitted when the experimenter agent starts
- `TaskProgressMessage` — real-time progress with **cumulative usage metrics**
- `TaskNotificationMessage` — completion notification

**Implication:** The orchestrator gets real-time token usage from the experimenter without waiting for completion. Can implement early termination if budget is exceeded mid-experiment.

## 5. Agent SDK — Rate Limit Events

```python
from claude_agent_sdk import RateLimitEvent

async for message in query(prompt="...", options=ClaudeAgentOptions()):
    if isinstance(message, RateLimitEvent):
        print(f"Status: {message.rate_limit_info.status}")  # allowed, allowed_warning, rejected
        if message.rate_limit_info.resets_at:
            print(f"Resets at: {message.rate_limit_info.resets_at}")
```

**Implication:** The orchestrator can pause the loop when rate-limited instead of burning tokens on retries.

## 6. Hook Events for Observability

Available hook events (usable in plugin hooks):

| Event | When | Use for autoimprove |
|---|---|---|
| `PreToolUse` | Before any tool call | Enforce forbidden_paths, validate constraints |
| `PostToolUse` | After any tool call | Log file changes, track tool usage counts |
| `PostToolUseFailure` | After a tool call fails | Track failure patterns |
| `Stop` | Agent stops | Capture final state |
| `SubagentStop` | Subagent completes | Capture experimenter results |
| `SubagentStart` | Subagent spawns | Log experiment start |
| `SessionStart` | Session begins | Initialize epoch baseline |
| `SessionEnd` | Session ends | Write final report |
| `UserPromptSubmit` | User sends prompt | N/A for autonomous loop |
| `PreCompact` | Before context compaction | Track context pressure |
| `Notification` | System notification | Forward to experiment log |
| `PermissionRequest` | Permission needed | Auto-approve in bypass mode |

Hook callbacks receive `agent_id` and `agent_type` fields, allowing hooks to distinguish orchestrator from experimenter tool calls.

**SDK hook registration:**
```python
from claude_agent_sdk import HookMatcher

hooks = {
    "PostToolUse": [HookMatcher(matcher="Edit|Write", hooks=[log_file_change])],
    "SubagentStop": [HookMatcher(matcher=".*", hooks=[capture_experiment_result])],
    "PreToolUse": [HookMatcher(matcher="Edit|Write", hooks=[enforce_forbidden_paths])],
}
```

## 7. Agent Tool Return Format

When the Agent tool (subagent) completes, the task notification includes:

```
<task-notification>
  <task-id>agent-id</task-id>
  <status>completed</status>
  <result>Agent's final output text</result>
  <usage>
    <total_tokens>19107</total_tokens>
    <tool_uses>1</tool_uses>
    <duration_ms>43080</duration_ms>
  </usage>
</task-notification>
```

**Available metrics from each experiment:**
- `total_tokens` — total token consumption
- `tool_uses` — number of tool calls made
- `duration_ms` — wall clock time

**Implication:** These three numbers go directly into `experiments.tsv` for each experiment.

## 8. Built-in Worktree Support

Claude Code has built-in `EnterWorktree` / `ExitWorktree` tools (available as deferred tools). The Agent tool also supports `isolation: "worktree"` parameter:

```python
# When spawning via Agent tool:
Agent(
    prompt="...",
    isolation="worktree",  # creates isolated git worktree automatically
)
```

The worktree is automatically cleaned up if the agent makes no changes. If changes are made, the worktree path and branch are returned in the result.

**Implication:** Worktree isolation is a first-class primitive. The orchestrator doesn't need to manage `git worktree add/remove` manually — the Agent tool does it.

## 9. CLI Flags for Headless Execution

Claude Code can be invoked programmatically:

```bash
# Print mode (non-interactive, single response)
claude -p "prompt here"
claude --print "prompt here"

# With model selection
claude -p --model claude-sonnet-4-6 "prompt here"

# Output format control
claude -p --output-format json "prompt here"

# Piped input
echo "prompt" | claude -p

# Resume a session
claude --resume <session-id>
```

**Implication:** The orchestrator could use CLI invocation for gates/benchmarks that don't need the full Agent SDK, reducing overhead.

## 10. Permission Modes

```python
ClaudeAgentOptions(
    permission_mode="bypassPermissions"  # for autonomous overnight operation
    # or "acceptEdits" for auto-accept file edits only
)
```

**Implication:** The experimenter must run in `bypassPermissions` or `acceptEdits` mode for autonomous operation. The orchestrator can use hooks (`PreToolUse`) to enforce constraints instead of relying on permission prompts.

## 11. Model Selection Per Agent

```python
ClaudeAgentOptions(
    model="claude-sonnet-4-6"  # experimenter can use cheaper model
)
```

Or via Agent tool:
```python
Agent(
    prompt="...",
    model="sonnet",  # or "opus", "haiku"
)
```

**Implication:** Cost optimization: use Sonnet for experimenters, Haiku for gate-checking, Opus only when needed.

## Summary: What autoimprove Can Track

| Metric | Source | Granularity |
|---|---|---|
| Token usage | `AssistantMessage.usage` / task notification | Per-turn / per-experiment |
| Cost | `max_budget_usd` + token counting | Per-experiment |
| Wall time | Task notification `duration_ms` | Per-experiment |
| Tool calls | Task notification `tool_uses` | Per-experiment |
| Files changed | `PostToolUse` hook on Edit/Write | Per-tool-call |
| Session ID | `SystemMessage` init | Per-session |
| Rate limits | `RateLimitEvent` | Real-time |
| Worktree isolation | `Agent(isolation="worktree")` | Built-in |
| Forbidden path enforcement | `PreToolUse` hook | Per-tool-call |
| Subagent lifecycle | `SubagentStart` / `SubagentStop` hooks | Per-experiment |

## Known Gaps & Mitigations

Identified through adversarial review of the telemetry surface.

### Gap 1: No Per-Metric Raw Data in Experiment Log

The composite score in `experiments.tsv` is a scalar — you can't audit which metrics improved vs regressed, or replay scoring with different weights.

**Fix:** Store full metric breakdown in `experiments/<id>/context.json`:
```json
{
  "metrics": {
    "checks_passed": { "baseline": 37, "candidate": 39, "delta": 0.054, "weight": 3.0 },
    "compression_ratio": { "baseline": 4.2, "candidate": 4.3, "delta": 0.024, "weight": 2.0 }
  },
  "composite_score": 0.847,
  "baseline_composite": 0.832,
  "epoch_composite": 0.832
}
```

### Gap 2: Token Cap Not Directly Enforceable

The SDK has `max_budget_usd` and `max_turns` but no `max_tokens` parameter. Token-to-USD conversion varies by model and cache hits.

**Mitigation:** Use `max_budget_usd` as the hard enforcement. The `max_tokens_per_experiment` config value is soft guidance — the orchestrator converts it to an approximate USD cap at session start based on the selected model's pricing.

### Gap 3: Crash Recovery / Orphaned Worktrees

If the orchestrator or experimenter crashes, `SubagentStop` may not fire. Worktrees leak, budget accounting is corrupted, `experiments.tsv` entry is missing.

**Fix:** Recovery protocol on session start:
1. Scan for orphaned `autoimprove/*` git branches
2. Check for incomplete entries in `experiments.tsv` (started but no verdict)
3. Clean up any leaked worktrees
4. Recalculate budget from logged entries
5. Write a per-experiment heartbeat file (`experiments/<id>/heartbeat`) updated every 30s — if stale on restart, the experiment crashed

### Gap 4: Aspirational APIs Need Verification

`TaskProgressMessage` cumulative usage, `RateLimitEvent.resets_at`, and exact `HookMatcher` regex syntax need testing during implementation.

**Mitigation:** Implementation Phase 1 should include a "telemetry smoke test" that verifies each API actually returns the expected data shape before building the full orchestrator on top of it.

### Gap 5: Orchestrator Token Overhead Not Attributed

The orchestrator's own turns (reading config, running gates, computing scores) consume tokens not attributed to any experiment. The `max_cost_per_session` is understated.

**Fix:** Track orchestrator tokens separately. The session-level `AssistantMessage.usage` accumulation includes both orchestrator and experimenter turns. Subtract experimenter totals (from task notifications) to get orchestrator overhead. Report both in the morning report.

### Gap 6: Per-Experiment Wall-Clock Timeout

`max_turns` caps turns, not time. A slow test suite could make each turn take minutes.

**Mitigation:** The orchestrator can implement its own wall-clock watchdog: start a timer when the experimenter launches, kill the agent if it exceeds `budget.max_time_per_experiment`. The Agent SDK supports `client.interrupt()` for this purpose.
