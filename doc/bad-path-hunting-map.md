# Bad Path Hunting Map for RunThru

> Scope note: this is a planning artifact built from the repo layout, CLAUDE.md rules, and the active milestone (M1.5 → M1.6). Confidence is tagged per row; "Needs inspection" rows require code reads before any fix is attempted.

---

## 1. Project Section Map

### 1. Runtime and Navigation
#### 1.1 App bootstrap & root providers
- Key files: `lib/main.dart`, `lib/app.dart` (if present), `lib/core/`, root `ProviderScope`
- Responsibility: Flutter binding init, error zone, Riverpod root, theme, observers
- Dependencies: Riverpod, SharedPreferences, Isar(?) init, design tokens
- User flows: cold start, warm resume, deep link entry
- Existing tests: typically minimal (`test/widget_test.dart` smoke)
- Missing tests: cold-start failure (storage unavailable), error-zone capture, async init ordering
- Bad path candidates: uncaught zone errors, race between `runApp` and async pre-init, missing `ensureInitialized`, provider overrides leaking between tests

#### 1.2 Routing (go_router)
- Key files: `lib/navigation/`, route definitions, redirect logic
- Responsibility: declarative routes, deep links, share-intent landing, guards
- Dependencies: go_router, Riverpod auth/onboarding state
- User flows: app open → home → reader, share-sheet import → reader, settings
- Existing tests: likely sparse
- Missing tests: stale route extras after kill/restore, redirect loops, unknown route fallback
- Bad path candidates: passing non-serializable `extra`, double-pop, back-stack desync after share intent, route arguments stale after process death

#### 1.3 Lifecycle & app state
- Key files: `WidgetsBindingObserver` usages, pacing pause-on-background
- Responsibility: pause pacing on background, resume safely, save progress
- Dependencies: ORP engine, persistence
- Bad path candidates: timer not cancelled on pause, double-resume, save dropped if killed during write

---

### 2. Reading Engine and Pacing
#### 2.1 ORP/per-word pacing
- Key files: `lib/features/reading/` engine, scheduler, WPM controller
- Responsibility: word scheduling, adaptive timing, dwell/comma weighting
- Dependencies: `Ticker`/`Timer`, settings provider, reduced-motion
- User flows: start/pause/resume, WPM dial, calibrated swipes
- Existing tests: unit tests on pacing math (assumed)
- Missing tests: tick drift under load, isolate stutter, reduced-motion override, end-of-document boundary
- Bad path candidates: ticker not disposed on route pop, off-by-one at last word, division by zero at WPM=0, negative dwell from corrupt config

#### 2.2 ContextReveal (2-state)
- Key files: `lib/features/reading/widgets/context_reveal*.dart`
- Bad path candidates: state desync with pacing engine, animation continuing after dispose, reduced-motion path skipped

#### 2.3 3D cube viewport
- Key files: `lib/three_d/`
- Bad path candidates: GPU/transform cost on low-end Android, no-shadow path when design tokens missing, gesture conflict with system back, accessibility focus traversal broken in 3D

---

### 3. Content Ingestion and Import
#### 3.1 Universal share sheet & intents
- Key files: `ios/ShareExtension/`, `android/.../runthru/` share receiver, Dart bridge
- Responsibility: receive URL/text/file from OS, hand to ContentNormaliser
- Dependencies: platform channels, file URIs, MIME detection
- User flows: share from Safari/Chrome, share PDF from Files
- Existing tests: hard to unit-test; integration likely thin
- Bad path candidates: duplicate intent on cold start + warm resume, lost intent if app killed mid-handoff, file URI without read permission (Android scoped storage), oversized payload

#### 3.2 ContentNormaliser
- Key files: `lib/features/content/services/`
- Bad path candidates: empty string, non-UTF8 text, HTML with scripts, mixed encodings, MIME spoofing

#### 3.3 Instapaper integration
- Key files: `lib/features/content/services/instapaper_client.dart`, `instapaper_auth_service.dart`, `instapaper_sync_queue.dart`, providers
- Dependencies: xAuth, dio, secure storage
- User flows: login, list bookmarks, fetch article, mark read, offline queue
- Existing tests: `test/features/content/providers/instapaper_bookmarks_provider_test.dart`, `test/features/content/services/instapaper_client_test.dart`
- Missing tests: token refresh failure, 429 backoff, sync queue replay after crash, partial article body
- Bad path candidates: token stored in SharedPreferences vs secure storage, queue corruption, duplicate writes on retry, clock skew on xAuth nonce

#### 3.4 Clipboard / text import
- Bad path candidates: empty clipboard, RTL text, control chars, very large paste blocking main isolate

---

### 4. PDF / EPUB / Text Extraction
#### 4.1 PDF (pdfrx + pdfium)
- Key files: `lib/services/epub_extractor*.dart` (mis-named?), pdf-related services, `lib/services/preprocessing_queue.dart`
- Dependencies: pdfrx FFI (main isolate only per Hard Rule 10)
- Bad path candidates: encrypted/password PDF, malformed XRef, fonts missing, huge page count OOM, FFI invoked off main isolate

#### 4.2 EPUB extractor
- Key files: `lib/services/epub_extractor.dart`, test `test/services/epub_extractor_test.dart` (modified)
- Bad path candidates: DRM'd EPUB, broken manifest, missing spine items, images-only chapters, encoding declared but wrong

#### 4.3 Preprocessing queue
- Key files: `lib/services/preprocessing_queue.dart`
- Bad path candidates: queue not drained on dispose, isolate spawn fail on low-memory devices, duplicate enqueue, ordering bug if user navigates away

---

### 5. Persistence, Bookmarks, Cache, Config
#### 5.1 Isar local storage
- Bad path candidates: schema migration on app update, write during dispose, lock contention with isolate, corrupt db on force-quit

#### 5.2 SharedPreferences (analytics/stats per CLAUDE.md)
- Bad path candidates: key collisions, no atomicity across multi-key writes, large blobs slowing startup

#### 5.3 Bookmarks / reading progress
- Key files: `lib/features/content/services/reading_progress_sync.dart`
- Bad path candidates: progress saved after process death misses last tick, sync conflict with Instapaper "mark read", off-by-one in word index when document re-extracted

#### 5.4 Secure storage / auth tokens
- Bad path candidates: keychain access denied on iOS first-launch, Android keystore reset on backup restore

---

### 6. UI, Gestures, Accessibility, Design Tokens
#### 6.1 Design-token compliance
- Bad path candidates: raw `Color(0xFF...)`, hardcoded `TextStyle`, hardcoded `BoxDecoration` shadow (violates Hard Rules 1–3)

#### 6.2 Reduced motion & a11y
- Bad path candidates: animation paths not gated by `isReducedMotion`, touch targets <44pt iOS / <48dp Android, focus order broken in 3D viewport, semantics labels missing, color-only state indication

#### 6.3 Gestures (calibrated swipes, WPM dial, hints)
- Bad path candidates: gesture conflict with go_router back swipe on iOS, dial overshoot, swipe threshold drift after calibration, hint loop never dismissed

#### 6.4 Loading indicators
- Bad path candidates: raw `CircularProgressIndicator`/`LinearProgressIndicator`/`RefreshIndicator` (Hard Rule 7)

---

### 7. Platform Integrations
#### 7.1 Android
- Key files: `android/app/.../com/runthru/`, `android/settings.gradle`, `android/gradle.properties`
- Bad path candidates: applicationId mismatch with Play Console, share intent filter too broad/narrow, FileProvider auth missing for shared PDFs, scoped-storage failures on Android 13+

#### 7.2 iOS
- Key files: `ios/Runner.xcodeproj/project.pbxproj`, `ios/ShareExtension/`
- Bad path candidates: Share Ext bundle id drift from `com.mgmacri.runthru.ShareExtension`, App Group missing for sharing files, ATS blocking Instapaper http, background mode mismatch

#### 7.3 Desktop (linux/macos/windows)
- Bad path candidates: features assuming mobile-only (share sheet, secure storage), window resize breaking 3D viewport, missing platform channel implementations crashing on launch

---

### 8. Analytics, Purchases, Notifications, External Services
#### 8.1 Analytics + Stats screen
- Bad path candidates: PII leaking into events (ethical violation), SharedPreferences race on concurrent increments, stats overflow at long durations

#### 8.2 Purchases (if scaffolded for M1.5)
- Bad path candidates: accessibility features behind paywall (ethical violation), receipt validation skipped on restore, double-charge on retry

#### 8.3 Notifications
- Bad path candidates: permission denied flow, scheduled notifications surviving uninstall on Android

---

### 9. Tests and Integration Coverage
- Key files: `test/`, `integration_test/`
- Missing: integration tests for share intent, Instapaper offline replay, PDF stress, lifecycle pause/resume, deep-link cold-start
- Bad path candidates: tests relying on real network/clock, mocktail leaks across tests, golden tests not run under reduced-motion

---

### 10. CI, Release, Docs, Scripts
- Key files: `.github/workflows/`, `scripts/`, Fastlane (`ios/fastlane`?), Codemagic config, `scripts/verify_ai_parity.sh`, `scripts/fix_runthru_refs.dart`
- Bad path candidates: Fastlane match cert expiry, bundle id drift between Xcode/Info.plist/entitlements, dart-defines missing in release builds, codesign skipped silently, Android signing config reading from missing env vars, `flutter build ios --no-codesign` masking real signing failures

---

## 2. Bad Path Risk Table

| ID | Section | Bad Path | Trigger | Expected Safe Behavior | Current Risk | Evidence to Inspect | Severity | Confidence | Test Needed | Suggested Fix Direction |
|---|---|---|---|---|---|---|---|---|---|---|
| R01 | 1.1 | Async pre-init race with `runApp` | Cold start on slow device | Splash until init complete | Possible crash / null provider | `lib/main.dart`, root provider overrides | High | Likely | Widget test with delayed init mock | Gate UI on a single `AsyncValue` boot provider |
| R02 | 1.2 | Stale `extra` after process death | Share intent → OS kills app → relaunch | Re-derive from persisted state | Bad route args / crash | `lib/navigation/`, go_router config | High | Likely | Integration test simulating restore | Persist intent payload, never store non-serializable in `extra` |
| R03 | 1.3 | Pacing timer not cancelled on dispose | Navigate away mid-reading | Timer cancelled | Memory/CPU leak, ghost ticks | Reading engine `dispose()` | High | Needs inspection | Unit test with fake clock | Cancel in `dispose`, assert in test |
| R04 | 2.1 | WPM=0 or negative dwell | Corrupt SharedPreferences | Clamp to safe min | Div-by-zero / infinite loop | WPM provider, settings | Medium | Likely | Unit test malformed prefs | Validate on read, default + log |
| R05 | 2.1 | Off-by-one at last word | Reach end of doc | Show completion UI | Index out-of-range | Pacing scheduler | High | Possible | Unit test boundary | Bound-check + completion state |
| R06 | 2.2 | ContextReveal animates after dispose | Pop during reveal | No-op after dispose | setState-after-dispose | Reveal widget | Medium | Likely | Widget test rapid pop | `mounted` guard / `Listenable` |
| R07 | 2.3 | 3D viewport stutters on low-end Android | Long doc on API 28 device | Degrade gracefully | Jank, dropped frames | `lib/three_d/` | Medium | Possible | Manual perf test | Reduced-motion fallback path |
| R08 | 3.1 | Duplicate share intent | Cold + warm both deliver | Idempotent handoff | Article opened twice | Share receivers + Dart bridge | High | Likely | Integration test | Dedupe by intent id/hash |
| R09 | 3.1 | Lost intent if killed mid-handoff | OS kills before Dart ready | Intent re-delivered on relaunch | Article never imported | Platform channels | High | Needs inspection | Manual + integration | Persist intent until ack |
| R10 | 3.1 | Android file URI without read perm | Scoped storage PDF share | Copy into app dir first | FileNotFound | Share handler | High | Likely | Manual Android 13/14 | `takePersistableUriPermission` or copy |
| R11 | 3.2 | Non-UTF8 / mixed encoding text | Paste from legacy source | Detect & decode | Mojibake or crash | ContentNormaliser | Medium | Likely | Unit test fixtures | charset_converter or fallback |
| R12 | 3.3 | Instapaper token in SharedPreferences | Login | Stored in secure storage | Token leak via backup | `instapaper_auth_service.dart` | Critical | Needs inspection | Static check | Move to `flutter_secure_storage` |
| R13 | 3.3 | Sync queue replay duplicates | Crash mid-replay | Idempotent ops | Duplicate marks/writes | `instapaper_sync_queue.dart` | High | Likely | Unit test crash/replay | Op-id + server-side idempotency |
| R14 | 3.3 | 429/5xx backoff missing | API rate limit | Exponential backoff | Hammering API, ban risk | `instapaper_client.dart` | High | Needs inspection | Mocked-dio unit test | Retry with jitter, cap |
| R15 | 3.3 | xAuth nonce/clock skew | Device clock wrong | Server time fallback | Login fails silently | Auth service | Medium | Possible | Unit test with skewed clock | Surface error, retry |
| R16 | 4.1 | Encrypted/password PDF | Open shared PDF | Friendly error | Crash or blank | pdfrx wrapper | High | Likely | Unit test fixture | Detect + UX prompt |
| R17 | 4.1 | pdfrx invoked off main isolate | Refactor mistake | Main-isolate only | FFI crash | Calls into pdfrx | Critical | Needs inspection | Static grep + assert | Wrap in main-isolate guard |
| R18 | 4.1 | Huge PDF OOM | 500-page doc | Stream/page-on-demand | OOM kill | Extractor + preprocessing | High | Likely | Integration on low-RAM device | Lazy extraction |
| R19 | 4.2 | EPUB DRM/malformed manifest | Library import | Clear error | Crash or empty reader | `epub_extractor.dart` | Medium | Likely | Fixture tests | Validate + reject |
| R20 | 4.3 | Preprocessing queue leak | Navigate away mid-process | Cancel pending | CPU/battery drain | `preprocessing_queue.dart` | Medium | Likely | Unit test cancel | Cancellation tokens |
| R21 | 5.1 | Isar schema migration on update | Version bump | Migrate or rebuild | Crash on launch | Isar setup | Critical | Needs inspection | Upgrade-from-prev-build test | Migration plan + fallback |
| R22 | 5.2 | SharedPreferences non-atomic stats | Concurrent writes | Single transaction | Lost increments | Stats provider | Medium | Likely | Concurrency unit test | Single-flight writer or Isar |
| R23 | 5.3 | Reading progress dropped on kill | OS kills during read | Save every N words | Lost position | progress sync | High | Likely | Integration: kill mid-read | Throttled persistent writes |
| R24 | 5.4 | Keychain denial on first launch | iOS prompts | Retry/fallback | Login loop | Secure storage usage | Medium | Possible | Manual iOS | Defer access until needed |
| R25 | 6.1 | Raw `Color(0xFF...)` in widgets | Drift from tokens | Tokens only | Hard Rule 1 violation | grep across `lib/` | Low | Likely | Lint/CI grep | Add custom_lint rule |
| R26 | 6.2 | Animation without `isReducedMotion` | New widget added | Always check | Accessibility violation | Animation call sites | High | Likely | Golden test reduced-motion | Helper + lint |
| R27 | 6.2 | Touch target <44pt | Compact controls | Min size enforced | Hard Rule 12 | Buttons in reader UI | Medium | Possible | Widget test min-size | Wrap in `ConstrainedBox` |
| R28 | 6.3 | Gesture conflict with iOS back swipe | Edge swipes | One wins, documented | User confusion | Gesture detectors | Medium | Likely | Manual iOS | Reserve edge inset |
| R29 | 6.4 | Raw progress indicator usage | New code | Custom tokenized indicator | Hard Rule 7 | grep | Low | Likely | CI grep | Replace with shared widget |
| R30 | 7.1 | applicationId/Play Console drift | Release | Match | Upload rejected | `android/app/build.gradle` | High | Needs inspection | CI assertion | Source-of-truth file |
| R31 | 7.2 | Share Ext bundle id drift | Xcode refactor | `com.mgmacri.runthru.ShareExtension` | Ext doesn't appear | `ios/ShareExtension/Info.plist`, pbxproj | High | Likely | Fastlane verify | Pin in script, assert in CI |
| R32 | 7.2 | App Group missing for shared files | Share Ext writes file | Read by app | Article not imported | Entitlements | High | Likely | Manual iOS | Add App Group + verify |
| R33 | 7.2 | ATS blocks Instapaper HTTP | API call | HTTPS only | Network failure | `Info.plist` | Medium | Needs inspection | Integration | Confirm HTTPS endpoints |
| R34 | 7.3 | Desktop platform channel missing | Run on Linux | Feature-flag off | Crash | platform-channel call sites | Medium | Possible | Smoke test linux/macos | Capability checks |
| R35 | 8.1 | PII in analytics events | New event added | Hashed/no content | Privacy violation | analytics service | Critical | Needs inspection | Static review | Event schema + lint |
| R36 | 8.2 | Accessibility feature paywalled | Settings gate | Always free | Ethical violation | settings + purchases | Critical | Needs inspection | Audit + test | Hard-code as free |
| R37 | 9 | Tests rely on real network/clock | New Instapaper test | Mocked | Flaky CI | new test files in `test/features/content/` | Medium | Likely | CI run | mocktail + fake_async |
| R38 | 10 | dart-defines missing in release | Codemagic build | Required defines enforced | Misconfigured release | Codemagic + Fastlane | High | Likely | CI assertion | Fail-fast if missing |
| R39 | 10 | `--no-codesign` masks signing issues | iOS CI | Real signing step exists too | Bad release artifact | workflow files | High | Likely | Fastlane verify (M1.5 step 4) | Ensure signed build runs |
| R40 | 1.3 | Background pacing keeps timers | Phone call interrupts | Pause on `inactive` | Battery drain | lifecycle observer | Medium | Likely | Widget test lifecycle | Pause on `inactive`+`paused` |
| R41 | 3.3 | New file `reading_progress_sync.dart` untested | Conflict resolution | Deterministic merge | Data loss | the file itself | High | Needs inspection | Unit tests | Document merge rule, test it |
| R42 | 1.2 | Deep link to deleted bookmark | User taps stale link | Fallback to library | Crash or blank | router redirect | Medium | Likely | Integration | 404 route |
| R43 | 6.2 | Color-only state (CVD) | New indicator | Shape+label too | Hard Rule 11/13 | indicator widgets | Medium | Likely | A11y review | Add icon/label |
| R44 | 3.1 | Oversized share payload | Huge text shared | Stream/limit | OOM | share receivers | Medium | Possible | Manual | Size cap + warning |
| R45 | 9 | No integration test for cold-start deep link | — | Has one | Regressions invisible | `integration_test/` | High | Likely | Add test | New integration test |

---

## 3. Test-Hunting Matrix

**Section 1 — Runtime/Nav**
- Unit: boot provider states (R01); router redirect rules (R02, R42)
- Widget: error-zone capture; lifecycle pause (R40)
- Integration: cold-start deep link (R45), restore-from-kill (R02)

**Section 2 — Reading/Pacing**
- Unit: WPM clamp (R04), end-of-doc boundary (R05), tick cadence with fake_async (R03)
- Widget: ContextReveal dispose (R06), reduced-motion path (R26)
- Golden: reduced-motion vs default
- Manual: 3D viewport on low-end Android (R07)

**Section 3 — Ingestion**
- Unit: ContentNormaliser fixtures incl. non-UTF8 (R11); Instapaper client mocked-dio incl. 429 (R14); auth nonce/clock (R15); sync queue replay (R13)
- Integration: share intent dedupe and replay (R08, R09); Android scoped storage URI copy (R10); oversize payload (R44)
- Manual: Safari/Chrome/Files share on iOS; Android 13/14 share

**Section 4 — Extraction**
- Unit: encrypted PDF (R16), DRM/malformed EPUB (R19), cancellation (R20)
- Static: grep that pdfrx is only called on main isolate (R17)
- Integration: large-PDF memory (R18)

**Section 5 — Persistence**
- Unit: Isar migration from prior schema (R21); SharedPreferences concurrency (R22); progress merge (R41)
- Integration: kill mid-read, verify resume (R23)
- Manual iOS: keychain first-launch denial (R24)

**Section 6 — UI/A11y**
- Static (CI grep): raw colors / text styles / shadows / progress indicators (R25, R29)
- Widget: touch-target min size (R27)
- Golden: reduced-motion (R26); CVD shape/label (R43)
- Manual: iOS back-swipe vs custom gesture (R28)

**Section 7 — Platform**
- CI assertion: bundle ids and applicationId (R30, R31)
- Manual iOS: share extension appears, App Group write/read (R32), HTTPS endpoints (R33)
- Smoke: desktop launches without channel crash (R34)

**Section 8 — Analytics/Purchases**
- Unit: event schema redaction (R35)
- Audit + test: free-tier matrix proves a11y features unlocked (R36)

**Section 9/10 — Tests & CI**
- CI: forbid network in unit tests (R37); enforce dart-defines (R38); ensure real signing path exercised (R39)

---

## 4. Top 10 Highest-Value Bad Paths

1. **R12 — Instapaper token storage**. Critical privacy/security; touches an active surface (new auth service file).
2. **R36 — Accessibility paywalling regression**. Critical ethical commitment; M1.5 is launch readiness — easy to break here.
3. **R35 — PII in analytics events**. Critical privacy; M1.5 step 1 just changed analytics surface.
4. **R21 — Isar migration on upgrade**. Critical data loss class; bumping `2.0.0+15` will hit this for existing users.
5. **R31/R32 — iOS Share Ext bundle-id and App Group**. High; M1.5 step 4 (Fastlane verify) is current step — must be green before release.
6. **R09 — Lost share intent across cold start**. High; share-in is a core ingest path.
7. **R23 — Reading progress dropped on kill**. High; directly contradicts "Completion, not speed" positioning.
8. **R17 — pdfrx off main isolate**. Critical crash class; Hard Rule 10 exists precisely because this has been a footgun.
9. **R13 — Instapaper sync queue duplicate replay**. High; user-visible data correctness.
10. **R39 — `--no-codesign` masking signing failures**. High; release-blocker risk for M1.5 step 4.

**Top 5 missing tests (highest exposure)**

1. Integration test: kill app mid-read, verify resume position within N words (R23, R41).
2. Integration test: share intent — cold start, warm resume, dedupe (R08, R09).
3. Unit test: Instapaper sync queue replay with simulated crash (R13).
4. Upgrade test: launch with previous Isar schema fixture (R21).
5. Golden/widget test: reduced-motion path on each animated widget (R26).

**Files most likely to hide lifecycle/race bugs**
- `lib/features/reading/` engine + `WidgetsBindingObserver` users
- `lib/services/preprocessing_queue.dart`
- `lib/features/content/services/instapaper_sync_queue.dart`
- `lib/features/content/services/reading_progress_sync.dart` (new, untested)

**Files most likely to hide platform/import bugs**
- `ios/ShareExtension/Info.plist`, `ShareViewController.swift`, `Runner.xcodeproj/project.pbxproj`
- `android/app/src/main/kotlin/com/runthru/` share receiver
- `lib/features/content/services/instapaper_client.dart`

**Files most likely to hide data-loss bugs**
- Isar schema + migration setup (wherever `Isar.open` lives)
- `reading_progress_sync.dart`
- `instapaper_sync_queue.dart`
- SharedPreferences-backed stats provider

---

## 5. Recommended Audit Order

1. **Read CLAUDE.md hard rules and M1.5 context** — establish invariants.
2. **Boot + routing**: `lib/main.dart`, `lib/navigation/` — confirm async init pattern and route schema. Drives R01/R02/R42.
3. **Reading engine lifecycle**: pacing dispose, lifecycle observer, ContextReveal — R03/R05/R06/R40.
4. **Persistence layer**: Isar open/migration, SharedPreferences stats, secure storage — R12/R21/R22/R24.
5. **Instapaper trio**: `instapaper_auth_service.dart`, `instapaper_client.dart`, `instapaper_sync_queue.dart`, plus new `reading_progress_sync.dart` — R12/R13/R14/R15/R41.
6. **Extraction**: pdfrx wrappers + `epub_extractor.dart` + `preprocessing_queue.dart` — R16/R17/R18/R19/R20.
7. **Share intents**: iOS Share Extension + Android receiver + Dart bridge — R08/R09/R10/R32/R44.
8. **Platform configs**: `Info.plist`, entitlements, `build.gradle`, signing — R30/R31/R33/R38/R39.
9. **Design-token & a11y compliance sweep** (grep-driven): R25/R26/R27/R29/R43.
10. **Analytics + purchases ethics audit**: R35/R36.
11. **CI/Fastlane verify** (M1.5 step 4 deliverable): R38/R39.
12. **Test gap fill** per Top 5.

---

## 6. First Patch Candidates

Small, high-confidence, low-risk improvements worth doing surgically:

1. **CI grep gate (Hard Rules 1/2/3/7)**: add a script that fails on `Color(0xFF`, hardcoded `TextStyle(`, `BoxShadow(`, `CircularProgressIndicator(`, `LinearProgressIndicator(`, `RefreshIndicator(` outside design-token files. Catches R25/R29 with near-zero risk.
2. **WPM/dwell clamp on read** (R04): a single validator at the settings provider read site; default-and-log on invalid.
3. **`mounted` guard in ContextReveal `setState` paths** (R06): one-line guards where async completion calls `setState`.
4. **Bundle-id assertion script for Fastlane verify** (R31): a tiny script that diffs Xcode pbxproj + Info.plists against the documented IDs in CLAUDE.md. Directly supports M1.5 step 4.
5. **dart-defines presence check at app boot** (R38): if a required define is missing in release, fail loudly with a tokenized error screen.
6. **Static-grep test that pdfrx imports only appear in main-isolate files** (R17): cheap insurance for Hard Rule 10.
7. **Idempotency key on Instapaper sync ops** (R13): add an op-id when enqueuing; safe even before full replay tests land.
8. **Lifecycle pause on `inactive` (not just `paused`)** (R40): one-line change in the reading lifecycle observer.
9. **Forbid network in unit tests** (R37): a test-setup helper that overrides dio with a mock by default; existing tests already use mocktail.
10. **Add a `reading_progress_sync.dart` smoke unit test** (R41): even a single deterministic-merge test is a meaningful guardrail for a brand-new untested file.

> Nothing above edits generated `.g.dart`, rebuilds engines, or changes architecture. Each is one file or one CI script.
