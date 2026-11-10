# RunThru — Release Triage Board

The single shared work board for the swarm. Agents edit **only their own
row**. Statuses: `todo` · `in-progress` · `blocked` · `done` · `deferred`.
Put the agent name in Owner when claiming, the commit hash in Verify when done.

Severity: **P0** crash or blocks reading · **P1** feature visibly wrong · **P2** polish (not on release path).

## Scope cuts (lane `cuts`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| R-01 | Remove the placeholder `PurchaseService` stub that granted premium for free | P0 | done | claude | `lib/services/purchase_service.dart` | 2ef8768 — superseded by R-11 (owner wants a one-time purchase) |
| R-02 | Remove Discover / OPDS tab | P1 | done | claude | `lib/screens/discover_screen.dart`, `lib/services/opds_service.dart`, `lib/screens/home_shell.dart` tabs, router redirects, tests | ab21e38 — files were already orphaned |
| R-03 | Drop `CAMERA` permission from Android manifest | P1 | done | claude | `android/app/src/main/AndroidManifest.xml` | 7068e65 — also iOS purpose string + Podfile PERMISSION_CAMERA macro; privacy policy updated |
| R-04 | Hide Google Drive source when OAuth client IDs are empty at runtime | P1 | done | claude | `lib/features/content/widgets/google_drive_source_panel.dart`, `lib/screens/sources_screen.dart`, `lib/features/content/providers/google_drive_auth_provider.dart` | fdb4c4d — googleDriveAvailableProvider gates Sources panel, add action, Settings card |

## Broken features from device pass (lane `fix`)

Fill during Step 1 of `RELEASE_PLAN.md`. One row per failure. Repro goes in the title or a sub-bullet.

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| B-01 | Screenshot generator hung `flutter test` (toImage under fake async + window_manager channel + pending timers). Now tagged `screenshots`, skipped by default via `dart_test.yaml`; run with `flutter test --tags screenshots --run-skipped test/screenshots` | P0 | done | claude | `test/screenshots/app_screenshots_test.dart`, `dart_test.yaml` | 1943eea |
| B-02 | Range picker `dispose()` called `ref.read` (throws on unmount in Riverpod 2.6), skipping the rest of dispose and leaking controllers | P0 | done | claude | `lib/screens/range_picker_screen.dart`, `test/screens/range_picker_screen_test.dart` | a603151 |
| B-03 | Google Drive source panel title row overflowed 44px at 390pt width (iPhone 14) | P1 | done | claude | `lib/features/content/widgets/google_drive_source_panel.dart` | 838dce8 |
| B-04 | Primary button announced its label twice and exposed no semantic tap | P1 | done | claude | `lib/widgets/runthru_shell_widgets.dart` | cfe365b |
| B-05 | Gate script wrote analyzer/test output to fixed `/tmp` files shared by every worktree, so parallel swarm gates reported each other's failures | P1 | done | claude | `scripts/verify_release_readiness.sh` | per-run `mktemp` logs |
| B-06 | Onboarding "Next" threw `LateInitializationError` with reduced motion on (`nextPage(Duration.zero)`), stranding users on card 1. Found on emulator with animations off | P0 | done | claude | `lib/widgets/reading_goal_onboarding_gate.dart`, `test/widgets/reading_entry_onboarding_gate_test.dart` | jumpToPage under reduced motion; regression test |
| B-07 | Onboarding drew the design mockup's fake status bar ("8:19 · 5G", signal, battery) under the real one; TalkBack read it out | P1 | done | claude | `lib/widgets/reading_goal_onboarding_gate.dart`, `test/screens/home_shell_test.dart` | widget removed in 3554151; test now asserts it is absent |
| B-08 | EPUB text showed raw markup (`epub:type="titlepage"`, `class="level1">`, `id="toc-li-2">`) in every reading mode: the opening-block-tag rule ate only `<p ` and left attributes behind. Head `<title>` was also read as body text | P0 | done | claude | `lib/services/epub_extractor.dart`, `test/services/epub_extractor_test.dart` | consume whole tag, drop `<head>`; regression test |

## Reading screen (lane `reading`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| R-05 | Sentence mode aligned with the design reference (karaoke line, edge fade) and shipped | P1 | done | claude | `lib/features/reading/widgets/sentence_mode_view.dart`, `reading_focus_chrome.dart` | 945e407 — owner needs Sentence mode |
| R-06 | 60 fps word-flash check on low-end Android with `FpsProbe` | P1 | blocked | claude → owner | `lib/debug/fps_probe.dart`, `lib/screens/parallax_reading_screen.dart` (only if a regression is found) | needs a physical low-end Android (none attached); run on the Play internal-track build and paste the probe log here |

## Store readiness (lane `store`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| R-07 | Privacy policy: real contact, hosted URL, linked from Settings | P0 | done | claude | `doc/legal/privacy_policy.md`, `lib/screens/settings_screen.dart`, gh-pages `privacy/index.html` | a5a6686 + gh-pages 9a22a0a; live at https://runthruapp.com/privacy. OWNER: paste URL into both store consoles |
| R-08 | Store listing copy + screenshots + feature graphic | P0 | in-progress | claude | `doc/release/store/` (new), `screenshots/` | copy in doc/release/store/listing.md. OWNER: 6.9" screenshots, feature graphic, console entry |
| R-09 | Version bump to `2.0.0+16`, release notes | P0 | done | claude | `pubspec.yaml`, `doc/release/CHANGELOG.md` (new) | 31bd936 — Android versionCode now auto-increments in Codemagic |
| R-10 | Verify Codemagic env groups and signing (keystore, ASC key) | P0 | in-progress | claude | `codemagic.yaml` | static check OK (export compliance set, build numbers monotonic, groups referenced); Flutter pinned to 3.41.2. Remaining: green TestFlight + internal builds after push to `main` |
| R-11 | RunThru Unlock one-time IAP (`runthru_unlock`): store purchase, restore, gates on Reading Wins / page ranges / 3D room | P0 | done | claude | `lib/services/purchase_service.dart`, `lib/widgets/unlock_sheet.dart`, gates in home shell / router / settings | be22190 — OWNER: create product in both consoles, set price, sandbox-test on device |

## AI lane (non-blocking, see `AI_INTEGRATION.md`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| A-01 | Define `summarize` and `difficulty` tasks + annotation schema | P2 | done | swarm/A-01 | `lib/services/edge_ai_queue.dart`, `lib/services/content_store/section_models.dart` | c45ca7f |
| A-02 | Implement a `ModelProcessor` behind an opt-in flag (default off) | P2 | deferred |  | `lib/services/edge_ai_queue.dart`, new `lib/services/ai/` | 2.1 per RELEASE_PLAN "After release"; AI lane does not block 2.0 |
| A-03 | Consent + settings toggle; privacy policy addendum draft | P2 | deferred |  | `lib/screens/settings_screen.dart`, `doc/legal/privacy_policy.md` | 2.1 per RELEASE_PLAN "After release"; AI lane does not block 2.0 |

## Deferred

| ID | Title | Reason |
|----|-------|--------|
| P-8 | Range picker picks first occurrence of duplicate word | needs pdfrx positional data; edge case |
| LEG | Remove `/read-legacy` + `ReadingScreen` | keep as deep-link fallback for one release |
| EPUB-NAV | EPUB `nav.xhtml` (table of contents) is in the spine and read as text | dropping it changes chapter counts that `epubChapterCountInIsolate` computes separately; fix both together in 2.0.1 |
| EPUB-CACHE | Text extracted before B-08 and migrated from legacy caches keeps the leaked markup (identity is content hash, so re-import does not re-extract) | ContentStore is new in 2.0 so no shipped ContentStore cache exists; bump `kContentStoreSchemaVersion` with a read-path re-extract in 2.0.1 |
| AIQ | `SectionProcessingRequest.fromJson` uses `as` casts; a wrongly typed persisted entry throws `TypeError` that `_decode` does not catch | nothing enqueues in 2.0 (A-02 deferred); fix before A-02 lands |
