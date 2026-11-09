# RunThru — Launch Readiness Report
**Generated**: 2026-06-10 15:54 PDT
**Model**: claude-fable-5
**Prepared by**: Automated pre-launch audit + remediation

## Summary Verdict
**READY FOR INTERNAL TESTING**

One known gate for GA (not internal testing): `PurchaseService.purchasePremium()`
is a stub that grants premium unconditionally (P-4, FIXME'd in source). It must
be replaced with StoreKit/Play Billing + server-side receipt validation before
public launch.

## Changes Made This Session

### Phase 1 — Audit findings
**Critical (8)**
1. Reading-screen chrome buttons (`_HeadBtn`: back / fullscreen / font) were bare
   `GestureDetector`s — no `Semantics`, 38×38dp targets.
2. Focus-mode back arrow — no `Semantics`, ~36dp target.
3. `FinishedRangeOverlay` action buttons — no `Semantics`, ~40dp height, no
   completion announcement.
4. No `Semantics(liveRegion:)` on the RSVP stage word display (2D or 3D path).
5. WPM dial had zero semantics — inoperable via assistive technology.
6. Shared `http://` links were fetched over cleartext (Dart `HttpClient`
   bypasses the platform cleartext blocks).
7. Reading content (first words of documents, incl. clipboard) was written to
   the in-app diagnostic log.
8. Raw `Color(0xFFBF4733)` declared outside `tokens.dart`, violating the
   repo's single-source-of-color rule.

**Major**
9. Whole-screen rebuild on every word advance (top-level `progress` watch +
   unselected `wordTimerProvider` watches inside the multi-word mode views).
10. Speed-selector chips at 44dp height (< 48dp Android tap-target guideline);
    `RunThruSegmentedFilter` chips at 40dp.
11. ContextReveal onboarding copy described the removed v3 tier progression.
12. iOS Fastlane had no App Store Connect API key wiring.
13. Android Fastlane used a file-path service-account key instead of inline
    `json_key_data` from the environment.
14. `PurchaseService.purchasePremium()` stub (pre-existing P-4; deferred, see
    Known Remaining Issues).
15. Stage word ignored the system text-size setting; tour-target measurement
    and word render disagreed about scaling.
16. Dead code: `_flatPainterPool` in the reading screen; `PdfCard3D` widget
    referenced nowhere.
17. Focus-mode toggle `Switch` had no semantic label (caught by the new
    guideline tests).

**Minor**
18. Stale doc comment in `dynamic_font_size.dart`.
19. `/read-legacy` route unreachable from UI (kept deliberately as a deep-link
    fallback).
20. Decorative chrome labels pinned to `TextScaler.noScaling` (intentional,
    documented).

**Verified clean in audit (no action needed)**: secrets only via
`String.fromEnvironment` with presence-only logging and an `InstapaperRedactor`;
no `print`/`debugPrint` in lib/; no `.p8` files anywhere in the repo; platform
cleartext/ATS defaults intact (no `usesCleartextTraffic`, no
`NSAllowsArbitraryLoads`); `RepaintBoundary` isolates `ParallaxRoom`,
`WordDisplay3D`, `CubeViewport`, and the WPM dial painter; anchor-contrast
safety net draws a shadow behind the ORP glyph when contrast < 4.5:1 (both
painters); AtkinsonHyperlegible is the default reading font; reduced motion is
honored across overlays, dial, room, nav, and word-flash selection; zone +
`FlutterError.onError` + `PlatformDispatcher.onError` wired in `main.dart`;
all bug-backlog items (BUG-1…6, P-1…P-8) verified present in code; word timer
is autoDispose; config notifier serializes mutations via an async mutex;
Android signing uses `key.properties` indirection.

### Phase 2–3 — Fixes applied
| File | Change |
|------|--------|
| `lib/design/tokens.dart` | Added `stageFocalRed` token (moved from screen-local const; 3.96:1 on stageBase — passes WCAG AA large-text for the viewport-scaled word) |
| `lib/design/a11y_tokens.dart` | **New** — `RunThruA11y.minTapTarget` (48dp) |
| `lib/design/design.dart` | Export the new a11y tokens |
| `lib/screens/parallax_reading_screen.dart` | `_HeadBtn` + focus-mode back arrow: `Semantics(button, '[Action]: [Subject]')` labels, 48dp hit areas, `excludeFromSemantics` on inner detectors; stage word live region (one node covers 2D + 3D paths); word text removed from logs (length only); `stageFocalRed` token used; v4 ContextReveal onboarding copy; speed chips to 48dp; perf — `_ProgressRail` self-watches `(progress, totalWords)`, multi-word mode views watch `currentIndex` inside a scoped `Consumer`, paused context-sentence panel watches its own index; clamped system text scale (1.0–1.3×) applied once to the stage font size; `_FocalTourTarget` measurement now matches the render; removed dead `_flatPainterPool`; root `Semantics(container, 'Reading screen')` |
| `lib/widgets/finished_range_overlay.dart` | `liveRegion` completion announcement; `Semantics(button, 'Select: …')` on all three actions; 48dp min height |
| `lib/widgets/wpm_dial_3d.dart` | Slider semantics (`Adjust: reading speed`, value, onIncrease/onDecrease by one snap step, haptic + accumulator sync); labeled dismiss scrim |
| `lib/features/content/providers/share_intent_provider.dart` | `http://` → `https://` upgrade before fetch; non-https schemes rejected; cleartext redirect hops rejected |
| `lib/widgets/pdf_card_3d.dart` | **Deleted** — zero references (library redesign superseded it) |
| `lib/core/dynamic_font_size.dart` | Corrected stale doc comment |
| `test/screens/parallax_reading_screen_test.dart` | Tour-target height slack updated for 48dp chips (intent preserved, comment added) |

### Phase 4 — Quality hardening
- **4A** — Screen-level `Semantics(container, explicitChildNodes, label)` on all
  four tabs (`home_shell.dart`), the reading screen, and the range picker;
  focus-mode `Switch` labeled `'Toggle: focus mode'` (`pause_fog_3d.dart`);
  `RunThruSegmentedFilter` chips to 48dp with de-duplicated semantics nodes
  (`runthru_shell_widgets.dart`); `ReadingRuler` confirmed `excludeSemantics`;
  `HintOverlay`, `ReadingGoalOnboardingOverlay`, `ContextRevealOverlay`
  confirmed `liveRegion`; guideline assertions
  (`androidTapTargetGuideline`, `textContrastGuideline`,
  `labeledTapTargetGuideline`) added to
  `test/widgets/runthru_shell_widgets_test.dart` and
  `test/screens/parallax_reading_screen_test.dart` — these caught and now
  guard the 40dp filter chips, the unlabeled switch, and duplicate unlabeled
  tap nodes.
- **4B** — Word-flash path now rebuilds only the word widget(s): the screen
  watches no per-word state at the top level (verified by the previously
  failing stale-panel test, now watch-scoped). `RepaintBoundary` placement
  verified. `const` hygiene enforced by `--fatal-infos` (0 issues).
- **4C** — Global error boundary: `ErrorWidget.builder` in `main.dart` replaces
  the red error screen with `CalmErrorPanel` (token-styled, Material-free,
  animation-free, live-region announced). Typed error states confirmed:
  `GoogleDriveException` kind/classification enums, `InstapaperFailureKind`.

### Phase 5 — Privacy policy
Created `doc/legal/privacy_policy.md` (effective 2026-06-10). Covers: clipboard
(local, ephemeral, explicit-action only), local files (on-device extraction +
cache), Google Drive (inbound import, secure-storage token, delete on
disconnect), Instapaper (the only outbound connection — progress sync on
pause/leave/finish, archive on completion, xAuth token in secure storage),
shared web links (HTTPS-only fetch), diagnostic logs (on-device, no reading
content), and explicit "no analytics / no crash SDK / no ads / no accounts /
no data sale" statements. Checklist verified: zero "we may/we might", zero
ableist language, plain English, contact placeholder present.

### Phase 6 — CI hardening
- `android/fastlane/Fastfile`: both lanes use
  `json_key_data: ENV["GOOGLE_PLAY_JSON_KEY_DATA"]`; `:beta` → internal track,
  `:release` promotes internal → production. `Appfile` no longer references a
  key file path.
- `ios/fastlane/Fastfile`: shared `app_store_connect_api_key` private lane
  sourced from `APP_STORE_CONNECT_API_KEY_ID` / `_ISSUER_ID` / `_KEY_CONTENT`
  (base64); `:beta` → TestFlight with `skip_waiting_for_build_processing`,
  `:release` → App Store.
- Created `android/fastlane/README.md` and `ios/fastlane/README.md` (lanes +
  required env vars + never-commit warnings).
- Created `scripts/verify_release_readiness.sh` (executable). The secret scan
  matches key/secret identifiers assigned long quoted literals, so legitimate
  OAuth parameter names mapped to dart-define values do not false-positive.

## Final Verification Results
| Check | Result |
|-------|--------|
| dart analyze --fatal-infos | ✅ 0 issues |
| flutter test | ✅ 935 tests, all pass |
| Accessibility guidelines | ✅ WCAG 2.2 AA assertions pass (tap target, contrast, labels) |
| No hardcoded secrets | ✅ Verified (grep + manual review of both API clients) |
| Privacy policy | ✅ doc/legal/privacy_policy.md |
| Android Fastlane :beta lane | ✅ internal track, env-injected key data |
| iOS Fastlane :beta lane | ✅ TestFlight, env-injected ASC API key |
| Verification script | ✅ All checks pass |

Verification ran on Flutter 3.41.2 (stable) / Dart 3.11.4. Note for this
machine: the system (Arch-packaged) Flutter at `/usr/lib/flutter` has a tool
snapshot built against Dart 3.11.4 while `/opt/dart-sdk` is 3.12.0, so
`flutter` from PATH fails with "Wrong full snapshot version". A self-contained
official SDK was installed at `~/.flutter-sdk` — use
`export PATH="$HOME/.flutter-sdk/bin:$PATH"` (or fix the system package) when
running the verification script locally. CI (GitHub Actions / Codemagic)
installs its own matched SDK and is unaffected.

## Known Remaining Issues (post-launch backlog)
1. **P-4 — purchase stub grants premium unconditionally** (`lib/services/purchase_service.dart`).
   Acceptable for the internal testing track (testers get premium features);
   **blocks GA**. Requires StoreKit 2 / Play Billing and server-side receipt
   validation.
2. **P-8 — range picker picks the first occurrence of a duplicate word**
   (documented TODO in `range_picker_screen.dart`); needs positional data from
   pdfrx's selection callback.
3. `/read-legacy` route + `ReadingScreen` retained as a deep-link fallback;
   candidates for removal once the parallax screen has a full release cycle of
   field data.
4. Decorative chrome labels (`tinyLabel` percentage/time chips) pin
   `TextScaler.noScaling` by design; the reading word honors a clamped
   1.0–1.3× system text scale. Revisit after internal-tester feedback.
5. Camera permission is declared in the Android manifest for head-tracking
   experiments while `MotionParallaxController` currently uses only
   gyro/accelerometer — consider removing the permission before GA to reduce
   Play review friction.

## Next Steps for GA
1. Submit to Play Store internal testing track via `bundle exec fastlane beta`
   (from `android/`)
2. Submit to TestFlight via `bundle exec fastlane beta` from `ios/`
3. Smoke test on physical Android + iOS device (word flash 60fps via
   `FpsProbe`, TalkBack/VoiceOver pass on the reading screen)
4. Collect internal tester feedback
5. Replace the purchase stub (P-4) and address the major backlog before public
   launch

## Files Modified
**Source**
- `lib/main.dart` (error boundary + CalmErrorPanel)
- `lib/design/tokens.dart`, `lib/design/design.dart`
- `lib/design/a11y_tokens.dart` *(new)*
- `lib/screens/parallax_reading_screen.dart`
- `lib/screens/home_shell.dart`
- `lib/screens/range_picker_screen.dart`
- `lib/widgets/finished_range_overlay.dart`
- `lib/widgets/wpm_dial_3d.dart`
- `lib/widgets/runthru_shell_widgets.dart`
- `lib/widgets/pause_fog_3d.dart`
- `lib/widgets/pdf_card_3d.dart` *(deleted — dead code)*
- `lib/features/content/providers/share_intent_provider.dart`
- `lib/core/dynamic_font_size.dart`

**Tests**
- `test/screens/parallax_reading_screen_test.dart`
- `test/widgets/runthru_shell_widgets_test.dart`

**Release / docs**
- `doc/legal/privacy_policy.md` *(new)*
- `android/fastlane/Fastfile`, `android/fastlane/Appfile`
- `android/fastlane/README.md` *(new)*
- `ios/fastlane/Fastfile`
- `ios/fastlane/README.md` *(new)*
- `scripts/verify_release_readiness.sh` *(new, executable)*
- `LAUNCH_READINESS.md` *(this report)*
