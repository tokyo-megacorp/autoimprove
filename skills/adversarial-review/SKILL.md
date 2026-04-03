---
name: adversarial-review
description: "Run an adversarial Enthusiast→Adversary→Judge debate review on code. Automatically converges — no manual round control needed. Use when the user says 'adversarial review', 'debate review', 'run a review round', 'do a review round', 'review code with debate agents', 'i want an adversarial review', or '/autoimprove review'. Do NOT trigger on generic 'review' requests or PR reviews. Takes a file, diff, or PR as target."
argument-hint: "[file|diff] [--map-mode none|map|hybrid]"
allowed-tools: [Read, Glob, Grep, Bash, Agent, TodoWrite, TodoRead]
---

<!-- EXPERIMENTAL FLAG -->
<!-- --map-mode [none|map|hybrid]  (default: none = current full-code behavior) -->
<!-- Experimental flag — for A/B/C benchmarking of context-map approaches. -->
<!-- Mode none: current behavior, full TARGET_CODE passed to every agent every round. -->
<!-- Mode map:  structured map only (function sigs, TODOs, git log) — no raw code. -->
<!-- Mode hybrid: map as index + agents may request specific sections via REQUEST_SECTION. -->

<SKILL-GUARD>
You are NOW executing the adversarial-review skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

# MANDATORY CHAIN: E → A → J

**This chain is not interpretable. Follow each numbered step exactly. No step may be skipped, reordered, or improvised.**

Agents are loaded via `subagent_type` — do NOT inline their prompts or improvise their logic.

---

# STEP 0 — ADAPTIVE MODE DETECTION

Measure target size first. Mode gates max rounds and prompt depth.

- Diff target: `git diff HEAD | wc -l` (or `--staged`).
- File/glob target: count lines via Read/Glob.

| Condition | MODE | MAX_ROUNDS |
|-----------|------|------------|
| Target file has `.md` extension | `FULL` | 10 |
| Single file OR diff ≤ 150 lines | `LIGHTWEIGHT` | 3 |
| Multi-file OR diff > 150 lines | `FULL` | 10 |

**.md override:** If the target is a `.md` file, force `FULL` mode regardless of line count. Design specs generate ~14 findings/round vs ~3 for equivalent code — the line-count heuristic does not apply.

Log: `"[AR] Mode: {MODE} ({N} lines, max_rounds: {MAX_ROUNDS})"`. If `.md` override applied, append `" [spec-mode: .md override]"` to the log line.

---

# STEP 1 — GATHER TARGET CODE

Target is: file path, glob, or `"diff"`.

- File/glob: use Read/Glob, concatenate with `=== {filepath} ===` headers.
- Diff: `git diff HEAD` (fallback: `git diff --staged`). If empty: stop and inform user.

After resolving the target, store `TARGET_PATH` when there is a concrete file path; for diff or ambiguous glob-only targets, leave `TARGET_PATH = null`.

Store as `TARGET_CODE`. If empty: stop — nothing to review.

**After storing `TARGET_CODE`:** Extract the ordered list of file paths from the `=== {filepath} ===` headers and store as `ALL_TARGET_FILES`. For single-file and diff targets this list will have 0 or 1 entries; the file budget only activates when `ALL_TARGET_FILES.length > 1`.

## STEP 1b — Parse --map-mode Flag

Parse the invocation arguments for `--map-mode`:
```
MAP_MODE = argument value of --map-mode, or "none" if flag absent
```

Valid values: `none`, `map`, `hybrid`. If an invalid value is supplied, log a warning and fall back to `none`.

Log: `"[AR] map-mode: {MAP_MODE}"`

## STEP 1c — Generate Map (map and hybrid modes only)

**Skip entirely if `MAP_MODE == "none"`.** Proceed directly to STEP 2.

For each file in `ALL_TARGET_FILES`, generate a `FILE_MAP` entry:

```
For each filepath in ALL_TARGET_FILES:
  lines = content of file (already in TARGET_CODE)
  line_count = total number of lines

  # Signatures / structure
  if filepath ends with .sh or .bash:
    signatures = lines matching regex ^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\s*\) — capture name + line number
  elif filepath ends with .md:
    signatures = lines matching ^## — capture heading text + line number
  else:
    signatures = first 5 lines (as "module header")

  # Markers
  markers = lines containing TODO, FIXME, or HACK — capture line number + text (truncated to 80 chars)

  # Recent git history
  git_log = run: git log --oneline -3 -- {filepath}
            if command fails or no output: git_log = "(no git history)"

  FILE_MAP[filepath] = {
    path: filepath,
    line_count: line_count,
    signatures: [...],   # [{line: N, text: "..."}]
    markers: [...],      # [{line: N, text: "..."}]
    git_log: git_log
  }
```

Combine all `FILE_MAP` entries into `MAP_SUMMARY` — a structured text block:

```
=== MAP SUMMARY ===
<for each file:>
--- {filepath} ({line_count} lines) ---
Signatures:
  L{line}: {text}
  ...
Markers (TODO/FIXME/HACK):
  L{line}: {text}
  ...
Recent changes:
  {git_log}

```

**Token estimation (store for telemetry):**
```
MAP_TOKENS      = len(MAP_SUMMARY) / 3.5   # character-based estimate
FULLCODE_TOKENS = len(TARGET_CODE) / 3.5
TOKEN_RATIO     = MAP_TOKENS / FULLCODE_TOKENS if FULLCODE_TOKENS > 0 else 0.0
```

Log: `"[AR] map-mode token estimate: map={MAP_TOKENS:.0f} / full={FULLCODE_TOKENS:.0f} (ratio={TOKEN_RATIO:.2f})"`

---

# STEP 2 — INITIALIZE RUN

**Generate run ID:** `YYYYMMDD-HHMMSS-<target-slug>` (basename, lowercased, non-alnum → `-`, max 40 chars).

```bash
mkdir -p ~/.autoimprove/runs/<RUN_ID>
```

Store: `RUN_ID`, `RUN_DIR=~/.autoimprove/runs/<RUN_ID>`.

**Write `$RUN_DIR/meta.json`:**
```json
{ "run_id": "<RUN_ID>", "target": "<target>", "date": "<ISO>", "mode": "<MODE>", "rounds_planned": <N>, "rounds_completed": 0, "status": "running" }
```

**Initialize state:**
```
ROUND = 1
ROUNDS = []
CONFIRMED_LOCATIONS = []   # (file, line) tuples from enthusiast/split rulings
PRIOR_JUDGE_OUTPUT = null
PRIOR_JUDGE_SUMMARY = null
ROUND_YIELDS = []
TARGET_TYPE = "code"
CONTEXT_BRIEF = ""
AGENT_ENTHUSIAST = "autoimprove:enthusiast"
AGENT_ADVERSARY = "autoimprove:adversary"
AGENT_JUDGE = "autoimprove:judge"
ROUND_MODEL = "haiku"
MODEL_LADDER = ["haiku", "sonnet", "opus"]
converged = false
FILE_FINDING_COUNTS = {}   # {filepath → confirmed finding count} across all rounds; populated after each Judge ruling
REVIEWED_FILES = Set()     # {filepath} — files sent to the Enthusiast in any prior round (distinct from having findings)
ALL_TARGET_FILES = []      # ordered list of all file paths present in TARGET_CODE (populated in STEP 1)
# Map mode state (set in STEP 1b / 1c)
MAP_MODE = "none"          # "none" | "map" | "hybrid"
MAP_SUMMARY = ""           # structured map block (populated in STEP 1c, empty for MAP_MODE=none)
MAP_TOKENS = 0             # estimated token count of MAP_SUMMARY
FULLCODE_TOKENS = 0        # estimated token count of TARGET_CODE
TOKEN_RATIO = 0.0          # MAP_TOKENS / FULLCODE_TOKENS
INJECTED_SECTIONS = []     # accumulated REQUEST_SECTION snippets for hybrid mode (cleared each round)
```

## Target Type Detection

After resolving `TARGET_PATH`:
- If `TARGET_PATH` ends with `.md` AND (contains a markdown heading `## Implementation Plan`, `## Spec`, `## Design`, or `## Plan` (heading format only, not bare substring) in its first 20 lines OR is explicitly in a `docs/superpowers/` path): set `TARGET_TYPE = "spec"`
- Otherwise: set `TARGET_TYPE = "code"`

```
AGENT_ENTHUSIAST = TARGET_TYPE == "spec" ? "autoimprove:enthusiast-spec" : "autoimprove:enthusiast"
AGENT_ADVERSARY  = TARGET_TYPE == "spec" ? "autoimprove:adversary-spec"  : "autoimprove:adversary"
AGENT_JUDGE      = TARGET_TYPE == "spec" ? "autoimprove:judge-spec"       : "autoimprove:judge"
ROUND_MODEL      = TARGET_TYPE == "spec" ? "sonnet"                       : "haiku"
```

If detection fails or the target is not a concrete markdown spec, keep the default `"code"` behavior.

## Step 2b — Compile Pre-digest Brief (~2KB)

After loading `TARGET_CODE`, compile a brief from the content already in memory and store it as `CONTEXT_BRIEF`.

For `TARGET_TYPE == "code"`:
- List all exported functions/types (first line of each)
- Note imports and dependencies
- Note any `TODO` / `FIXME` comments
- Result target: about 500 tokens

For `TARGET_TYPE == "spec"`:
- Extract all `##` headings (section map)
- Extract the first sentence of each section
- Note any `Phase N`, `Future`, `TODO`, `Will add`, or `will be implemented` planned-work markers
- Result target: about 500 tokens

Do not replace `TARGET_CODE`; this brief is additive and exists only to orient agents before they read the full code/spec.

**Create progress tasks (MANDATORY — do this before dispatching any agent):**

```
TodoWrite([
  {id: "enthusiast", content: "🔍 Enthusiast: find strengths and risks", status: "pending"},
  {id: "adversary",  content: "⚔️ Adversary: challenge all findings",   status: "pending"},
  {id: "judge",      content: "⚖️ Judge: deliver final verdict",         status: "pending"}
])
```

Mark each task `in_progress` immediately before running its agent, and `completed` immediately after. This ensures the E→A→J chain is always visible in the todo list throughout the review.

---

# STEP 3 — DEBATE LOOP

Repeat STEP 3A → 3B → 3C → 3D until `converged = true` or `ROUND > MAX_ROUNDS`.

**ORDERING RULE (non-negotiable):** 3A must fully complete before 3B starts. 3B must fully complete before 3C starts. No parallel dispatch. No skipping.

---

## STEP 3A — ENTHUSIAST (MANDATORY)

**Compliance pre-check:** If `ROUND > MAX_ROUNDS`, exit loop immediately.

Mark todo: `{id: "enthusiast", status: "in_progress"}`.

**Build CONFIRMED_LOCATIONS list** (round > 1 only):
Extract `(file, line)` from all prior rulings where `winner` = `"enthusiast"` or `"split"`. Format: `"src/foo.ts:42, src/bar.ts:17"`.
_(Note: ±5-line dedup tolerance at pre-adversary dedup step may suppress distinct new findings that happen to be near confirmed ones. This is intentional — prefer fewer false duplicates over rare missed nearby findings.)_

**Build RELEVANT_FILES + ACTIVE_CODE (round > 1, multi-file only):**

This applies ONLY when `ROUND > 1` AND `ALL_TARGET_FILES.length > 1`. For R1, single-file, and diff reviews: skip this block entirely, use `TARGET_CODE` as-is.

```
RELEVANT_FILES = files where FILE_FINDING_COUNTS[file] > 0   # at least 1 confirmed finding
              + files where file not in REVIEWED_FILES        # never sent to the Enthusiast yet (regardless of findings)

# Fallback: if RELEVANT_FILES is empty (all files reviewed, none had findings), include all files
if RELEVANT_FILES is empty:
  RELEVANT_FILES = ALL_TARGET_FILES

Log: "[AR] R{ROUND} file budget: {RELEVANT_FILES.length}/{ALL_TARGET_FILES.length} files"

# Build ACTIVE_CODE from TARGET_CODE by extracting only sections for RELEVANT_FILES
# Each section in TARGET_CODE is delimited by "=== {filepath} ===" headers
# Output format: preserve the same "=== {filepath} ===" delimiter for each included file
ACTIVE_CODE = join of TARGET_CODE sections for each file in RELEVANT_FILES (in original order)
REVIEWED_FILES.update(RELEVANT_FILES)   # mark these files as seen by the Enthusiast
```

Use `ACTIVE_CODE` in the Enthusiast prompt below instead of `TARGET_CODE` when file budget is active. For R1, single-file, and diff: `ACTIVE_CODE = TARGET_CODE`.

**Map mode override (applied AFTER file budget logic above):**
```
if MAP_MODE == "map":
  CONTEXT_PAYLOAD = MAP_SUMMARY
  CONTEXT_TAG = "map"
  CONTEXT_NOTE = "You are reviewing a structured map, not full source. Flag findings at signature level. You do NOT have access to implementation details."
elif MAP_MODE == "hybrid":
  # Start with map; inject any requested sections from prior round
  CONTEXT_PAYLOAD = MAP_SUMMARY
  if INJECTED_SECTIONS is not empty:
    CONTEXT_PAYLOAD += "\n\n=== INJECTED SECTIONS (requested from prior round) ===\n" + join(INJECTED_SECTIONS, "\n---\n")
  CONTEXT_TAG = "map+sections"
  CONTEXT_NOTE = "You are reviewing a structured map. To request raw source for a specific range, output a line: REQUEST_SECTION: <filepath>:<start>-<end>"
else:  # MAP_MODE == "none"
  CONTEXT_PAYLOAD = ACTIVE_CODE
  CONTEXT_TAG = "code"
  CONTEXT_NOTE = ""
```

**Dispatch — use EXACTLY this Agent call:**
```
Agent(
  subagent_type: AGENT_ENTHUSIAST,
  model: ROUND_MODEL,
  prompt: "[AR Round {ROUND} — {MODE}] Review the {CONTEXT_TAG} below. Output ONLY valid JSON per your schema.
<brief>{CONTEXT_BRIEF}</brief>
<{CONTEXT_TAG}>{CONTEXT_PAYLOAD}</{CONTEXT_TAG}>
<if CONTEXT_NOTE != "">Note: {CONTEXT_NOTE}</if>
<if round > 1>BLOCKLIST (do not re-raise): {CONFIRMED_LOCATIONS}
Prior summary: {PRIOR_JUDGE_SUMMARY}
Find issues NOT in the blocklist only.</if>"
)
# Note: <if condition>...</if> blocks are conditional inclusions — include the content only when the condition is true, omit otherwise.
```

**Hybrid mode — parse REQUEST_SECTION lines (after receiving Enthusiast output):**
```
if MAP_MODE == "hybrid":
  INJECTED_SECTIONS = []   # reset for this round
  for each line in raw Enthusiast response matching "REQUEST_SECTION: <filepath>:<start>-<end>":
    parse filepath, start_line_str, end_line_str from tag
    start_line = int(start_line_str) if start_line_str is a valid integer else null
    end_line   = int(end_line_str)   if end_line_str   is a valid integer else null
    if start_line is null or end_line is null:
      log: "[AR] WARN: malformed REQUEST_SECTION line numbers"
      skip this tag
    start_line = max(1, start_line)
    end_line   = min(end_line, FILE_MAP[filepath].line_count if available else line_count_of_file(filepath))
    if filepath not in ALL_TARGET_FILES OR start_line > end_line:
      log: "[AR] WARN: invalid REQUEST_SECTION range"
      skip this tag
    snippet = extract lines start_line..end_line from TARGET_CODE section for filepath
    INJECTED_SECTIONS.append("=== {filepath}:{start_line}-{end_line} ===\n{snippet}")
    log: "[AR] hybrid: injected {filepath}:{start_line}-{end_line} ({end_line-start_line+1} lines)"
```

**Validate output (MANDATORY — do not skip):**
1. Parse response as JSON.
2. If invalid JSON → re-prompt once: `"Return only the corrected JSON object — no prose, no fences."` Re-parse.
3. If still invalid → log `enthusiast_malformed_json`, skip 3B and 3C, go to 3D with `findings: []`.
4. If round == 1 and response ≤ 50 chars → re-prompt once: `"Response appears truncated. Return full JSON."` If still ≤ 50 chars → log `enthusiast_sparse_output`, treat as `findings: []`.
5. Store as `ENTHUSIAST_OUTPUT`.

**Pre-adversary dedup:**

**Spec-target skip condition:** If `TARGET_TYPE == "spec"`, skip the pre-adversary dedup pass entirely: set `NOVEL_FINDINGS = ENTHUSIAST_OUTPUT.findings` and log `"[AR] Pre-dedup skipped: spec target (TARGET_TYPE=spec) — Judge handles repetition via blocklist."`. Proceed directly to 3B.

Otherwise (code targets):
- Extract `(file, line)` from each new finding.
- Match against `CONFIRMED_LOCATIONS` where same file AND `|new_line - confirmed_line| <= 5`.
- Split into `NOVEL_FINDINGS` (no match) and `DUPLICATE_FINDINGS` (matched).
- If duplicates exist: log `"Auto-dismissed {N} duplicate(s): {locations}"`.
- Replace `ENTHUSIAST_OUTPUT.findings` with `NOVEL_FINDINGS`.
Mark todo complete: `{id: "enthusiast", content: "🔍 AR Round {ROUND}: Enthusiast ({NOVEL_FINDINGS.length} findings)", status: "completed"}`.

- If `NOVEL_FINDINGS` is empty: skip 3B and 3C, go to 3D (convergence path).

---

## STEP 3B — ADVERSARY (MANDATORY after 3A produces findings)

**Compliance pre-check:** `ENTHUSIAST_OUTPUT` must exist and `NOVEL_FINDINGS.length > 0`. If not, skip to 3D.

Mark todo: `{id: "adversary", content: "⚔️ AR Round {ROUND}: Adversary — challenging {NOVEL_FINDINGS.length} findings", status: "in_progress"}`.

**Map mode payload for Adversary:** Use the same `CONTEXT_PAYLOAD` / `CONTEXT_TAG` / `CONTEXT_NOTE` computed in 3A above (do NOT recompute — reuse values set during 3A). For `MAP_MODE == "none"`, this is `TARGET_CODE`.

**Dispatch — use EXACTLY this Agent call:**
```
Agent(
  subagent_type: AGENT_ADVERSARY,
  model: ROUND_MODEL,
  prompt: "[AR Round {ROUND} — {MODE}] Challenge the findings. Output ONLY valid JSON per your schema.
<brief>{CONTEXT_BRIEF}</brief>
<{CONTEXT_TAG}>{CONTEXT_PAYLOAD}</{CONTEXT_TAG}>
<if CONTEXT_NOTE != "">Note: {CONTEXT_NOTE}</if>
<findings>{ENTHUSIAST_OUTPUT with NOVEL_FINDINGS only}</findings>
Healthy challenge rate: 15–25%. Validating 100% without pushback = insufficient scrutiny."
)
```

**Validate output (MANDATORY):**
1. Parse response as JSON.
2. If invalid → re-prompt once. If still invalid → log `adversary_malformed_json`, use `{"verdicts": []}` (all findings uncontested).
3. Store as `ADVERSARY_OUTPUT`.

**Compliance check:** `ADVERSARY_OUTPUT.verdicts` must contain one entry per finding in `NOVEL_FINDINGS`. If count mismatches: log `"adversary_verdict_count_mismatch: expected {N}, got {M}"` — proceed anyway.

Mark todo: `{id: "adversary", content: "⚔️ AR Round {ROUND}: Adversary ({challenged_count} challenged)", status: "completed"}` where `challenged_count` = verdicts where verdict != "valid".

---

## STEP 3C — JUDGE (MANDATORY after 3B)

**Compliance pre-check:** Both `ENTHUSIAST_OUTPUT` and `ADVERSARY_OUTPUT` must exist. If not, log `judge_skipped_missing_inputs` and go to 3D.

Mark todo: `{id: "judge", content: "⚖️ AR Round {ROUND}: Judge — ruling on debate", status: "in_progress"}`.

**Map mode payload for Judge:** Use the same `CONTEXT_PAYLOAD` / `CONTEXT_TAG` / `CONTEXT_NOTE` computed in 3A above (reuse, do not recompute). For `MAP_MODE == "none"`, this is `TARGET_CODE`.

**Dispatch — use EXACTLY this Agent call:**
```
Agent(
  subagent_type: AGENT_JUDGE,
  model: ROUND_MODEL,
  prompt: "[AR Round {ROUND} — {MODE}] Arbitrate. Output ONLY valid JSON per your schema.
<brief>{CONTEXT_BRIEF}</brief>
<{CONTEXT_TAG}>{CONTEXT_PAYLOAD}</{CONTEXT_TAG}>
<if CONTEXT_NOTE != "">Note: {CONTEXT_NOTE}</if>
<findings>{ENTHUSIAST_OUTPUT}</findings>
<verdicts>{ADVERSARY_OUTPUT}</verdicts>
<if round > 1>Prior rulings: {PRIOR_JUDGE_OUTPUT}
Set convergence:true only if ALL (file,line,winner,final_severity) tuples match prior round.</if>
<if MODE == FULL>Set next_round_model='sonnet' if: security findings, critical/high multi-file, 0% debunk rate, or strong E/A disagreement. Otherwise 'haiku'.</if>"
)
```

**Validate output (MANDATORY):**
1. Parse response as JSON.
2. If invalid → re-prompt once. If still invalid → log `judge_malformed_json`, mark all findings as `status: unresolved`, exit loop.
3. Store as `JUDGE_OUTPUT`.

**Compliance check:** `JUDGE_OUTPUT.rulings` must have one entry per `NOVEL_FINDINGS`. If count mismatches: log `"judge_ruling_count_mismatch: expected {N}, got {M}"`.

**Count results:** `confirmed_count` = rulings where winner ∈ {enthusiast, split}; `debunked_count` = rulings where winner = adversary.

Mark todo: `{id: "judge", content: "⚖️ AR Round {ROUND}: Judge ({confirmed_count} confirmed, {debunked_count} debunked)", status: "completed"}`.

**Update state:**
- Append confirmed `(file, line)` tuples to `CONFIRMED_LOCATIONS`.
- Store `PRIOR_JUDGE_OUTPUT = JUDGE_OUTPUT`.
- Store `PRIOR_JUDGE_SUMMARY = JUDGE_OUTPUT.summary`.
- **Update FILE_FINDING_COUNTS:** For every ruling in `JUDGE_OUTPUT.rulings`, increment `FILE_FINDING_COUNTS[ruling.file]` by 1 for rulings where `winner` ∈ {enthusiast, split}. For rulings where `file` is null or not a recognized path (e.g. diff-mode findings), skip. This ensures the next round's RELEVANT_FILES set reflects which files produced confirmed findings.

**Model escalation (FULL mode only — skip entirely if MODE == LIGHTWEIGHT):**
- Path A (anomaly): if any `*_malformed_json` logged this round → `ROUND_MODEL = "sonnet"`. Set `escalated_this_round = true`.
- Path B (judge recommendation): use `JUDGE_OUTPUT.next_round_model` if not already escalated by Path A (Path A takes priority). Note: `next_round_model` is an undocumented extension to the judge schema; if absent, default to `"haiku"`.
- If `ROUND_MODEL == "sonnet"` for 3+ consecutive rounds: log `"[COST WARNING] Sonnet active 3 consecutive rounds."`

**Write round telemetry** (save agent outputs to temp files, then call the helper):
```bash
# Save agent outputs to temp files
ENTHUSIAST_TMP=$(mktemp /tmp/ar-enthusiast-XXXXXX.json)
ADVERSARY_TMP=$(mktemp /tmp/ar-adversary-XXXXXX.json)
JUDGE_TMP=$(mktemp /tmp/ar-judge-XXXXXX.json)
echo '<ENTHUSIAST_OUTPUT_JSON>' > "$ENTHUSIAST_TMP"
echo '<ADVERSARY_OUTPUT_JSON>'  > "$ADVERSARY_TMP"
echo '<JUDGE_OUTPUT_JSON>'      > "$JUDGE_TMP"

# Write round-N.json and update meta.json incrementally
AR_ROUND_MODEL="<ROUND_MODEL>" \
AR_ROUND_ERRORS='<ERRORS_JSON_ARRAY_OR_EMPTY_ARRAY>' \
bash scripts/ar-write-round.sh "$RUN_DIR" <ROUND> "$ENTHUSIAST_TMP" "$ADVERSARY_TMP" "$JUDGE_TMP"

rm -f "$ENTHUSIAST_TMP" "$ADVERSARY_TMP" "$JUDGE_TMP"
```
(`scripts/ar-write-round.sh` writes `$RUN_DIR/round-{ROUND}.json` and updates `meta.json`.)
Also append the round-N.json contents to the `ROUNDS` array in state.

---

## STEP 3D — CONVERGENCE CHECK

**Append** `NOVEL_FINDINGS.length` to `ROUND_YIELDS`.

**Empty-findings shortcut:** If `NOVEL_FINDINGS.length == 0` this round AND `ROUND > 1` → `converged = true; converged_at_round = ROUND`.
_(Round 1 exception: zero findings on round 1 means nothing was found — exit with empty results. This is not premature convergence. The compliance rule "Round 1 convergence = always false" applies to the Judge's self-report, not to the empty-findings shortcut.)_

**Deterministic check (round > 1, when findings exist):**
- Extract `(file, line, winner, final_severity)` tuples from this round's rulings AND prior round's rulings.
- Apply ±5-line tolerance: normalize each tuple to its cluster's lowest line. Clustering is **pairwise** — two findings are in the same cluster if their lines are within ±5 of each other directly (not transitively). Each cluster's representative is its minimum line number.
- For `file: null` findings: use `(null, first-60-chars-of-resolution, winner, final_severity)`.
- If normalized sets are identical → `converged = true; converged_at_round = ROUND`.
- If Judge reported `convergence: true` but deterministic check says false: log `"Judge convergence overridden by deterministic check."` and continue.
- Round 1 guard: if `ROUND == 1` and Judge returned `convergence: true` → override to `false`. Log: `"convergence: true ignored on round 1."`.

**Near-convergence escalation (FULL mode only — skip this entire block if MODE == LIGHTWEIGHT):**
```
if MODE != "FULL": skip to "Increment" below

current_yield = ROUND_YIELDS[-1]
prev_yield = ROUND_YIELDS[-2] if len >= 2 else null

near_convergence = current_yield <= 2 AND prev_yield != null AND current_yield < prev_yield * 0.4

# Guard: if 3C already escalated this round (escalated_this_round = true), skip near-convergence
# escalation to avoid double-jumping the model tier in a single round.
if NOT escalated_this_round AND (converged OR near_convergence):
  if ROUND_MODEL == "opus": converged = true (final stop)
  else:
    # Guard: if convergence was from deterministic check (not near-convergence), skip escalation.
    # Escalating after true convergence produces a wasted round that re-converges immediately.
    if converged AND NOT near_convergence: skip escalation (stay converged)
    else:
      next_model = MODEL_LADDER[MODEL_LADDER.index(ROUND_MODEL) + 1]
      ROUND_MODEL = next_model
      converged = false
      Log: "Round {N}: escalating to {next_model} (yield={current_yield})"
      Re-emit todos as pending for round {N+1}
```

## Round 2 Gate (after Round 1 only)

After Round 1 Judge output, before incrementing `ROUND`:
- Count confirmed findings: `confirmed_count = rulings where winner ∈ {enthusiast, split}`
- Count medium+ findings: `medium_plus = confirmed findings where final_severity ∈ {medium, high, critical}`

If `confirmed_count < 3` AND `medium_plus == 0`:
- Log: `"round2_skipped: confirmed={confirmed_count}, medium+={medium_plus} — below threshold"`
- Skip to final report: exit the loop and go directly to STEP 4

Otherwise, proceed to Round 2 normally.

Note: This gate applies ONLY after Round 1. Rounds 2+ always proceed if the Judge says not converged.

**Increment:** `ROUND += 1`. ← happens AFTER Round 2 Gate and AFTER loop-decision check; do not increment before the gate.

**Loop decision:** If `converged = true` OR `ROUND > MAX_ROUNDS` → exit loop. Otherwise → go to STEP 3A.

---

# STEP 4 — FORMAT OUTPUT

```
## Debate Review — {target} ({total_rounds} rounds{if converged: ", converged at round N"})
### Confirmed Findings
{For each winner ∈ {enthusiast, split}: - **{severity}** `[{target_type}]` [{file}:{line}] {resolution}}
### Debunked Findings
{For each winner=adversary: - ~~{description}~~ — {adversary reasoning}}
### Unresolved Findings (if judge_malformed_json occurred)
### Summary
{JUDGE_OUTPUT.summary} | {if converged: "Converged at round {converged_at_round}."} | {if errors: "Warning: N round(s) had agent errors."}
```

**Severity calibration note (display only):** For confirmed findings where `target_type == "spec"`, append ` *(spec: high → medium effective)*` after the severity label when `final_severity == "medium"` and the original finding was `high`. This makes the downgrade visible in the output without affecting the stored ruling.

Structured JSON: `{"total_rounds": N, "converged_at_round": converged_at_round, "confirmed": [...], "debunked": [...], "by_severity": {"critical": 0, "high": 0, "medium": 0, "low": 0}}`

**Self-Assessment:**
```
## Self-Assessment
- Mode: [LIGHTWEIGHT|FULL] | Model: [haiku|sonnet|opus]
- Could cheaper model have done this? [1=definitely haiku … 5=this tier essential]
- Reason: [1 sentence]
```

---

# STEP 5 — WRITE TELEMETRY

Non-fatal — skip silently if `RUN_DIR` is unset or any write fails.

- `$RUN_DIR/run.json` — full structured run (all rounds + confirmed + debunked + meta)
- `$RUN_DIR/meta.json` — update with final stats (`status: "complete"`, counts, `by_severity`)
- `$RUN_DIR/report.md` — markdown table of confirmed findings

**Map mode telemetry** — add these fields to `meta.json` and `run.json` (only when `MAP_MODE != "none"`; for `MAP_MODE == "none"` omit or set to null):
```json
{
  "map_mode": "<MAP_MODE>",
  "map_tokens": <MAP_TOKENS>,
  "fullcode_tokens": <FULLCODE_TOKENS>,
  "token_ratio": <TOKEN_RATIO>
}
```

For `MAP_MODE == "hybrid"`, also include:
```json
{
  "hybrid_injections_total": <total REQUEST_SECTION injections across all rounds>
}
```

Print last: `📁 Run saved: ~/.autoimprove/runs/<RUN_ID>/`

## Final Step - Cleanup

Before leaving the execution flow, close all todos explicitly:

```javascript
TodoWrite([
  {id: "enthusiast", content: "✅ AR complete", status: "completed"},
  {id: "adversary",  content: "✅ AR complete", status: "completed"},
  {id: "judge",      content: "✅ AR complete", status: "completed"}
])
```

---

# Map Mode

> **Experimental flag — for A/B/C benchmarking only.** Do not use in production reviews where finding quality is critical until benchmarks validate a mode.

The `--map-mode` flag controls how much source code context is sent to E/A/J agents. Three variants:

## Variant A — `none` (default)

Full `TARGET_CODE` passed to every agent every round. Current behavior, unchanged.

Use when: quality is the primary concern and token cost is secondary.

## Variant B — `map`

Agents receive only a structured map: function signatures, TODO/FIXME markers, and recent git history. No raw implementation code.

Use when: exploring whether high-level structural issues (missing error handling, API surface problems, design smells) can be caught without full source.

Expected token savings: ~80% vs full code.

Quality tradeoff: agents cannot see implementation details. CRITICAL/HIGH findings that require reading logic (off-by-one, null dereference, etc.) will be missed. Best for architecture/API reviews.

## Variant C — `hybrid`

Agents receive the structured map first. After each Enthusiast pass, any `REQUEST_SECTION: <file>:<start>-<end>` lines in the output trigger injection of the actual source snippet into the next agent's prompt.

Use when: you want most of the token savings of map mode but need agents to be able to drill into suspicious areas on demand.

Expected token savings: ~40-60% depending on how many sections are injected. Each injection adds the raw source for that range.

Quality tradeoff: agents may miss issues they didn't know to ask for. Findings in regions that weren't flagged in the map are invisible.

## Telemetry

Every run with `--map-mode map` or `--map-mode hybrid` records in `meta.json`:
- `map_mode`: which variant was used
- `map_tokens`: estimated token count of the map (chars / 3.5)
- `fullcode_tokens`: estimated token count of full code (chars / 3.5)
- `token_ratio`: map_tokens / fullcode_tokens (lower = more savings)

Use `token_ratio` and confirmed finding counts across A/B/C runs on the same target to measure the quality/cost tradeoff.

---

# COMPLIANCE RULES

| Rule | Violation action |
|------|-----------------|
| 3A before 3B | Adversary dispatched without ENTHUSIAST_OUTPUT → abort, re-run from 3A |
| 3B before 3C | Judge dispatched without ADVERSARY_OUTPUT → log error, use `{"verdicts": []}` |
| Each agent uses exact subagent_type | `AGENT_ENTHUSIAST` / `AGENT_ADVERSARY` / `AGENT_JUDGE` (resolved in Step 2a) |
| Output validated before passing forward | Invalid → one re-prompt → fallback (never skip validation) |
| Convergence = deterministic check only | Judge self-report overridden when it disagrees |
| Round 1 convergence = always false | No exception |

**Background execution:** This skill executes E→A→J inline — never re-dispatches itself. Caller wanting non-blocking AR: `Agent(run_in_background: true, prompt: "Invoke Skill('autoimprove:adversarial-review', args: '...')")` — no `subagent_type`.
