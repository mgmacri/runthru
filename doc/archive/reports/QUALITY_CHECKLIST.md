# RunThru — Pre-Launch Quality Audit Checklist
> This checklist is a structured companion to `FABLE5_PROMPT.md`. 
> Fable 5 should work through every item, mark it, and include the completed version in `LAUNCH_READINESS.md`.

---

## A — Code Quality

### A1 — Static Analysis
- [ ] `dart analyze --fatal-infos` returns 0 issues
- [ ] No `// ignore:` suppression comments added without a written justification comment on the line above
- [ ] No unawaited `Future`s in widget lifecycle methods (`initState`, `dispose`, `build`)
- [ ] No unawaited `Future`s in provider `build()` methods
- [ ] `flutter test` passes with 0 failures, 0 errors

### A2 — Dead Code
- [ ] No unused imports in any `lib/` file
- [ ] No unreachable `else` branches or `switch` cases
- [ ] No commented-out code blocks (remove or convert to `// TODO:` with ticket)

### A3 — Complexity
- [ ] No method in `lib/core/` has cyclomatic complexity > 10
- [ ] `parallax_reading_screen.dart`'s `build()` method contains no business logic — only widget composition
- [ ] `WordTimerNotifier` methods each have a single responsibility

### A4 — Conventions
- [ ] All files in `lib/` use `library;` directive at the top (Dart convention)
- [ ] All public symbols have `///` doc comments
- [ ] No `print()` or `debugPrint()` in any `lib/` file — only `appLog()`
- [ ] All Riverpod providers are declared at file scope, not inside classes
- [ ] `@riverpod` generated `.g.dart` files are up to date (run `dart run build_runner build --delete-conflicting-outputs`)

---

## B — Accessibility (WCAG 2.2 AA + Neurodivergent)

### B1 — Semantics Labels
- [ ] Every `IconButton` has `tooltip` set (Flutter auto-creates Semantics from tooltip)
- [ ] Every `GestureDetector` wrapping a meaningful action has `Semantics(label: ..., button: true)` parent
- [ ] `WpmDial3D` has `Semantics(label: 'Reading speed: X words per minute', slider: true)`
- [ ] `ProgressHairline3D` / `_ProgressRail` has `Semantics(label: 'X percent complete')`
- [ ] `ContextRevealOverlay` has `Semantics(liveRegion: true, label: 'Context: [sentence]')`
- [ ] RSVP word display has `Semantics(liveRegion: true, label: currentWord)`
- [ ] All navigation items have `Semantics(label: ..., selected: isSelected)`
- [ ] `RunThruProgressRing` announces `'X percent read'`
- [ ] `RunThruSegmentedFilter` segments have `Semantics(inMutuallyExclusiveGroup: true, selected: ...)`

### B2 — Touch Targets
- [ ] All interactive elements are ≥ 48×48 dp
- [ ] `RunThruHeaderIconButton` is 44×44 minimum (check `_ReaderHeaderRow` back button)
- [ ] WPM dial long-press area is ≥ 48×48
- [ ] All bottom-tray buttons have minimum 48×48 hit area

### B3 — Text Scaling
- [ ] No hard-coded `fontSize` values in any widget — all via `RunThruTypography.*`
- [ ] Reading stage font size slider uses `MediaQuery.textScaleFactor` as a baseline multiplier
- [ ] Shell text does not overflow at `textScaleFactor: 2.0`

### B4 — Reduced Motion
- [ ] `isReducedMotion(context)` checked before: word flash animation, CR overlay animation, parallax room motion, WPM dial animation, cube transition, wall fold transition, hint overlay animation
- [ ] All `Duration` values for animations have a `reduced ? Duration.zero : const Duration(...)` pattern
- [ ] `ParallaxRoom` stops all motion when `reduceMotion: true` (not just slows down)

### B5 — Color and Contrast
- [ ] `wcag_contrast.dart` used to validate anchor color vs. stage background — must be ≥ 4.5:1 at all theme settings
- [ ] `contrast_audit_test.dart` passes
- [ ] `anchor_contrast_test.dart` passes
- [ ] Contrast warning UI shows when user picks a low-contrast anchor color
- [ ] Information is never conveyed by color alone (e.g., error states have icon + text, not just color change)

### B6 — Screen Reader Flow
- [ ] TalkBack/VoiceOver can navigate the reading screen without looking at the display
- [ ] Library screen announces book titles and progress
- [ ] Settings screen announces current values of all controls
- [ ] Onboarding overlays are announced as `liveRegion: true`

### B7 — Font
- [ ] `AtkinsonHyperlegible` is the first font in `RunThruTypography.availableFonts`
- [ ] `AppConfig.readingFontFamily` defaults to `'AtkinsonHyperlegible'`

---

## C — Security

### C1 — Credentials
- [ ] Zero matches for hardcoded credential patterns in `lib/`: `grep -rn "consumer_key\|consumer_secret\|api_key\s*=\s*['\"]" lib/`
- [ ] `INSTAPAPER_CONSUMER_KEY` and `INSTAPAPER_CONSUMER_SECRET` accessed only via `String.fromEnvironment()`
- [ ] Google OAuth client IDs are not in source — only in `dart_defines/` or environment
- [ ] No `.p12`, `.p8`, `.pem`, `.keystore`, `.jks` files tracked in git
- [ ] `AuthKey_*.p8` at repo root: **flag in report** if present (do not delete)

### C2 — Data Privacy
- [ ] Clipboard content body is never written to logs
- [ ] Document text (extracted from PDF/EPUB) is never transmitted over the network
- [ ] Instapaper sync only sends reading progress (position), not document content
- [ ] Google Drive only downloads file bytes transiently — not persisted to external storage

### C3 — Network Security
- [ ] `android/app/src/main/AndroidManifest.xml` does not set `android:usesCleartextTraffic="true"` without a specific allow-list
- [ ] `ios/Runner/Info.plist` does not contain `NSAllowsArbitraryLoads: true`
- [ ] All API calls use HTTPS endpoints

### C4 — Secrets in CI
- [ ] `android/fastlane/Fastfile` has zero hardcoded passwords or API keys
- [ ] `ios/fastlane/Fastfile` has zero hardcoded passwords or API keys
- [ ] `codemagic.yaml` references environment groups, not inline secrets

---

## D — Architecture

### D1 — Separation of Concerns
- [ ] No business logic in `build()` methods across all `lib/screens/`
- [ ] No `ref.read()` inside `build()` — only `ref.watch()` or `ref.listen()`
- [ ] `WordTimerNotifier` does not import any widget classes
- [ ] `ContextRevealNotifier` does not import any widget classes

### D2 — Provider Hygiene
- [ ] `keepAlive: true` is only on providers that hold persistent state (config, auth, library)
- [ ] Transient reading session providers do NOT use `keepAlive`
- [ ] No provider reads another provider via `ref.read()` inside `build()` (use `ref.watch()`)

### D3 — Memory / Resource Management
- [ ] `PreprocessingQueue` disposes all `StreamController` instances on unmount
- [ ] `MotionParallaxController` cancels sensor subscriptions in `dispose()`
- [ ] `GradientSweepEngine` cancels its timer in `dispose()`
- [ ] `WordTimerNotifier` cancels its periodic timer in `dispose()`
- [ ] All `AnimationController` instances in widgets are disposed in `dispose()`

### D4 — Widget Tree
- [ ] `RepaintBoundary` wraps `ParallaxRoomPainter`
- [ ] `RepaintBoundary` wraps `CubeViewportPainter`
- [ ] Word display widget subtree uses `const` wherever the word content is stable

---

## E — Release Readiness

### E1 — Error Handling
- [ ] `FlutterError.onError` is configured in `main.dart`
- [ ] `runZonedGuarded` or zone error handler wraps `runApp()`
- [ ] All `async` operations in screens use try/catch with typed error display
- [ ] No unhandled `Future` can crash the app silently

### E2 — Build
- [ ] `flutter build appbundle --release --dart-define=INSTAPAPER_CONSUMER_KEY=test --dart-define=INSTAPAPER_CONSUMER_SECRET=test` succeeds (substitute real values in CI)
- [ ] `flutter build ipa --release` succeeds (in Codemagic)
- [ ] No debug banners visible (`debugShowCheckedModeBanner: false` in `MaterialApp`)
- [ ] No `kDebugMode` gates around production-required code

### E3 — Fastlane
- [ ] `android/fastlane/Fastfile` has `:beta` lane targeting `track: "internal"`
- [ ] `android/fastlane/Fastfile` has `:release` lane
- [ ] `ios/fastlane/Fastfile` has `:beta` lane using `upload_to_testflight`
- [ ] `ios/fastlane/Fastfile` has `:release` lane
- [ ] Both Appfiles use correct bundle IDs (`com.runthru.app` / `com.mgmacri.runthru`)
- [ ] `android/fastlane/README.md` created with env var table
- [ ] `ios/fastlane/README.md` created with env var table

### E4 — Privacy
- [ ] `doc/legal/privacy_policy.md` exists
- [ ] Effective date is populated
- [ ] Zero "we may" / "we might" matches: `grep -c "we may\|we might" doc/legal/privacy_policy.md`
- [ ] Zero ableist language
- [ ] All data flows described
- [ ] Instapaper identified as only outbound data connection

### E5 — Verification
- [ ] `scripts/verify_release_readiness.sh` exists and passes

---

## F — Neurodivergent UX Audit

These are product-level checks specific to the app's mission:

- [ ] Pause-and-auto-rewind works correctly (3-word rewind, clamp to 0)
- [ ] ContextReveal enters sentence view on swipe-up and resumes from correct word position
- [ ] CR resume does NOT auto-rewind (only regular pause→play rewinds)
- [ ] `AtkinsonHyperlegible` is the default font and is selectable in settings
- [ ] Reading goal presets are accessible from onboarding and settings
- [ ] All animations can be disabled via reduced motion setting
- [ ] WPM dial long-press is discoverable with a hint overlay
- [ ] `focusModeEnabled` removes all chrome and shows only the reading word + minimal back button
- [ ] Onboarding hint overlays have `Semantics(liveRegion: true)` for screen reader users

---

## Summary Scorecard

Fill this in after completing the audit:

| Category | Items | Passed | Failed | Deferred |
|----------|-------|--------|--------|---------|
| A — Code Quality | 16 | | | |
| B — Accessibility | 25 | | | |
| C — Security | 12 | | | |
| D — Architecture | 12 | | | |
| E — Release Readiness | 20 | | | |
| F — Neurodivergent UX | 10 | | | |
| **Total** | **95** | | | |

**Launch gate: All critical items (A1, B1–B5, C1–C3, E1–E4) must be ✅ before submitting to internal testing.**
