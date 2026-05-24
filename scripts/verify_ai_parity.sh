#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_MCP_URL="https://developers.openai.com/mcp"
EXPECTED_INSTRUCTION='For OpenAI API, ChatGPT Apps SDK, Codex, or model-doc questions: use the `openaiDeveloperDocs` MCP server first.'
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

failures=0

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

check_file_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if [[ ! -f "$file" ]]; then
    fail "$label (missing file: $file)"
    return
  fi

  if rg -Fq "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

printf '\n== Repo instruction parity ==\n'
check_file_contains "$REPO_ROOT/AGENTS.md" "$EXPECTED_INSTRUCTION" "AGENTS.md includes shared OpenAI Docs MCP instruction"
check_file_contains "$REPO_ROOT/CLAUDE.md" "$EXPECTED_INSTRUCTION" "CLAUDE.md includes shared OpenAI Docs MCP instruction"

printf '\n== Shared project MCP ==\n'
if [[ -f "$REPO_ROOT/.mcp.json" ]]; then
  if python3 - "$REPO_ROOT/.mcp.json" "$EXPECTED_MCP_URL" <<'PY'
import json, sys
path, expected_url = sys.argv[1], sys.argv[2]
obj = json.load(open(path))
srv = obj.get("mcpServers", {}).get("openaiDeveloperDocs", {})
ok = srv.get("url") == expected_url
print("ok" if ok else "bad")
sys.exit(0 if ok else 1)
PY
  then
    pass ".mcp.json defines openaiDeveloperDocs with expected URL"
  else
    fail ".mcp.json defines openaiDeveloperDocs with expected URL"
  fi
else
  fail ".mcp.json exists"
fi

if [[ -f "$REPO_ROOT/.vscode/mcp.json" ]]; then
  if python3 - "$REPO_ROOT/.vscode/mcp.json" "$EXPECTED_MCP_URL" <<'PY'
import json, sys
path, expected_url = sys.argv[1], sys.argv[2]
obj = json.load(open(path))
srv = obj.get("servers", {}).get("openaiDeveloperDocs", {})
ok = srv.get("url") == expected_url
print("ok" if ok else "bad")
sys.exit(0 if ok else 1)
PY
  then
    pass ".vscode/mcp.json defines openaiDeveloperDocs with expected URL"
  else
    fail ".vscode/mcp.json defines openaiDeveloperDocs with expected URL"
  fi
else
  fail ".vscode/mcp.json exists"
fi

printf '\n== Global Codex MCP ==\n'
if codex mcp get openaiDeveloperDocs 2>/dev/null | rg -Fq "$EXPECTED_MCP_URL"; then
  pass "Codex global MCP includes openaiDeveloperDocs"
else
  fail "Codex global MCP includes openaiDeveloperDocs"
fi

printf '\n== Global Claude MCP ==\n'
if claude mcp get openaiDeveloperDocs 2>/dev/null | rg -Fq "$EXPECTED_MCP_URL"; then
  pass "Claude user MCP includes openaiDeveloperDocs"
else
  fail "Claude user MCP includes openaiDeveloperDocs"
fi

printf '\n== Claude plugin baseline ==\n'
claude_plugins="$(claude plugin list 2>/dev/null || true)"
if rg -Fq "frontend-design@claude-plugins-official" <<<"$claude_plugins"; then
  pass "Claude frontend-design plugin installed"
else
  fail "Claude frontend-design plugin installed"
fi
if rg -Fq "clangd-lsp@claude-plugins-official" <<<"$claude_plugins"; then
  pass "Claude clangd-lsp plugin installed"
else
  fail "Claude clangd-lsp plugin installed"
fi

printf '\n== Codex skill baseline ==\n'
for skill in imagegen openai-docs skill-installer skill-creator plugin-creator; do
  if [[ -f "$CODEX_HOME/skills/.system/$skill/SKILL.md" ]]; then
    pass "Codex system skill present: $skill"
  else
    fail "Codex system skill present: $skill"
  fi
done

for skill in screenshot playwright; do
  if [[ -f "$CODEX_HOME/skills/$skill/SKILL.md" ]]; then
    pass "Codex curated skill present: $skill"
  else
    fail "Codex curated skill present: $skill"
  fi
done

printf '\n== Shared agent files ==\n'
for agent_file in "$REPO_ROOT/.github/agents/backlog-auditor.agent.md" "$REPO_ROOT/.github/agents/v4-auditor.agent.md"; do
  if [[ -f "$agent_file" ]]; then
    pass "Agent file present: ${agent_file#$REPO_ROOT/}"
  else
    fail "Agent file present: ${agent_file#$REPO_ROOT/}"
  fi
done

printf '\n== Summary ==\n'
if [[ "$failures" -eq 0 ]]; then
  printf 'All parity checks passed.\n'
  exit 0
fi

printf '%d parity check(s) failed.\n' "$failures"
exit 1
