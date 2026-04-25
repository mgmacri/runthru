# Speedy Boy v3.0 — Task Backlog

**Generated**: 2026-04-01
**Spec version**: 3.0.0
**Codebase scanned**: `c:\Users\Matthew\speedy-boyv3`

## Scan Summary

- **Implemented**: 0 / 9 priorities
- **Partial**: 0 / 9 priorities
- **Not started**: 9 / 9 priorities
- **Total tasks generated**: 52

## Blockers & Ambiguities

1. **No `SpeedyBoyTiming` class exists.** The v2 spec defines `SpeedyBoyTiming` in `lib/design/timing_tokens.dart`, but this file was never created. All animation constants live in `SpeedyBoyAnimations` in `lib/design/animations.dart`. TASK-001 must create the file and add it to the barrel export.
2. **No `ParallaxIntensity` enum or parallax settings exist.** The settings screen has no parallax intensity toggle at all. Priority 6 ("None" option) requires building the full 4-way control, not just adding one option.
3. **WordTimerNotifier has no `_wasPaused` flag.** State is inferred purely from `state.isPlaying`. Auto-rewind (Priority 2) must add a flag that distinguishes "first play" from "resume after pause."
4. **No WPM advisory text exists.** Priority 3 (shortening advisory text) requires first implementing the advisory, since the WPM slider currently shows only the numeric value. Alternatively, can be scoped as "add the short advisory from scratch."
5. **No room intensity or difficulty adaptation exists.** `ParallaxRoom` always renders at full intensity. Priority 4 (hysteresis + rolling window) requires building the intensity controller from scratch, not modifying existing logic.
6. **Contrast ratio utility exists only in test code** (`test/design/contrast_audit_test.dart`). It needs to be extracted into production code for Priority 5 (anchor contrast warning).
7. **A-013 animation is always used for parallax words regardless of WPM.** `ParallaxWordPainter` always receives `depthBounceValue` from the A-013 controller. There's no conditional fallback to A-001 at high WPM.
8. **`AppConfig` has only 7 fields.** All v3 features requiring new config fields (`orpCondition`, `hasSeenContextRevealOnboarding`, `parallaxIntensity`, `readingGoalPreset`) must add fields to `AppConfig` and update `fromJson`/`toJson`/`copyWith`.
9. **No per-word timing.** `WordTimerNotifier.intervalMs` uses flat `60000 / wpm`. The v2 spec defines `SpeedyBoyTiming.wordDisplayMs()` for per-word duration, but this was never implemented. A-013 adaptive timing (Priority 1) can still work with flat timing — the `displayMs` parameter in `selectWordTransition` can use the flat interval.

---

## Sprint 1: Prerequisites & Critical Fixes

### TASK-001: Create `SpeedyBoyTiming` with v3 timing tokens
- **Priority**: 0 (prerequisite for all other tasks)
- **Files**: `CREATE: lib/design/timing_tokens.dart`, `lib/design/design.dart`
- **Action**: Create `lib/design/timing_tokens.dart` with the `SpeedyBoyTiming` abstract final class containing all v3 timing tokens. Add the export to the `lib/design/design.dart` barrel file.
  ```dart
  abstract final class SpeedyBoyTiming {
    // ── Auto-Rewind (P18 — Grade C) ──
    static const int autoRewindWords = 3;

    // ── ContextReveal (P17 — Grade C) ──
    static const int contextRevealSweepMs = 400;
    static const double contextRevealDimOpacity = 0.6;
    static const int contextRevealMicroWords = 3;
    static const int contextRevealClauseWords = 5;
    static const Duration contextRevealEnter = Duration(milliseconds: 200);
    static const Duration contextRevealTierAdvance = Duration(milliseconds: 250);
    static const Duration contextRevealExit = Duration(milliseconds: 150);

    // ── Room Intensity (P7 — Grade C/D) ──
    static const int roomHysteresisHoldSeconds = 30;
    static const int roomDifficultyWindowSize = 5;
    static const double roomDifficultyThresholdHigh = 9.0;  // Grade D — tunable
    static const double roomDifficultyThresholdLow = 4.0;   // Grade D — tunable

    // ── A-013 Adaptive Timing (P6 — Grade A) ──
    static const int a013FallbackWpmThreshold = 300;
    static const double a013MaxDisplayFraction = 0.6;
    static const int a013MinBaseDuration = 40;
  }
  ```
- **Acceptance criteria**:
  - [ ] All 15 token names match spec exactly
  - [ ] All default values match spec
  - [ ] Grade D tokens have `// Grade D — tunable` comment
  - [ ] `lib/design/design.dart` barrel exports `timing_tokens.dart`
  - [ ] File compiles with no errors (`dart analyze lib/design/timing_tokens.dart`)
- **Principles**: P6, P7, P17, P18
- **Effort**: XS (~15 min)
- **Depends on**: Nothing

---

### TASK-002: Add v3 fields to `AppConfig`
- **Priority**: 0 (prerequisite for Priorities 2, 6, 7, 8, 9)
- **Files**: `lib/store/models.dart`, `lib/store/config.dart`
- **Action**: Add new fields to `AppConfig` for v3 features. Update constructor, `fromJson`, `toJson`, and `copyWith`.
  ```dart
  // New fields in AppConfig:
  final ParallaxIntensity parallaxIntensity;  // default: ParallaxIntensity.subtle
  final ReadingGoalPreset? readingGoalPreset; // default: null (no preset selected)
  final OrpCondition orpCondition;            // default: OrpCondition.orpBoldColor
  final bool hasSeenContextRevealOnboarding;  // default: false
  ```
  Add enums in `lib/store/models.dart`:
  ```dart
  enum ParallaxIntensity { none, off, subtle, full }
  enum ReadingGoalPreset { deepRead, comfortable, quickScan }
  enum OrpCondition { orpBoldColor, orpColorOnly, centerAligned }
  ```
- **Acceptance criteria**:
  - [ ] `ParallaxIntensity` enum has 4 values in order: none, off, subtle, full
  - [ ] `ReadingGoalPreset` enum has 3 values: deepRead, comfortable, quickScan
  - [ ] `OrpCondition` enum has 3 values: orpBoldColor, orpColorOnly, centerAligned
  - [ ] `hasSeenContextRevealOnboarding` defaults to `false`
  - [ ] `parallaxIntensity` defaults to `ParallaxIntensity.subtle`
  - [ ] `orpCondition` defaults to `OrpCondition.orpBoldColor`
  - [ ] `readingGoalPreset` defaults to `null`
  - [ ] JSON round-trip preserves all new fields
  - [ ] Missing JSON keys default safely (backward-compatible with existing stored configs)
  - [ ] File compiles with no errors
- **Principles**: P10, P16, P17, P18
- **Effort**: S (~30 min)
- **Depends on**: Nothing

---

### TASK-003: Add `AppConfig` v3 fields unit tests
- **Priority**: 0
- **Files**: `test/store/config_test.dart`
- **Action**: Add tests for the new `AppConfig` fields: JSON roundtrip, defaults when keys missing, enum serialization.
  ```dart
  test('v3 fields default safely when JSON keys missing')
  test('parallaxIntensity serializes and deserializes')
  test('orpCondition serializes and deserializes')
  test('readingGoalPreset null by default')
  test('hasSeenContextRevealOnboarding defaults to false')
  ```
- **Acceptance criteria**:
  - [ ] All 5 tests pass
  - [ ] Backward compatibility verified: old JSON without new keys produces valid defaults
- **Principles**: —
- **Effort**: S (~20 min)
- **Depends on**: TASK-002

---

### TASK-004: Add `ConfigNotifier` setters for v3 fields
- **Priority**: 0
- **Files**: `lib/store/config.dart`
- **Action**: Add setter methods to `ConfigNotifier`:
  ```dart
  Future<void> setParallaxIntensity(ParallaxIntensity intensity) async { ... }
  Future<void> setReadingGoalPreset(ReadingGoalPreset? preset) async { ... }
  Future<void> setOrpCondition(OrpCondition condition) async { ... }
  Future<void> setHasSeenContextRevealOnboarding(bool seen) async { ... }
  ```
  Follow the existing `_synchronized` pattern used by `setDefaultWpm`, `setAnchorColorIndex`, etc.
- **Acceptance criteria**:
  - [ ] Each setter persists to SharedPreferences
  - [ ] Each setter uses `_synchronized` for thread safety
  - [ ] File compiles with no errors
- **Principles**: —
- **Effort**: S (~20 min)
- **Depends on**: TASK-002

---

## Sprint 2: Priorities 1–5 (Critical Fixes & Ergonomic Improvements)

### TASK-005: Implement A-013 adaptive timing — `selectWordTransition` logic
- **Priority**: 1 (critical — ship-blocking for parallax mode)
- **Files**: `CREATE: lib/core/word_transition.dart`
- **Action**: Create a function that selects the word transition animation based on WPM. This is the core fix from the cognitive ergonomics evaluation.
  ```dart
  import 'package:speedy_boy/design/design.dart';

  enum WordTransition { a001Breathe, a013BounceIn }

  /// Select word entrance animation based on WPM and word length.
  /// Above 300 WPM: fall back to A-001 (eliminates timing overrun).
  /// At 200–300 WPM: cap A-013 to 60% of display time, 40ms min base.
  ({WordTransition transition, int baseDurationMs}) selectWordTransition({
    required int wpm,
    required int charCount,
    required int displayMs,
  }) {
    if (wpm > SpeedyBoyTiming.a013FallbackWpmThreshold) {
      return (
        transition: WordTransition.a001Breathe,
        baseDurationMs: SpeedyBoyAnimations.wordAdvanceDuration.inMilliseconds,
      );
    }

    final maxAnimMs = (displayMs * SpeedyBoyTiming.a013MaxDisplayFraction).round();
    final staggerTotal = SpeedyBoyAnimations.glyphStaggerMs * (charCount - 1);
    final cappedBase = (maxAnimMs - staggerTotal)
        .clamp(SpeedyBoyTiming.a013MinBaseDuration, 160);

    return (
      transition: WordTransition.a013BounceIn,
      baseDurationMs: cappedBase,
    );
  }
  ```
- **Acceptance criteria**:
  - [ ] >300 WPM → returns `a001Breathe` with 80ms base duration
  - [ ] 200–300 WPM → returns `a013BounceIn` with capped base ≤ 60% of display time
  - [ ] Base duration never below 40ms
  - [ ] Uses `SpeedyBoyTiming` constants (not hardcoded values)
  - [ ] File compiles with no errors
- **Principles**: P6 Grade A
- **Effort**: S (~20 min)
- **Depends on**: TASK-001

---

### TASK-006: Unit tests for `selectWordTransition`
- **Priority**: 1
- **Files**: `CREATE: test/core/word_transition_test.dart`
- **Action**: Test all WPM tiers and edge cases.
  ```dart
  test('A-001 at 350 WPM for any word length')
  test('A-001 at 500 WPM for any word length')
  test('A-013 capped at 250 WPM for "the" (3 chars)')
  test('A-013 capped at 250 WPM for "reading" (7 chars)')
  test('A-013 base never below 40ms')
  test('A-013 uncapped when animation fits within display budget')
  test('301 WPM triggers A-001 fallback')
  test('300 WPM stays on A-013')
  ```
- **Acceptance criteria**:
  - [ ] All 8 tests pass
  - [ ] Tests use boundary values (300, 301)
  - [ ] Tests verify stable time = displayMs − animMs > 0 for all scenarios
- **Principles**: P6 Grade A
- **Effort**: S (~25 min)
- **Depends on**: TASK-005

---

### TASK-007: Integrate `selectWordTransition` into `ParallaxRoom`
- **Priority**: 1
- **Files**: `lib/three_d/parallax_room.dart`
- **Action**: In the `didUpdateWidget` method (or equivalent word-change handler), call `selectWordTransition()` with the current WPM and char count. Based on the result:
  - If `a001Breathe`: trigger only `_wordController.forward(from: 0)`, skip `_depthBounceController`.
  - If `a013BounceIn`: update `_depthBounceController.duration` to the capped base + stagger, then `forward(from: 0)`.
  The WPM should be read from the Riverpod `wordTimerProvider` or passed as a widget parameter.
- **Acceptance criteria**:
  - [ ] At >300 WPM, depth bounce controller does NOT fire
  - [ ] At 200–300 WPM, depth bounce duration is dynamically capped
  - [ ] Reduced motion check still applies (both animations skip when reduced motion)
  - [ ] No visual stutter at 350+ WPM (manual verification)
- **Principles**: P6 Grade A
- **Effort**: M (~45 min)
- **Depends on**: TASK-005

---

### TASK-008: Implement auto-rewind on resume in `WordTimerNotifier`
- **Priority**: 2
- **Files**: `lib/core/word_timer.dart`
- **Action**: Add `_wasPaused` flag and rewind logic:
  ```dart
  bool _wasPaused = false;
  bool _hasPlayedOnce = false;

  void play() {
    if (state.isFinished || state.totalWords == 0) return;

    if (_wasPaused && _hasPlayedOnce) {
      final rewindTarget = (state.currentIndex - SpeedyBoyTiming.autoRewindWords)
          .clamp(0, state.currentIndex);
      state = state.copyWith(currentIndex: rewindTarget);
      _wasPaused = false;
    }

    if (!_hasPlayedOnce) _hasPlayedOnce = true;
    state = state.copyWith(isPlaying: true);
    _startTimer();
  }

  void pause() {
    _stopTimer();
    _wasPaused = true;
    state = state.copyWith(isPlaying: false);
  }
  ```
  Add import for `SpeedyBoyTiming` via `package:speedy_boy/design/design.dart`.
- **Acceptance criteria**:
  - [ ] DO: Auto-rewind applies on every resume-from-pause
  - [ ] DO: Clamp to word 0 at document start (if < 3 words in)
  - [ ] DON'T: Auto-rewind on first play (beginning of a session)
  - [ ] DON'T: Show any visual "rewinding…" indicator (silent)
  - [ ] `_wasPaused` set to `true` in `pause()`, consumed in `play()`
  - [ ] `loadDocument()` resets `_wasPaused` and `_hasPlayedOnce` to false
- **Principles**: P16 Grade C, P18 Grade C
- **Effort**: S (~25 min)
- **Depends on**: TASK-001

---

### TASK-009: Unit tests for auto-rewind
- **Priority**: 2
- **Files**: `test/core/word_timer_test.dart`
- **Action**: Add tests to the existing word timer test file.
  ```dart
  test('auto-rewind subtracts 3 words on resume from pause')
  test('auto-rewind clamps to word 0 at document start')
  test('auto-rewind does not apply on first play')
  test('auto-rewind applies on every subsequent resume')
  test('auto-rewind resets on loadDocument')
  test('auto-rewind is silent — no extra state emissions for rewind')
  ```
- **Acceptance criteria**:
  - [ ] All 6 tests pass
  - [ ] Tests verify `currentIndex` value after `play()` following `pause()`
  - [ ] First-play vs resume behavior correctly distinguished
- **Principles**: P16, P18
- **Effort**: S (~20 min)
- **Depends on**: TASK-008

---

### TASK-010: Add WPM advisory text at >350 WPM
- **Priority**: 3
- **Files**: `lib/screens/settings_screen.dart`
- **Action**: In the WPM slider section, add conditional advisory text that appears when WPM > 350. Use the v3 shortened text:
  ```dart
  if (currentWpm > 350)
    Text(
      'Best for scanning familiar text',
      style: SpeedyBoyTypography.caption(),
    ),
  ```
  The text should appear below the WPM value display, styled with shell surface tokens.
- **Acceptance criteria**:
  - [ ] Advisory appears only when WPM > 350
  - [ ] Text is exactly: "Best for scanning familiar text" (5 words)
  - [ ] Uses `SpeedyBoyTypography` (not hardcoded `TextStyle`)
  - [ ] Uses shell surface tokens (not stage tokens)
  - [ ] Advisory disappears when WPM returns to ≤350
  - [ ] Semantics: text is announced by screen readers
- **Principles**: P1 Grade A
- **Effort**: XS (~15 min)
- **Depends on**: Nothing

---

### TASK-011: Extract WCAG contrast ratio utility into production code
- **Priority**: 5 (prerequisite for contrast warning)
- **Files**: `CREATE: lib/core/wcag_contrast.dart`
- **Action**: Extract the contrast ratio logic from `test/design/contrast_audit_test.dart` into a reusable production utility. The test file has `luminance()` and `contrastRatio()` functions — move them to a proper utility class.
  ```dart
  import 'dart:ui';

  /// WCAG 2.1 contrast ratio utilities.
  abstract final class WcagContrast {
    /// Compute contrast ratio between two colors (returns value ≥ 1.0).
    static double contrastRatio(Color fg, Color bg) { ... }

    /// Compute relative luminance of a color per WCAG 2.1.
    static double relativeLuminance(Color color) { ... }
  }
  ```
  Use `dart:math` for the power function instead of the Taylor series approximation in the test file.
- **Acceptance criteria**:
  - [ ] `contrastRatio()` returns values matching W3C examples
  - [ ] Pure white on pure black returns 21.0
  - [ ] Same color on same color returns 1.0
  - [ ] Uses `dart:math` pow() (not Taylor approximation)
  - [ ] File compiles with no errors
- **Principles**: P14 Grade C
- **Effort**: S (~20 min)
- **Depends on**: Nothing

---

### TASK-012: Unit tests for WCAG contrast utility
- **Priority**: 5
- **Files**: `CREATE: test/core/wcag_contrast_test.dart`
- **Action**: Test the production contrast utility against known WCAG values.
  ```dart
  test('white on black is 21:1')
  test('identical colors return 1:1')
  test('stageText on stageBase exceeds 7:1')
  test('stageAnchor on stageBase exceeds 3:1')
  test('known mid-contrast pair returns expected ratio')
  ```
- **Acceptance criteria**:
  - [ ] All 5 tests pass
  - [ ] Results match `test/design/contrast_audit_test.dart` existing values
- **Principles**: P14
- **Effort**: XS (~15 min)
- **Depends on**: TASK-011

---

### TASK-013: Anchor contrast live preview in color picker
- **Priority**: 5
- **Files**: `lib/screens/settings_screen.dart`
- **Action**: Below the anchor color palette, add a live preview widget that shows a sample word on the `stageBase` background with the selected anchor color applied to the ORP character. Use the same rendering as `WordPainter` but as a static preview (no animation).
- **Acceptance criteria**:
  - [ ] Preview shows a sample word (e.g., "reading") on `stageBase` background
  - [ ] ORP character uses the selected anchor color
  - [ ] Preview updates immediately when a new color swatch is tapped
  - [ ] Uses shell surface world for the preview card frame
  - [ ] Uses `SpeedyBoyTypography.readingWord()` and `readingAnchor()` styles
  - [ ] Semantics: "Preview of anchor color on reading background"
- **Principles**: P10 Grade B, P14 Grade C
- **Effort**: M (~45 min)
- **Depends on**: Nothing

---

### TASK-014: Anchor contrast warning UI with 3 tiers
- **Priority**: 5
- **Files**: `lib/screens/settings_screen.dart`
- **Action**: After color swatch selection, compute `WcagContrast.contrastRatio(anchorColor, stageBase)` and display a warning:
  - ≥4.5:1 → No warning (standard selection ring)
  - 3:1–4.49:1 → Yellow caution: "This color may be hard to see at speed"
  - <3:1 → Red danger: "This color is very hard to see — consider a darker option"
  Use `SpeedyBoyTokens.shellProcessing` for yellow and `SpeedyBoyTokens.shellError` for red.
- **Acceptance criteria**:
  - [ ] Warning appears inline near the color picker
  - [ ] ≥4.5:1 → no warning visible
  - [ ] 3:1–4.49:1 → yellow caution indicator + text
  - [ ] <3:1 → red warning indicator + text
  - [ ] Warning updates immediately on color change
  - [ ] Uses design system tokens (no hardcoded colors)
  - [ ] Semantics: warning text announced by screen readers
- **Principles**: P10 Grade B, P14 Grade C
- **Effort**: S (~30 min)
- **Depends on**: TASK-011

---

### TASK-015: Auto text-shadow for low-contrast anchors in rendering
- **Priority**: 5
- **Files**: `lib/three_d/word_painter.dart`, `lib/three_d/parallax_word_painter.dart`
- **Action**: In both WordPainter and ParallaxWordPainter, when the anchor color has <4.5:1 contrast against `stageBase`, apply a 0.5px text shadow behind the anchor character:
  ```dart
  Paint? anchorShadow;
  if (WcagContrast.contrastRatio(anchorColor, SpeedyBoyTokens.stageBase) < 4.5) {
    anchorShadow = Paint()
      ..color = SpeedyBoyTokens.stageText.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);
  }
  ```
  Pass the shadow through the glyph rendering loop and paint it behind anchor characters.
- **Acceptance criteria**:
  - [ ] Shadow applied only when contrast < 4.5:1
  - [ ] Shadow uses `stageText` at 30% opacity
  - [ ] Shadow blur radius is 0.5px
  - [ ] Shadow present in both 2D (`WordPainter`) and 3D (`ParallaxWordPainter`)
  - [ ] No shadow applied for high-contrast anchors (e.g., Hot Coral, High Risk Red)
  - [ ] Shadow applied for known low-contrast anchors (e.g., Buttercup, Limelight)
- **Principles**: P10, P14 Grade C
- **Effort**: M (~45 min)
- **Depends on**: TASK-011

---

### TASK-016: Widget tests for anchor contrast warning and shadow
- **Priority**: 5
- **Files**: `CREATE: test/design/anchor_contrast_test.dart`
- **Action**: Test contrast warning thresholds and auto-shadow application.
  ```dart
  test('Hot Coral on stageBase exceeds 4.5:1 — no warning')
  test('Buttercup on stageBase is between 3:1 and 4.5:1 — caution warning')
  test('Limelight on stageBase is below 3:1 — danger warning')
  test('auto-shadow applied when contrast below 4.5:1')
  test('auto-shadow NOT applied when contrast above 4.5:1')
  ```
- **Acceptance criteria**:
  - [ ] All 5 tests pass
  - [ ] Tests use actual anchor colors from `SpeedyBoyTokens.anchorColors`
- **Principles**: P10, P14
- **Effort**: S (~20 min)
- **Depends on**: TASK-014, TASK-015

---

## Sprint 3: Priorities 4, 6, 7, 8 (Validation Infrastructure & Components)

### TASK-017: Implement `RoomIntensityController` with rolling window
- **Priority**: 4
- **Files**: `CREATE: lib/core/room_intensity_controller.dart`
- **Action**: Create the room intensity controller with rolling window for difficulty smoothing:
  ```dart
  import 'package:speedy_boy/design/design.dart';

  enum RoomIntensityLevel { minimal, moderate, rich }

  class RoomIntensityController {
    final List<double> _recentDifficultyScores = [];
    RoomIntensityLevel _currentIntensity = RoomIntensityLevel.moderate;
    DateTime? _lastIntensityChange;

    RoomIntensityLevel get currentIntensity => _currentIntensity;

    double get smoothedDifficulty {
      if (_recentDifficultyScores.isEmpty) return 0.5;
      return _recentDifficultyScores.reduce((a, b) => a + b) /
          _recentDifficultyScores.length;
    }

    void onSentenceComplete(double sentenceDifficulty) {
      _recentDifficultyScores.add(sentenceDifficulty);
      if (_recentDifficultyScores.length > SpeedyBoyTiming.roomDifficultyWindowSize) {
        _recentDifficultyScores.removeAt(0);
      }
      _evaluateIntensityChange();
    }

    void _evaluateIntensityChange() {
      if (_lastIntensityChange != null &&
          DateTime.now().difference(_lastIntensityChange!) <
              Duration(seconds: SpeedyBoyTiming.roomHysteresisHoldSeconds)) {
        return; // Hysteresis hold — too soon
      }

      final target = _intensityFromDifficulty(smoothedDifficulty);
      if (target != _currentIntensity) {
        _currentIntensity = target;
        _lastIntensityChange = DateTime.now();
      }
    }

    RoomIntensityLevel _intensityFromDifficulty(double avgCharsPerWord) {
      if (avgCharsPerWord >= SpeedyBoyTiming.roomDifficultyThresholdHigh) {  // Grade D — tunable
        return RoomIntensityLevel.minimal;
      }
      if (avgCharsPerWord <= SpeedyBoyTiming.roomDifficultyThresholdLow) {  // Grade D — tunable
        return RoomIntensityLevel.rich;
      }
      return RoomIntensityLevel.moderate;
    }

    void reset() {
      _recentDifficultyScores.clear();
      _currentIntensity = RoomIntensityLevel.moderate;
      _lastIntensityChange = null;
    }
  }
  ```
- **Acceptance criteria**:
  - [ ] Rolling window stores last 5 sentence difficulty scores
  - [ ] Window rolls (oldest removed when exceeding size 5)
  - [ ] `smoothedDifficulty` returns running average
  - [ ] Default (empty window) returns 0.5 (moderate)
  - [ ] Uses `SpeedyBoyTiming` constants (not hardcoded)
  - [ ] Constants annotated `// Grade D — tunable`
  - [ ] No elaborate calibration system — simple constant only
- **Principles**: P7 Grade C/D
- **Effort**: S (~30 min)
- **Depends on**: TASK-001

---

### TASK-018: Add hysteresis hold to `RoomIntensityController`
- **Priority**: 4
- **Files**: `lib/core/room_intensity_controller.dart`
- **Action**: Verify hysteresis logic (already included in TASK-017 code). The `_evaluateIntensityChange` method checks `_lastIntensityChange` and enforces a 30-second minimum hold between transitions. This task adds a `DateTime Function()` clock parameter for testability:
  ```dart
  class RoomIntensityController {
    RoomIntensityController({DateTime Function()? clock})
        : _clock = clock ?? DateTime.now;
    final DateTime Function() _clock;
    // ... use _clock() instead of DateTime.now() in _evaluateIntensityChange
  }
  ```
- **Acceptance criteria**:
  - [ ] Hysteresis blocks intensity transition within 30 seconds of last change
  - [ ] Hysteresis allows transition after 30+ seconds
  - [ ] Injectable clock for deterministic testing
- **Principles**: P7 Grade C
- **Effort**: XS (~15 min)
- **Depends on**: TASK-017

---

### TASK-019: Unit tests for `RoomIntensityController`
- **Priority**: 4
- **Files**: `CREATE: test/core/room_intensity_controller_test.dart`
- **Action**: Test rolling window, smoothing, and hysteresis.
  ```dart
  test('window fills with first 5 sentences')
  test('window rolls — oldest removed after 5th entry')
  test('smoothedDifficulty returns running average')
  test('empty window returns 0.5 default')
  test('high difficulty (≥9.0 avg chars) triggers minimal intensity')
  test('low difficulty (≤4.0 avg chars) triggers rich intensity')
  test('moderate difficulty stays moderate')
  test('hysteresis blocks intensity transition within 30 seconds')
  test('hysteresis allows transition after 30 seconds')
  test('single-sentence spike ignored by rolling average')
  test('reset clears all state')
  ```
- **Acceptance criteria**:
  - [ ] All 11 tests pass
  - [ ] Hysteresis tests use injectable clock (not real time)
  - [ ] Grade D thresholds tested at exact boundary values (4.0, 4.1, 8.9, 9.0)
- **Principles**: P7 Grade C/D
- **Effort**: S (~30 min)
- **Depends on**: TASK-018

---

### TASK-020: Add `ParallaxIntensity` settings control
- **Priority**: 6
- **Files**: `lib/screens/settings_screen.dart`
- **Action**: Add a segmented control for parallax intensity with 4 options: None / Off / Subtle / Full. Place it in the settings screen (Primary Settings section). Wire to `ConfigNotifier.setParallaxIntensity()`.
- **Acceptance criteria**:
  - [ ] 4 segments in order: None, Off, Subtle, Full
  - [ ] Default selection: Subtle
  - [ ] Tapping a segment persists the value via ConfigNotifier
  - [ ] Uses shell surface tokens
  - [ ] Uses `SpeedyBoyDecorations` for neumorphic styling
  - [ ] Semantics: each segment labelled for screen reader
  - [ ] Keyboard: arrow keys navigate segments, Enter selects
- **Principles**: P6 Grade B, P10 Grade B, P15
- **Effort**: M (~45 min)
- **Depends on**: TASK-002, TASK-004

---

### TASK-021: Implement "None" rendering branch in reading viewport
- **Priority**: 6
- **Files**: `lib/screens/parallax_reading_screen.dart`, `lib/three_d/parallax_room.dart`
- **Action**: When `parallaxIntensity == ParallaxIntensity.none`, render:
  - Background: `stageBase` fill, edge-to-edge
  - Word: 2D `WordPainter` (not `ParallaxWordPainter`)
  - Neumorphic frame: `SpeedyBoyDecorations.insetDecoration(SpeedyBoySurface.stage)` around viewport edges
  - Progress hairline: unchanged
  - No room geometry, no marble, no grid, no vignette, no fog on pause (simple dimming via `stageBase` with opacity instead)
- **Acceptance criteria**:
  - [ ] "None" renders flat `stageBase` background
  - [ ] Word displayed with 2D `WordPainter`, not parallax painter
  - [ ] No 3D room geometry visible
  - [ ] Neumorphic frame present around viewport
  - [ ] Pause state uses simple dimming (not fog overlay)
  - [ ] Progress hairline still visible
  - [ ] Reduced motion: no additional changes needed (already flat)
- **Principles**: P6, P15
- **Effort**: M (~1 hr)
- **Depends on**: TASK-020

---

### TASK-022: "Off" and "Full" parallax rendering branches
- **Priority**: 6
- **Files**: `lib/three_d/parallax_room.dart`, `lib/screens/parallax_reading_screen.dart`
- **Action**: Ensure existing rendering maps to intensity levels:
  - **Off**: 3D room renders statically. Set `headX = 0, headY = 0` (no parallax), disable cube breathe animation. Depth cues visible.
  - **Subtle**: Current behavior with parallax clamped to ≤2.5% displacement, breathe enabled.
  - **Full**: Current behavior with parallax up to ≤5% displacement, breathe enabled.
  Read `parallaxIntensity` from `configProvider` and pass to the room widget.
- **Acceptance criteria**:
  - [ ] "Off" shows static room (no parallax or breathe)
  - [ ] "Subtle" shows gentle parallax (≤2.5% displacement)
  - [ ] "Full" shows full parallax (≤5% displacement)
  - [ ] Switching intensity in settings updates the reading viewport immediately
- **Principles**: P6
- **Effort**: M (~45 min)
- **Depends on**: TASK-020

---

### TASK-023: Widget test for parallax intensity settings
- **Priority**: 6
- **Files**: `CREATE: test/screens/parallax_intensity_test.dart`
- **Action**: Test that the settings control has all 4 options and that selection persists.
  ```dart
  test('parallax intensity control shows 4 options: None, Off, Subtle, Full')
  test('selecting None persists ParallaxIntensity.none')
  test('default selection is Subtle')
  ```
- **Acceptance criteria**:
  - [ ] All 3 tests pass
- **Principles**: P6
- **Effort**: S (~20 min)
- **Depends on**: TASK-020

---

### TASK-024: Create `ReadingGoalPreset` data model with preset values
- **Priority**: 7
- **Files**: `CREATE: lib/core/reading_goal_presets.dart`
- **Action**: Define the 3 preset configurations from the spec:
  ```dart
  import 'package:speedy_boy/store/models.dart';

  class ReadingGoalConfig {
    const ReadingGoalConfig({
      required this.preset,
      required this.name,
      required this.description,
      required this.wpm,
      required this.parallaxIntensity,
    });

    final ReadingGoalPreset preset;
    final String name;
    final String description;
    final int wpm;
    final ParallaxIntensity parallaxIntensity;
  }

  const readingGoalConfigs = [
    ReadingGoalConfig(
      preset: ReadingGoalPreset.deepRead,
      name: 'Deep Read',
      description: 'Take your time with difficult material.',
      wpm: 200,
      parallaxIntensity: ParallaxIntensity.subtle,
    ),
    ReadingGoalConfig(
      preset: ReadingGoalPreset.comfortable,
      name: 'Comfortable',
      description: 'Your everyday reading pace.',
      wpm: 250,
      parallaxIntensity: ParallaxIntensity.subtle,
    ),
    ReadingGoalConfig(
      preset: ReadingGoalPreset.quickScan,
      name: 'Quick Scan',
      description: 'Get the gist of material you already know.',
      wpm: 350,
      parallaxIntensity: ParallaxIntensity.off,
    ),
  ];
  ```
- **Acceptance criteria**:
  - [ ] 3 presets with correct names: Deep Read, Comfortable, Quick Scan
  - [ ] Deep Read: 200 WPM, Subtle parallax
  - [ ] Comfortable: 250 WPM, Subtle parallax
  - [ ] Quick Scan: 350 WPM, Off parallax
  - [ ] Each has a one-sentence description matching spec
- **Principles**: P1 Grade A, P10 Grade B
- **Effort**: XS (~15 min)
- **Depends on**: TASK-002

---

### TASK-025: `ReadingGoalPresets` UI component (3 cards)
- **Priority**: 7
- **Files**: `CREATE: lib/widgets/reading_goal_presets.dart`
- **Action**: Build the ReadingGoalPresets widget — 3 tappable cards. Each card shows preset name, description, and WPM. Uses shell surface tokens and `SpeedyBoyDecorations.raisedDecoration(SpeedyBoySurface.shell)`. On tap, apply the preset's settings via ConfigNotifier and call an `onSelected` callback.
- **Acceptance criteria**:
  - [ ] 3 cards displayed: Deep Read, Comfortable, Quick Scan
  - [ ] DO: Present presets as reading intentions ("Deep Read")
  - [ ] DON'T: Present presets as speed tiers ("Slow / Medium / Fast")
  - [ ] Each card shows name, description, WPM value
  - [ ] Uses shell surface tokens (not stage)
  - [ ] Uses `SpeedyBoyDecorations.raisedDecoration(SpeedyBoySurface.shell)`
  - [ ] Uses `SpeedyBoyTypography` for all text
  - [ ] No hardcoded colors or text styles
  - [ ] Tapping a card applies settings (WPM, parallax intensity)
  - [ ] Semantics: "Deep Read: 200 words per minute. Take your time with difficult material."
  - [ ] Keyboard: arrow keys navigate between presets, Enter to select
- **Principles**: P1 Grade A, P10 Grade B
- **Effort**: M (~1 hr)
- **Depends on**: TASK-024

---

### TASK-026: Onboarding integration for reading goal presets
- **Priority**: 7
- **Files**: `lib/screens/parallax_reading_screen.dart` (or appropriate reading entry point)
- **Action**: After the user loads their first PDF and attempts to start the first reading session, present the `ReadingGoalPresets` widget. Show a "Customize later in Settings" link below the cards. Tapping a card applies settings and begins reading. If user skips (taps "Customize later"), default to Comfortable preset values.
- **Acceptance criteria**:
  - [ ] Presets shown after first PDF load, before first reading session
  - [ ] "Customize later in Settings" link visible
  - [ ] DO: Default to "Comfortable" if user skips onboarding
  - [ ] DON'T: Require preset selection to use the app (never block reading)
  - [ ] Shown only once (persist whether onboarding was completed)
  - [ ] Reduced motion: card transitions instant
- **Principles**: P1, P10
- **Effort**: M (~1 hr)
- **Depends on**: TASK-025, TASK-004

---

### TASK-027: Settings integration for reading goal selector
- **Priority**: 7
- **Files**: `lib/screens/settings_screen.dart`
- **Action**: Add a "Reading Goal" selector at the top of the Primary Settings section. Show the 3 presets + a "Custom" indicator. Selecting a preset updates WPM and parallax intensity. When the user modifies any individual setting, change the preset indicator to "Custom."
- **Acceptance criteria**:
  - [ ] "Reading Goal" selector at top of settings
  - [ ] 3 preset options + "Custom" indicator
  - [ ] Selecting a preset updates WPM and parallax intensity
  - [ ] DO: Show "Custom" when user modifies settings after preset selection
  - [ ] DON'T: Silently break the preset without indication
  - [ ] DO: Allow full customization after preset selection
  - [ ] DON'T: Lock users into preset configurations
  - [ ] Persists selected preset in AppConfig
  - [ ] Semantics: each option announced with name and description
- **Principles**: P1, P10
- **Effort**: M (~1 hr)
- **Depends on**: TASK-025, TASK-020

---

### TASK-028: Widget tests for reading goal presets
- **Priority**: 7
- **Files**: `CREATE: test/widgets/reading_goal_presets_test.dart`
- **Action**: Test preset behavior.
  ```dart
  test('selecting Deep Read preset applies 200 WPM')
  test('selecting Quick Scan preset applies 350 WPM and Off parallax')
  test('modifying WPM after preset selection shows Custom indicator')
  test('skipping onboarding defaults to Comfortable preset values')
  test('3 preset cards are visible')
  ```
- **Acceptance criteria**:
  - [ ] All 5 tests pass
- **Principles**: P1, P10
- **Effort**: S (~25 min)
- **Depends on**: TASK-025, TASK-027

---

### TASK-029: Add `OrpCondition` rendering branch
- **Priority**: 8
- **Files**: `lib/three_d/word_painter.dart`, `lib/three_d/parallax_word_painter.dart`
- **Action**: Read `orpCondition` from AppConfig and modify anchor rendering:
  - `orpBoldColor` (default): Bold weight + anchor color (current behavior, no change)
  - `orpColorOnly`: Anchor color applied but regular weight (use `readingWord` style with color override instead of `readingAnchor`)
  - `centerAligned`: Horizontally centered word (no ORP alignment), anchor color on ORP position
  
  Pass `OrpCondition` as a parameter to both painters.
- **Acceptance criteria**:
  - [ ] `orpBoldColor` renders bold + color (existing behavior unchanged)
  - [ ] `orpColorOnly` renders anchor color with regular weight
  - [ ] `centerAligned` centers the word horizontally instead of ORP-aligning
  - [ ] Feature flag is not user-facing in settings (controlled by A/B infrastructure)
  - [ ] All 3 conditions work in both 2D and 3D painters
- **Principles**: P14 Grade D
- **Effort**: M (~45 min)
- **Depends on**: TASK-002

---

### TASK-030: Unit test for ORP conditions
- **Priority**: 8
- **Files**: `test/core/orp_test.dart`
- **Action**: Add tests verifying the 3 ORP rendering conditions.
  ```dart
  test('orpBoldColor uses bold weight and anchor color')
  test('orpColorOnly uses regular weight with anchor color')
  test('centerAligned centers word horizontally')
  ```
- **Acceptance criteria**:
  - [ ] All 3 tests pass
  - [ ] Tests verify text style weight and alignment behavior
- **Principles**: P14
- **Effort**: S (~20 min)
- **Depends on**: TASK-029

---

## Sprint 4: Priority 9 — ContextReveal (12+ tasks)

### TASK-031: ContextReveal state model
- **Priority**: 9
- **Files**: `CREATE: lib/core/context_reveal_state.dart`
- **Action**: Define the ContextReveal state model and notifier:
  ```dart
  enum ContextRevealTier { none, micro, clause, sentence }

  class ContextRevealState {
    const ContextRevealState({
      this.tier = ContextRevealTier.none,
      this.sweepPosition = 0,
      this.isSweepPaused = false,
      this.windowOffset = 0,
      this.triggerWordIndex = 0,
    });

    final ContextRevealTier tier;
    final int sweepPosition;       // Index of sweep focus word within displayed words
    final bool isSweepPaused;
    final int windowOffset;        // How many words the window has shifted (negative = backward)
    final int triggerWordIndex;    // Word index when ContextReveal was triggered
    // copyWith...

    /// The word index RSVP should resume from (leftmost visible word).
    int get resumeWordIndex => triggerWordIndex + windowOffset - _leftExtent;

    int get _leftExtent {
      switch (tier) {
        case ContextRevealTier.micro: return 1;  // ±1
        case ContextRevealTier.clause: return 2; // ±2
        case ContextRevealTier.sentence: return 0; // handled differently
        case ContextRevealTier.none: return 0;
      }
    }
  }
  ```
- **Acceptance criteria**:
  - [ ] Tier enum: none, micro, clause, sentence
  - [ ] State tracks: tier, sweepPosition, isSweepPaused, windowOffset, triggerWordIndex
  - [ ] `resumeWordIndex` computed from leftmost visible word
  - [ ] `copyWith` method for immutable state updates
  - [ ] File compiles with no errors
- **Principles**: P17 Grade C
- **Effort**: S (~25 min)
- **Depends on**: Nothing

---

### TASK-032: ContextReveal Riverpod notifier
- **Priority**: 9
- **Files**: `CREATE: lib/core/context_reveal_notifier.dart`
- **Action**: Create a `StateNotifier<ContextRevealState>` with methods:
  - `enter(int currentWordIndex)` → set tier to micro, record trigger word
  - `advanceTier()` → micro→clause→sentence, no-op at sentence
  - `dismiss()` → set tier to none, return resume word index
  - `shiftWindowBack()` → decrement windowOffset, reset sweep
  - `shiftWindowForward()` → increment windowOffset, reset sweep
  - `toggleSweepPause()` → pause/resume sweep
  - `advanceSweep()` → increment sweep position (called by timer)
- **Acceptance criteria**:
  - [ ] DO: Pause RSVP immediately on enter (tier != none)
  - [ ] DON'T: Let RSVP continue during ContextReveal
  - [ ] `dismiss()` returns the resume word index (leftmost visible word)
  - [ ] `advanceTier()` is no-op at sentence tier
  - [ ] Navigation resets sweep to leftmost word
  - [ ] Provider is auto-dispose
- **Principles**: P17 Grade C
- **Effort**: S (~30 min)
- **Depends on**: TASK-031

---

### TASK-033: Gesture detector integration for ContextReveal
- **Priority**: 9
- **Files**: `lib/screens/parallax_reading_screen.dart` (or main reading viewport)
- **Action**: Add gesture detection for ContextReveal:
  - Swipe up during reading → `contextRevealNotifier.enter(currentWordIndex)`, pause `wordTimerNotifier`
  - Swipe up while in ContextReveal → `contextRevealNotifier.advanceTier()`
  - Swipe down while in ContextReveal → dismiss, resume RSVP from returned resume index
  - Swipe left/right while in ContextReveal → shift window
  - Tap while in ContextReveal → toggle sweep pause
  Existing gestures (tap to pause/resume, swipe left/right for sentence nav) should only apply when NOT in ContextReveal.
- **Acceptance criteria**:
  - [ ] Swipe-up enters ContextReveal (pauses RSVP immediately)
  - [ ] Swipe-up in tier advances to next tier
  - [ ] Swipe-down dismisses and resumes RSVP from leftmost visible word
  - [ ] Swipe left/right shifts context window
  - [ ] Tap pauses/resumes sweep
  - [ ] Existing gestures still work when NOT in ContextReveal
  - [ ] No gesture conflicts with system gestures (`immersiveSticky`)
- **Principles**: P17
- **Effort**: M (~1 hr)
- **Depends on**: TASK-032

---

### TASK-034: PacingEngine integration — no auto-rewind on ContextReveal exit
- **Priority**: 9
- **Files**: `lib/core/word_timer.dart`
- **Action**: Add a `resumeFromContextReveal(int wordIndex)` method that resumes from a specific index WITHOUT auto-rewind:
  ```dart
  void resumeFromContextReveal(int wordIndex) {
    seekTo(wordIndex);
    _wasPaused = false; // Prevent auto-rewind — ContextReveal has its own resume logic
    play();
  }
  ```
  The swipe-down dismiss handler calls this instead of `play()`.
- **Acceptance criteria**:
  - [ ] DON'T: Apply auto-rewind when exiting ContextReveal
  - [ ] Resume from the exact word index returned by ContextReveal dismiss
  - [ ] `_wasPaused` reset to prevent auto-rewind on next play()
  - [ ] Regular tap-to-resume still triggers auto-rewind (not affected)
- **Principles**: P17, P18
- **Effort**: XS (~15 min)
- **Depends on**: TASK-008, TASK-032

---

### TASK-035: Micro tier rendering (3 words)
- **Priority**: 9
- **Files**: `CREATE: lib/widgets/context_reveal_overlay.dart`
- **Action**: Create the ContextReveal overlay widget. For Micro tier:
  - Display current word ± 1 (3 words total) in a single line
  - Current word's ORP anchor character pinned to viewport horizontal center
  - Surrounding words positioned naturally using measured glyph widths
  - Use `SpeedyBoyTypography.readingWord()` and `readingAnchor()` styles
  - Display on dim overlay (60% of pause fog opacity)
- **Acceptance criteria**:
  - [ ] 3 words visible (current ± 1)
  - [ ] Current word ORP anchor at viewport center (same position as RSVP)
  - [ ] Adjacent words positioned by measured glyph width
  - [ ] Uses design system typography
  - [ ] Dim overlay at 60% of `stagePauseOverlay` opacity
  - [ ] Room visible behind overlay
- **Principles**: P17 Grade C, P5 Grade A
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-032

---

### TASK-036: Clause tier rendering (5 words)
- **Priority**: 9
- **Files**: `lib/widgets/context_reveal_overlay.dart`
- **Action**: Add Clause tier rendering:
  - Display current word ± 2 (5 words total)
  - Centered block layout (no fixed ORP anchor point)
  - Single line or soft-wrap
  - Each word's ORP character highlighted during sweep
- **Acceptance criteria**:
  - [ ] 5 words visible (current ± 2)
  - [ ] Centered block layout (not ORP-pinned)
  - [ ] Soft-wrap when line exceeds viewport width
  - [ ] Each word's ORP character uses anchor color during sweep focus
- **Principles**: P17 Grade C
- **Effort**: M (~45 min)
- **Depends on**: TASK-035

---

### TASK-037: Sentence tier rendering (full sentence)
- **Priority**: 9
- **Files**: `lib/widgets/context_reveal_overlay.dart`
- **Action**: Add Sentence tier rendering:
  - Display the full current sentence
  - Wrapped text block, centered vertically in viewport
  - Gradient sweep treats each word individually
  - Requires access to sentence boundaries (use `SentenceResolver`)
- **Acceptance criteria**:
  - [ ] Full sentence displayed (using sentence boundary detection)
  - [ ] Text wrapped and centered vertically
  - [ ] All words individually styled during sweep
  - [ ] Handles long sentences with graceful wrapping
- **Principles**: P17
- **Effort**: M (~1 hr)
- **Depends on**: TASK-036

---

### TASK-038: Tier advance transitions + reduced motion
- **Priority**: 9
- **Files**: `lib/widgets/context_reveal_overlay.dart`
- **Action**: Implement transition animations between tiers:
  - Enter (RSVP → Micro): Current word stays; ±1 fade in from 0% opacity, slide in ±20px. 200ms easeOut.
  - Tier advance (Micro → Clause, Clause → Sentence): New words fade in at edges, existing reposition. 250ms easeInOut.
  - Exit (any tier → RSVP): Context words fade out. 150ms easeOut, then immediate RSVP resume.
  - Dim overlay: 200ms enter / 150ms exit (consistent with A-006/A-007).
  Use `SpeedyBoyTiming` constants. Check `isReducedMotion(context)` — when true, all transitions instant. Gradient sweep timing (400ms/word) is NOT reduced (functional, not decorative).
- **Acceptance criteria**:
  - [ ] Enter: 200ms easeOut, words fade + slide
  - [ ] Advance: 250ms easeInOut, words fade at edges
  - [ ] Exit: 150ms easeOut
  - [ ] Reduced motion: all transitions instant (no fade, no slide)
  - [ ] Reduced motion: 400ms/word sweep timing PRESERVED (functional)
  - [ ] Uses `SpeedyBoyTiming` duration constants
  - [ ] Uses `isReducedMotion(context)` check
- **Principles**: P6 Grade A, P17 Grade C
- **Effort**: M (~1 hr)
- **Depends on**: TASK-035, TASK-001

---

### TASK-039: Gradient sweep engine
- **Priority**: 9
- **Files**: `CREATE: lib/core/gradient_sweep_engine.dart`
- **Action**: Implement the gradient sweep timer:
  - Fixed rate: 400ms per word (`SpeedyBoyTiming.contextRevealSweepMs`)
  - Auto-advances through displayed words
  - Tap pauses/resumes sweep (word stays highlighted)
  - Holds on last word indefinitely
  - On navigation (window shift), reset sweep to new leftmost word
  Use a `Timer` or `AnimationController` to drive the sweep.
- **Acceptance criteria**:
  - [ ] Sweep advances at 400ms per word (150 WPM)
  - [ ] Tap pauses sweep — word stays highlighted at current position
  - [ ] Tap again resumes sweep
  - [ ] Sweep holds on last word (does not loop or auto-dismiss)
  - [ ] Navigation resets sweep to leftmost word
  - [ ] Uses `SpeedyBoyTiming.contextRevealSweepMs` constant
- **Principles**: P17 Grade C
- **Effort**: S (~30 min)
- **Depends on**: TASK-001

---

### TASK-040: Gradient sweep rendering
- **Priority**: 9
- **Files**: `lib/widgets/context_reveal_overlay.dart`
- **Action**: Apply gradient sweep styling to displayed words:
  
  | Position | ORP char | Body text |
  |----------|----------|-----------|
  | Focus word | Full `stageAnchor`, bold | `stageText`, regular |
  | ±1 from focus | `stageAnchor` at 40% opacity, regular | `stageText` at 70% opacity |
  | All others | `stageText` at 50% opacity | `stageText` at 50% opacity |
  
  Connect to the gradient sweep engine's current position.
- **Acceptance criteria**:
  - [ ] Focus word ORP character: full anchor color, bold
  - [ ] ±1 words: 40% anchor on ORP, 70% text opacity
  - [ ] Other words: 50% text opacity
  - [ ] Styling updates as sweep advances
  - [ ] Uses `SpeedyBoyTokens.stageAnchor` and `stageText`
  - [ ] Uses `SpeedyBoyTypography` styles
- **Principles**: P5 Grade A, P17 Grade C
- **Effort**: M (~45 min)
- **Depends on**: TASK-039, TASK-035

---

### TASK-041: Navigation within ContextReveal
- **Priority**: 9
- **Files**: `lib/widgets/context_reveal_overlay.dart`, `lib/core/context_reveal_notifier.dart`
- **Action**: Wire swipe left/right gestures:
  - Swipe right: shift window backward 1 word, reset sweep to new leftmost
  - Swipe left: shift window forward 1 word, reset sweep to new leftmost
  - Update resume position: RSVP resumes from leftmost visible word after dismiss
  - DO: Resume from leftmost visible word after navigation
  - DON'T: Resume from the word where ContextReveal was triggered
- **Acceptance criteria**:
  - [ ] Swipe right shifts window backward
  - [ ] Swipe left shifts window forward
  - [ ] Sweep resets on navigation
  - [ ] Resume position updates to leftmost visible word
  - [ ] Boundary handling: don't shift past word 0 or past end of document
- **Principles**: P17
- **Effort**: S (~30 min)
- **Depends on**: TASK-032, TASK-039

---

### TASK-042: Dim overlay (60% pause fog)
- **Priority**: 9
- **Files**: `lib/widgets/context_reveal_overlay.dart`
- **Action**: Apply the dim overlay when ContextReveal is active:
  - Use `stagePauseOverlay` at 60% of its standard opacity
  - Room visible behind the overlay
  - Animate in 200ms / out 150ms (same as A-006/A-007)
  - Check `isReducedMotion` — instant when true
- **Acceptance criteria**:
  - [ ] DO: Keep the 3D room visible (dimmed) behind the context
  - [ ] DON'T: Replace the room with a flat background
  - [ ] Opacity = `SpeedyBoyTiming.contextRevealDimOpacity` × pause fog opacity
  - [ ] Transition timing matches A-006/A-007
  - [ ] Reduced motion: instant show/hide
- **Principles**: P6, P17
- **Effort**: S (~20 min)
- **Depends on**: TASK-035

---

### TASK-043: First-use ContextReveal onboarding overlay
- **Priority**: 9
- **Files**: `lib/widgets/context_reveal_overlay.dart`, `lib/store/config.dart`
- **Action**: On first swipe-up during reading, check `hasSeenContextRevealOnboarding`. If `false`:
  - Show overlay with text: "Swipe up to see surrounding words. Swipe again for more context. Swipe down to resume."
  - Auto-dismiss after 3 seconds, or dismiss on tap
  - Set `hasSeenContextRevealOnboarding = true` via ConfigNotifier
  - After overlay dismisses, proceed to Micro tier normally
- **Acceptance criteria**:
  - [ ] Overlay shown on first swipe-up (once per installation)
  - [ ] Text matches spec exactly
  - [ ] Auto-dismisses after 3 seconds
  - [ ] Tap dismisses immediately
  - [ ] After dismissal, Micro tier activates
  - [ ] `hasSeenContextRevealOnboarding` persisted to `true`
  - [ ] Never shown again after first dismissal
  - [ ] Semantics: overlay text announced by screen reader
- **Principles**: P10 Grade B, P17
- **Effort**: S (~30 min)
- **Depends on**: TASK-035, TASK-004

---

### TASK-044: ContextReveal accessibility
- **Priority**: 9
- **Files**: `lib/widgets/context_reveal_overlay.dart`
- **Action**: Add screen reader and keyboard support:
  - **Screen reader**: Announce full context phrase on entry. "Context: [phrase]. Swipe down to resume reading." On tier advance, re-announce expanded phrase.
  - **Keyboard**: Up arrow = enter/advance tier. Down arrow = dismiss. Left/Right = shift window. Space = pause/resume sweep.
- **Acceptance criteria**:
  - [ ] Semantics: context phrase announced on entry
  - [ ] Semantics: "Swipe down to resume reading" announced
  - [ ] Semantics: re-announce on tier advance
  - [ ] Keyboard: Up = enter/advance, Down = dismiss
  - [ ] Keyboard: Left/Right = shift window
  - [ ] Keyboard: Space = pause/resume sweep
- **Principles**: P17
- **Effort**: M (~45 min)
- **Depends on**: TASK-035

---

### TASK-045: Unit tests for gradient sweep engine and ContextReveal state
- **Priority**: 9
- **Files**: `CREATE: test/core/context_reveal_test.dart`
- **Action**: Test sweep engine logic and state transitions.
  ```dart
  test('sweep advances at 400ms intervals')
  test('sweep pauses on toggle')
  test('sweep resumes on second toggle')
  test('sweep holds on last word')
  test('navigation resets sweep to leftmost')
  test('enter sets tier to micro and records trigger word')
  test('advanceTier progresses micro → clause → sentence')
  test('advanceTier is no-op at sentence tier')
  test('dismiss returns resume index from leftmost visible word')
  test('dismiss after backward navigation returns earlier word index')
  test('window shift backward decrements offset')
  test('window shift forward increments offset')
  ```
- **Acceptance criteria**:
  - [ ] All 12 tests pass
  - [ ] Sweep timing tests use fake/injectable timer
- **Principles**: P17
- **Effort**: M (~45 min)
- **Depends on**: TASK-032, TASK-039

---

### TASK-046: Widget tests for ContextReveal tier rendering
- **Priority**: 9
- **Files**: `CREATE: test/widgets/context_reveal_overlay_test.dart`
- **Action**: Widget tests for the overlay rendering at each tier.
  ```dart
  test('micro tier displays 3 words')
  test('clause tier displays 5 words')
  test('sentence tier displays full sentence')
  test('gradient sweep highlights focus word with full anchor color')
  test('dim overlay visible behind context words')
  test('onboarding overlay shown on first activation')
  ```
- **Acceptance criteria**:
  - [ ] All 6 tests pass
- **Principles**: P17
- **Effort**: S (~30 min)
- **Depends on**: TASK-035, TASK-036, TASK-037

---

## Sprint 5: Integration Testing & Polish

### TASK-047: Integration test — ContextReveal full flow
- **Priority**: 9
- **Files**: `CREATE: integration_test/context_reveal_test.dart`
- **Action**: End-to-end integration test:
  1. Start reading a document
  2. Swipe up → verify onboarding overlay
  3. Wait 3s or tap → verify Micro tier with 3 words
  4. Swipe up → verify Clause tier with 5 words
  5. Swipe up → verify Sentence tier
  6. Swipe right twice → verify window shifted backward
  7. Swipe down → verify RSVP resumes from leftmost visible word
  8. Verify resume word index is earlier than trigger word
- **Acceptance criteria**:
  - [ ] Full gesture flow completes without errors
  - [ ] Resume position verified via word timer state
- **Principles**: P17
- **Effort**: L (~2 hr)
- **Depends on**: TASK-033 through TASK-044

---

### TASK-048: Integration test — auto-rewind + ContextReveal interaction
- **Priority**: 9
- **Files**: `test/core/word_timer_test.dart`
- **Action**: Test that auto-rewind does NOT apply when exiting ContextReveal:
  ```dart
  test('auto-rewind does not apply after ContextReveal exit')
  test('auto-rewind applies on regular pause-resume after ContextReveal session')
  ```
- **Acceptance criteria**:
  - [ ] ContextReveal exit → no 3-word rewind
  - [ ] Subsequent regular pause → auto-rewind works normally
- **Principles**: P17, P18
- **Effort**: S (~20 min)
- **Depends on**: TASK-034

---

### TASK-049: End-to-end gesture flow test (all 7 gestures)
- **Priority**: Integration
- **Files**: `CREATE: integration_test/gesture_flow_test.dart`
- **Action**: Test complete gesture map:
  1. Tap → pause/resume (verify auto-rewind on resume)
  2. Swipe left → next sentence
  3. Swipe right → previous sentence
  4. Swipe up → ContextReveal entry
  5. Swipe up (in ContextReveal) → tier advance
  6. Swipe left/right (in ContextReveal) → window shift
  7. Swipe down → dismiss ContextReveal + resume
- **Acceptance criteria**:
  - [ ] All 7 gestures mapped and functional
  - [ ] No gesture conflicts
  - [ ] Correct context (reading vs ContextReveal) determines gesture behavior
- **Principles**: P17, P18
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-033, TASK-008

---

### TASK-050: Design token completeness audit
- **Priority**: Integration
- **Files**: `lib/design/tokens.dart`, `lib/design/timing_tokens.dart`
- **Action**: Verify all design tokens referenced by v3 spec exist in the token files. Cross-reference every token name in the spec against the codebase.
  ```
  - [ ] All timing tokens from v3 spec present in SpeedyBoyTiming
  - [ ] All color tokens used by ContextReveal present in SpeedyBoyTokens
  - [ ] All typography styles used by new components present in SpeedyBoyTypography
  ```
- **Acceptance criteria**:
  - [ ] Zero missing tokens
  - [ ] `dart analyze lib/` reports zero warnings
- **Principles**: All
- **Effort**: S (~30 min)
- **Depends on**: TASK-001

---

### TASK-051: Reduced motion walkthrough
- **Priority**: Integration
- **Files**: All files with `isReducedMotion` checks
- **Action**: Manual walkthrough with reduced motion enabled:
  1. Verify A-001 word advance is instant
  2. Verify A-013 depth bounce is skipped
  3. Verify ContextReveal tier transitions are instant
  4. Verify gradient sweep timing (400ms/word) is PRESERVED
  5. Verify pause fog transitions are instant
  6. Verify card press/release animations are instant
  7. Verify no decorative motion occurs anywhere
- **Acceptance criteria**:
  - [ ] All decorative animations skip at reducedMotion
  - [ ] Functional timing (sweep, word display) preserved
  - [ ] No visual stutter or jarring transitions
- **Principles**: P5, P6
- **Effort**: M (~45 min)
- **Depends on**: All animation tasks

---

### TASK-052: `dart analyze` clean sweep
- **Priority**: Integration (final gate)
- **Files**: All lib/ files
- **Action**: Run `dart analyze lib/` and resolve any warnings or errors introduced by v3 tasks. Ensure zero warnings.
- **Acceptance criteria**:
  - [ ] `dart analyze lib/` → No issues found
  - [ ] `flutter test` → all tests pass (v2 + v3)
- **Principles**: All
- **Effort**: S (depends on findings)
- **Depends on**: All tasks

---

## Dependency Graph Summary

```
TASK-001 (timing tokens) ──┬── TASK-005 (A-013 logic) ── TASK-006 (tests) ── TASK-007 (integration)
                           ├── TASK-008 (auto-rewind) ── TASK-009 (tests)
                           ├── TASK-017 (room intensity) ── TASK-018 ── TASK-019 (tests)
                           └── TASK-038 (tier transitions)
                               TASK-039 (sweep engine)

TASK-002 (AppConfig fields) ─┬── TASK-003 (tests)
                             ├── TASK-004 (setters) ──┬── TASK-020 (parallax settings) ── TASK-021, 022, 023
                             │                        ├── TASK-026 (onboarding)
                             │                        └── TASK-043 (CR onboarding)
                             ├── TASK-024 (preset model) ── TASK-025 (UI) ── TASK-026, 027, 028
                             └── TASK-029 (ORP condition) ── TASK-030 (tests)

TASK-011 (contrast util) ──┬── TASK-012 (tests)
                           ├── TASK-014 (warning UI) ── TASK-016
                           └── TASK-015 (auto-shadow) ── TASK-016

TASK-031 (CR state) ── TASK-032 (notifier) ──┬── TASK-033 (gestures) ── TASK-047, 049
                                             ├── TASK-034 (pacing) ── TASK-048
                                             ├── TASK-035 (micro) ──┬── TASK-036 (clause)── TASK-037 (sentence) ── TASK-046
                                             │                      ├── TASK-038 (transitions)
                                             │                      ├── TASK-042 (overlay)
                                             │                      ├── TASK-043 (onboarding)
                                             │                      └── TASK-044 (a11y)
                                             ├── TASK-041 (navigation)
                                             └── TASK-045 (tests)

Independent: TASK-010 (WPM advisory), TASK-013 (contrast preview)
Final: TASK-050, TASK-051, TASK-052
```

---

**Effort Distribution:**
- XS (<15 min): 5 tasks
- S (15–45 min): 22 tasks
- M (45 min–2 hr): 18 tasks
- L (2–4 hr): 1 task
- **Total estimated tasks**: 52
- **Critical path**: TASK-001 → TASK-005 → TASK-007 (A-013 fix — ship-blocking)
