#!/bin/bash
# autoimprove-trigger.sh — Poll merged PRs on target repos and trigger /autoimprove run
#
# Intended use: Add to ~/.xgh/ingest.yaml schedule.jobs at cron: "*/10 * * * *"
# Then copy/symlink to ~/.xgh/scripts/autoimprove-trigger.sh
#
# Setup: bash ~/Developer/autoimprove/scripts/autoimprove-trigger.sh --install
#
# Quota protection: never fires more than once per 5 minutes (UNBREAKABLE_RULES §2)
# State file: ~/.xgh/state/autoimprove-last-check.yaml
# Lock file:  ~/.xgh/state/autoimprove-trigger.lock
# Log file:   ~/.xgh/logs/autoimprove-trigger.log

set -euo pipefail

XGH_HOME="${XGH_HOME:-$HOME/.xgh}"
STATE_DIR="$XGH_HOME/state"
STATE_FILE="$STATE_DIR/autoimprove-last-check.yaml"
LOCK_FILE="$STATE_DIR/autoimprove-trigger.lock"
LOG_FILE="$XGH_HOME/logs/autoimprove-trigger.log"
AUTOIMPROVE_LOGS_DIR="${HOME}/.autoimprove/logs"
SIGNAL_SKIP_LOG="${AUTOIMPROVE_LOGS_DIR}/signal-skips.log"
MIN_INTERVAL_SECONDS=300  # 5-minute minimum (UNBREAKABLE_RULES §2 quota protection)

# --- --install mode: copy script to ~/.xgh/scripts/ and add ingest.yaml job ---
if [ "${1:-}" = "--install" ]; then
  SCRIPTS_DIR="$XGH_HOME/scripts"
  mkdir -p "$SCRIPTS_DIR"
  cp "$0" "$SCRIPTS_DIR/autoimprove-trigger.sh"
  chmod +x "$SCRIPTS_DIR/autoimprove-trigger.sh"
  echo "Installed: $SCRIPTS_DIR/autoimprove-trigger.sh"

  # Add to ingest.yaml schedule.jobs via python3
  INGEST="$XGH_HOME/ingest.yaml"
  if [ -f "$INGEST" ]; then
    INGEST_PATH="$INGEST" python3 - <<'PYEOF'
import yaml, os

ingest_path = os.environ['INGEST_PATH']
with open(ingest_path) as f:
    cfg = yaml.safe_load(f) or {}

jobs = cfg.setdefault('schedule', {}).setdefault('jobs', [])
jobs = [j for j in jobs if j.get('name') != 'autoimprove-trigger']
jobs.append({
    'name': 'autoimprove-trigger',
    'cron': '*/10 * * * *',
    'command': '/bin/bash $HOME/.xgh/scripts/autoimprove-trigger.sh --quiet',
    'description': 'Poll merged PRs on claudinho/xgh/lossless-claude, trigger /autoimprove run on new merges',
})
cfg['schedule']['jobs'] = jobs

with open(ingest_path, 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, allow_unicode=True)

print(f'Added autoimprove-trigger to {ingest_path} schedule.jobs (cron: */10 * * * *)')
PYEOF
  else
    echo "WARN: $INGEST not found — add the cron job manually"
  fi
  exit 0
fi

QUIET="${1:-}"

# Create directories if needed
mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")" "$AUTOIMPROVE_LOGS_DIR"

log() {
  local msg="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
  echo "$msg" >> "$LOG_FILE"
  [ "${QUIET:-}" != "--quiet" ] && echo "$msg"
}

signal_skip_log() {
  local reason="$1"
  local msg="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [SIGNAL_SKIP: ${reason}]"
  echo "$msg" >> "$SIGNAL_SKIP_LOG"
  log "SIGNAL_SKIP: ${reason}"
}

# --- Lock guard: prevent concurrent runs ---
if [ -f "$LOCK_FILE" ]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0) ))
  if [ "$LOCK_AGE" -lt 60 ]; then
    log "SKIP: lock held (age: ${LOCK_AGE}s)"
    exit 0
  fi
  log "WARN: stale lock (age: ${LOCK_AGE}s), removing"
  rm -f "$LOCK_FILE"
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# --- Rate guard: enforce minimum interval (UNBREAKABLE_RULES §2) ---
if [ -f "$STATE_FILE" ]; then
  # Pass state file path via environment to avoid single-quote heredoc expansion issue
  LAST_RUN=$(STATE_FILE_PATH="$STATE_FILE" python3 - <<'PYEOF'
import yaml, os
state_file = os.environ['STATE_FILE_PATH']
try:
    with open(state_file) as f:
        d = yaml.safe_load(f) or {}
    print(d.get('last_run_epoch', 0))
except FileNotFoundError:
    print(0)
PYEOF
)
  NOW=$(date +%s)
  ELAPSED=$(( NOW - LAST_RUN ))
  if [ "$ELAPSED" -lt "$MIN_INTERVAL_SECONDS" ]; then
    log "SKIP: last run ${ELAPSED}s ago (minimum: ${MIN_INTERVAL_SECONDS}s)"
    exit 0
  fi
fi

# --- Target repos: "owner/repo LOCAL_PATH" pairs (no associative array — bash 3.2 compat) ---
# Each must have autoimprove.yaml in the local checkout for trigger to fire
REPO_NAMES=(
  "ipedro/claudinho"
  "extreme-go-horse/xgh"
  "lossless-claude/lcm"
)
REPO_PATHS=(
  "$HOME/Developer/claudinho"
  "$HOME/Developer/xgh"
  "$HOME/Developer/lossless-claude"
)

# Collected new SHAs written to a temp file for state persistence
NEW_SHAS_FILE=$(mktemp)
trap 'rm -f "$LOCK_FILE" "$NEW_SHAS_FILE"' EXIT

get_last_sha() {
  local repo="$1"
  STATE_FILE_PATH="$STATE_FILE" REPO_KEY="$repo" python3 - <<'PYEOF'
import yaml, os
state_file = os.environ['STATE_FILE_PATH']
repo = os.environ['REPO_KEY']
try:
    with open(state_file) as f:
        d = yaml.safe_load(f) or {}
    print(d.get('last_merged_sha', {}).get(repo, ''))
except FileNotFoundError:
    print('')
PYEOF
}

# --- Poll and trigger ---
TRIGGERED=0
IDX=0

for REPO in "${REPO_NAMES[@]}"; do
  LOCAL_PATH="${REPO_PATHS[$IDX]}"
  IDX=$(( IDX + 1 ))

  # Require autoimprove.yaml in the local checkout
  if [ ! -f "$LOCAL_PATH/autoimprove.yaml" ]; then
    log "SKIP $REPO: no autoimprove.yaml at $LOCAL_PATH"
    continue
  fi

  # Fetch latest merged PR merge commit SHA
  LATEST_SHA=$(gh pr list --repo "$REPO" --state merged --limit 1 \
    --json mergeCommit --jq '.[0].mergeCommit.oid // ""' 2>/dev/null || echo "")

  if [ -z "$LATEST_SHA" ]; then
    log "SKIP $REPO: no merged PRs found"
    continue
  fi

  # Record SHA for state persistence (one "repo::sha" per line)
  printf '%s::%s\n' "$REPO" "$LATEST_SHA" >> "$NEW_SHAS_FILE"

  LAST_SHA=$(get_last_sha "$REPO")

  if [ "$LATEST_SHA" = "$LAST_SHA" ]; then
    log "OK $REPO: no new merges (sha: ${LATEST_SHA:0:8})"
    continue
  fi

  LAST_SHA_SHORT="${LAST_SHA:0:8}"
  LATEST_SHA_SHORT="${LATEST_SHA:0:8}"
  log "TRIGGER $REPO: new merge (${LAST_SHA_SHORT:-none} -> ${LATEST_SHA_SHORT})"

  # --- xgh metrification: collect signal entry on every merge (autoimprove#7) ---
  IS_XGH=0
  SHOULD_RUN=1
  if echo "$REPO" | grep -q "extreme-go-horse/xgh"; then
    IS_XGH=1

    # Collect xgh metrics: sprint PR count + adversarial findings on latest PR
    SPRINT_PR_COUNT=$(gh pr list --repo "$REPO" --state merged --limit 20 \
      --json number --jq 'length' 2>/dev/null || echo "0")
    FINDINGS=$(gh pr list --repo "$REPO" --state merged --limit 1 \
      --json reviews --jq '.[0].reviews | map(select(.state=="CHANGES_REQUESTED")) | length' \
      2>/dev/null || echo "0")

    # --- Signal validation guards (SP4, issue #8) ---
    # Note: gate flexibility config planned for SP5 (issue #<N>).
    # Validation guards here must be preserved when gate is made configurable.

    SIGNAL_VALID=1

    # Guard 1: PR count must be > 0
    if [ "${SPRINT_PR_COUNT:-0}" -le 0 ] 2>/dev/null; then
      signal_skip_log "empty PR count"
      SIGNAL_VALID=0
    fi

    # Guard 2: Adversarial findings must be parseable (numeric)
    if [ "$SIGNAL_VALID" = "1" ]; then
      if ! echo "${FINDINGS:-}" | grep -qE '^[0-9]+$'; then
        signal_skip_log "parse error"
        SIGNAL_VALID=0
      fi
    fi

    # Write YAML signal entry consumed by /autoimprove run pipeline
    if [ "$SIGNAL_VALID" = "1" ]; then
      SIGNAL_FILE="${STATE_DIR}/xgh-signal-${LATEST_SHA_SHORT}.yaml"
      python3 - <<PYEOF
import yaml, time
signal = {
    'source': 'github',
    'project': 'xgh',
    'repo': '$REPO',
    'merge_sha': '$LATEST_SHA',
    'timestamp_iso': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'tags': ['project:xgh', 'source:github'],
    'metrics': {
        'merged_per_sprint': int('$SPRINT_PR_COUNT' or 0),
        'findings_per_pr': int('$FINDINGS' or 0),
        'coverage_delta': None,
    },
}
with open('$SIGNAL_FILE', 'w') as f:
    yaml.dump(signal, f, default_flow_style=False)
print('Signal written: $SIGNAL_FILE')
PYEOF
      log "SIGNAL xgh: metrics written -> $SIGNAL_FILE"
    fi

    # Enforce 20% allocation gate: only 1 in 5 xgh merges triggers /autoimprove run
    # (signal collection above runs on every merge regardless)
    XGH_TRIGGER_COUNT=$(STATE_FILE_PATH="$STATE_FILE" python3 - <<'PYEOF'
import yaml, os
state_file = os.environ['STATE_FILE_PATH']
try:
    with open(state_file) as f:
        d = yaml.safe_load(f) or {}
    print(d.get('xgh_trigger_count', 0))
except FileNotFoundError:
    print(0)
PYEOF
)
    XGH_TRIGGER_COUNT=$(( XGH_TRIGGER_COUNT + 1 ))
    STATE_FILE_PATH="$STATE_FILE" XGH_COUNT="$XGH_TRIGGER_COUNT" python3 - <<'PYEOF'
import yaml, os
state_file = os.environ['STATE_FILE_PATH']
count = int(os.environ['XGH_COUNT'])
try:
    with open(state_file) as f:
        d = yaml.safe_load(f) or {}
except FileNotFoundError:
    d = {}
d['xgh_trigger_count'] = count
with open(state_file, 'w') as f:
    yaml.dump(d, f, default_flow_style=False)
PYEOF
    if [ $(( XGH_TRIGGER_COUNT % 5 )) -ne 0 ]; then
      log "SKIP xgh /autoimprove run: allocation gate (trigger $XGH_TRIGGER_COUNT/5, signal collected)"
      SHOULD_RUN=0
    fi
  fi

  # Trigger /autoimprove run in the repo directory (detached)
  CLAUDE_CMD=$(command -v claude 2>/dev/null || echo "claude")
  if [ "$SHOULD_RUN" = "1" ]; then
    (
      cd "$LOCAL_PATH" 2>/dev/null || {
        log "ERROR $REPO: cannot cd to $LOCAL_PATH"
        exit 0
      }
      "$CLAUDE_CMD" --print --dangerously-skip-permissions \
        "/autoimprove run" >> "$LOG_FILE" 2>&1
      log "DONE $REPO: autoimprove run completed"
    ) &
  fi

  TRIGGERED=$(( TRIGGERED + 1 ))
done

# --- Persist state (single Python call reads the temp file) ---
STATE_FILE_PATH="$STATE_FILE" NEW_SHAS_FILE="$NEW_SHAS_FILE" python3 - <<'PYEOF'
import yaml, time, os

state_file = os.environ['STATE_FILE_PATH']
new_shas_file = os.environ['NEW_SHAS_FILE']

try:
    with open(state_file) as f:
        state = yaml.safe_load(f) or {}
except FileNotFoundError:
    state = {}

state['last_run_epoch'] = int(time.time())
state['last_run_iso'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
shas = state.setdefault('last_merged_sha', {})

try:
    with open(new_shas_file) as f:
        for line in f:
            line = line.strip()
            if '::' in line:
                repo, sha = line.split('::', 1)
                if repo and sha:
                    shas[repo] = sha
except FileNotFoundError:
    pass

with open(state_file, 'w') as f:
    yaml.dump(state, f, default_flow_style=False)
PYEOF

log "DONE: triggered=$TRIGGERED"
exit 0
