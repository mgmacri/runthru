# Speedy Boy v4 — Autopilot Prompt Sequence

Place this file in `docs/v4-autopilot-prompts.md` for reference.
Paste one sprint prompt at a time into Copilot Agent mode.
After each sprint: verify with `dart analyze lib/` and `flutter test`, then paste the next.

---

## Pre-flight: Apply Copilot Instructions Patch

**Mode**: Manual
**Action**: Apply the changes from `docs/v4-copilot-patch.md` to `.github/copilot-instructions.md`:
1. Replace Rule 20 with the v4 version (2-state ContextReveal)
2. Add Rules 24–28
3. Add the new design system files list
4. Add the updated gesture map
5. Add new/removed SpeedyBoyTiming tokens
6. Add updated skill mapping table

This must be done BEFORE running any sprint prompts — Copilot reads `.github/copilot-instructions.md` automatically.

---

## Sprint 0: v3 Cleanup

**Mode**: Agent
**Paste this**:

```
Execute Sprint 0 from docs/v4-task-backlog.md — v3 cleanup tasks TASK-100 through TASK-103.

CONTEXT: We are upgrading Speedy Boy from v3 to v4. The v4 design spec is at
docs/v4-design-spec.md. The task backlog is at docs/v4-task-backlog.md.
Read both files before starting.

The v3 implementation had 4 ContextReveal tiers (none/micro/clause/sentence).
v4 simplifies to 2 states (none/sentence). This sprint removes the dead code.

TASK-100: Remove micro and clause tiers
- In lib/core/context_reveal_state.dart: remove micro and clause from ContextRevealTier enum
- In lib/core/context_reveal_notifier.dart: remove advanceTier() method, simplify to
  enterSentence()/dismiss() only. Remove any micro/clause branching logic.
- In lib/widgets/context_reveal_overlay.dart: remove micro tier rendering (3-word display)
  and clause tier rendering (5-word display). Keep only the sentence tier rendering.
- Search entire lib/ for any remaining references to micro or clause and remove them.

TASK-101: Remove timing tokens
- In lib/design/timing_tokens.dart: remove contextRevealMicroWords,
  contextRevealClauseWords, and contextRevealTierAdvance

TASK-102: Remove dead tests
- In test/core/context_reveal_test.dart: remove tests referencing micro or clause
- In test/widgets/context_reveal_overlay_test.dart: remove micro/clause widget tests
- In integration_test/context_reveal_test.dart: remove micro/clause test steps
- Update remaining sentence tests to use the 2-state model

TASK-103: Replace hasSeenContextRevealOnboarding with shownHints
- In lib/store/models.dart: (no enum change needed)
- In lib/store/config.dart AppConfig: remove hasSeenContextRevealOnboarding field,
  add Set<String> shownHints field (default: empty set)
- Add to ConfigNotifier: markHintShown(String id) and hasHintBeenShown(String id)
- Serialize shownHints as List<String> in JSON, deserialize back to Set
- Must be backward compatible: missing key in JSON → empty set
- Update any code that checked hasSeenContextRevealOnboarding to use
  shownHints.contains('hint_swipe_up') instead
- Add/update tests in test/store/config_test.dart

RULES (from .github/copilot-instructions.md):
- Rule 10: barrel exports via lib/design/design.dart
- Rule 12: snake_case files, lowerCamelCase variables, UpperCamelCase classes
- Rule 13: Riverpod for state
- Rule 18: evidence traceability comments

After completing all 4 tasks, run:
  dart analyze lib/
  flutter test

Report any issues found.
```

**Verify before proceeding**:
- [ ] `ContextRevealTier` has only `none` and `sentence`
- [ ] No references to micro/clause in lib/ or test/
- [ ] `shownHints` field works with JSON round-trip
- [ ] `dart analyze lib/` → zero issues
- [ ] `flutter test` → all pass

---

## Sprint 1: Gesture System Overhaul

**Mode**: Agent
**Paste this**:

```
Execute Sprint 1 from docs/v4-task-backlog.md — gesture system tasks TASK-104 through TASK-108.

Reference these skill files for best practices:
- .claude/flutter-animating-apps.md (gesture detection patterns)
- .claude/riverpod-consumers.md (reading provider state in widgets)

CONTEXT: All swipe gestures were broken on Android in v3 due to gesture arena
conflicts. The fix is to use specific drag handlers instead of onPanEnd, and
require both distance AND velocity thresholds.

TASK-104: Create lib/design/gesture_tokens.dart
- abstract final class SpeedyBoyGestures with 4 constants:
  horizontalDistanceRatio = 0.30, horizontalMinVelocity = 200.0,
  verticalDistanceRatio = 0.20, verticalMinVelocity = 150.0
- Add // P3 — calibrated from Android testing traceability comments
- Add export to lib/design/design.dart barrel

TASK-105: Refactor gesture detection in reading viewport
- File: lib/screens/parallax_reading_screen.dart
- CRITICAL: Replace ALL onPanEnd/onPanUpdate handlers with SEPARATE
  onVerticalDragEnd/onVerticalDragUpdate and
  onHorizontalDragEnd/onHorizontalDragUpdate handlers
- Track drag distance via the Update callbacks using a _horizontalDragDistance
  and _verticalDragDistance accumulator, reset in onDragStart
- In the End callbacks, check BOTH conditions:
  distance >= screenDimension * SpeedyBoyGestures.ratio AND
  velocity >= SpeedyBoyGestures.minVelocity
- Use MediaQuery.of(context).size for screen dimensions
- IMPORTANT: Flutter does NOT allow both onVerticalDrag* and onHorizontalDrag*
  on the SAME GestureDetector. You must either:
  (a) Use onPanEnd with manual direction detection from velocity, OR
  (b) Use a RawGestureDetector with custom recognizers, OR
  (c) Use onPanUpdate/onPanEnd but manually classify direction from the
      primary axis of the drag delta
  Option (c) is simplest: track cumulative dx and dy in onPanUpdate.
  In onPanEnd, determine if the drag was primarily horizontal or vertical
  by comparing abs(dx) vs abs(dy). Then apply the appropriate threshold.
  This avoids the Flutter limitation while still getting specific thresholds.

TASK-106: Add double-tap handler
- Add onDoubleTap to the GestureDetector
- In RSVP mode: call new WordTimerNotifier.restartCurrentSentence() method
  that uses SentenceResolver to find current sentence start, seeks there,
  continues playing. If already at sentence start, go to previous sentence.
- In sentence view: restart gradient sweep from first word
- Add 200ms anchor color flash on the restart word (use AnimationController)
- NOTE: Adding onDoubleTap means onTap fires with ~300ms delay. This is
  expected and acceptable per Rule 25.

TASK-107: Add gesture logging
- Every detected gesture logs: [gestures] detected: <type> velocity=X distance=Y
- Use the existing AppLogger pattern

TASK-108: Create test/core/gesture_threshold_test.dart
- Test threshold logic at exact boundary values
- 5 tests: horizontal accepted, horizontal rejected (distance), horizontal
  rejected (velocity), vertical accepted, vertical rejected

After completing all tasks, run:
  dart analyze lib/
  flutter test

Verify on Android emulator:
- Tap to pause/resume works
- Swipe left/right at 30%+ triggers sentence nav
- Swipe up triggers sentence view
- Small accidental swipes do NOT trigger
```

**Verify before proceeding**:
- [ ] No `onPanEnd` used without manual direction classification
- [ ] Swipe thresholds use `SpeedyBoyGestures` tokens
- [ ] Double-tap restarts sentence
- [ ] Gesture logging visible in `flutter logs`
- [ ] All tests pass

---

## Sprint 2: ContextReveal v4 + Elastic Jiggle

**Mode**: Agent
**Paste this**:

```
Execute Sprint 2 from docs/v4-task-backlog.md — tasks TASK-109 through TASK-113.

Reference these skill files:
- .claude/flutter-animating-apps.md (spring animations, reduced motion)
- .claude/flutter-building-layouts.md (adaptive text sizing)
- .claude/flutter-theming-apps.md (token consumption)

TASK-109: Add v4 timing tokens to lib/design/timing_tokens.dart
Add these 12 new constants to SpeedyBoyTiming with traceability comments:
- jiggleScaleUpMs = 100 (P1), jiggleSpringBackMs = 200 (P1),
  jiggleMaxScale = 1.2 (P1), jiggleDampingRatio = 0.5 (P1)
- wpmDialInactivityMs = 1500 (P2), wpmDialFadeMs = 200 (P2),
  wpmDialStep = 25 (P2)
- hintAutoDismissMs = 4000 (P6), hintSlideInMs = 200 (P6)
- doubleTapWindowMs = 300 (P4), restartHighlightMs = 200 (P4)

TASK-110: Simplify ContextRevealNotifier for 2-state model
- File: lib/core/context_reveal_notifier.dart
- Remove advanceTier() entirely
- Rename enter() to enterSentence() — goes directly to sentence tier
- Add isJiggling transient flag (set true when jiggle triggered, clears after animation)
- Add triggerJiggle() method that sets isJiggling = true
- Keep: dismiss(), shiftWindowBack(), shiftWindowForward(),
  toggleSweepPause(), advanceSweep()

TASK-111: Implement elastic jiggle animation
- File: lib/widgets/context_reveal_overlay.dart
- When notifier.isJiggling is true, run this animation:
  1. Scale text container to 1.2x over 100ms (ease-out curve)
  2. Spring back to 1.0x over 200ms using SpringSimulation with
     dampingRatio 0.5
  3. Clear isJiggling flag after animation completes
- Use SpeedyBoyTiming.jiggleMaxScale, jiggleScaleUpMs, jiggleSpringBackMs,
  jiggleDampingRatio
- REDUCED MOTION CHECK (Rule 5): when isReducedMotion(context) is true,
  instead do opacity flash: 1.0 → 0.7 → 1.0 over 150ms total.
  The jiggle is decorative, not functional.
- Wire to gesture: swipe-up while already in sentence view → call
  notifier.triggerJiggle()

TASK-112: Adaptive sentence display sizing
- File: lib/widgets/context_reveal_overlay.dart
- When rendering sentence text in sentence view:
  1. Measure text at default SpeedyBoyTypography.readingWord() size
  2. If overflows 80% of viewport area → reduce font size by 2pt steps
  3. Readability floor based on device:
     shortestSide >= 600 (tablet): 18pt min
     shortestSide >= 400 (large phone): 16pt min
     below 400 (small phone): 14pt min
  4. If still overflows at floor → soft-wrap, center vertically
  5. Last resort: vertical scroll within sentence overlay
- Use LayoutBuilder to get constraints
- ORP anchor highlighting must work at all sizes
- Keep SpeedyBoyTypography.readingWord() font family, only adjust size

TASK-113: Create test/widgets/adaptive_sentence_test.dart
- 5 tests for adaptive sizing logic

After completing all tasks, run:
  dart analyze lib/
  flutter test

Verify on Android emulator:
- Swipe up → sentence view appears
- Swipe up again in sentence view → text jiggles and springs back
- Long sentence wraps readably (test with a 40-word sentence)
- Reduced motion → opacity flash instead of jiggle
```

**Verify before proceeding**:
- [ ] Jiggle animation feels like a spring (not linear)
- [ ] No micro/clause states reachable
- [ ] Long sentences don't shrink below readability floor
- [ ] Reduced motion works correctly
- [ ] All tests pass

---

## Sprint 3: WPM Dial

**Mode**: Agent
**Paste this**:

```
Execute Sprint 3 from docs/v4-task-backlog.md — tasks TASK-114 through TASK-118.

Reference these skill files:
- .claude/flutter-animating-apps.md (fade animation, timer patterns)
- .claude/flutter-building-layouts.md (overlay positioning)
- .claude/riverpod-providers.md (auto-dispose notifier)
- .claude/riverpod-auto-dispose.md (lifecycle management)
- .claude/flutter-handling-concurrency.md (inactivity timer)

TASK-114: Create lib/core/wpm_dial_state.dart
- WpmDialState immutable class: isVisible, currentWpm, position (Offset)
- copyWith method, defaults: isVisible=false, currentWpm=200, position=Offset.zero

TASK-115: Create lib/core/wpm_dial_notifier.dart
- Riverpod StateNotifier<WpmDialState> with auto-dispose
- Methods:
  show(Offset position, int currentWpm) → set visible, record position
  updateWpm(int wpm) → update WPM (clamp 100-600), reset inactivity timer
  dismiss() → hide dial, persist WPM via ConfigNotifier, fire onDismiss callback
- Inactivity timer: Timer that fires after SpeedyBoyTiming.wpmDialInactivityMs (1500ms)
  of no updateWpm() calls → auto-dismiss
- Injectable Timer.new factory for testability (same pattern as RoomIntensityController clock)
- On dispose, cancel any active timer

TASK-116: Create lib/widgets/wpm_dial.dart
- Vertical slider design (simpler than circular, works better on phones):
  - Tall rounded rectangle, positioned at long-press point
  - Drag UP to increase WPM, drag DOWN to decrease
  - WPM in 25-step increments (SpeedyBoyTiming.wpmDialStep)
  - Numeric WPM value displayed above the dial
  - Haptic feedback on each step: HapticFeedback.selectionClick()
- Visual:
  - 40% dim overlay behind dial (less than sentence view's 60%)
  - SpeedyBoyDecorations.raisedDecoration(SpeedyBoySurface.shell) for dial
  - SpeedyBoyTypography for WPM number
  - Shell surface tokens for dial, stage tokens for WPM display
- Fade out: SpeedyBoyTiming.wpmDialFadeMs (200ms) on dismiss
- Reduced motion: instant show/hide, no fade
- Rule 1: no raw colors. Rule 2: no hardcoded TextStyle. Rule 3: no hardcoded shadows.

TASK-117: Wire long-press into reading viewport
- File: lib/screens/parallax_reading_screen.dart
- Add onLongPressStart to GestureDetector (provides position)
- On long-press: pause WordTimerNotifier, show WPM dial at press position
- On dial dismiss: resume WordTimerNotifier at new WPM
- Tap anywhere outside dial → immediate dismiss
- Must work in both RSVP mode and sentence view
- Long-press does NOT conflict with tap or double-tap (different gesture)

TASK-118: Create test/core/wpm_dial_test.dart
- 6 tests with injectable timer
- Test: show/pause, updateWpm/reset timer, inactivity auto-dismiss,
  persist on dismiss, rapid changes reset timer, clamp to 100-600

After completing all tasks, run:
  dart analyze lib/
  flutter test

Verify on Android emulator:
- Long-press → dial appears, reading pauses
- Drag up/down → WPM changes in 25-step increments
- Release and wait 1.5s → dial fades, reading resumes
- Haptic feedback on each step
- Works in both RSVP and sentence view
```

**Verify before proceeding**:
- [ ] Dial appears at press position
- [ ] WPM persists after dismiss
- [ ] Auto-resume after 1.5s inactivity
- [ ] Haptic feedback on increments
- [ ] All tests pass

---

## Sprint 4: Overlay Hints (Onboarding)

**Mode**: Agent
**Paste this**:

```
Execute Sprint 4 from docs/v4-task-backlog.md — tasks TASK-119 through TASK-122.

Reference these skill files:
- .claude/flutter-animating-apps.md (slide-in animation)
- .claude/flutter-building-layouts.md (overlay positioning)
- .claude/flutter-improving-accessibility.md (screen reader for hints)
- .claude/flutter-theming-apps.md (token consumption)

TASK-119: Create lib/widgets/hint_overlay.dart
- Reusable pill-shaped overlay widget
- Parameters: text (String), position (Alignment), slideFrom (AxisDirection),
  onDismiss (VoidCallback)
- Visual:
  - Semi-transparent pill: 60% black background, white text
  - Rounded corners (borderRadius: 20)
  - Positioned near relevant gesture zone using Align widget
  - Slide-in from gesture direction over 200ms (SpeedyBoyTiming.hintSlideInMs)
  - Auto-dismiss timer: 4s (SpeedyBoyTiming.hintAutoDismissMs)
  - Any touch anywhere → dismiss immediately
- Use HitTestBehavior.translucent so touches pass through to the reading viewport
- Reduced motion: instant show/hide, no slide animation
- Semantics: hint text announced by screen reader
- Rule 1: no raw colors (use shell surface tokens for frame)
- Rule 2: no hardcoded TextStyle

TASK-120: Create lib/core/hint_controller.dart
- Class that manages hint trigger conditions
- Hint definitions:
  hint_tap: trigger after first word displayed
  hint_swipe_up: trigger after 10 words read
  hint_swipe_lr: trigger after first pause
  hint_double_tap: trigger after first sentence navigation
  hint_long_press: trigger after first WPM change OR after 2 minutes of reading
  hint_clipboard: trigger on empty library screen
- Each hint checked against AppConfig.shownHints via ConfigNotifier
- Method: shouldShowHint(String id, {required HintTriggerContext ctx}) → bool
  Returns true only if the trigger condition is met AND hint hasn't been shown
- Method: onHintShown(String id) → calls ConfigNotifier.markHintShown(id)
- HintTriggerContext: wordsRead, isPaused, hasDoneSentenceNav, hasChangedWpm,
  readingDurationSeconds, isLibraryEmpty

TASK-121: Wire hints into reading viewport
- File: lib/screens/parallax_reading_screen.dart
- Create a HintController instance
- At each trigger point, check shouldShowHint and overlay the HintOverlay widget
- Trigger points:
  - After WordTimerNotifier advances first word → check hint_tap
  - After wordsRead >= 10 → check hint_swipe_up
  - After first pause (tap) → check hint_swipe_lr
  - After first sentence navigation (swipe) → check hint_double_tap
  - After 2 minutes OR first WPM change → check hint_long_press
- Only show ONE hint at a time (queue if multiple would trigger)
- Hints must NOT block gesture detection

TASK-122: Create test/core/hint_controller_test.dart
- 5 tests for trigger conditions and persistence

After completing all tasks, run:
  dart analyze lib/
  flutter test

Verify on Android emulator:
- First word → "Tap to pause" hint appears near center
- After 10 words → "Swipe up to see the full sentence" appears
- After first pause → "Swipe left or right to change sentences" appears
- Hints auto-dismiss after 4s
- Hints never reappear after shown once
- Restart app → hints still dismissed
```

**Verify before proceeding**:
- [ ] Each hint appears at correct trigger
- [ ] No hint appears twice
- [ ] Hints don't block gestures
- [ ] Reduced motion: instant show/hide
- [ ] All tests pass

---

## Sprint 5: Clipboard Reader

**Mode**: Agent
**Paste this**:

```
Execute Sprint 5 from docs/v4-task-backlog.md — tasks TASK-123 through TASK-128.

Reference these skill files:
- .claude/flutter-building-layouts.md (clipboard UI, empty state)
- .claude/flutter-implementing-navigation-and-routing.md (navigation to reader)
- .claude/riverpod-providers.md (clipboard document provider)
- .claude/flutter-improving-accessibility.md (button labels)

TASK-123: Create lib/core/clipboard_document.dart
- ClipboardDocument class: title, fullText, words (List<String>), pastedAt (DateTime)
- Factory: ClipboardDocument.fromClipboardText(String text)
  - Title: first 40 chars trimmed, or "Clipboard" if shorter than 5 chars
  - Words: split on whitespace, preserve attached punctuation (same as PDF extraction)
  - Sentence boundaries: use SentenceResolver AND treat \n\n as boundaries

TASK-124: Create lib/core/clipboard_service.dart
- ClipboardService class with:
  Future<ClipboardDocument?> readFromClipboard() async
  - Uses Clipboard.getData(Clipboard.kTextPlain)
  - Returns null if clipboard empty, null, or text < 10 characters
  - Returns ClipboardDocument.fromClipboardText(text) for valid content
- PRIVACY: only reads when explicitly called, never auto-reads

TASK-125: Add "Paste from Clipboard" button to library screen
- File: lib/screens/ (find the library/home screen — search for the file list UI)
- Add a button/card: "Paste from Clipboard"
  - Always visible in the library, not just empty state
  - In empty state: make it prominent (larger, centered)
  - On tap: call ClipboardService.readFromClipboard()
  - If valid: show preview dialog with first ~100 chars + "Read" / "Cancel" buttons
  - If null: show inline snackbar "Nothing to read — copy some text first"
  - On "Read": navigate to reading viewport with the ClipboardDocument
- Uses shell surface tokens, SpeedyBoyDecorations, SpeedyBoyTypography
- Semantics: "Paste text from clipboard to read"

TASK-126: Wire ClipboardDocument into reading viewport
- File: lib/screens/parallax_reading_screen.dart, lib/core/word_timer.dart
- The reading viewport currently takes a PDF file path
- Add support for receiving a ClipboardDocument instead:
  Option A: Route parameter that carries either filePath OR ClipboardDocument
  Option B: Riverpod provider that holds the active document (either type)
- WordTimerNotifier.loadDocument() must accept a word list directly
  (not just extract from PDF)
- ALL existing functionality must work: gestures, WPM dial, sentence view,
  sentence restart, hints
- SentenceResolver must work on clipboard text
- Clipboard document NOT persisted — session only
- Use go_router for navigation (Rule 14)

TASK-127: Clipboard hint on empty library
- On empty library screen, if hint_clipboard not yet shown, display hint
  overlay pointing at the paste button
- Uses the hint system from Sprint 4

TASK-128: Create test/core/clipboard_test.dart
- 6 tests: tokenization, title extraction, paragraph boundaries,
  under 10 chars null, empty null, word list for viewport

After completing all tasks, run:
  dart analyze lib/
  flutter test

Verify on Android emulator:
- Copy text on the emulator (from browser or notes app)
- Open Speedy Boy → tap "Paste from Clipboard"
- Preview dialog shows first ~100 chars
- Tap "Read" → reading viewport with clipboard words
- All gestures work on clipboard content
- WPM dial works
- Sentence view works
- Empty clipboard → "Nothing to read" message
```

**Verify before proceeding**:
- [ ] Clipboard text reads and displays correctly
- [ ] Preview dialog shows before reading starts
- [ ] All gestures work on clipboard content
- [ ] Empty/short clipboard handled gracefully
- [ ] All tests pass

---

## Sprint 6: Integration Testing & Polish

**Mode**: Agent
**Paste this**:

```
Execute Sprint 6 from docs/v4-task-backlog.md — tasks TASK-129 through TASK-135.

Reference these skill files:
- .claude/flutter-testing-apps.md (integration test patterns)
- .claude/riverpod-testing.md (provider overrides in tests)

TASK-129: Create integration_test/context_reveal_v4_test.dart
- Full flow: start reading → swipe up → verify sentence view →
  swipe up again → verify jiggle (no tier change, stays in sentence) →
  swipe left/right → verify window shift →
  swipe down → verify resume from leftmost word →
  verify no micro/clause states are reachable

TASK-130: Create integration_test/gesture_flow_v4_test.dart
- Test all 7 v4 gestures:
  1. Tap → pause/resume (with 300ms delay)
  2. Double-tap → sentence restart
  3. Swipe left (30% + velocity) → next sentence
  4. Swipe right (30% + velocity) → previous sentence
  5. Swipe up → sentence view
  6. Swipe up in sentence → jiggle
  7. Swipe down → dismiss
  8. Long-press → WPM dial
  9. Sub-threshold swipe → nothing happens

TASK-131: Create integration_test/clipboard_test.dart
- Set clipboard text → tap paste → verify preview →
  confirm → verify reading viewport → verify all gestures

TASK-132: Create integration_test/wpm_dial_test.dart
- Long-press → dial → drag → wait 1.5s → auto-dismiss → verify persist

TASK-133: Create integration_test/hints_test.dart
- First word → tap hint → 10 words → swipe hint → verify persistence

TASK-134: Reduced motion walkthrough (MANUAL — do not automate)
- Print a checklist to console of what to verify manually:
  Elastic jiggle → opacity flash
  WPM dial fade → instant
  Hint slide-in → instant
  Sweep 400ms/word → preserved
  Double-tap highlight → preserved

TASK-135: Clean sweep
- Run: dart analyze lib/
- Run: flutter test
- Run: flutter test integration_test/
- Report results. Fix any issues found.

After ALL tasks, run:
  dart analyze lib/
  flutter test
  flutter test integration_test/ -d <emulator_device_id>

Report final status.
```

**Final verification**:
- [ ] `dart analyze lib/` → zero issues
- [ ] `flutter test` → all pass
- [ ] Integration tests pass on Android emulator
- [ ] Manual reduced motion walkthrough complete
- [ ] All 7 gestures work on Android
- [ ] Clipboard reading works end-to-end

---

## Troubleshooting: Common Autopilot Failures

**If Agent produces `onVerticalDragEnd` AND `onHorizontalDragEnd` on the same GestureDetector**:
Flutter doesn't allow this. Redirect to the onPanEnd approach with manual direction
classification described in Sprint 1 TASK-105.

**If gesture arena conflicts persist on Android**:
Add HitTestBehavior.opaque to the GestureDetector and verify no parent Scrollable
is consuming drag events. Check for SafeArea or Scaffold body wrappers.

**If double-tap doesn't fire**:
Verify onDoubleTap is on the SAME GestureDetector as onTap. They must coexist
on one detector for Flutter to arbitrate correctly.

**If WPM dial timer doesn't auto-dismiss**:
Check that the Timer is being reset (cancelled + recreated) on each updateWpm call,
not just restarted. Timer.periodic won't work here — use one-shot Timer.

**If hints block gesture detection**:
Verify HitTestBehavior.translucent on the hint overlay. The hint must let
touch events pass through to the reading viewport beneath it.

**If clipboard returns null on Android emulator**:
The emulator clipboard works through adb. Set it via:
adb shell input text "your test text here"
Or use the emulator's extended controls (⋮ → clipboard).
