# Speedy Boy — Copilot Instructions v4 Patch

Apply these changes to `.github/copilot-instructions.md` on top of the existing v3 content.

---

## Changes to Existing Rules

### Rule 20 — REPLACE with:
**Old**: ContextReveal state machine. ContextReveal has exactly 4 tiers: none → micro → clause → sentence...
**New**:
20. **ContextReveal is 2-state.** ContextReveal has exactly 2 states: `none` ↔ `sentence`. There are NO intermediate tiers. Swipe up enters sentence view. Swipe up again in sentence view triggers elastic jiggle (ceiling feedback). Swipe down dismisses. RSVP MUST pause the instant state != none. Resume position is always the leftmost visible word, NOT the trigger word.

---

## New Rules (24–28)

24. **Gesture thresholds use screen ratios.** Horizontal swipes require 30% of screen width AND 200 px/s velocity. Vertical swipes require 20% of screen height AND 150 px/s. Both conditions must be met. All thresholds come from `SpeedyBoyGestures` in `lib/design/gesture_tokens.dart`. Use `onVerticalDragEnd` and `onHorizontalDragEnd` — never `onPanEnd`.
25. **Single-tap has 300ms delay.** Because of double-tap detection, `onTap` fires after a 300ms window. This is expected platform behavior. Do not work around it.
26. **WPM dial auto-resumes.** When the WPM dial is shown via long-press, reading pauses. After 1.5 seconds of no interaction, the dial auto-dismisses and reading resumes. Explicit tap elsewhere also dismisses immediately.
27. **Hints show once per installation.** Each gesture hint has a unique ID tracked in `AppConfig.shownHints`. Once shown, never show again. Use `ConfigNotifier.markHintShown(id)` and `ConfigNotifier.hasHintBeenShown(id)`.
28. **Clipboard documents are ephemeral.** ClipboardDocument is not persisted to the library. Reading position is tracked during the session only. Cleared on app restart. Clipboard is only read on explicit user action (never automatically).

---

## Updated ContextRevealTier Enum
```dart
// v4 — simplified from v3's { none, micro, clause, sentence }
enum ContextRevealTier { none, sentence }
```

---

## New Design System Files (v4)

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

---

## Updated Gesture Map (v4)

| Gesture | RSVP Mode | Sentence View |
|---------|-----------|---------------|
| Tap | Pause / resume (300ms delay) | Pause / resume sweep |
| Double-tap | Restart current sentence | Restart sweep from first word |
| Swipe left | Next sentence (30% + 200px/s) | Shift window forward |
| Swipe right | Previous sentence (30% + 200px/s) | Shift window backward |
| Swipe up | Enter sentence view (20% + 150px/s) | Elastic jiggle |
| Swipe down | *(no action)* | Dismiss → resume RSVP |
| Long-press | Show WPM dial | Show WPM dial |

---

## New SpeedyBoyTiming Tokens (v4)

```dart
// Elastic Jiggle (P1)
static const int jiggleScaleUpMs = 100;
static const int jiggleSpringBackMs = 200;
static const double jiggleMaxScale = 1.2;
static const double jiggleDampingRatio = 0.5;

// WPM Dial (P2)
static const int wpmDialInactivityMs = 1500;
static const int wpmDialFadeMs = 200;
static const int wpmDialStep = 25;

// Overlay Hints (P6)
static const int hintAutoDismissMs = 4000;
static const int hintSlideInMs = 200;

// Double-Tap (P4)
static const int doubleTapWindowMs = 300;
static const int restartHighlightMs = 200;
```

## Removed SpeedyBoyTiming Tokens (v4)
```dart
// REMOVED — micro/clause tiers eliminated
// contextRevealMicroWords
// contextRevealClauseWords
// contextRevealTierAdvance
```

---

## Updated Skill → Task Mapping (v4 additions)

| Domain | Skill File | v4 Tasks |
|--------|-----------|----------|
| Animation | `flutter-animating-apps` | Elastic jiggle, WPM dial fade, hint slide-in |
| Layout | `flutter-building-layouts` | WPM dial widget, clipboard UI, adaptive sentence sizing |
| Accessibility | `flutter-improving-accessibility` | Hint overlay a11y, WPM dial a11y |
| Concurrency | `flutter-handling-concurrency` | WPM dial inactivity timer, hint auto-dismiss timer |
