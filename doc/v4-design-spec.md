# Speedy Boy v4.0 — Design Specification

**Version**: 4.0.0
**Date**: 2026-04-05
**Status**: Draft
**Based on**: Real-device Android testing of v3.0 implementation

---

## Design Philosophy

v4 is a **refinement release** driven by hands-on testing. The core RSVP reading engine is solid. v4 simplifies what didn't work (multi-word context tiers), strengthens what did (gesture system, single-word + sentence view), and adds quality-of-life features (clipboard reading, WPM dial, onboarding hints).

**Guiding principle**: Every interaction should be discoverable within 30 seconds of use, and every gesture should feel physically intuitive on a phone held at arm's length.

---

## Change Summary

| # | Change | Type | Impact |
|---|--------|------|--------|
| 1 | Remove micro/clause tiers, flatten ContextReveal to sentence-only | Simplification | Removes ~6 components, simplifies state machine |
| 2 | Elastic jiggle on swipe-up at sentence ceiling | Polish | Tactile feedback, prevents confusion |
| 3 | Long-press WPM dial (all screens) | New feature | Inline speed control without leaving reading |
| 4 | Gesture threshold tuning (30% screen width + velocity) | Fix | Eliminates accidental triggers, fixes Android swipe |
| 5 | Double-tap to restart sentence with highlight sweep | New feature | Quick re-read without manual navigation |
| 6 | Adaptive sentence display with readability floor | Improvement | Handles 30+ word sentences gracefully |
| 7 | First-use overlay hints per gesture | New feature | Progressive onboarding for new users |
| 8 | Read from clipboard | New feature | Opens app to non-PDF content |

---

## Priority 1: ContextReveal Simplification

### Current State (v3)
ContextReveal has 4 tiers: none → micro (3 words) → clause (5 words) → sentence. Testing revealed micro and clause modes are not useful — too few words for context recovery, too many states to navigate.

### v4 Design
Flatten to 2 states: **single-word** ↔ **sentence view**.

#### State Machine
```
┌─────────────┐    swipe up    ┌──────────────┐
│ Single Word  │──────────────▶│ Sentence View │
│   (RSVP)     │◀──────────────│              │
└─────────────┘   swipe down   └──────────────┘
                                      │
                                swipe up again
                                      │
                                      ▼
                               elastic jiggle
                              (stay in sentence)
```

#### Behavioral Rules

1. **Swipe up** during RSVP → pause reading, show full current sentence with gradient sweep
2. **Swipe up** while already in sentence view → text scales up ~120% then elastic-snaps back to normal size with a subtle jiggle (spring animation, ~300ms). This communicates "you're at the top — no more levels."
3. **Swipe down** in sentence view → dismiss, resume RSVP from leftmost visible word
4. **Swipe left/right** in sentence view → shift context window backward/forward by one sentence
5. **Tap** in sentence view → pause/resume gradient sweep
6. Gradient sweep still runs at 400ms/word (SpeedyBoyTiming.contextRevealSweepMs)
7. RSVP MUST pause the instant sentence view activates
8. Resume position is always the leftmost visible word, NOT the trigger word

#### Elastic Jiggle Animation
- Scale text to 1.2× over 100ms (ease-out)
- Spring back to 1.0× over 200ms (damped spring, dampingRatio ~0.5)
- Check `isReducedMotion` — when true, show a brief opacity flash instead (100% → 70% → 100% over 150ms)
- This animation is decorative, NOT functional

#### Do / Don't

| Do | Don't |
|----|-------|
| Show full current sentence in sentence view | Show partial sentence or word fragments |
| Resume from leftmost visible word | Resume from trigger word |
| Pause RSVP immediately on swipe-up | Let RSVP continue during sentence view |
| Jiggle on repeated swipe-up (ceiling feedback) | Add more tiers or levels |
| Keep gradient sweep at 400ms/word | Speed up sweep to match RSVP WPM |

#### Files to Remove (v3 cleanup)
- All micro tier rendering code in `context_reveal_overlay.dart`
- All clause tier rendering code in `context_reveal_overlay.dart`
- `ContextRevealTier.micro` and `ContextRevealTier.clause` enum values
- `contextRevealMicroWords` and `contextRevealClauseWords` from `SpeedyBoyTiming`
- Tier advance logic in `ContextRevealNotifier.advanceTier()`
- Micro/clause widget tests
- Micro/clause integration test steps

#### ContextRevealTier Enum (v4)
```dart
enum ContextRevealTier { none, sentence }
```

---

## Priority 2: Long-Press WPM Dial

### Design
A radial or linear dial that appears on long-press, allowing inline WPM adjustment without navigating to settings. Available in both single-word RSVP and sentence view.

#### Behavioral Rules

1. **Long-press** (anywhere on reading viewport) → reading pauses, WPM dial appears centered on press point
2. **Drag** on dial → adjust WPM (range: 100–600, same as settings slider)
3. **Release** → dial stays visible, timer starts (1.5 seconds of inactivity)
4. **No interaction for 1.5 seconds** → dial fades out (200ms), reading auto-resumes at new WPM
5. **Tap elsewhere while dial visible** → immediate dismiss + resume
6. WPM value displayed numerically above/below the dial while active
7. Haptic feedback on each 25 WPM increment (if device supports it)
8. Persist WPM change to AppConfig (same as settings slider)

#### Visual Design
- Semi-transparent overlay (40% dim, less than sentence view's 60%)
- Dial uses shell surface tokens for the control, stage tokens for the WPM display
- Circular dial: drag clockwise = increase, counter-clockwise = decrease
- OR vertical slider: drag up = increase, drag down = decrease
- Use `SpeedyBoyDecorations.raisedDecoration(SpeedyBoySurface.shell)` for dial background

#### Do / Don't

| Do | Don't |
|----|-------|
| Auto-resume after 1.5s inactivity | Require explicit dismiss gesture |
| Persist WPM change immediately | Wait for session end to persist |
| Show numeric WPM value while adjusting | Only show the dial position |
| Provide haptic feedback per increment | Fire haptics continuously |
| Work in both RSVP and sentence view | Only work in RSVP mode |

#### SpeedyBoyTiming Tokens
```dart
static const int wpmDialInactivityMs = 1500; // P2 — auto-resume delay
static const int wpmDialFadeMs = 200;         // P2 — fade out duration
static const int wpmDialStep = 25;            // P2 — haptic increment size
```

---

## Priority 3: Gesture Threshold Tuning

### Current Problem
Swipe gestures either don't trigger (too high threshold) or trigger accidentally. Horizontal swipes need consistent, intentional activation.

### v4 Design

#### Horizontal Swipe (Sentence Navigation)
- **Minimum distance**: 30% of screen width
- **Minimum velocity**: 200 pixels/second
- **Both conditions must be met** — distance alone or velocity alone is not enough
- Applies to: next sentence (swipe left), previous sentence (swipe right), and sentence view window shift

#### Vertical Swipe (ContextReveal)
- **Minimum distance**: 20% of screen height
- **Minimum velocity**: 150 pixels/second
- Applies to: enter sentence view (swipe up), dismiss sentence view (swipe down)

#### Implementation
Use `onVerticalDragEnd` and `onHorizontalDragEnd` (NOT `onPanEnd`) to avoid gesture arena conflicts. These specific recognizers win over general scroll recognizers.

```dart
// P3 — gesture thresholds calibrated from Android testing
abstract final class SpeedyBoyGestures {
  static const double horizontalDistanceRatio = 0.30;  // 30% of screen width
  static const double horizontalMinVelocity = 200.0;   // px/sec
  static const double verticalDistanceRatio = 0.20;     // 20% of screen height
  static const double verticalMinVelocity = 150.0;      // px/sec
}
```

#### Do / Don't

| Do | Don't |
|----|-------|
| Use onVerticalDragEnd / onHorizontalDragEnd | Use onPanEnd (loses gesture arena) |
| Require both distance AND velocity | Accept either condition alone |
| Calculate distance as ratio of screen size | Use fixed pixel thresholds |
| Test on Android emulator specifically | Assume iOS thresholds work on Android |

---

## Priority 4: Double-Tap Sentence Restart

### Design
Double-tap during RSVP restarts the current sentence from its first word, with the gradient sweep highlighting each word as it advances.

#### Behavioral Rules

1. **Double-tap** during RSVP → seek to first word of current sentence
2. Reading continues at current WPM from the sentence start
3. Brief highlight pulse on the first word (200ms anchor color flash) to confirm restart
4. If already at the first word of a sentence, double-tap restarts the PREVIOUS sentence
5. Double-tap in sentence view → restart sweep from first word (no dismiss)
6. Uses `SentenceResolver` to find sentence boundaries

#### Timing
- Double-tap window: 300ms between taps (standard platform default)
- Must NOT conflict with single-tap (pause/resume) — use `GestureDetector.onDoubleTap`
- Single tap fires after 300ms delay (waiting to confirm no second tap)

#### Do / Don't

| Do | Don't |
|----|-------|
| Restart from first word of current sentence | Rewind a fixed number of words |
| Show brief highlight pulse to confirm | Show modal "restarting" indicator |
| Seek to previous sentence if at sentence start | Do nothing at sentence start |
| Work in both RSVP and sentence view | Only work in RSVP mode |

#### Impact on Existing Gestures
Single-tap (pause/resume) will have a 300ms delay before firing, to wait for possible double-tap. This is the standard platform trade-off and is expected by users.

---

## Priority 5: Adaptive Sentence Display

### Design
When showing a sentence in sentence view, adapt text size and layout to maximize readability on the actual screen size.

#### Algorithm
```
1. Measure sentence text at default reading font size
2. If it fits within 80% of viewport area → display at default size
3. If it overflows → reduce font size in steps of 2pt
4. Stop reducing at readability floor (minimum font size)
5. If still overflows at minimum size → soft-wrap, allow vertical scroll within sentence view
```

#### Readability Floor
```dart
// P5 — adaptive sentence display
static double sentenceMinFontSize(BuildContext context) {
  final shortestSide = MediaQuery.of(context).size.shortestSide;
  if (shortestSide >= 600) return 18.0;  // Tablet
  if (shortestSide >= 400) return 16.0;  // Large phone
  return 14.0;                            // Small phone
}

static double sentenceMaxViewportRatio = 0.80; // Use 80% of viewport
```

#### Rules
- Never shrink below the readability floor for the device class
- Prefer wrapping over shrinking — 3 lines at readable size beats 1 line at tiny size
- Center text block vertically in the viewport
- Maintain `SpeedyBoyTypography.readingWord()` font family, only adjust size
- ORP anchor highlighting must work at all sizes

#### Do / Don't

| Do | Don't |
|----|-------|
| Adapt font size based on screen dimensions | Use a fixed font size for all devices |
| Set a readability floor per device class | Shrink text to fit no matter what |
| Prefer wrapping over shrinking | Truncate sentences |
| Center text block vertically | Align to top or bottom |
| Allow vertical scroll as last resort | Clip text that doesn't fit |

---

## Priority 6: First-Use Overlay Hints

### Design
Progressive onboarding: each gesture gets an overlay hint the FIRST TIME it becomes relevant. Hints appear once per gesture, per installation. Never block reading.

#### Hint Triggers

| Gesture | Trigger Moment | Hint Text |
|---------|---------------|-----------|
| Tap | First word displayed | "Tap to pause" |
| Swipe up | After first 10 words read | "Swipe up to see the full sentence" |
| Swipe left/right | After first pause | "Swipe left or right to change sentences" |
| Double-tap | After first sentence navigation | "Double-tap to restart this sentence" |
| Long-press | After first WPM change (or 2 min) | "Long-press for speed dial" |
| Clipboard | On empty library screen | "Paste text from clipboard to read" |

#### Visual Design
- Semi-transparent pill-shaped overlay near the gesture zone
- White text on dark overlay (60% black)
- Subtle slide-in animation (200ms, from gesture direction)
- Auto-dismiss after 4 seconds OR on any touch
- Shell surface tokens for overlay frame

#### Persistence
- Track per-hint shown state in AppConfig: `Set<String> shownHints`
- Hint IDs: `hint_tap`, `hint_swipe_up`, `hint_swipe_lr`, `hint_double_tap`, `hint_long_press`, `hint_clipboard`
- Never show the same hint twice
- Respect reduced motion: instant show/hide, no slide animation

#### Do / Don't

| Do | Don't |
|----|-------|
| Show hints progressively as gestures become relevant | Show all hints at once on first launch |
| Auto-dismiss after 4 seconds | Require user to dismiss each hint |
| Show each hint exactly once per installation | Re-show hints on app update |
| Allow any touch to dismiss early | Require tapping a specific "X" button |
| Time hints to natural pauses in reading | Interrupt active reading with hints |

#### AppConfig Addition
```dart
final Set<String> shownHints; // default: {} (empty set)
```

---

## Priority 7: Read from Clipboard

### Design
Allow users to paste text from their clipboard and read it through the RSVP engine. This opens the app to non-PDF content — articles, messages, study notes.

#### Entry Points
1. **Library screen**: "Paste from Clipboard" button (always visible)
2. **Empty state**: When no PDFs loaded, prominent clipboard CTA
3. **Share sheet** (future): Receive text from other apps via Android share intent

#### Flow
```
User taps "Paste from Clipboard"
  → Read system clipboard
  → If clipboard has text (>10 characters):
      → Create temporary document from clipboard text
      → Navigate to reading viewport
      → Begin RSVP at current WPM settings
  → If clipboard is empty or too short:
      → Show inline message: "Nothing to read — copy some text first"
  → If clipboard has non-text content:
      → Ignore, show same "Nothing to read" message
```

#### Temporary Document Model
```dart
class ClipboardDocument {
  final String title;       // First 40 chars of text, or "Clipboard"
  final String fullText;    // Raw pasted text
  final List<String> words; // Tokenized word list
  final DateTime pastedAt;
}
```

#### Word Tokenization
- Split on whitespace
- Preserve punctuation attached to words (same as PDF extraction)
- Use `SentenceResolver` for sentence boundary detection
- Treat paragraph breaks (\n\n) as sentence boundaries

#### Persistence
- Clipboard documents are NOT saved to the library by default
- Reading position IS saved during the session (can pause and resume)
- On app restart, clipboard document is cleared
- Future: "Save to Library" option to persist as a text document

#### Do / Don't

| Do | Don't |
|----|-------|
| Read clipboard on explicit user action (tap) | Auto-read clipboard on app launch |
| Show the first ~40 chars as preview before reading | Start reading immediately without confirmation |
| Support all plain text content | Try to parse HTML, markdown, or rich text |
| Clear clipboard document on app restart | Persist clipboard content permanently |
| Use the same reading viewport and gestures | Build a separate reader for clipboard |

#### Privacy
- Only access clipboard when user explicitly taps "Paste from Clipboard"
- Never access clipboard in the background
- Never send clipboard content anywhere
- Show a brief preview of what will be read before starting

---

## v4 Timing Tokens Update

### New Tokens
```dart
abstract final class SpeedyBoyTiming {
  // ... existing v3 tokens ...

  // ── v4: WPM Dial (P2) ──
  static const int wpmDialInactivityMs = 1500;
  static const int wpmDialFadeMs = 200;
  static const int wpmDialStep = 25;

  // ── v4: Elastic Jiggle (P1) ──
  static const int jiggleScaleUpMs = 100;
  static const int jiggleSpringBackMs = 200;
  static const double jiggleMaxScale = 1.2;
  static const double jiggleDampingRatio = 0.5;

  // ── v4: Overlay Hints (P6) ──
  static const int hintAutoDismissMs = 4000;
  static const int hintSlideInMs = 200;

  // ── v4: Double-Tap (P4) ──
  static const int doubleTapWindowMs = 300;
  static const int restartHighlightMs = 200;
}
```

### Removed Tokens
```dart
// REMOVED in v4:
// static const int contextRevealMicroWords = 3;
// static const int contextRevealClauseWords = 5;
// static const Duration contextRevealTierAdvance = Duration(milliseconds: 250);
```

### New Gesture Tokens
```dart
abstract final class SpeedyBoyGestures {
  // P3 — calibrated from Android testing
  static const double horizontalDistanceRatio = 0.30;
  static const double horizontalMinVelocity = 200.0;
  static const double verticalDistanceRatio = 0.20;
  static const double verticalMinVelocity = 150.0;
}
```

---

## v4 Gesture Map (Complete)

| Gesture | RSVP Mode | Sentence View |
|---------|-----------|---------------|
| **Tap** | Pause / resume | Pause / resume sweep |
| **Double-tap** | Restart current sentence | Restart sweep from first word |
| **Swipe left** | Next sentence | Shift window forward 1 sentence |
| **Swipe right** | Previous sentence | Shift window backward 1 sentence |
| **Swipe up** | Enter sentence view | Elastic jiggle (at ceiling) |
| **Swipe down** | *(no action)* | Dismiss → resume RSVP |
| **Long-press** | Show WPM dial | Show WPM dial |

---

## Updated AppConfig Fields (v4)

```dart
// New in v4:
final Set<String> shownHints;  // default: {} — tracks which hints have been shown
```

### Removed Fields
```dart
// REMOVED in v4 (was only needed for multi-tier ContextReveal):
// final bool hasSeenContextRevealOnboarding;  // replaced by shownHints system
```
