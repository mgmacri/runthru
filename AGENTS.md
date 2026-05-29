# RunThru — Codex Agent Instructions

Read `.github/copilot-instructions.md` first. It is the shared baseline for all
assistant tools in this repo.

## Codex Operating Notes

- Treat the committed source code as the source of truth for current product
  behavior and architecture.
- Do not use old milestone docs as active instructions unless the user names
  that milestone or prompt explicitly.
- The product pivot has not been recorded in this repo as a concrete plan. Do
  not invent new product goals; keep edits aligned to the current app or ask for
  the missing plan when strategy affects implementation.
- Preserve MCP configuration, agent definitions, skill definitions, platform
  integrations, build configuration, CI/CD assumptions, security/privacy rules,
  and established Flutter architecture unless the user explicitly asks to change
  them.

## Current Project Snapshot

- App: RunThru, a paced reading app focused on completion rather than speed.
- Package/version: `runthru`, `2.0.0+15`.
- Main app surfaces: Library, Sources, Analytics, Settings, reading routes for
  local files, clipboard/share content, Instapaper, and Google Drive.
- Current dependencies include Riverpod, go_router, pdfrx/pdfium,
  shared_preferences, http, Google sign-in, secure storage, file picker,
  XML/archive parsing, and sensor/window utilities.
- Do not assume Isar or dio; they are not current dependencies.

## Current AI/Tooling Assets

Shared and tool-specific assistant files:

```text
.github/copilot-instructions.md     # shared baseline rules
AGENTS.md                           # Codex-specific entry point
CLAUDE.md                           # Claude-specific entry point
.github/agents/                     # agent definitions; preserve unless asked
.github/instructions/               # historical/context docs; not active roadmap
.github/prompts/                    # historical prompt assets; not active roadmap
.agents/skills/                     # skill definitions; preserve unless asked
.mcp.json                           # repo MCP config
.vscode/mcp.json                    # editor MCP config
```

For OpenAI API, ChatGPT Apps SDK, Codex, or model-doc questions, use the
`openaiDeveloperDocs` MCP server first. For library/framework docs, follow the
repo Context7 instruction when available.

## Infrastructure Notes

The iOS-on-Linux dev loop uses OSX-KVM context and scripts documented in:

```text
.github/instructions/infra-osx-kvm-context.instructions.md
.github/prompts/infra-i1.*.prompt.md
doc/infra-backlog.json
```

These are infrastructure guardrails, not app product-roadmap instructions.

## App Metadata

| Item | Value |
|------|-------|
| Version | `2.0.0+15` (`pubspec.yaml`) |
| Android applicationId | `com.runthru.app` |
| iOS bundle id | `com.mgmacri.runthru` |
| iOS Share Extension bundle id | `com.mgmacri.runthru.ShareExtension` |
| iOS App Group | `group.com.mgmacri.runthru` |

The Android/iOS bundle ID mismatch is intentional. Do not "fix" it without
explicit user approval.

## Required Guardrails

Follow the architecture, hard rules, integration boundaries, ethical
commitments, and commands in `.github/copilot-instructions.md`. In particular:

- Riverpod for shared state, `go_router` for navigation, generated `.g.dart`
  files are never manually edited.
- Existing reading engine, document model, import pipeline, progress model,
  Instapaper/Drive boundaries, Share Extension wiring, and platform build
  settings should be reused rather than rebuilt.
- Reading content and credentials must not be logged or uploaded without an
  explicit user-controlled feature that requires it.
