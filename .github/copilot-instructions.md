# RunThru — Copilot Instructions (Dart/Flutter)

This project is **RunThru**, a paced reading app for ADHD/neurodivergent users. Rebranded from Speedy Boy.
Positioning: "Your attention isn't broken. It just needs a better direction." Not speed-reading — completion.

## Tech Stack

Flutter (Dart), iOS + Android. Riverpod for state (NotifierProvider + AutoDisposeNotifier, codegen).
Isar for new local storage. go_router for navigation. pdfrx + pdfium for PDF. dio for HTTP.
flutter_test + mocktail for testing. GitHub Actions CI. Fastlane signing.

## What Is Built (Do Not Rebuild)

ORP pacing engine (competitive core), 3D neumorphic cube viewport, ContextReveal (2-state),
gesture system (calibrated swipes, WPM dial, hints), text/clipboard import, PDF/EPUB extraction (beta).

## Architecture

New features: `lib/features/{name}/`. Shared code: `lib/shared/`. Providers co-located with features.
No StatefulWidget — use ConsumerWidget or HookConsumerWidget. Run `dart run build_runner build` after
modifying @riverpod providers. `.g.dart` files are generated — never edit.

## Hard Rules

1. All colors via design tokens. No raw `Color(0xFF...)` in widgets.
2. All text styles via typography tokens. No hardcoded `TextStyle`.
3. All box shadows via decoration factories. No hardcoded `BoxDecoration` shadows.
4. Every animation checks `isReducedMotion(context)`.
5. Riverpod for state. No `setState()` for shared state.
6. go_router only. No `Navigator.push()`.
7. No raw `CircularProgressIndicator`/`LinearProgressIndicator`/`RefreshIndicator`.
8. Heavy computation in Isolates. Never on main event loop.
9. No deprecated Flutter APIs. `ListenableBuilder` over `AnimatedBuilder`.
10. pdfrx on main isolate only (FFI). Classification in `Isolate.run()`.
11. No color-only signals. Shape/label/position fallback on every indicator.
12. Touch targets: ≥44pt iOS, ≥48dp Android.
13. CVD-safe defaults (blue+orange + lightness). Tested against protanopia/deuteranopia/tritanopia.
14. Conventional commits: `feat/fix/chore/docs/test/refactor`.
15. All public symbols have dartdoc comments.

## Ethical Commitments (NON-NEGOTIABLE)

- Accessibility features NEVER paywalled (adaptive spacing, OpenDyslexic, ruler, CVD themes, font size).
- No dark patterns. No fake urgency, manipulative countdowns, or guilt flows.
- Privacy by default. Reading content on-device. No cloud upload without per-session opt-in.
- No ableist language in UI, marketing, or code comments.

## Conventions

- Naming: `lowerCamelCase` vars/functions, `UpperCamelCase` classes, `snake_case` files.
- Branches: `feat/{task-id}-{desc}`, `fix/{task-id}-{desc}`.
- PRs: one logical change, linked to backlog task ID.
- Tests mirror `lib/` structure in `test/`.

## Backlog

Source of truth: `doc/runthru-backlog.json`. Every task has `files_in_scope` and `verification_command`.
Read only files in scope for the current task.

## Commands

```
flutter pub get                    # Install deps
dart analyze --fatal-infos         # Lint (CI mode)
flutter test                       # All tests
flutter build apk --release        # Android release
flutter build ios --no-codesign    # iOS release
dart run build_runner build --delete-conflicting-outputs  # Riverpod codegen
```
