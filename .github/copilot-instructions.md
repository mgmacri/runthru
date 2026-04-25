# Speedy Boy — Copilot Instructions (Dart/Flutter)

You are an expert Flutter/Dart developer building **Speedy Boy v4.0**, a speed reading app with a **3D neumorphic cube viewport**, optional **stereoscopic head-tracking**, a refined **ContextReveal** comprehension recovery system, and a tuned gesture/onboarding layer.

## Absolute Rules — NEVER Violate

1. **No raw hex Color()** in widget code. All colors MUST use `SpeedyBoyTokens.tokenName` from `lib/design/tokens.dart`. The ONLY file with `Color(0xFF...)` is `tokens.dart`.
2. **No hardcoded TextStyle** in widget files. All styles from `SpeedyBoyTypography` in `lib/design/typography.dart`.
3. **No hardcoded BoxDecoration shadows** in widgets. Use `SpeedyBoyDecorations.raisedDecoration(surface, size)` or `.insetDecoration(...)`.
4. **No hardcoded 3D material constants.** Use `SpeedyBoyMaterials` from `lib/design/materials.dart`.
5. **Every animation** must check `isReducedMotion(context)` and apply the reduced-motion override.
6. **Stereoscopic is always optional.** Every code path involving camera/head-tracking must have graceful fallback.
7. **Two surface worlds** — NEVER mix `stage*` tokens on shell surfaces or vice versa.
8. **Bricolage Grotesque for shell UI.** Reading stage font is user-selectable (default Bricolage Grotesque). See `SpeedyBoyTypography.availableFonts` for the canonical list.
9. **TextPainter pool** (max 3) for 3D word rendering. Never allocate TextPainters in `paint()`.
10. **All imports from design system** go through `lib/design/design.dart` barrel export.
11. **Heavy computation in Isolates.** PDF extraction, cache I/O — never on the main isolate's event loop.
12. **Dart naming conventions.** `lowerCamelCase` for variables/functions, `UpperCamelCase` for classes, `snake_case` for file names.
13. **Riverpod for state.** No raw setState() for global/shared state.
14. **go_router for navigation.** No Navigator.push() calls.
15. **No raw Material loading widgets.** Never use CircularProgressIndicator, LinearProgressIndicator, or RefreshIndicator. Use the SpeedyBoy design system loading states (neumorphic pulse, ripple overlay, or styled text).
16. **CI build number is auto-managed.** Never manually set the +N build number in pubspec.yaml for release builds. Codemagic auto-increments it.
17. **No deprecated Flutter APIs.** Prefer ListenableBuilder over AnimatedBuilder. Migrate promptly.

### v3-Specific Rules (18–23)

18. **Evidence traceability.** Every new constant, behavioral rule, or design decision gets a comment citing its principle and grade. Format: `// P[N] Grade [X] — [brief rationale]`. Example:
    ```dart
    // P18 Grade C — auto-rewind 3 words on resume from pause
    static const int autoRewindWords = 3;
    ```
19. **Spec gap annotation.** When the spec is silent on an edge case, choose the conservative default and mark it: `// SPEC GAP — conservative default, revisit in v3.1`
20. **ContextReveal is 2-state.** ContextReveal has exactly 2 states: `none` ↔ `sentence`. There are NO intermediate tiers. Swipe up enters sentence view. Swipe up again in sentence view triggers elastic jiggle (ceiling feedback). Swipe down dismisses. RSVP MUST pause the instant state != none. Resume position is always the leftmost visible word, NOT the trigger word.
21. **Grade D = simple constant.** No elaborate calibration systems. Use a named constant in `SpeedyBoyTiming` with `// Grade D — tunable` comment.
22. **Do/Don't enforcement.** Before committing any component, cross-check the v3 spec's Do/Don't table. Every "Don't" is a hard constraint.
23. **Timing tokens live in `SpeedyBoyTiming`.** All animation durations, thresholds, and window sizes for v3 features come from `lib/design/timing_tokens.dart`, never hardcoded.

### v4-Specific Rules (24–28)

24. **Gesture thresholds use screen ratios.** Horizontal swipes require 30% of screen width AND 200 px/s velocity. Vertical swipes require 20% of screen height AND 150 px/s. Both conditions must be met. All thresholds come from `SpeedyBoyGestures` in `lib/design/gesture_tokens.dart`. Use `onVerticalDragEnd` and `onHorizontalDragEnd` — never `onPanEnd`.
25. **Single-tap has 300ms delay.** Because of double-tap detection, `onTap` fires after a 300ms window. This is expected platform behavior. Do not work around it.
26. **WPM dial auto-resumes.** When the WPM dial is shown via long-press, reading pauses. After 1.5 seconds of no interaction, the dial auto-dismisses and reading resumes. Explicit tap elsewhere also dismisses immediately.
27. **Hints show once per installation.** Each gesture hint has a unique ID tracked in `AppConfig.shownHints`. Once shown, never show again. Use `ConfigNotifier.markHintShown(id)` and `ConfigNotifier.hasHintBeenShown(id)`.
28. **Clipboard documents are ephemeral.** ClipboardDocument is not persisted to the library. Reading position is tracked during the session only. Cleared on app restart. Clipboard is only read on explicit user action (never automatically).

## Design System Inventory

### New Files (created during v3 implementation)
```
lib/design/timing_tokens.dart        → SpeedyBoyTiming (exported via design.dart barrel)
lib/core/word_transition.dart         → selectWordTransition(), WordTransition enum
lib/core/wcag_contrast.dart           → WcagContrast utility
lib/core/room_intensity_controller.dart → RoomIntensityController
lib/core/reading_goal_presets.dart    → ReadingGoalConfig, readingGoalConfigs
lib/core/context_reveal_state.dart    → ContextRevealState, ContextRevealTier enum
lib/core/context_reveal_notifier.dart → ContextRevealNotifier (Riverpod)
lib/core/gradient_sweep_engine.dart   → Gradient sweep timer for ContextReveal
lib/widgets/reading_goal_presets.dart → ReadingGoalPresets widget (3 cards)
lib/widgets/context_reveal_overlay.dart → ContextReveal overlay (all 3 tiers)
```

### New Files (v4)
```
lib/design/gesture_tokens.dart        → SpeedyBoyGestures (exported via design.dart barrel)
lib/core/wpm_dial_state.dart          → WpmDialState
lib/core/wpm_dial_notifier.dart       → WpmDialNotifier (Riverpod, auto-dispose)
lib/core/hint_controller.dart         → HintController (trigger logic)
lib/core/clipboard_document.dart      → ClipboardDocument model
lib/core/clipboard_service.dart       → ClipboardService
lib/widgets/wpm_dial.dart             → WPM dial circular/vertical control
lib/widgets/hint_overlay.dart         → Reusable hint pill overlay
```

### New Enums (in `lib/store/models.dart`)
```dart
enum ParallaxIntensity { none, off, subtle, full }      // default: subtle
enum ReadingGoalPreset { deepRead, comfortable, quickScan }
enum OrpCondition { orpBoldColor, orpColorOnly, centerAligned } // default: orpBoldColor
```

### New Enum (in `lib/core/context_reveal_state.dart`)
```dart
// v4 — simplified from v3's { none, micro, clause, sentence }
enum ContextRevealTier { none, sentence }
```

### New Enum (in `lib/core/word_transition.dart`)
```dart
enum WordTransition { a001Breathe, a013BounceIn }
```

### New AppConfig Fields
```dart
final ParallaxIntensity parallaxIntensity;  // default: ParallaxIntensity.subtle
final ReadingGoalPreset? readingGoalPreset; // default: null
final OrpCondition orpCondition;            // default: OrpCondition.orpBoldColor
final Set<String> shownHints;               // default: {} (empty set)
```

### SpeedyBoyTiming Token Reference
```dart
abstract final class SpeedyBoyTiming {
  // Auto-Rewind (P18 Grade C)
  static const int autoRewindWords = 3;

  // ContextReveal (P17 Grade C)
  static const int contextRevealSweepMs = 400;
  static const double contextRevealDimOpacity = 0.6;
  static const Duration contextRevealEnter = Duration(milliseconds: 200);
  static const Duration contextRevealExit = Duration(milliseconds: 150);

  // Room Intensity (P7 Grade C/D)
  static const int roomHysteresisHoldSeconds = 30;
  static const int roomDifficultyWindowSize = 5;
  static const double roomDifficultyThresholdHigh = 9.0;  // Grade D — tunable
  static const double roomDifficultyThresholdLow = 4.0;   // Grade D — tunable

  // A-013 Adaptive Timing (P6 Grade A)
  static const int a013FallbackWpmThreshold = 300;
  static const double a013MaxDisplayFraction = 0.6;
  static const int a013MinBaseDuration = 40;

  // ── v4: Elastic Jiggle (P1) ──
  static const int jiggleScaleUpMs = 100;
  static const int jiggleSpringBackMs = 200;
  static const double jiggleMaxScale = 1.2;
  static const double jiggleDampingRatio = 0.5;

  // ── v4: WPM Dial (P2) ──
  static const int wpmDialInactivityMs = 1500;
  static const int wpmDialFadeMs = 200;
  static const int wpmDialStep = 25;

  // ── v4: Overlay Hints (P6) ──
  static const int hintAutoDismissMs = 4000;
  static const int hintSlideInMs = 200;

  // ── v4: Double-Tap (P4) ──
  static const int doubleTapWindowMs = 300;
  static const int restartHighlightMs = 200;
}
```

### SpeedyBoyGestures Token Reference
```dart
abstract final class SpeedyBoyGestures {
  // P3 — calibrated from Android testing
  static const double horizontalDistanceRatio = 0.30;  // 30% of screen width
  static const double horizontalMinVelocity = 200.0;   // px/sec
  static const double verticalDistanceRatio = 0.20;     // 20% of screen height
  static const double verticalMinVelocity = 150.0;      // px/sec
}
```

## v4 Gesture Map

| Gesture | RSVP Mode | Sentence View |
|---------|-----------|---------------|
| **Tap** | Pause / resume (300ms delay) | Pause / resume sweep |
| **Double-tap** | Restart current sentence | Restart sweep from first word |
| **Swipe left** | Next sentence (30% + 200px/s) | Shift window forward |
| **Swipe right** | Previous sentence (30% + 200px/s) | Shift window backward |
| **Swipe up** | Enter sentence view (20% + 150px/s) | Elastic jiggle |
| **Swipe down** | *(no action)* | Dismiss → resume RSVP |
| **Long-press** | Show WPM dial | Show WPM dial |

## Installed Skills Reference

When working on a task, reference the most relevant skill file(s) for domain-specific best practices. Skills are in `.claude/` and are available as workspace files.

| Domain | Skill File | Use For |
|--------|-----------|---------|
| State management | `flutter-managing-state` | Any Riverpod provider, notifier, or state pattern |
| Riverpod providers | `riverpod-providers` | Creating/consuming providers, auto-dispose |
| Riverpod notifiers | `riverpod-consumers` | Watching/reading providers in widgets |
| Riverpod testing | `riverpod-testing` | Overriding providers in tests |
| Riverpod auto-dispose | `riverpod-auto-dispose` | Auto-dispose lifecycle for ContextReveal notifier |
| Animation | `flutter-animating-apps` | A-013 timing, tier transitions, sweep engine, reduced motion, elastic jiggle, WPM dial fade, hint slide-in |
| Layout | `flutter-building-layouts` | ContextReveal overlay, preset cards, settings UI, WPM dial widget, clipboard UI, adaptive sentence sizing |
| Forms/controls | `flutter-building-forms` | Settings screen controls, segmented selectors |
| Theming | `flutter-theming-apps` | Token consumption, surface world compliance |
| Accessibility | `flutter-improving-accessibility` | Semantics widgets, keyboard handlers, screen reader, hint overlay a11y, WPM dial a11y |
| Testing | `flutter-testing-apps` | Widget tests, unit tests, integration tests |
| Navigation | `flutter-implementing-navigation-and-routing` | go_router patterns (Rule 14) |
| Concurrency | `flutter-handling-concurrency` | Isolate patterns (Rule 11), timer management, WPM dial inactivity timer, hint auto-dismiss timer |
| Databases | `flutter-working-with-databases` | SharedPreferences persistence in ConfigNotifier |

## Quarterly Maintenance Checklist
- [ ] Run `dart analyze lib/` with zero warnings
- [ ] Run `flutter test` with zero failures
- [ ] Search pubspec.yaml dependencies for unused packages (zero imports in lib/)
- [ ] Search assets/ for unreferenced files
- [ ] Verify all text colors respect surface world boundaries (Rule 7)
- [ ] Verify all animations check isReducedMotion (Rule 5)
- [ ] Verify all new constants have P[N] Grade [X] traceability comments (Rule 18)
- [ ] Verify no SPEC GAP comments remain unresolved from v3.0
- [ ] Bump minimum Flutter SDK if deprecated APIs have been migrated
- [ ] Cross-check all SpeedyBoyTiming tokens against v4 spec
