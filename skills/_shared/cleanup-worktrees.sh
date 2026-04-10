#!/bin/bash
# cleanup-worktrees.sh — Idempotent sweep of stale experiment worktrees and branches.
#
# Removes worktrees and branches matching autoimprove experiment patterns, while
# refusing to touch anything that is (a) checked out in a live worktree, (b) tagged
# as a kept experiment (exp-*), or (c) referenced by an in-flight experiment's
# context.json (verdict still null).
#
# Covers two branch namespaces:
#   - autoimprove/*      — experimenter branches created by the run skill
#   - worktree-agent-*   — branches created by Claude Code's Agent(isolation:"worktree")
#
# Usage:
#   scripts/cleanup-worktrees.sh [--dry-run] [--verbose]
#
# Exit 0 always (idempotent — absence of orphans is not an error).
# Output on stdout: one line per action (deleted/would-delete/skipped).
# Summary line at the end: "[cleanup] N worktrees, M branches removed"

set -uo pipefail

DRY_RUN=0
VERBOSE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --verbose) VERBOSE=1 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "[cleanup] unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

log() { [ $VERBOSE -eq 1 ] && echo "[cleanup] $*" >&2; return 0; }
act() {
  local kind="$1" target="$2"
  if [ $DRY_RUN -eq 1 ]; then
    echo "would-delete: $kind $target"
  else
    echo "deleted: $kind $target"
  fi
}

PATTERN='^(autoimprove/|worktree-agent-)'

# Guard A — collect branches currently checked out in any worktree. Never delete.
LIVE_BRANCHES=$(git worktree list --porcelain 2>/dev/null \
  | awk '/^branch /{sub("refs/heads/","",$2); print $2}')

# Guard C — collect in-flight experiment IDs (context.json with no terminal verdict).
# The find/jq pipeline is best-effort: missing experiments/ or missing jq is tolerated.
IN_FLIGHT_IDS=""
if command -v jq >/dev/null 2>&1 && [ -d experiments ]; then
  IN_FLIGHT_IDS=$(find experiments -maxdepth 2 -name context.json 2>/dev/null \
    | while read -r f; do
        jq -r 'select(.verdict == null or .verdict == "") | .id // empty' "$f" 2>/dev/null
      done)
fi
log "in-flight ids: ${IN_FLIGHT_IDS:-none}"

# --- Phase 1: remove orphan worktrees on disk -------------------------------
# A worktree is an orphan if its path matches the pattern and its branch is not
# protected. We remove the worktree first (frees the branch), then branch cleanup
# in phase 2 will pick up the now-unlocked branch.

WT_REMOVED=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  # porcelain format: "worktree <path>" / "branch refs/heads/<name>"
  case "$line" in
    "worktree "*) wt_path="${line#worktree }" ;;
    "branch refs/heads/"*)
      wt_branch="${line#branch refs/heads/}"
      # Only consider matching patterns.
      if echo "$wt_branch" | grep -qE "$PATTERN"; then
        # Guard B — tagged exp-* means a kept experiment. Never touch.
        if git tag --points-at "refs/heads/$wt_branch" 2>/dev/null | grep -q '^exp-'; then
          log "skip worktree (tagged): $wt_path ($wt_branch)"
          continue
        fi
        # Guard C — branch name embeds an in-flight experiment id.
        skip=0
        for id in $IN_FLIGHT_IDS; do
          case "$wt_branch" in *"$id"*) skip=1; break ;; esac
        done
        if [ $skip -eq 1 ]; then
          log "skip worktree (in-flight): $wt_path ($wt_branch)"
          continue
        fi
        # Safe to remove.
        if [ $DRY_RUN -eq 0 ]; then
          git worktree remove --force "$wt_path" 2>/dev/null || {
            log "worktree remove failed: $wt_path"
            continue
          }
        fi
        act worktree "$wt_path ($wt_branch)"
        WT_REMOVED=$((WT_REMOVED + 1))
      fi
      ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null)

# Refresh LIVE_BRANCHES after phase 1 so phase 2 doesn't try to delete branches
# whose worktrees we just removed (already gone from the worktree list).
LIVE_BRANCHES=$(git worktree list --porcelain 2>/dev/null \
  | awk '/^branch /{sub("refs/heads/","",$2); print $2}')

# --- Phase 2: delete orphan branches ----------------------------------------

BR_REMOVED=0
CANDIDATES=$(git branch --format='%(refname:short)' 2>/dev/null | grep -E "$PATTERN" || true)

for b in $CANDIDATES; do
  # Guard A — never delete a branch that is still checked out anywhere.
  if echo "$LIVE_BRANCHES" | grep -qx "$b"; then
    log "skip branch (live worktree): $b"
    continue
  fi
  # Guard B — tagged exp-*: kept experiment.
  if git tag --points-at "refs/heads/$b" 2>/dev/null | grep -q '^exp-'; then
    log "skip branch (tagged): $b"
    continue
  fi
  # Guard C — in-flight experiment id embedded in branch name.
  skip=0
  for id in $IN_FLIGHT_IDS; do
    case "$b" in *"$id"*) skip=1; break ;; esac
  done
  if [ $skip -eq 1 ]; then
    log "skip branch (in-flight): $b"
    continue
  fi
  # Delete. Use -D (force) because autoimprove branches are often unmerged by
  # design (regressed/neutral experiments never reach main).
  if [ $DRY_RUN -eq 0 ]; then
    git branch -D "$b" >/dev/null 2>&1 || {
      log "branch delete failed: $b"
      continue
    }
  fi
  act branch "$b"
  BR_REMOVED=$((BR_REMOVED + 1))
done

# --- Phase 3: prune stale worktree admin files ------------------------------
# Covers the case where a worktree directory was removed manually (e.g. rm -rf)
# but git's internal bookkeeping still lists it. Always safe — prune only
# touches entries whose on-disk path is already gone.
if [ $DRY_RUN -eq 0 ]; then
  git worktree prune 2>/dev/null || true
fi

echo "[cleanup] $WT_REMOVED worktrees, $BR_REMOVED branches removed$([ $DRY_RUN -eq 1 ] && echo ' (dry-run)')"
exit 0
