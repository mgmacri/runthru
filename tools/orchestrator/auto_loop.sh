#!/usr/bin/env bash
# auto_loop.sh — full-auto, human-gated multi-task driver.
#
# For each backlog task it runs the full single-task loop (run_loop.sh), then:
#   - computes a rough RISK reading,
#   - appends the task's manual-testing steps to a running ledger,
#   - pushes an APPROVAL request to your phone with "Approve next" / "Hold" buttons,
#   - BLOCKS until you tap one (or a timeout).
# Tap "Approve next" to keep advancing; tap "Hold" when the mounting manual-test
# debt / risk crosses your comfort line. It never pushes to a remote.
#
# Modes:
#   auto_loop.sh                 # real full-auto run, gated between tasks
#   auto_loop.sh --max 3         # stop after 3 tasks regardless of approvals
#   auto_loop.sh --dry-run       # show the task order it WOULD run; no calls
#   auto_loop.sh --demo-gate     # send ONE sample approval (real buttons), no model calls
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/orchestrator.env" ] && source "$SCRIPT_DIR/orchestrator.env"

NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:?set NTFY_TOPIC in orchestrator.env}"
NTFY_CONTROL_TOPIC="${NTFY_CONTROL_TOPIC:-${NTFY_TOPIC}-ctl}"
APPROVAL_TIMEOUT="${APPROVAL_TIMEOUT:-3600}"       # seconds to wait for a tap
APPROVAL_POLL_INTERVAL="${APPROVAL_POLL_INTERVAL:-15}"
GOAL_DOC="${GOAL_DOC:-doc/goals/google-drive-next-milestone-plan.md}"
LEDGER="$SCRIPT_DIR/MANUAL_TESTING_QUEUE.md"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

MAX_TASKS=0; DRY_RUN=0; DEMO=0
while [ $# -gt 0 ]; do case "$1" in
  --max) MAX_TASKS="$2"; shift 2;;
  --dry-run) DRY_RUN=1; shift;;
  --demo-gate) DEMO=1; shift;;
  -h|--help) sed -n '2,20p' "$0"; exit 0;;
  *) echo "Unknown arg: $1" >&2; exit 2;;
esac; done

log() { printf '\n\033[1;35m═ %s\033[0m\n' "$*"; }

# Untested debt = ledger entries since the last "TESTED" marker you add by hand.
untested_debt() {
  [ -f "$LEDGER" ] || { echo 0; return; }
  awk '/^<!-- TESTED /{c=0;next} /^## /{c++} END{print c+0}' "$LEDGER"
}

slack_mirror() { # optional one-way echo to Slack
  [ -z "$SLACK_WEBHOOK_URL" ] && return 0
  curl -fsS --max-time 10 -H 'Content-Type: application/json' \
    -d "{\"text\": $(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')}" \
    "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
}

# Push an approval request with tappable buttons; block until tap or timeout.
# echoes: approve | hold | timeout
wait_for_approval() {
  local title="$1" body="$2"
  local since; since="$(date +%s)"
  local ctl_url="${NTFY_SERVER%/}/${NTFY_CONTROL_TOPIC}"
  curl -fsS --max-time 10 \
    -H "Title: ${title}" -H "Priority: urgent" -H "Tags: rotating_light" \
    -H "Actions: http, ✅ Approve next, ${ctl_url}, method=POST, body=approve; http, 🧪 Hold — I'll test, ${ctl_url}, method=POST, body=hold, clear=true" \
    -d "${body}" \
    "${NTFY_SERVER%/}/${NTFY_TOPIC}" >/dev/null 2>&1 || echo "(push failed)" >&2
  slack_mirror "$title — $body (reply 'approve'/'hold' to $NTFY_CONTROL_TOPIC)"

  local deadline=$((since + APPROVAL_TIMEOUT))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    local reply
    reply="$(curl -fsS --max-time 10 "${NTFY_SERVER%/}/${NTFY_CONTROL_TOPIC}/json?poll=1&since=${since}" 2>/dev/null \
      | python3 -c '
import sys,json
ans=""
for ln in sys.stdin:
    ln=ln.strip()
    if not ln: continue
    try: m=json.loads(ln)
    except: continue
    if m.get("event")!="message": continue
    t=(m.get("message") or "").strip().lower()
    if t in ("approve","hold"): ans=t
print(ans)' || true)"
    case "$reply" in approve) echo approve; return 0;; hold) echo hold; return 0;; esac
    sleep "$APPROVAL_POLL_INTERVAL"
  done
  echo timeout
}

# ----- demo: show the phone gate without running models -----------------
if [ "$DEMO" = "1" ]; then
  log "Demo gate — sending a sample approval to your phone (no model calls)."
  echo "Subscribe to '$NTFY_TOPIC'; the buttons POST to '$NTFY_CONTROL_TOPIC'."
  APPROVAL_TIMEOUT="${APPROVAL_TIMEOUT_DEMO:-75}"
  decision="$(wait_for_approval \
    "🔶 Demo: approve next task?" \
    "SAMPLE — Session so far: 2 tasks done, 7 manual-test items queued. Risk: MEDIUM ↑ (last task took 2 review rounds, touched auth). Tap Approve to continue or Hold to test.")"
  log "You chose: $decision"
  exit 0
fi

# ----- dry run: just show the order ------------------------------------
if [ "$DRY_RUN" = "1" ]; then
  log "Tasks that WOULD run (in order), no calls made:"
  ORCH_AUTO=1 "$SCRIPT_DIR/run_loop.sh" --dry-run | sed -n '/Backlog status/,/Selected task/p'
  echo "Untested debt currently in ledger: $(untested_debt)"
  exit 0
fi

# ----- real full-auto loop ---------------------------------------------
touch "$LEDGER"
count=0
while :; do
  [ "$MAX_TASKS" -gt 0 ] && [ "$count" -ge "$MAX_TASKS" ] && { log "Reached --max $MAX_TASKS."; break; }

  log "Starting next task (completed this session: $count)"
  if ! ORCH_AUTO=1 AUTO_COMMIT="${AUTO_COMMIT:-0}" "$SCRIPT_DIR/run_loop.sh"; then
    bash "$SCRIPT_DIR/notify.sh" "🛑 Orchestrator error" "run_loop.sh exited non-zero. Stopping. Check terminal." urgent warning
    exit 1
  fi
  RUN_DIR="$(cat "$SCRIPT_DIR/runs/.last")"
  . "$RUN_DIR/summary.env"   # TASK VERDICT ROUNDS RUN_DIR
  count=$((count+1))

  debt="$(untested_debt)"
  risk_out="$(bash "$SCRIPT_DIR/risk.sh" "$RUN_DIR" "$TASK" "$debt")"
  bucket="$(printf '%s' "$risk_out" | head -1 | cut -f1)"

  # Append to the mounting manual-testing ledger.
  {
    echo "## $TASK — verdict $VERDICT, $ROUNDS round(s), risk $bucket"
    echo "_$(date '+%Y-%m-%d %H:%M')_ · run: \`${RUN_DIR#$REPO_ROOT/}\`"
    echo
    awk '/^## *Manual[ -]?[Tt]est/{f=1} f{print} /^## / && f && !/Manual/{}' "$RUN_DIR/MANUAL_TESTS.md" 2>/dev/null \
      | head -40 || true
    echo
  } >> "$LEDGER"

  total_items="$(grep -cE '^\s*[-*0-9]' "$LEDGER" || echo 0)"
  log "$risk_out"
  log "Manual-testing ledger: $LEDGER (untested tasks: $debt)"

  if [ "$VERDICT" != "PASS" ]; then
    bash "$SCRIPT_DIR/notify.sh" "⚠️ $TASK did not pass review" \
      "Stopped after $ROUNDS rounds. Risk $bucket. Needs you. See $RUN_DIR." urgent warning
    log "Stopping: task did not reach PASS."
    break
  fi

  decision="$(wait_for_approval \
    "✅ $TASK done — approve next?" \
    "Session: $count task(s) done, ~$total_items manual-test items queued (untested: $debt). Risk this task: $bucket. Approve to continue, or Hold to sit down and test.")"
  log "Approval decision: $decision"
  case "$decision" in
    approve)
      echo "$TASK" >> "$SCRIPT_DIR/.done_tasks"   # advance past this task next pick
      ;;
    hold|timeout)
      bash "$SCRIPT_DIR/notify.sh" "⏸️ Held at $TASK" \
        "Loop paused. $count task(s) done this session, untested: $debt. Do manual testing, then add '<!-- TESTED $(date +%F) -->' to the ledger and re-run." high pause_button
      log "Holding. Re-run auto_loop.sh after you've tested."
      break
      ;;
  esac
done

log "Auto loop ended. Completed $count task(s) this session. Nothing was pushed."
