# RunThru — Shared Assistant Instructions

RunThru is a Flutter/Dart app for paced reading and reading completion. The
committed source code is the source of truth for current product behavior.

The user has indicated a product-direction pivot, but no concrete replacement
plan is recorded in this repo yet. Do not infer a new roadmap from older
milestone docs. When product strategy matters, ask for the current plan or use
the current committed app behavior as the boundary.

## Source of Truth

Use this order when instructions conflict:

1. Current committed source code
2. Current project structure
3. `pubspec.yaml`, platform build files, and dev tooling
4. MCP, agent, skill, and assistant-tool configuration
5. Current product docs such as store listing, privacy policy, and goal docs
6. This file and tool-specific root instruction files
7. Historical roadmap, backlog, prompt, or milestone files

Files under `.github/prompts/` and old `.github/instructions/m*` or
`.github/instructions/e*` milestone docs are historical task context unless the
user explicitly asks to work from one. Never treat an old milestone as the
active roadmap just because the file exists.

## Current App Shape

- App name/package: RunThru (`pubspec.yaml` name `runthru`), version `2.0.0+15`.
- Platforms in active build files: Android and iOS, with iOS Share Extension.
- Primary routes: library, sources, analytics, settings, local reading,
  clipboard reading, Instapaper reading, and Google Drive reading.
- Main tabs: Library, Sources, Analytics, Settings.
- Content sources currently represented in code: local files, clipboard/share
  content, Instapaper, and Google Drive.
- Reading core: ORP/paced word display, adaptive per-word timing, WPM controls,
  ContextReveal, reading progress, PDF/EPUB extraction, parallax/3D viewport,
  and reading-mode/suppression UI.

## Current Tech Stack

Flutter/Dart with Riverpod (`flutter_riverpod`, `riverpod_annotation`,
generated providers), `go_router`, `pdfrx`/pdfium for PDF, `shared_preferences`
for local app/config/progress/analytics persistence, `http` for network calls,
`google_sign_in`, `flutter_secure_storage`, `file_picker`,
`permission_handler`, `window_manager`, `xml`, `archive`, `clock`, and
`sensors_plus`.

Do not introduce or assume Isar or dio. They are not current dependencies.

## Architecture

- New feature code belongs under `lib/features/{feature}/` when that matches
  existing boundaries. Shared app services remain in `lib/services/`; shared
  reading/design/navigation/store code remains in its existing package.
- Providers are co-located with the feature they support. Run
  `dart run build_runner build --delete-conflicting-outputs` after modifying
  `@riverpod` providers. Never edit generated `.g.dart` files directly.
- Use Riverpod for shared state. Local, ephemeral widget state may follow the
  existing `ConsumerStatefulWidget`/`StatefulWidget` patterns already present in
  the repo.
- Use `go_router` for navigation. Do not add `Navigator.push()` flows.
- Reuse the existing reading engine, document model, import pipeline, route
  patterns, progress records, and content-source boundaries.

## Integration Boundaries

- Instapaper uses the existing content feature files and secure token handling.
  Do not log tokens, credentials, article text, auth headers, or raw API secrets.
- Google Drive uses minimal read-only Drive access by default. Do not silently
  expand scopes, modify Drive files, upload document text, or sync progress to
  cloud storage without explicit user opt-in and matching implementation scope.
- iOS Share Extension and App Group identifiers are established integration
  points. Do not rename bundle IDs or app groups casually.
- Android application ID is `com.runthru.app`; iOS bundle ID is
  `com.mgmacri.runthru`; iOS Share Extension bundle ID is
  `com.mgmacri.runthru.ShareExtension`. The mismatch is intentional.
- MCP configuration lives in `.mcp.json` and `.vscode/mcp.json`. Agent
  definitions live in `.github/agents/`. Skills live in `.agents/skills/`.
  Preserve those unless the user explicitly asks to change them.

## Hard Rules

1. Use design tokens for new UI colors; do not add raw `Color(0xFF...)` in app
   widgets. Existing low-level painter constants are not a reason for broad
   cleanup.
2. Use typography tokens for UI text styles; avoid hardcoded `TextStyle`.
3. Use decoration/material factories for shadows and surfaces; avoid ad hoc
   `BoxDecoration` shadows in widgets.
4. Every animation or animated transition must respect `isReducedMotion(context)`
   when it can affect user comfort.
5. Shared state belongs in Riverpod, not widget-local `setState()`.
6. Navigation goes through `go_router`.
7. Do not add raw `CircularProgressIndicator`, `LinearProgressIndicator`, or
   `RefreshIndicator`; use the existing RunThru loading/refresh patterns.
8. Keep heavy parsing/classification off the main event loop where the library
   allows it. Respect pdfrx/pdfium constraints.
9. Avoid deprecated Flutter APIs.
10. Do not rely on color alone for status or meaning; include shape, text,
    position, semantics, or another non-color cue.
11. Maintain accessible touch targets: at least 44 pt on iOS and 48 dp on
    Android.
12. Keep defaults CVD-safe and accessible.
13. Use conventional commits when committing: `feat`, `fix`, `chore`, `docs`,
    `test`, or `refactor`.
14. Add Dartdoc for new public symbols.

## Ethical Commitments

- Accessibility features must not be paywalled.
- No dark patterns, fake urgency, manipulative countdowns, or guilt flows.
- Privacy by default: reading content stays on-device unless the user explicitly
  opts into a specific network/cloud operation.
- No ableist language in UI, marketing, code comments, docs, or tests.

## Commands

```bash
flutter pub get
dart analyze --fatal-infos
flutter test
flutter build apk --release
flutter build ios --no-codesign
dart run build_runner build --delete-conflicting-outputs
scripts/verify_ai_parity.sh
```
