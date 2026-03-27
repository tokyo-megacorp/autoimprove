# Approach C -- Adversary Review, Round 4

3x penalty for wrong debunks. These are runtime failure modes against the actual implemented code. I have read evaluate.sh, SKILL.md, loop.md, DESIGN.md, the experimenter agent, and autoimprove.yaml.

---

## Finding 1: Command injection via eval in extract_metric

**VALID. Severity: HIGH.**

I want to debunk this because the extract patterns come from `autoimprove.yaml`, which is human-authored and in `forbidden_paths`. The experimenter cannot modify it. So the attack vector as stated -- "experimenter modifies code so benchmark output contains shell metacharacters" -- requires a subtler path than described. But the vulnerability is still real, and the Enthusiast's core point survives.

Here is the actual code (evaluate.sh lines 96-107):

```bash
extract_metric() {
  local pattern="$1"
  local output="$2"
  if [[ "$pattern" == json:* ]]; then
    local jq_path="${pattern#json:}"
    echo "$output" | jq -r "$jq_path" 2>/dev/null
  else
    echo "$output" | eval "$pattern" 2>/dev/null
  fi
}
```

The `pattern` is safe (from config). But `output` is `bench_output`, which is the stdout of the benchmark command run inside the worktree. If the experimenter modifies source code such that the benchmark produces output containing shell metacharacters, and the extract pattern uses the non-json path (e.g., `grep -oP`), then `eval` processes the output as shell. In practice: `echo "$output" | eval "grep -oP '\\d+'"` is safe because the output flows through stdin to grep. The eval executes the pattern, not the output. The output is piped, not interpolated into the eval string.

Wait -- actually, re-reading carefully: `echo "$output" | eval "$pattern"` means `eval` executes `$pattern` as a command, and the output of `echo` is piped to it via stdin. The `$output` is never injected into the eval'd string. It is piped. This is not command injection.

However, there IS a real secondary risk: the `bench_cmd` itself on line 125 is `eval "$bench_cmd"`. If the benchmark command is something like `bash benchmark/metrics.sh` and the experimenter modifies `benchmark/metrics.sh`... except `benchmark/**` is in `forbidden_paths` in the test-project config, and DESIGN.md lists `test/benchmarks/**` and `test/fixtures/**`. But `forbidden_paths` is project-specific config, not a system guarantee. A project could omit benchmark scripts from `forbidden_paths`. The benchmark command is run in the worktree, so a malicious experimenter change to any file the benchmark sources could alter behavior.

But this is not what the finding claims. The finding specifically claims `eval "$pattern"` on benchmark output is the injection vector, which is wrong -- the output is piped to stdin, not interpolated. The broader benchmark-command-in-worktree concern is valid but is a different finding.

**Revised verdict: PARTIALLY VALID. Severity: MEDIUM.**

The specific `eval "$pattern"` injection claim is wrong -- `echo "$output" | eval "$pattern"` pipes output to stdin of the eval'd command, it does not interpolate output into the eval string. However, the non-json extraction path IS fragile and should be restricted to well-known patterns. The proposed fix (restrict to json: and grep -oP only) is reasonable defense-in-depth even though the stated attack vector is incorrect.

---

## Finding 2: Benchmark commands have no timeout

**VALID. Severity: MEDIUM.**

The code at evaluate.sh line 125:
```bash
bench_output=$(eval "$bench_cmd" 2>/dev/null)
```

And gate commands at line 60:
```bash
eval "$cmd" >/dev/null 2>&1
```

Neither is wrapped in `timeout`. The Enthusiast correctly notes that `max_time_per_experiment` in the budget covers the experimenter agent session, not the orchestrator's own benchmark execution. The orchestrator runs evaluate.sh synchronously after the experimenter returns. If a benchmark hangs, the entire Claude Code session stalls.

I considered debunking on the grounds that Claude Code itself has session timeouts. But Claude Code's Bash tool has a 2-minute default timeout (120000ms, max 600000ms). So there IS an implicit timeout from the Bash tool infrastructure. However: (a) the skill does not set this explicitly, (b) the default 2 minutes may be too short for legitimate benchmarks or too long for hangs, and (c) relying on the Bash tool's timeout is implicit infrastructure, not explicit design.

The fix is trivial: `timeout ${BENCH_TIMEOUT:-120} eval "$bench_cmd"`. Valid finding.

---

## Finding 3: Rolling baseline update runs AFTER merge, but worktree is already removed

**DEBUNKED. Severity: N/A.**

The Enthusiast claims: "post-merge benchmark produces different results (non-determinism), rolling baseline is corrupted and the merge can't be undone without git reset."

Look at the actual keep flow in loop.md step 3i:

```
1. Rebase onto main
2. git worktree remove <worktree_path>
3. git merge --ff-only <branch_name>
4. git tag "exp-<experiment_id>" HEAD
5. Update rolling baseline -- run evaluate.sh init mode on the new main
```

The rolling baseline update runs on `main` after the merge. The worktree IS removed, but the code is now ON main. evaluate.sh runs in the project root against the merged code. There is no need for the worktree.

The "non-determinism corrupts the baseline" concern: if the benchmark is non-deterministic, then the baseline was ALSO non-deterministic when it was first captured (step 2c). This is a general "non-deterministic benchmarks cause problems" concern, not specific to the post-merge ordering. Running the baseline update before or after worktree removal changes nothing -- the code is the same either way (it is on main after the ff-merge).

The "merge can't be undone" concern: this is what `git tag "exp-<experiment_id>"` is for. You can always `git revert HEAD` or `git reset --hard HEAD~1`. The tag provides a reference point. This is no different from any git merge -- if you discover a problem later, you revert.

At 3x penalty I am confident: the ordering concern is based on a misunderstanding that the baseline-update benchmark needs the worktree. It does not. It runs on main.

---

## Finding 4: Concurrent sessions have no mutual exclusion

**VALID. Severity: MEDIUM.**

Two simultaneous `/autoimprove run` sessions would:
1. Create conflicting worktrees (potentially with same branch names if themes collide)
2. Both append to `experiments.tsv` without coordination (interleaved rows, corrupted TSV)
3. Both read/write `rolling-baseline.json` and `state.json` non-atomically
4. Both create worktrees from the same main HEAD, then both try to ff-merge -- second merge fails or creates a race

The crash recovery in step 2f partially mitigates this -- a second session would detect orphan worktrees from the first. But crash recovery runs at session START, not during the session. Two concurrent sessions that start simultaneously would not protect each other.

I considered debunking on the grounds that Claude Code is inherently single-session (one terminal, one conversation). But this is not guaranteed -- a user could open two terminals and run `/autoimprove run` in both. The design has no mechanism to prevent or detect this.

The fix (lockfile, e.g. `experiments/.lock` with PID, checked at session start and periodically) is straightforward. Valid finding.

---

## Finding 5: experiments.tsv commit_msg can contain tabs, corrupting TSV

**VALID. Severity: MEDIUM.**

The experimenter is instructed (experimenter.md line 40): "Make exactly one commit with a clear message. Format: `<theme>: <what you did and why>`". Nothing prevents tabs in commit messages. Git allows tabs in commit messages. The TSV format uses tabs as delimiters.

Look at loop.md step 3j:
```
<id>	<ISO timestamp>	<theme>	<verdict>	<improved or ->	<regressed or ->	<tokens or 0>	<wall_time>	<commit_msg or ->
```

`commit_msg` is the last field, which partially mitigates the issue (a tab in the last field creates an extra column but does not shift other fields). However, any TSV parser that splits on tabs would see an extra column. And if the data is loaded into a spreadsheet or processed by `cut -f9`, extra tabs break the extraction.

The git log format used to extract the commit message (loop.md step 3g): `git log -1 --format=%s`. The `%s` format returns only the subject line (first line), which reduces the tab risk but does not eliminate it.

The fix options are all trivial: (a) `tr '\t' ' '` on the commit message, (b) use a different delimiter (unit separator `\x1f`), or (c) quote/escape per RFC 4180. Option (a) is simplest and loses nothing. Valid finding.

---

## Summary

| # | Finding | Verdict | Severity |
|---|---------|---------|----------|
| 1 | Command injection via eval | **PARTIALLY VALID** | MEDIUM (from HIGH) |
| 2 | No benchmark timeout | **VALID** | MEDIUM |
| 3 | Rolling baseline after worktree removal | **DEBUNKED** | N/A |
| 4 | No concurrent session mutex | **VALID** | MEDIUM |
| 5 | Tab corruption in TSV | **VALID** | MEDIUM |

**Score: 3 VALID, 1 PARTIALLY VALID, 1 DEBUNKED.**

Finding 1 is downgraded because the specific attack vector (eval injects benchmark output) is technically wrong -- `echo | eval` pipes to stdin, not into the eval string. The broader concern about the non-json extraction path is valid but at reduced severity. Finding 3 is debunked because the baseline update runs on main after the merge; it does not need the worktree. Findings 2, 4, and 5 are straightforward, real, and easy to fix.
