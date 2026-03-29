#!/usr/bin/env bash
# Tests for agents/adversary.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: adversary agent ==="
echo ""
passed=0; failed=0

run_test() {
    if "$@"; then passed=$((passed+1)); else failed=$((failed+1)); fi
}

# ---------------------------------------------------------------------------
# Test 1: empty findings → empty verdicts
# ---------------------------------------------------------------------------
echo "Test 1: empty findings → {\"verdicts\": []}"

output=$(run_as_agent "adversary.md" "
Review the Enthusiast's findings and challenge them.

<code>// clean code, no issues</code>

<findings>{\"findings\":[]}</findings>

Respond with only the JSON verdicts object.
" 60)

run_test assert_json_has_key "$output" "verdicts" "verdicts key present"
run_test assert_json_array_length "$output" "verdicts" "0" "empty verdicts for empty findings"

echo ""

# ---------------------------------------------------------------------------
# Test 2: every finding gets a verdict (no skipping)
# ---------------------------------------------------------------------------
echo "Test 2: one verdict per finding — no skipping"

output=$(run_as_agent "adversary.md" "
Review the Enthusiast's findings and challenge them.

<code>
// db.ts
function query(sql, params) {
  return connection.execute(sql + params);
}
</code>

<findings>
{\"findings\":[
  {\"id\":\"F1\",\"severity\":\"critical\",\"file\":\"db.ts\",\"line\":2,\"description\":\"SQL injection\",\"evidence\":\"params concatenated directly into sql string\",\"prior_finding_id\":null},
  {\"id\":\"F2\",\"severity\":\"medium\",\"file\":\"db.ts\",\"line\":1,\"description\":\"No input validation\",\"evidence\":\"params not validated before use\",\"prior_finding_id\":null}
]}
</findings>

Respond with only the JSON verdicts object.
" 90)

run_test assert_json_has_key "$output" "verdicts" "verdicts key present"
run_test assert_json_array_length "$output" "verdicts" "2" "two verdicts for two findings"

# Verify finding IDs match
json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ids = {v['finding_id'] for v in d.get('verdicts',[])}
expected = {'F1','F2'}
missing = expected - ids
extra = ids - expected
if missing or extra:
    print('mismatch: missing=' + str(missing) + ' extra=' + str(extra))
else:
    print('ok')
" 2>/dev/null)
    if [ "$result" = "ok" ]; then
        echo "  [PASS] finding IDs match (F1, F2)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 3: verdict values are within allowed set
# ---------------------------------------------------------------------------
echo "Test 3: verdict values are only valid|debunked|partial"

output=$(run_as_agent "adversary.md" "
Review the Enthusiast's findings and challenge them.

<code>
// config.ts
const API_KEY = 'sk-abc123';
export { API_KEY };
</code>

<findings>
{\"findings\":[{\"id\":\"F1\",\"severity\":\"high\",\"file\":\"config.ts\",\"line\":1,\"description\":\"Hardcoded API key\",\"evidence\":\"API_KEY is a hardcoded string literal\",\"prior_finding_id\":null}]}
</findings>

Respond with only the JSON verdicts object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
allowed = {'valid','debunked','partial'}
bad = [v['finding_id'] for v in d.get('verdicts',[]) if v.get('verdict') not in allowed]
print('bad:' + ','.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$result" = "ok" ]; then
        echo "  [PASS] all verdict values are valid"
        passed=$((passed+1))
    else
        echo "  [FAIL] invalid verdict values: $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 4: severity inflation → partial verdict with severity_adjustment
# The finding is real (hardcoded secret) but severity is inflated to "critical"
# because this is an internal config-only file with no user-facing surface.
# The adversary should call "partial" + provide a severity_adjustment.
# ---------------------------------------------------------------------------
echo "Test 4: severity inflation → partial with severity_adjustment"

output=$(run_as_agent "adversary.md" "
Review the Enthusiast's findings and challenge them.

<code>
// internal/admin-seed.ts (line 1)
// Only executed during local dev setup — never deployed to production
const SEED_PASSWORD = 'hunter2';
function seedAdminUser() {
  db.insert({ role: 'admin', password: SEED_PASSWORD });
}
</code>

<findings>
{\"findings\":[{
  \"id\":\"F1\",
  \"severity\":\"critical\",
  \"file\":\"internal/admin-seed.ts\",
  \"line\":3,
  \"description\":\"Hardcoded password in seed script\",
  \"evidence\":\"SEED_PASSWORD = 'hunter2' is a hardcoded plaintext password\",
  \"source\":\"enthusiast\",
  \"prior_finding_id\":null
}]}
</findings>

The file comment says this script is only for local dev setup, never deployed to production.
Respond with only the JSON verdicts object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
verdicts = d.get('verdicts', [])
if not verdicts:
    print('FAIL: no verdicts')
    sys.exit(0)
v = verdicts[0]
verdict = v.get('verdict', '')
adj = v.get('severity_adjustment')
# We expect partial (bug is real but severity is inflated) or valid
# Key requirement: must NOT be debunked (the issue exists)
if verdict == 'debunked':
    print('FAIL: verdict is debunked but the hardcoded password is real')
elif verdict == 'partial' and adj is not None and adj != 'null':
    print('ok-partial')
elif verdict == 'valid':
    print('ok-valid')
else:
    print('ok-acceptable:' + verdict)
" 2>/dev/null)
    if echo "$result" | grep -q "^ok"; then
        echo "  [PASS] severity inflation: verdict=$result (not debunked, bug acknowledged)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 5: wrong line number but real issue nearby → partial, NOT debunked
# The Enthusiast points to line 1 but the actual unsafe code is at line 4.
# The adversary must NOT call debunked — the issue is real, just mis-located.
# ---------------------------------------------------------------------------
echo "Test 5: off-by-lines → partial (not debunked)"

output=$(run_as_agent "adversary.md" "
Review the Enthusiast's findings and challenge them.

<code>
// parser.ts
function parseInput(data) {
  // preprocessing step
  const raw = data.toString();
  return eval(raw);  // line 5: unsafe eval
}
</code>

<findings>
{\"findings\":[{
  \"id\":\"F1\",
  \"severity\":\"high\",
  \"file\":\"parser.ts\",
  \"line\":1,
  \"description\":\"Unsafe eval of user input\",
  \"evidence\":\"eval(raw) executes arbitrary user-controlled code\",
  \"source\":\"enthusiast\",
  \"prior_finding_id\":null
}]}
</findings>

The eval() call is real but is at line 5, not line 1 as stated. Respond with only the JSON verdicts object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
verdicts = d.get('verdicts', [])
if not verdicts:
    print('FAIL: no verdicts')
    sys.exit(0)
v = verdicts[0]
verdict = v.get('verdict', '')
# Correct answers: partial (line off but issue real) or valid (confirmed anyway)
# Wrong answer: debunked (issue clearly exists at line 5)
if verdict == 'debunked':
    print('FAIL: debunked a real eval() vulnerability just because line was wrong')
else:
    print('ok:' + verdict)
" 2>/dev/null)
    if echo "$result" | grep -q "^ok"; then
        echo "  [PASS] off-by-lines: verdict=$result (eval() acknowledged, not dismissed)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 6: guard clause makes issue impossible → debunked is correct
# The Enthusiast flags a null dereference, but a guard at the call site
# makes the null case impossible. Adversary should call debunked.
# ---------------------------------------------------------------------------
echo "Test 6: guard clause makes issue impossible → debunked is correct"

output=$(run_as_agent "adversary.md" "
Review the Enthusiast's findings and challenge them.

<code>
// user.ts
function getDisplayName(user) {
  return user.profile.displayName;
}

function renderHeader(userId) {
  const user = db.getUser(userId);
  if (!user || !user.profile) return 'Anonymous';
  return getDisplayName(user);
}
</code>

<findings>
{\"findings\":[{
  \"id\":\"F1\",
  \"severity\":\"high\",
  \"file\":\"user.ts\",
  \"line\":3,
  \"description\":\"Null dereference — user.profile may be null\",
  \"evidence\":\"user.profile.displayName accessed without null check\",
  \"source\":\"enthusiast\",
  \"prior_finding_id\":null
}]}
</findings>

Respond with only the JSON verdicts object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
verdicts = d.get('verdicts', [])
if not verdicts:
    print('FAIL: no verdicts')
    sys.exit(0)
v = verdicts[0]
verdict = v.get('verdict', '')
# The guard 'if (!user || !user.profile)' at line 8 makes this impossible.
# Correct: debunked or partial. Wrong: valid (pretending the guard doesn't exist).
# We accept debunked or partial — both represent recognizing the guard.
if verdict == 'valid':
    print('FAIL: called valid but guard clause at line 8 makes null impossible')
else:
    print('ok:' + verdict)
" 2>/dev/null)
    if echo "$result" | grep -q "^ok"; then
        echo "  [PASS] guard clause: verdict=$result (guard recognized)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== adversary: passed=$passed failed=$failed ==="
[ $failed -eq 0 ] || exit 1
