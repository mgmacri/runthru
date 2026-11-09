# RunThru — Shared Assistant Instructions

RunThru is a Flutter/Dart app for paced reading and reading completion.

## App Shape

- App name/package: RunThru (`runthru`), version `2.0.0+15`
- Platforms: Android and iOS with iOS Share Extension
- Primary routes: library, sources, analytics, settings, local reading, clipboard reading, Instapaper reading, Google Drive reading
- Reading core: ORP/paced word display, adaptive per-word timing, WPM controls, ContextReveal, reading progress, PDF/EPUB extraction, parallax/3D viewport

## Tech Stack

Flutter/Dart with Riverpod (`flutter_riverpod`, `riverpod_annotation`, generated providers), `go_router`, `pdfrx`/pdfium, `shared_preferences`, `http`, `google_sign_in`, `flutter_appauth`, `flutter_secure_storage`, `file_picker`, `permission_handler`, `window_manager`, `xml`, `archive`, `clock`, `sensors_plus`.

Not in deps: Isar, dio.

## Architecture

- Features under `lib/features/{feature}/`, shared services in `lib/services/`
- Providers are co-located with the feature they support
- Run `dart run build_runner build --delete-conflicting-outputs` after modifying `@riverpod` providers
- Never edit generated `.g.dart` files directly
- Riverpod for shared state; `go_router` for navigation

## Integration Facts

- Android application ID: `com.runthru.app`
- iOS bundle ID: `com.mgmacri.runthru`
- iOS Share Extension bundle ID: `com.mgmacri.runthru.ShareExtension`
- iOS App Group: `group.com.mgmacri.runthru`
- The Android/iOS bundle ID mismatch is intentional
- MCP config: `.mcp.json` and `.vscode/mcp.json`
- Constitution and release plan: `CLAUDE.md`, `AGENTS.md`, `doc/release/`
- Agent definitions: `.claude/agents/`
- Skills: `.agents/skills/`
- Archived Copilot prompts/instructions: `doc/archive/prompts/` (history only)
- Instapaper and Google Drive tokens/credentials must not be logged

## Standards

- Accessibility: 44 pt touch targets on iOS, 48 dp on Android
- Animations must respect `isReducedMotion(context)`
- Status/meaning must not rely on color alone
- Conventional commits: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`
- Dartdoc for new public symbols

## Commands

```bash
flutter pub get
dart analyze --fatal-infos
flutter test
flutter build apk --release
flutter build ios --no-codesign
dart run build_runner build --delete-conflicting-outputs
scripts/verify_release_readiness.sh
```
