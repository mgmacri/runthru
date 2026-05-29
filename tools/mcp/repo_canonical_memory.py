"""MCP server exposing only canonical RunThru project memory files."""

from __future__ import annotations

import logging
from pathlib import Path

from mcp.server.fastmcp import FastMCP


logging.basicConfig(level=logging.WARNING)
logging.getLogger("mcp").setLevel(logging.WARNING)

mcp = FastMCP("RepoCanonicalMemory")

REPO_ROOT = Path(__file__).resolve().parents[2]

CANONICAL_PATTERNS = [
    "doc/runthru-backlog.json",
    "AGENTS.md",
    "CLAUDE.md",
    ".github/instructions/**",
    ".github/prompts/**",
    ".github/agents/**",
    "doc/sop/**",
    "doc/specs/active/**/*.md",
]


def _relative_to_repo(path: Path) -> str | None:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return None


def get_canonical_files() -> list[str]:
    """Resolve canonical allowlist patterns into repo-relative file paths."""
    files: set[str] = set()

    for pattern in CANONICAL_PATTERNS:
        for path in REPO_ROOT.glob(pattern):
            candidates = path.rglob("*") if path.is_dir() else [path]
            for candidate in candidates:
                if not candidate.is_file():
                    continue

                relative_path = _relative_to_repo(candidate)
                if relative_path is not None:
                    files.add(relative_path)

    return sorted(files)


@mcp.tool()
def list_canonical_files() -> list[str]:
    """List files currently tracked in canonical project memory."""
    return get_canonical_files()


@mcp.tool()
def read_canonical_file(file_path: str) -> str:
    """Read a specific whitelisted canonical document."""
    allowed_files = set(get_canonical_files())
    normalized_path = file_path.strip().replace("\\", "/")

    if normalized_path not in allowed_files:
        return (
            "Error: Access denied. "
            f"'{file_path}' is not part of canonical project memory."
        )

    try:
        return (REPO_ROOT / normalized_path).read_text(encoding="utf-8")
    except Exception as exc:  # pragma: no cover - defensive tool boundary.
        return f"Error reading file: {exc}"


@mcp.tool()
def search_canonical_memory(query: str) -> str:
    """Search approved canonical project documentation for keyword matches."""
    query_words = [word for word in query.lower().split() if word]
    if not query_words:
        return "No query terms provided."

    results: list[str] = []

    for file_path in get_canonical_files():
        try:
            content = (REPO_ROOT / file_path).read_text(encoding="utf-8")
        except Exception:
            continue

        if any(word in content.lower() for word in query_words):
            snippet = content[:1500].rstrip()
            results.append(f"=== File: {file_path} ===\n{snippet}\n")

    return "\n".join(results) if results else "No matching canonical documents found."


if __name__ == "__main__":
    mcp.run(transport="stdio")
