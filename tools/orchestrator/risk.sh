#!/usr/bin/env bash
# risk.sh — rough, deterministic risk reading for one completed task.
#
# Heuristic only (no model call): combines how hard the review was, how big the
# change is, whether tests were added, the task's own size estimate, whether it
# touched sensitive areas, and how much UNTESTED work has piled up this session.
#
# Usage: risk.sh <RUN_DIR> <TASK> <UNTESTED_DEBT_COUNT>
# Output: first line "BUCKET<TAB>SCORE", then a human-readable breakdown.
set -euo pipefail
RUN_DIR="$1"; TASK="$2"; DEBT="${3:-0}"

verdict="FAIL"; rounds=0
[ -f "$RUN_DIR/summary.env" ] && . "$RUN_DIR/summary.env" && verdict="${VERDICT:-FAIL}" && rounds="${ROUNDS:-0}"

# Diff vs HEAD = the task's changes (assumes a clean base; see README isolation note).
files="$(git diff HEAD --numstat 2>/dev/null | wc -l | tr -d ' ')"
lines="$(git diff HEAD --numstat 2>/dev/null | awk '{a+=$1+$2} END{print a+0}')"
testfiles="$(git diff HEAD --name-only 2>/dev/null | grep -c '_test\.dart' || true)"
sensitive="$(git diff HEAD 2>/dev/null | grep -icE 'token|secret|credential|oauth|password|secure.?storage|appauth' || true)"
size="$(grep -oE 'Estimated size: [A-Z/]+' "$RUN_DIR/task.md" 2>/dev/null | head -1 | awk '{print $NF}')"

score=0; why=()
add() { score=$((score+$1)); why+=("  +$1  $2"); }

[ "$rounds" -ge 1 ] && add $((rounds*15)) "$rounds remediation round(s)"
[ "$verdict" != "PASS" ] && add 25 "review did NOT converge to PASS"
if   [ "$files" -gt 15 ]; then add 20 "$files files changed (large surface)";
elif [ "$files" -gt 6 ];  then add 10 "$files files changed"; fi
if   [ "$lines" -gt 400 ]; then add 20 "$lines lines changed (large)";
elif [ "$lines" -gt 120 ]; then add 10 "$lines lines changed"; fi
[ "${testfiles:-0}" -eq 0 ] && add 15 "no *_test.dart touched (unverified)"
[ "${sensitive:-0}" -gt 0 ] && add 15 "touches auth/token/secure-storage surface"
case "$size" in
  *L*) add 15 "task self-estimated L";;
  *M*) add 8  "task self-estimated M";;
  *S*) add 3  "task self-estimated S";;
esac
[ "$DEBT" -gt 0 ] && add $((DEBT*8)) "$DEBT untested task(s) already queued this session"

bucket="LOW"
[ "$score" -ge 30 ] && bucket="MEDIUM"
[ "$score" -ge 60 ] && bucket="HIGH"

printf '%s\t%s\n' "$bucket" "$score"
echo "Risk: $bucket (score $score) — $TASK"
printf '%s\n' "${why[@]}"
echo "  facts: verdict=$verdict rounds=$rounds files=$files lines=$lines tests=$testfiles sensitive_hits=$sensitive size=${size:-?} debt=$DEBT"
