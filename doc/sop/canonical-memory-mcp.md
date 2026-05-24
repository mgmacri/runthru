# Canonical Memory MCP

This repo exposes a local read-only MCP server named `repoCanonicalMemory`.
It gives agent clients a narrow, canonical view of project memory instead of
the full repository.

## Exposed Tools

- `list_canonical_files`: list allowlisted canonical documents.
- `read_canonical_file`: read one allowlisted file by repo-relative path.
- `search_canonical_memory`: search allowlisted files by keywords.

## Canonical Allowlist

- `doc/runthru-backlog.json`
- `AGENTS.md`
- `CLAUDE.md`
- `.github/instructions/**`
- `.github/prompts/**`
- `.github/agents/**`
- `doc/sop/**`
- `doc/specs/active/**/*.md`

## Client Configs

- Claude Code: `.mcp.json`
- Gemini CLI: `.gemini/settings.json`
- Codex: `.codex/config.toml`

All three configs launch:

```bash
/home/matt/.local/bin/uv run --offline --with mcp python /home/matt/dev/speedy-boyv3/tools/mcp/repo_canonical_memory.py
```

The server roots itself from its own file location, so tool access stays scoped
to this repository even if a client launches it from another working directory.

## Notes

- The server uses stdio transport.
- The first launch may download the Python `mcp` package through `uv`.
- If the repo moves, update the absolute script path in all three client
  configs.
