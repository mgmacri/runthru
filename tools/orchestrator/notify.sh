#!/usr/bin/env bash
# notify.sh — push a notification to your phone via ntfy.sh.
#
# Reaches your phone over LAN or mobile data: the ntfy app keeps a persistent
# connection to the server, so delivery does not depend on you being on the
# same network as this machine.
#
# Usage:
#   notify.sh "Title" "Message body" [priority] [tags]
#
#   priority: min|low|default|high|urgent   (default: high)
#   tags:     comma-separated ntfy emoji/tags (default: warning)
#
# Falls back to a desktop notification (notify-send) and stdout if the network
# call fails, so a missed push never silently swallows a gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/orchestrator.env" ] && source "$SCRIPT_DIR/orchestrator.env"

NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
TITLE="${1:-RunThru orchestrator}"
MESSAGE="${2:-(no message)}"
PRIORITY="${3:-high}"
TAGS="${4:-warning}"

if [ -z "${NTFY_TOPIC:-}" ] || [ "${NTFY_TOPIC:-}" = "runthru-CHANGEME" ]; then
  echo "notify.sh: NTFY_TOPIC not set in orchestrator.env — skipping push." >&2
else
  if curl -fsS --max-time 10 \
      -H "Title: ${TITLE}" \
      -H "Priority: ${PRIORITY}" \
      -H "Tags: ${TAGS}" \
      -d "${MESSAGE}" \
      "${NTFY_SERVER%/}/${NTFY_TOPIC}" >/dev/null 2>&1; then
    echo "notify.sh: pushed to ${NTFY_TOPIC}" >&2
  else
    echo "notify.sh: push FAILED (offline?), falling back." >&2
    command -v notify-send >/dev/null 2>&1 && notify-send "$TITLE" "$MESSAGE" || true
  fi
fi

# Always echo so it appears in run logs regardless of network.
echo "🔔 [$TITLE] $MESSAGE"
