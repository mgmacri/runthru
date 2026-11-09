# RunThru development + agent-swarm container.
# Flutter 3.41.2 stable with Android SDK, plus Node (for Claude Code) and uv
# (for the repo MCP server). iOS builds still require a macOS host.

FROM node:22-bookworm-slim AS node

FROM ghcr.io/cirruslabs/flutter:3.41.2

# Node runtime copied from the official image (no curl | bash).
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

RUN apt-get update && apt-get install -y --no-install-recommends \
      git ripgrep jq curl ca-certificates less tmux python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*

# Claude Code CLI.
RUN npm install -g @anthropic-ai/claude-code

# uv for tools/mcp/repo_canonical_memory.py
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

ENV PUB_CACHE=/root/.pub-cache \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    CI=true

WORKDIR /workspace
RUN git config --global --add safe.directory /workspace \
 && flutter config --no-analytics --no-cli-animations >/dev/null 2>&1 || true

CMD ["bash"]
