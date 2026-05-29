#!/usr/bin/env bash
# run_loop.sh — single-task orchestrator for the RunThru build loop.
#
# Maps your manual flow onto the two CLIs (claude, codex), both on subscriptions:
#   1. pick the next backlog task
#   2. engineer an execution prompt   (prompt-engineer skill — replaces the GPT)
#   3. author writes the code         (AUTHOR: claude or codex)
#   4. reviewer audits it             (the OTHER model)
#   5. remediate until VERDICT: PASS  (or MAX_REVIEW_ROUNDS)
#   6. write manual-test notes + push a notification to your phone
#   7. STOP at the human gate (you do manual testing + PR). Optional gated local commit.
#
# It NEVER pushes to a remote and never opens a PR.
#
# Usage:
#   tools/orchestrator/run_loop.sh [--task GDI-M2-04A] [--dry-run] [--author claude|codex]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# ---- config ----
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/orchestrator.env" ] && source "$SCRIPT_DIR/orchestrator.env"
AUTHOR="${AUTHOR:-claude}"
MAX_REVIEW_ROUNDS="${MAX_REVIEW_ROUNDS:-4}"
GOAL_DOC="${GOAL_DOC:-doc/goals/google-drive-next-milestone-plan.md}"
CLAUDE_PERM="${CLAUDE_PERM:-acceptEdits}"
CODEX_EXEC_ARGS="${CODEX_EXEC_ARGS:-}"
AUTO_COMMIT="${AUTO_COMMIT:-0}"

# ---- args ----
TASK=""
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK="$2"; shift 2;;
    --author) AUTHOR="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

REVIEWER="codex"; [ "$AUTHOR" = "codex" ] && REVIEWER="claude"

log() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ---- task selection ------------------------------------------------------
# Lists every "### GDI-M2-XX: Title" header in goal-doc order, marks a task done
# if a "<!-- GDI-M2-XX done -->" or "<!-- GDI-M2-XX completed ... -->" comment exists.
list_tasks() {
  grep -nE '^### GDI-M2-[0-9A-Z]+:' "$GOAL_DOC" | sed -E 's/^[0-9]+:### //'
}
is_done() {
  grep -qE "<!-- *$1 (done|completed)" "$GOAL_DOC" && return 0
  [ -f "$SCRIPT_DIR/.done_tasks" ] && grep -qx "$1" "$SCRIPT_DIR/.done_tasks"
}
pick_next_task() {
  while IFS= read -r line; do
    local id="${line%%:*}"
    is_done "$id" || { echo "$id"; return 0; }
  done < <(list_tasks)
  return 1
}
task_block() { # print the markdown block for a task id
  awk -v id="$1" '
    $0 ~ "^### "id":" {grab=1}
    grab && /^### / && $0 !~ "^### "id":" && seen {exit}
    grab {print; seen=1}
  ' "$GOAL_DOC"
}

log "Backlog status ($GOAL_DOC)"
while IFS= read -r line; do
  id="${line%%:*}"
  if is_done "$id"; then echo "  [x] $line"; else echo "  [ ] $line"; fi
done < <(list_tasks)

[ -z "$TASK" ] && TASK="$(pick_next_task || true)"
[ -z "$TASK" ] && die "No incomplete task found. Pass --task GDI-M2-XX to override."
TITLE_LINE="$(list_tasks | grep -E "^$TASK:" || echo "$TASK")"
log "Selected task: $TITLE_LINE"
log "Author: $AUTHOR   Reviewer: $REVIEWER   Max rounds: $MAX_REVIEW_ROUNDS"

# ---- run workspace ----
RUN_ID="$(date +%Y%m%d-%H%M%S)-$TASK"
RUN_DIR="$SCRIPT_DIR/runs/$RUN_ID"
mkdir -p "$RUN_DIR"
task_block "$TASK" > "$RUN_DIR/task.md"
log "Run artifacts: $RUN_DIR"

# ---- CLI adapters --------------------------------------------------------
# Centralized so you can tweak flags/permissions for your setup in one place.
run_claude() { # $1 = prompt (string)
  claude -p "$1" --permission-mode "$CLAUDE_PERM"
}
run_codex() { # $1 = prompt (string)
  # shellcheck disable=SC2086
  codex exec $CODEX_EXEC_ARGS "$1"
}
run_model() { # $1 = claude|codex   $2 = prompt
  case "$1" in
    claude) run_claude "$2";;
    codex)  run_codex  "$2";;
    *) die "unknown model '$1'";;
  esac
}

# ---- step 2: engineer the prompt ----------------------------------------
log "Engineering execution prompt via prompt-engineer skill ($AUTHOR)"
ENGINEER_INPUT="Use the /prompt-engineer skill. Scope the following RunThru backlog task into a single, self-contained execution prompt for a coding agent. Output ONLY the finished prompt.

--- TASK ($TASK) ---
$(cat "$RUN_DIR/task.md")"

if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] Would run /prompt-engineer on the task block above. Skipping model calls."
  echo "$ENGINEER_INPUT" > "$RUN_DIR/engineer_input.txt"
  log "Dry run complete. Inspect $RUN_DIR/. No code changed, no notifications sent."
  exit 0
fi

run_model "$AUTHOR" "$ENGINEER_INPUT" | tee "$RUN_DIR/exec_prompt.md"
[ -s "$RUN_DIR/exec_prompt.md" ] || die "Prompt engineering produced no output."

# ---- step 3: author writes the code -------------------------------------
log "Authoring with $AUTHOR"
AUTHOR_PROMPT="Execute the following engineered task prompt in this repo. Make all code changes, add tests, and run the verification commands. Do not commit.

$(cat "$RUN_DIR/exec_prompt.md")"
run_model "$AUTHOR" "$AUTHOR_PROMPT" 2>&1 | tee "$RUN_DIR/author_round0.log"

# ---- steps 4-5: review + remediation loop -------------------------------
PROTOCOL="$(cat "$SCRIPT_DIR/review_protocol.md")"
verdict="FAIL"
round=0
while [ "$round" -lt "$MAX_REVIEW_ROUNDS" ]; do
  round=$((round+1))
  log "Review round $round — reviewer: $REVIEWER"
  REVIEW_PROMPT="$PROTOCOL

--- TASK ACCEPTANCE CRITERIA ($TASK) ---
$(cat "$RUN_DIR/task.md")

Review the uncommitted changes now."
  run_model "$REVIEWER" "$REVIEW_PROMPT" 2>&1 | tee "$RUN_DIR/review_round${round}.md"

  verdict="$(grep -oE '^VERDICT:[[:space:]]*(PASS|FAIL)' "$RUN_DIR/review_round${round}.md" | tail -1 | grep -oE '(PASS|FAIL)' || echo FAIL)"
  log "Verdict round $round: $verdict"
  [ "$verdict" = "PASS" ] && break

  log "Remediating findings with $AUTHOR"
  REMEDIATE_PROMPT="An independent reviewer audited your changes and returned findings below. Address every finding, keep tests green, and re-run the verification commands. Do not commit.

--- REVIEW FINDINGS ---
$(cat "$RUN_DIR/review_round${round}.md")"
  run_model "$AUTHOR" "$REMEDIATE_PROMPT" 2>&1 | tee "$RUN_DIR/remediate_round${round}.log"
done

# ---- step 6: gate -------------------------------------------------------
{
  echo "# Manual testing — $TASK"
  echo
  echo "Review verdict: **$verdict** after $round round(s)."
  echo "Run dir: \`$RUN_DIR\`"
  echo
  echo "## Task"
  cat "$RUN_DIR/task.md"
  echo
  echo "## Last review"
  cat "$RUN_DIR/review_round${round}.md"
} > "$RUN_DIR/MANUAL_TESTS.md"

# Machine-readable summary for auto_loop.sh / risk.sh.
{ echo "TASK=$TASK"; echo "VERDICT=$verdict"; echo "ROUNDS=$round"; echo "RUN_DIR=$RUN_DIR"; } > "$RUN_DIR/summary.env"
echo "$RUN_DIR" > "$SCRIPT_DIR/runs/.last"

if [ "$verdict" = "PASS" ] && [ "$AUTO_COMMIT" = "1" ]; then
  branch="orchestrator/$TASK"
  git checkout -b "$branch" 2>/dev/null || git checkout "$branch"
  git add -A
  git commit -m "feat($TASK): automated implementation (review PASS, $round round(s))

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>" >/dev/null
  log "Committed to branch $branch (NOT pushed)."
fi

# When driven by auto_loop.sh (ORCH_AUTO=1) the outer loop owns notifications
# and the approval gate, so stay quiet here.
if [ "${ORCH_AUTO:-0}" != "1" ]; then
  if [ "$verdict" = "PASS" ]; then
    bash "$SCRIPT_DIR/notify.sh" \
      "✅ $TASK ready for manual testing" \
      "Review PASSed in $round round(s). See MANUAL_TESTS.md in $RUN_DIR. Do manual testing + PR." \
      "high" "white_check_mark,test_tube"
  else
    bash "$SCRIPT_DIR/notify.sh" \
      "⚠️ $TASK stalled — needs you" \
      "Reviewer still FAILing after $MAX_REVIEW_ROUNDS rounds. Manual intervention needed. See $RUN_DIR." \
      "urgent" "warning"
  fi
fi

log "Done. Verdict: $verdict. Changes are uncommitted-or-on-branch and UNPUSHED. Your move: steps 8–10."
