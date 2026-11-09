#!/usr/bin/env bash
# Launch one headless Claude Code run per TRIAGE row, each in its own worktree.
#
#   scripts/swarm.sh R-01 R-02 B-03
#   scripts/swarm.sh --dry-run R-05            # print prompt, launch nothing
#   SWARM_PERMISSION_FLAGS="--permission-mode acceptEdits" scripts/swarm.sh R-01
#
# Worktrees: ../runthru-wt/<ID> on branch swarm/<ID>. Logs: .swarm/<ID>.log.
# Nothing is pushed. Merge lanes by hand in the order given in doc/release/SWARM.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BOARD="doc/release/TRIAGE.md"
WT_ROOT="${SWARM_WORKTREE_ROOT:-$ROOT/../runthru-wt}"
PERM="${SWARM_PERMISSION_FLAGS:---permission-mode acceptEdits}"
MODEL="${SWARM_MODEL:-}"
DRY=0
[ "${1:-}" = "--help" ] && { sed -n '2,10p' "$0"; exit 0; }
[ "${1:-}" = "--dry-run" ] && { DRY=1; shift; }
[ $# -eq 0 ] && { echo "usage: $0 [--dry-run] ROW_ID [ROW_ID...]"; exit 2; }
command -v claude >/dev/null || { echo "claude CLI not on PATH"; exit 1; }
mkdir -p .swarm "$WT_ROOT"

for ID in "$@"; do
  ROW=$(grep -E "^\| $ID \|" "$BOARD" || true)
  [ -z "$ROW" ] && { echo "$ID: not found in $BOARD"; continue; }
  STATUS=$(echo "$ROW" | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')
  [ "$STATUS" != "todo" ] && { echo "$ID: status is '$STATUS', skipping"; continue; }

  WT="$WT_ROOT/$ID"
  PROMPT=$(cat <<EOF
You are the triage-fixer agent for RunThru. Work exactly one row of doc/release/TRIAGE.md.

Row: $ROW

Read CLAUDE.md and doc/release/SWARM.md in full before editing anything. Follow the loop in SWARM.md:
claim the row (status in-progress, owner swarm/$ID, commit "[$ID] claim"), read every file in the
row's Files column, make the smallest change that makes the row true, run
scripts/verify_release_readiness.sh until it prints GATE: PASS, commit "[$ID] <what changed>",
set the row to done with the short commit hash in Verify, commit that. Never push. Never add a
dependency. If blocked, set the row to blocked with a one-line reason and stop.
Finish with a plain-prose report: what was broken, what changed, the last five lines of the gate.
EOF
)
  if [ $DRY -eq 1 ]; then echo "=== $ID (dry run) ==="; echo "$PROMPT"; echo; continue; fi

  if [ ! -d "$WT" ]; then
    git worktree add "$WT" -b "swarm/$ID" >/dev/null 2>&1 || git worktree add "$WT" "swarm/$ID" >/dev/null
  fi
  echo "$ID: launching in $WT (log .swarm/$ID.log)"
  ( cd "$WT" && claude -p "$PROMPT" $PERM ${MODEL:+--model "$MODEL"} ) >"$ROOT/.swarm/$ID.log" 2>&1 &
done
wait
echo "swarm finished. Review branches with: git log --oneline main..swarm/<ID>"
