# RunThru

Paced reading for focus. RunThru flashes one word at a time at the Optimal
Recognition Point, with adaptive per-word timing, a ContextReveal gesture for
the surrounding sentence, Paragraph and Full Page modes, and a 3D parallax
reading room. Built for ADHD, dyslexic, autistic, and low-vision readers.
Android + iOS, Flutter.

> The repo folder is historically `speedy-boyv3`. The app, packages, and all
> docs are **RunThru**. See `CLAUDE.md` for the project constitution and
> `doc/release/RELEASE_PLAN.md` for what we are shipping next.

## Status

Release mode. Analyzer and test suite are the gate; the live work board is
`doc/release/TRIAGE.md`. Agents and humans claim rows there.

## Quick start

The devcontainer is the canonical environment (Flutter 3.41.2 + Android SDK
+ Claude Code). See `.devcontainer/README.md`. On a host:

```bash
flutter pub get
cp dart_defines/development.json.example dart_defines/development.json   # fill in real values or leave placeholders
flutter run -d <device> --dart-define-from-file=dart_defines/development.json
```

Arch host note: the system Flutter package is broken; use `~/.flutter-sdk/bin/flutter`.

## Gate and tooling

| Command | Purpose |
|---|---|
| `scripts/verify_release_readiness.sh` | analyze + tests + print/secret/legacy-name scans; must print `GATE: PASS` |
| `scripts/verify_release_readiness.sh --quick` | same without the test suite |
| `dart run build_runner build --delete-conflicting-outputs` | regenerate Riverpod providers after editing `@riverpod` code |
| `scripts/swarm.sh R-01 R-02` | headless Claude Code run per TRIAGE row, each in its own worktree |
| `flutter build apk --debug` | sideload build for device testing |

## Secrets

Never in source. Dart-defines at build time, env vars in CI.

| Key | Used by |
|---|---|
| `INSTAPAPER_CONSUMER_KEY`, `INSTAPAPER_CONSUMER_SECRET` | Instapaper xAuth |
| `GOOGLE_IOS_CLIENT_ID` | Google Sign-In on iOS |
| `GOOGLE_WEB_CLIENT_ID` | Google Sign-In server client ID on Android |

Codemagic env groups: `instapaper_credentials`, `google_signin_credentials`,
`google_play_credentials`. Fastlane env vars are listed in
`android/fastlane/README.md` and `ios/fastlane/README.md`.

## Release pipeline

- Push to `main` → GitHub Actions (`analyze` + `test`) and Codemagic
  (`codemagic.yaml`: TestFlight + Play internal track).
- Promote with `bundle exec fastlane release` from `android/` and `ios/`.
- Package IDs: Android `com.runthru.app`, iOS `com.mgmacri.runthru`. Fixed.

## Code map

```
lib/
  core/        WordTimer, ContextReveal, ORP, sentence resolver, logger (Ring 1, sealed)
  design/      tokens, typography, animations, a11y tokens (only source of design values)
  features/
    content/   Drive, Instapaper, clipboard, share intent, file import
    reading/   reading modes, pacing (RSVP Nano derived), providers
    settings/  settings panels
  navigation/  go_router, cube + wall-fold transitions
  screens/     library, sources, analytics, settings, reading screens
  services/    ContentStore (Ring 2), extraction, manifests, cache policy, EdgeAiQueue
  store/       AppConfig, bookmarks, library sources
  three_d/     parallax room, cube viewport, ORP painters
  widgets/     shell widgets, overlays
test/            unit + widget tests        integration_test/   gesture and reliability flows
```

Architecture detail: `doc/architecture/data_layer.md`.

## Docs

| Path | What |
|---|---|
| `CLAUDE.md`, `AGENTS.md` | constitution and agent entry point |
| `doc/release/` | release plan, triage board, swarm protocol, AI lane |
| `doc/architecture/` | data layer design |
| `doc/legal/privacy_policy.md` | privacy policy (store requirement) |
| `ui-improvement-plan/` | designer recommendations for the 3D UI |
| `doc/archive/` | dated audit reports, old Copilot prompts, old specs. History, not instructions. |

## Attribution

Per-word pacing derives from RSVP Nano (ionutdecebal/rsvpnano, MIT). See `NOTICE`.
