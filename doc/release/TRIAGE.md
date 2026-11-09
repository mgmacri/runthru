# RunThru — Release Triage Board

The single shared work board for the swarm. Agents edit **only their own
row**. Statuses: `todo` · `in-progress` · `blocked` · `done` · `deferred`.
Put the agent name in Owner when claiming, the commit hash in Verify when done.

Severity: **P0** crash or blocks reading · **P1** feature visibly wrong · **P2** polish (not on release path).

## Scope cuts (lane `cuts`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| R-01 | Remove premium gate and `PurchaseService` stub; app ships free | P0 | todo | | `lib/services/purchase_service.dart`, `lib/navigation/app_router.dart` (`_PremiumReadGuard`), `lib/store/config.dart` (`hasPremium`), settings purchase UI, related tests | gate + no "premium" string reachable in UI |
| R-02 | Remove Discover / OPDS tab | P1 | todo | | `lib/screens/discover_screen.dart`, `lib/services/opds_service.dart`, `lib/screens/home_shell.dart` tabs, router redirects, tests | gate + 3 tabs remain |
| R-03 | Drop `CAMERA` permission from Android manifest | P1 | todo | | `android/app/src/main/AndroidManifest.xml` | `aapt dump permissions` shows no CAMERA |
| R-04 | Hide Google Drive source when OAuth client IDs are empty at runtime | P1 | todo | | `lib/features/content/widgets/google_drive_source_panel.dart`, `lib/screens/sources_screen.dart`, `lib/features/content/providers/google_drive_auth_provider.dart` | gate + source hidden in a build without dart-defines |

## Broken features from device pass (lane `fix`)

Fill during Step 1 of `RELEASE_PLAN.md`. One row per failure. Repro goes in the title or a sub-bullet.

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| B-01 | Screenshot generator hung `flutter test` (toImage under fake async + window_manager channel + pending timers). Now tagged `screenshots`, skipped by default via `dart_test.yaml`; run with `flutter test --tags screenshots --run-skipped test/screenshots` | P0 | done | claude | `test/screenshots/app_screenshots_test.dart`, `dart_test.yaml` | 1943eea |
| B-02 | Range picker `dispose()` called `ref.read` (throws on unmount in Riverpod 2.6), skipping the rest of dispose and leaking controllers | P0 | done | claude | `lib/screens/range_picker_screen.dart`, `test/screens/range_picker_screen_test.dart` | a603151 |
| B-03 | Google Drive source panel title row overflowed 44px at 390pt width (iPhone 14) | P1 | done | claude | `lib/features/content/widgets/google_drive_source_panel.dart` | 838dce8 |
| B-04 | | | todo | | | |
| B-05 | | | todo | | | |
| B-06 | | | todo | | | |

## Reading screen (lane `reading`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| R-05 | Sentence mode: align with design reference or hide it from the mode switcher | P1 | todo | | `lib/features/reading/widgets/sentence_mode_view.dart`, `lib/features/reading/widgets/mode_switcher.dart`, `lib/features/reading/providers/reading_mode_provider.dart` | gate + screenshot vs design JSX |
| R-06 | 60 fps word-flash check on low-end Android with `FpsProbe` | P1 | todo | | `lib/debug/fps_probe.dart`, `lib/screens/parallax_reading_screen.dart` (only if a regression is found) | probe log pasted in row |

## Store readiness (lane `store`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| R-07 | Privacy policy: real contact, hosted URL, linked from Settings | P0 | todo | | `doc/legal/privacy_policy.md`, `lib/screens/settings_screen.dart` | URL resolves; link opens from Settings |
| R-08 | Store listing copy + screenshots + feature graphic | P0 | todo | | `doc/release/store/` (new), `screenshots/` | both consoles show complete listings |
| R-09 | Version bump to `2.0.0+16`, release notes | P0 | todo | | `pubspec.yaml`, `doc/release/CHANGELOG.md` (new) | Codemagic build number check passes |
| R-10 | Verify Codemagic env groups and signing (keystore, ASC key) | P0 | todo | | `codemagic.yaml` (read only) | green TestFlight + internal builds from `main` |

## AI lane (non-blocking, see `AI_INTEGRATION.md`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| A-01 | Define `summarize` and `difficulty` tasks + annotation schema | P2 | todo | | `lib/services/edge_ai_queue.dart`, `lib/services/content_store/section_models.dart` | unit tests |
| A-02 | Implement a `ModelProcessor` behind an opt-in flag (default off) | P2 | todo | | `lib/services/edge_ai_queue.dart`, new `lib/services/ai/` | unit tests with fake transport |
| A-03 | Consent + settings toggle; privacy policy addendum draft | P2 | todo | | `lib/screens/settings_screen.dart`, `doc/legal/privacy_policy.md` | a11y guideline tests |

## Deferred

| ID | Title | Reason |
|----|-------|--------|
| P-8 | Range picker picks first occurrence of duplicate word | needs pdfrx positional data; edge case |
| LEG | Remove `/read-legacy` + `ReadingScreen` | keep as deep-link fallback for one release |
