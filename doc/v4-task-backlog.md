# Speedy Boy v4.0 — Task Backlog

**Generated**: 2026-04-05
**Spec version**: 4.0.0
**Tasks**: 38
**Based on**: Android testing feedback from v3 implementation

---

## Sprint 0: v3 Cleanup (Remove Dead Code)

### TASK-100: Remove micro and clause tiers from ContextReveal
- **Priority**: 0 (prerequisite)
- **Files**: `lib/core/context_reveal_state.dart`, `lib/core/context_reveal_notifier.dart`, `lib/widgets/context_reveal_overlay.dart`
- **Action**: Remove `ContextRevealTier.micro` and `ContextRevealTier.clause` from the enum. Simplify to `{ none, sentence }`. Remove `advanceTier()` method — replace with `enterSentence()` and `dismiss()`. Remove all micro/clause rendering branches from the overlay widget. Remove `_leftExtent` switch cases for micro/clause.
- **Acceptance criteria**:
  - [ ] `ContextRevealTier` enum has only `none` and `sentence`
  - [ ] No references to micro or clause anywhere in lib/
  - [ ] `dart analyze lib/` passes
- **Effort**: S (~30 min)
- **Depends on**: Nothing

---

### TASK-101: Remove micro/clause timing tokens
- **Priority**: 0
- **Files**: `lib/design/timing_tokens.dart`
- **Action**: Remove `contextRevealMicroWords`, `contextRevealClauseWords`, and `contextRevealTierAdvance` from `SpeedyBoyTiming`.
- **Acceptance criteria**:
  - [ ] 3 tokens removed
  - [ ] No references to removed tokens in lib/
  - [ ] `dart analyze lib/` passes
- **Effort**: XS (~10 min)
- **Depends on**: TASK-100

---

### TASK-102: Remove micro/clause tests
- **Priority**: 0
- **Files**: `test/core/context_reveal_test.dart`, `test/widgets/context_reveal_overlay_test.dart`, `integration_test/context_reveal_test.dart`
- **Action**: Remove all test cases that reference micro or clause tiers. Update remaining sentence-tier tests to use the simplified 2-state model.
- **Acceptance criteria**:
  - [ ] No test references to micro or clause
  - [ ] Remaining tests pass
  - [ ] `flutter test` all green
- **Effort**: S (~20 min)
- **Depends on**: TASK-100, TASK-101

---

### TASK-103: Replace `hasSeenContextRevealOnboarding` with `shownHints`
- **Priority**: 0
- **Files**: `lib/store/models.dart`, `lib/store/config.dart`, `test/store/config_test.dart`
- **Action**: Remove `hasSeenContextRevealOnboarding` field from AppConfig. Add `Set<String> shownHints` field (default: empty set). Add `markHintShown(String hintId)` and `hasHintBeenShown(String hintId)` methods to ConfigNotifier. Update fromJson/toJson (serialize Set as List<String>). Update existing onboarding code to use `shownHints.contains('hint_swipe_up')` instead.
- **Acceptance criteria**:
  - [ ] `hasSeenContextRevealOnboarding` removed
  - [ ] `shownHints` field added with empty set default
  - [ ] JSON round-trip preserves hint set
  - [ ] Backward compatible (missing key → empty set)
  - [ ] `flutter test test/store/config_test.dart` passes
- **Effort**: S (~30 min)
- **Depends on**: Nothing

---

## Sprint 1: Gesture System Overhaul

### TASK-104: Create `SpeedyBoyGestures` token class
- **Priority**: 3
- **Files**: `CREATE: lib/design/gesture_tokens.dart`, `lib/design/design.dart`
- **Action**: Create gesture threshold token class and add to barrel export.
  ```dart
  abstract final class SpeedyBoyGestures {
    static const double horizontalDistanceRatio = 0.30;
    static const double horizontalMinVelocity = 200.0;
    static const double verticalDistanceRatio = 0.20;
    static const double verticalMinVelocity = 150.0;
  }
  ```
- **Acceptance criteria**:
  - [ ] 4 constants with traceability comments
  - [ ] Exported via design.dart barrel
  - [ ] `dart analyze` passes
- **Effort**: XS (~10 min)
- **Depends on**: Nothing

---

### TASK-105: Refactor gesture detection to split drag handlers
- **Priority**: 3
- **Files**: `lib/screens/parallax_reading_screen.dart`
- **Action**: Replace any `onPanEnd` with separate `onVerticalDragEnd` and `onHorizontalDragEnd`. Both handlers must check distance (as ratio of screen dimension) AND velocity against `SpeedyBoyGestures` tokens. Both conditions must be met for a swipe to register.
  ```dart
  onHorizontalDragEnd: (details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final distance = details.primaryVelocity != null ? _dragDistance.abs() : 0;
    final velocity = details.primaryVelocity?.abs() ?? 0;
    if (distance >= screenWidth * SpeedyBoyGestures.horizontalDistanceRatio &&
        velocity >= SpeedyBoyGestures.horizontalMinVelocity) {
      // Fire swipe
    }
  }
  ```
  Track `_dragDistance` via `onHorizontalDragUpdate` / `onVerticalDragUpdate`.
- **Acceptance criteria**:
  - [ ] No `onPanEnd` in reading viewport
  - [ ] Horizontal swipe requires 30% screen width + 200 px/s
  - [ ] Vertical swipe requires 20% screen height + 150 px/s
  - [ ] Both conditions must be met (AND, not OR)
  - [ ] Uses `SpeedyBoyGestures` tokens (no hardcoded values)
  - [ ] Tap still works (no interference)
- **Effort**: M (~1 hr)
- **Depends on**: TASK-104

---

### TASK-106: Add double-tap handler for sentence restart
- **Priority**: 4
- **Files**: `lib/screens/parallax_reading_screen.dart`, `lib/core/word_timer.dart`
- **Action**: Add `onDoubleTap` to the GestureDetector. In RSVP mode: seek to first word of current sentence using `SentenceResolver`, continue playing. In sentence view: restart gradient sweep from first word. Add `restartCurrentSentence()` method to WordTimerNotifier that uses SentenceResolver to find and seek to sentence start. If already at sentence start, seek to previous sentence start. Flash anchor color on first word (200ms) to confirm.
- **Acceptance criteria**:
  - [ ] Double-tap during RSVP → restart from sentence beginning
  - [ ] Double-tap at sentence start → go to previous sentence
  - [ ] Double-tap in sentence view → restart sweep
  - [ ] Brief highlight pulse on first word (200ms)
  - [ ] Single-tap still works (300ms delay is acceptable)
  - [ ] Uses `SentenceResolver` for boundary detection
- **Effort**: M (~1 hr)
- **Depends on**: TASK-105

---

### TASK-107: Add gesture logging for debugging
- **Priority**: 3
- **Files**: `lib/screens/parallax_reading_screen.dart`
- **Action**: Add `[gestures]` log lines for every detected gesture:
  ```
  [gestures] detected: swipeUp velocity=X distance=Y
  [gestures] detected: doubleTap
  [gestures] detected: longPress
  ```
- **Acceptance criteria**:
  - [ ] Every gesture fires a log line with relevant metrics
  - [ ] Logs visible in `flutter logs` on Android
- **Effort**: XS (~15 min)
- **Depends on**: TASK-105

---

### TASK-108: Gesture threshold unit tests
- **Priority**: 3
- **Files**: `CREATE: test/core/gesture_threshold_test.dart`
- **Action**: Test gesture threshold logic.
  ```dart
  test('horizontal swipe accepted at 30% width + 200px/s')
  test('horizontal swipe rejected at 29% width + 200px/s')
  test('horizontal swipe rejected at 30% width + 199px/s')
  test('vertical swipe accepted at 20% height + 150px/s')
  test('vertical swipe rejected below threshold')
  ```
- **Acceptance criteria**:
  - [ ] All 5 tests pass with boundary values
- **Effort**: S (~20 min)
- **Depends on**: TASK-105

---

## Sprint 2: ContextReveal v4 + Elastic Jiggle

### TASK-109: Add v4 timing tokens (jiggle, WPM dial, hints)
- **Priority**: 1
- **Files**: `lib/design/timing_tokens.dart`
- **Action**: Add new v4 tokens to SpeedyBoyTiming:
  ```dart
  // v4: Elastic Jiggle (P1)
  static const int jiggleScaleUpMs = 100;
  static const int jiggleSpringBackMs = 200;
  static const double jiggleMaxScale = 1.2;
  static const double jiggleDampingRatio = 0.5;

  // v4: WPM Dial (P2)
  static const int wpmDialInactivityMs = 1500;
  static const int wpmDialFadeMs = 200;
  static const int wpmDialStep = 25;

  // v4: Overlay Hints (P6)
  static const int hintAutoDismissMs = 4000;
  static const int hintSlideInMs = 200;

  // v4: Double-Tap (P4)
  static const int doubleTapWindowMs = 300;
  static const int restartHighlightMs = 200;
  ```
- **Acceptance criteria**:
  - [ ] All 12 new tokens with traceability comments
  - [ ] `dart analyze` passes
- **Effort**: XS (~15 min)
- **Depends on**: TASK-101

---

### TASK-110: Simplify ContextRevealNotifier for 2-state model
- **Priority**: 1
- **Files**: `lib/core/context_reveal_notifier.dart`
- **Action**: Replace `advanceTier()` with `jiggle()` callback. Methods: `enterSentence(int currentWordIndex)`, `dismiss() → int`, `shiftWindowBack()`, `shiftWindowForward()`, `toggleSweepPause()`, `advanceSweep()`. Add `isJiggling` transient state flag (not persisted, clears after animation completes).
- **Acceptance criteria**:
  - [ ] Only 2 states: none and sentence
  - [ ] `enterSentence()` replaces `enter()` + automatic tier to sentence
  - [ ] No tier advancement logic
  - [ ] `isJiggling` flag for animation
  - [ ] All existing sentence-level behavior preserved
- **Effort**: S (~30 min)
- **Depends on**: TASK-100

---

### TASK-111: Implement elastic jiggle animation
- **Priority**: 1
- **Files**: `lib/widgets/context_reveal_overlay.dart`
- **Action**: When swipe-up fires while already in sentence view, trigger the elastic jiggle:
  1. Scale text container to 1.2× over 100ms (ease-out)
  2. Spring back to 1.0× over 200ms (damped spring, dampingRatio 0.5)
  Use `AnimationController` with `SpringSimulation`. Check `isReducedMotion` — when true, opacity flash (100% → 70% → 100% over 150ms) instead.
- **Acceptance criteria**:
  - [ ] Text scales up then springs back
  - [ ] Animation total ~300ms
  - [ ] Reduced motion: opacity flash instead
  - [ ] Uses SpeedyBoyTiming tokens
  - [ ] Feels physically satisfying (spring, not linear)
- **Effort**: M (~45 min)
- **Depends on**: TASK-109, TASK-110
- **Skills**: `flutter-animating-apps`

---

### TASK-112: Adaptive sentence display sizing
- **Priority**: 5
- **Files**: `lib/widgets/context_reveal_overlay.dart`
- **Action**: When rendering sentence view, measure text at default size. If it overflows 80% of viewport, reduce font size in 2pt steps down to readability floor. Floor depends on device class:
  - Tablet (shortestSide ≥ 600): 18pt min
  - Large phone (shortestSide ≥ 400): 16pt min
  - Small phone: 14pt min
  If still overflows at floor, soft-wrap with vertical centering. As absolute last resort, allow vertical scroll within the sentence overlay.
- **Acceptance criteria**:
  - [ ] Short sentences (~10 words) display at default size
  - [ ] Long sentences (30+ words) reduce size but stay above floor
  - [ ] Very long sentences wrap rather than shrink below floor
  - [ ] Text centered vertically in viewport
  - [ ] ORP anchor highlighting works at all sizes
  - [ ] Tested on both phone and tablet screen sizes
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-110
- **Skills**: `flutter-building-layouts`

---

### TASK-113: Sentence display unit tests
- **Priority**: 5
- **Files**: `CREATE: test/widgets/adaptive_sentence_test.dart`
- **Action**: Test adaptive sizing logic.
  ```dart
  test('short sentence renders at default font size')
  test('30-word sentence reduces font size')
  test('font size never below readability floor')
  test('very long sentence wraps with vertical centering')
  test('readability floor varies by device class')
  ```
- **Acceptance criteria**:
  - [ ] All 5 tests pass
- **Effort**: S (~25 min)
- **Depends on**: TASK-112

---

## Sprint 3: WPM Dial

### TASK-114: WPM dial state model
- **Priority**: 2
- **Files**: `CREATE: lib/core/wpm_dial_state.dart`
- **Action**: Create state model for WPM dial:
  ```dart
  class WpmDialState {
    final bool isVisible;
    final int currentWpm;
    final Offset position;  // Center point of dial
    const WpmDialState({
      this.isVisible = false,
      this.currentWpm = 200,
      this.position = Offset.zero,
    });
  }
  ```
- **Acceptance criteria**:
  - [ ] Immutable state with copyWith
  - [ ] Default: not visible, 200 WPM
- **Effort**: XS (~10 min)
- **Depends on**: Nothing

---

### TASK-115: WPM dial notifier with inactivity timer
- **Priority**: 2
- **Files**: `CREATE: lib/core/wpm_dial_notifier.dart`
- **Action**: Riverpod StateNotifier for dial. Methods:
  - `show(Offset position, int currentWpm)` → show dial, pause reading
  - `updateWpm(int wpm)` → update WPM, reset inactivity timer
  - `dismiss()` → hide dial, persist WPM, resume reading
  - Inactivity timer: 1.5 seconds after last `updateWpm()` call → auto-dismiss
  - On dismiss, call `ConfigNotifier.setDefaultWpm()` to persist
- **Acceptance criteria**:
  - [ ] Dial shows on `show()`, pauses reading
  - [ ] WPM updates on drag
  - [ ] Inactivity timer auto-dismisses after 1.5s
  - [ ] WPM persisted to AppConfig on dismiss
  - [ ] Auto-dispose provider
- **Effort**: S (~30 min)
- **Depends on**: TASK-114, TASK-109

---

### TASK-116: WPM dial widget
- **Priority**: 2
- **Files**: `CREATE: lib/widgets/wpm_dial.dart`
- **Action**: Circular or vertical dial widget. Requirements:
  - Semi-transparent overlay (40% dim)
  - Centered on long-press point
  - Drag to adjust WPM (100–600 range)
  - Numeric WPM display above/below dial
  - Haptic feedback per 25 WPM increment
  - Fade out over 200ms on dismiss
  - Shell surface tokens for dial, stage tokens for WPM text
  - `SpeedyBoyDecorations.raisedDecoration(SpeedyBoySurface.shell)` for background
- **Acceptance criteria**:
  - [ ] Dial renders at press position
  - [ ] Drag adjusts WPM in 25-step increments
  - [ ] Numeric value displayed and updates live
  - [ ] Haptic fires per increment
  - [ ] Overlay at 40% dim
  - [ ] Fade out on dismiss
  - [ ] Uses design system tokens
  - [ ] Reduced motion: no fade, instant show/hide
- **Effort**: L (~2.5 hr)
- **Depends on**: TASK-115
- **Skills**: `flutter-animating-apps`, `flutter-building-layouts`

---

### TASK-117: Wire long-press to WPM dial in reading viewport
- **Priority**: 2
- **Files**: `lib/screens/parallax_reading_screen.dart`
- **Action**: Add `onLongPress` and `onLongPressStart` to GestureDetector. On long-press, show WPM dial at press position. Works in both RSVP and sentence view. Ensure long-press does NOT conflict with tap (different gesture, handled by Flutter's gesture system natively).
- **Acceptance criteria**:
  - [ ] Long-press shows WPM dial
  - [ ] Works in both RSVP and sentence view
  - [ ] Pauses reading while dial visible
  - [ ] Auto-resumes after 1.5s inactivity
  - [ ] Tap elsewhere dismisses immediately
  - [ ] No conflict with tap or double-tap
- **Effort**: S (~30 min)
- **Depends on**: TASK-116, TASK-106

---

### TASK-118: WPM dial tests
- **Priority**: 2
- **Files**: `CREATE: test/core/wpm_dial_test.dart`
- **Action**: Test dial state and inactivity timer.
  ```dart
  test('show() makes dial visible and pauses reading')
  test('updateWpm changes WPM and resets timer')
  test('inactivity timer fires after 1.5 seconds')
  test('dismiss persists WPM to AppConfig')
  test('rapid WPM changes reset timer each time')
  test('WPM clamped to 100-600 range')
  ```
- **Acceptance criteria**:
  - [ ] All 6 tests pass
  - [ ] Uses injectable timer for deterministic testing
- **Effort**: S (~25 min)
- **Depends on**: TASK-115

---

## Sprint 4: Overlay Hints (Onboarding)

### TASK-119: Hint overlay widget
- **Priority**: 6
- **Files**: `CREATE: lib/widgets/hint_overlay.dart`
- **Action**: Reusable hint overlay widget:
  - Semi-transparent pill shape (60% black background, white text)
  - Positioned near the relevant gesture zone
  - Slide-in animation from gesture direction (200ms)
  - Auto-dismiss timer (4 seconds)
  - Any touch dismisses immediately
  - `isReducedMotion` → instant show/hide, no slide
  - Uses shell surface tokens for frame
  ```dart
  class HintOverlay extends StatelessWidget {
    final String text;
    final Alignment position;     // Where on screen
    final AxisDirection slideFrom; // Animation direction
    final VoidCallback onDismiss;
  }
  ```
- **Acceptance criteria**:
  - [ ] Pill-shaped overlay with correct styling
  - [ ] Slide-in animation from gesture direction
  - [ ] Auto-dismiss after 4s
  - [ ] Touch anywhere dismisses
  - [ ] Reduced motion: instant
  - [ ] Uses SpeedyBoyTiming tokens
- **Effort**: M (~45 min)
- **Depends on**: TASK-109
- **Skills**: `flutter-animating-apps`, `flutter-building-layouts`

---

### TASK-120: Hint trigger system
- **Priority**: 6
- **Files**: `CREATE: lib/core/hint_controller.dart`
- **Action**: Controller that decides when to show each hint based on user progress:
  - `hint_tap` → after first word displayed
  - `hint_swipe_up` → after 10 words read
  - `hint_swipe_lr` → after first pause
  - `hint_double_tap` → after first sentence navigation
  - `hint_long_press` → after first WPM change OR after 2 minutes
  - `hint_clipboard` → on empty library screen
  Each hint checked against `AppConfig.shownHints`. Once shown, `markHintShown()` called.
- **Acceptance criteria**:
  - [ ] Each hint triggers at correct moment
  - [ ] Hints never shown twice
  - [ ] Hint state persisted across sessions
  - [ ] Hints don't interrupt active word advancement
- **Effort**: M (~1 hr)
- **Depends on**: TASK-103, TASK-119

---

### TASK-121: Wire hints into reading viewport
- **Priority**: 6
- **Files**: `lib/screens/parallax_reading_screen.dart`
- **Action**: Integrate hint controller into the reading viewport. At each trigger point, check if hint should show and overlay it. Hints must NOT block gesture detection — they overlay on top but touch passes through to dismiss.
- **Acceptance criteria**:
  - [ ] Tap hint appears on first word
  - [ ] Swipe-up hint appears after 10 words
  - [ ] Swipe-LR hint appears after first pause
  - [ ] Double-tap hint appears after first sentence nav
  - [ ] Long-press hint appears after 2 min or first WPM change
  - [ ] No hint blocks any gesture
- **Effort**: M (~45 min)
- **Depends on**: TASK-120

---

### TASK-122: Hint tests
- **Priority**: 6
- **Files**: `CREATE: test/core/hint_controller_test.dart`
- **Action**: Test trigger conditions and persistence.
  ```dart
  test('tap hint triggers after first word')
  test('swipe-up hint triggers after 10 words')
  test('hint not shown if already in shownHints')
  test('markHintShown persists to AppConfig')
  test('all 6 hint IDs recognized')
  ```
- **Acceptance criteria**:
  - [ ] All 5 tests pass
- **Effort**: S (~20 min)
- **Depends on**: TASK-120

---

## Sprint 5: Clipboard Reader

### TASK-123: ClipboardDocument model
- **Priority**: 7
- **Files**: `CREATE: lib/core/clipboard_document.dart`
- **Action**: Create model for clipboard-sourced documents:
  ```dart
  class ClipboardDocument {
    final String title;       // First 40 chars or "Clipboard"
    final String fullText;
    final List<String> words;
    final DateTime pastedAt;
  }
  ```
  Include `fromClipboardText(String text)` factory that tokenizes words using the same logic as PDF extraction. Use `SentenceResolver` for sentence boundary detection. Treat `\n\n` as sentence boundaries.
- **Acceptance criteria**:
  - [ ] Title extracted from first 40 chars
  - [ ] Words tokenized same as PDF pipeline
  - [ ] Sentence boundaries detected
  - [ ] Paragraph breaks treated as sentence boundaries
- **Effort**: S (~30 min)
- **Depends on**: Nothing

---

### TASK-124: Clipboard reading service
- **Priority**: 7
- **Files**: `CREATE: lib/core/clipboard_service.dart`
- **Action**: Service to read from system clipboard:
  ```dart
  class ClipboardService {
    Future<ClipboardDocument?> readFromClipboard() async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.length < 10) return null;
      return ClipboardDocument.fromClipboardText(data.text!);
    }
  }
  ```
  Only reads when explicitly called. Never auto-reads. Returns null for empty, too-short, or non-text clipboard.
- **Acceptance criteria**:
  - [ ] Returns ClipboardDocument for valid text (≥10 chars)
  - [ ] Returns null for empty clipboard
  - [ ] Returns null for text under 10 characters
  - [ ] Never reads automatically
- **Effort**: XS (~15 min)
- **Depends on**: TASK-123

---

### TASK-125: "Paste from Clipboard" button on library screen
- **Priority**: 7
- **Files**: `lib/screens/library_screen.dart` (or equivalent)
- **Action**: Add "Paste from Clipboard" button to library screen:
  - Always visible (not just empty state)
  - On tap: read clipboard via ClipboardService
  - If valid: show preview (first ~100 chars) in confirmation dialog → navigate to reading viewport
  - If empty/invalid: show inline message "Nothing to read — copy some text first"
  - Prominent CTA in empty state (when no PDFs loaded)
  - Uses shell surface tokens
- **Acceptance criteria**:
  - [ ] Button always visible on library screen
  - [ ] Preview shown before starting read
  - [ ] Invalid clipboard → helpful error message
  - [ ] Navigates to reading viewport on confirm
  - [ ] Prominent placement in empty state
  - [ ] Privacy: only reads on explicit tap
- **Effort**: M (~1 hr)
- **Depends on**: TASK-124
- **Skills**: `flutter-building-layouts`

---

### TASK-126: Wire ClipboardDocument into reading viewport
- **Priority**: 7
- **Files**: `lib/screens/parallax_reading_screen.dart`, `lib/core/word_timer.dart`
- **Action**: Reading viewport currently expects a PDF file path. Add alternate constructor or provider that accepts a `ClipboardDocument` directly. `WordTimerNotifier.loadDocument()` should accept either a file path + extracted words OR a ClipboardDocument's word list. All gestures, WPM dial, sentence view work identically.
- **Acceptance criteria**:
  - [ ] Reading viewport works with clipboard text
  - [ ] All gestures function identically
  - [ ] WPM dial works
  - [ ] Sentence view works (SentenceResolver on clipboard text)
  - [ ] Reading position tracked during session
  - [ ] Clipboard document cleared on app restart
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-125

---

### TASK-127: Clipboard hint on empty library
- **Priority**: 7
- **Files**: `lib/screens/library_screen.dart`
- **Action**: When library is empty and `hint_clipboard` hasn't been shown, display the clipboard hint overlay pointing at the paste button. Uses the hint system from TASK-119/120.
- **Acceptance criteria**:
  - [ ] Hint appears on empty library (first time only)
  - [ ] Points at paste button
  - [ ] Auto-dismiss after 4s
  - [ ] Persisted via shownHints
- **Effort**: XS (~15 min)
- **Depends on**: TASK-121, TASK-125

---

### TASK-128: Clipboard tests
- **Priority**: 7
- **Files**: `CREATE: test/core/clipboard_test.dart`
- **Action**: Test clipboard document creation and service.
  ```dart
  test('clipboard text tokenized into words')
  test('title extracted from first 40 chars')
  test('paragraph breaks create sentence boundaries')
  test('clipboard under 10 chars returns null')
  test('empty clipboard returns null')
  test('clipboard document provides word list for reading viewport')
  ```
- **Acceptance criteria**:
  - [ ] All 6 tests pass
- **Effort**: S (~20 min)
- **Depends on**: TASK-124

---

## Sprint 6: Integration Testing & Polish

### TASK-129: Integration test — simplified ContextReveal flow
- **Priority**: Integration
- **Files**: `integration_test/context_reveal_v4_test.dart`
- **Action**: End-to-end test:
  1. Start reading → swipe up → verify sentence view
  2. Swipe up again → verify elastic jiggle (no tier change)
  3. Swipe left/right → verify sentence window shift
  4. Swipe down → verify resume from leftmost word
  5. Verify no micro/clause states reachable
- **Effort**: M (~1 hr)
- **Depends on**: TASK-110, TASK-111

---

### TASK-130: Integration test — full gesture flow (v4)
- **Priority**: Integration
- **Files**: `integration_test/gesture_flow_v4_test.dart`
- **Action**: Test all v4 gestures:
  1. Tap → pause/resume
  2. Double-tap → sentence restart
  3. Swipe left (30% + velocity) → next sentence
  4. Swipe right (30% + velocity) → previous sentence
  5. Swipe up → sentence view
  6. Swipe up in sentence → jiggle
  7. Swipe down → dismiss
  8. Long-press → WPM dial appears
  9. Verify sub-threshold swipes don't trigger
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-106, TASK-117

---

### TASK-131: Integration test — clipboard reading flow
- **Priority**: Integration
- **Files**: `integration_test/clipboard_test.dart`
- **Action**: Test clipboard-to-reading flow:
  1. Set clipboard text programmatically
  2. Tap "Paste from Clipboard"
  3. Verify preview dialog
  4. Confirm → verify reading viewport with clipboard words
  5. Verify all gestures work on clipboard content
- **Effort**: M (~1 hr)
- **Depends on**: TASK-126

---

### TASK-132: Integration test — WPM dial
- **Priority**: Integration
- **Files**: `integration_test/wpm_dial_test.dart`
- **Action**: Test dial lifecycle:
  1. Long-press → dial appears, reading pauses
  2. Drag → WPM changes
  3. Wait 1.5s → dial auto-dismisses, reading resumes
  4. Verify WPM persisted
- **Effort**: S (~30 min)
- **Depends on**: TASK-117

---

### TASK-133: Overlay hints integration test
- **Priority**: Integration
- **Files**: `integration_test/hints_test.dart`
- **Action**: Test hint progression:
  1. First word → tap hint appears
  2. After 10 words → swipe-up hint
  3. Dismiss hints, verify they don't reappear
  4. Restart app → verify hints still dismissed
- **Effort**: S (~30 min)
- **Depends on**: TASK-121

---

### TASK-134: Reduced motion walkthrough (v4)
- **Priority**: Integration
- **Files**: Manual
- **Action**: Verify with reduced motion enabled:
  1. Elastic jiggle → opacity flash instead
  2. WPM dial fade → instant show/hide
  3. Hint slide-in → instant show/hide
  4. Gradient sweep 400ms/word → PRESERVED
  5. Double-tap highlight → PRESERVED (functional)
- **Effort**: S (~30 min)
- **Depends on**: All animation tasks

---

### TASK-135: `dart analyze` clean sweep (v4)
- **Priority**: Integration (final gate)
- **Files**: All lib/ files
- **Action**: `dart analyze lib/` + `flutter test` → zero issues.
- **Effort**: S (depends on findings)
- **Depends on**: All tasks

---

## Dependency Graph

```
Sprint 0 (cleanup):
  TASK-100 (remove tiers) ── TASK-101 (remove tokens) ── TASK-102 (remove tests)
  TASK-103 (shownHints) ─────────────────────────────────┐
                                                          │
Sprint 1 (gestures):                                      │
  TASK-104 (gesture tokens) ── TASK-105 (split drags) ──┬── TASK-106 (double-tap)
                                                        └── TASK-107 (logging)
                                                        └── TASK-108 (tests)

Sprint 2 (ContextReveal v4):
  TASK-109 (v4 tokens) ──┬── TASK-111 (jiggle animation)
                         └── TASK-119 (hint widget)
  TASK-100 ── TASK-110 (simplified notifier) ──┬── TASK-111
                                               ├── TASK-112 (adaptive sizing) ── TASK-113
                                               └── TASK-129 (integration)

Sprint 3 (WPM dial):
  TASK-114 (dial state) ── TASK-115 (dial notifier) ──┬── TASK-116 (dial widget)
                                                       └── TASK-118 (tests)
  TASK-116 ── TASK-117 (wire long-press) ── TASK-132 (integration)

Sprint 4 (hints):
  TASK-103 ── TASK-120 (hint controller) ── TASK-121 (wire into viewport) ── TASK-133
  TASK-119 ── TASK-120
  TASK-122 (tests)

Sprint 5 (clipboard):
  TASK-123 (model) ── TASK-124 (service) ──┬── TASK-125 (UI) ── TASK-126 (wire) ── TASK-131
                                           └── TASK-128 (tests)
  TASK-127 (hint) requires TASK-121 + TASK-125

Sprint 6: TASK-129–135 (integration + polish)
```

---

## Effort Distribution

- XS (<15 min): 6 tasks
- S (15–45 min): 14 tasks
- M (45 min–2 hr): 13 tasks
- L (2–4 hr): 1 task
- **Total tasks**: 38 (vs 52 in v3 — simpler scope)
- **Estimated total**: ~22 hours

## Critical Path

```
TASK-100 (remove tiers) → TASK-110 (simplify notifier) → TASK-111 (jiggle) → TASK-129 (integration)
```

This is the shortest path to a working v4 ContextReveal. ~2.5 hours.
