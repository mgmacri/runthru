# RunThru v3.0 — UX/UI Design Specification

**Product**: RunThru v3.0 — Adaptive Reading with 3D Neumorphic Cube Viewport
**Spec Version**: 3.0.0
**Date**: 2026-04-01
**Supersedes**: `runthru_design_spec_v2.md` v1.0.0
**Platform**: Flutter (Dart) — iOS 16+, Android API 28+, Desktop (Windows/macOS), Web (experimental)
**Primary Test Device**: iPhone 12 Pro (390×844 @ 3x, 6.1")

This document is a **complete v3 specification**. It incorporates all v2 content by reference and specifies all changes, additions, and modifications. Sections not listed here are unchanged from v2.

---

## Change Log

| Version | Date | Summary |
|---|---|---|
| 1.0.0 | 2026-04-01 | Initial specification (16 evidence-graded design principles, 37 peer-reviewed sources) |
| 3.0.0 | 2026-04-01 | Regression recovery (ContextReveal), auto-rewind on resume, reading goal presets, room-off baseline condition, ORP third A/B condition, 3 ergonomic fixes from cognitive evaluation, text difficulty proxy improvements |

### v3.0.0 Change Summary

| Change | Type | Priority | Complexity | Source |
|---|---|---|---|---|
| ContextReveal (swipe-up regression recovery) | New component | High | Medium | Design review: RSVP eliminates regression — the primary comprehension-repair mechanism |
| Auto-rewind on resume | New behavior (PacingEngine) | High | Very low (~10 lines) | Design review: mind-wandering self-detection is an EF demand ADHD users lack |
| Reading Goal presets | New component | Medium | Low | Design review: reframe product around reading goals, not speed |
| Room-off baseline ("None" parallax option) | Modified component (SettingsPanel, ParallaxRoom) | Medium | Very low (~1 rendering branch) | Design review: 3D room is unvalidated — needs A/B baseline |
| ORP third A/B condition (color-only, no bold) | Modified evaluation hook | Low | Very low (feature flag) | Cognitive ergonomics evaluation DT-4 recommendation |
| A-013 adaptive timing by WPM | Modified animation (WordDisplay) | **Critical** | Very low (~5 lines) | Cognitive ergonomics evaluation: Red finding — A-013 overruns display time at ≥350 WPM |
| Room intensity hysteresis + rolling window | Modified behavior (ParallaxRoom) | High | Low (~15 lines) | Cognitive ergonomics evaluation: Yellow finding — oscillation risk |
| Anchor contrast warning | Modified component (SettingsPanel) | Medium | Low | Cognitive ergonomics evaluation: Yellow finding — silent ORP degradation |
| WPM advisory text shortening | Modified component (WPMControl) | Low | Trivial | Cognitive ergonomics evaluation: Yellow finding — dual-task interference |
| Text difficulty proxy flagged as Grade D | Modified documentation | Low | None (documentation only) | Design review: ≥9 char threshold is not empirically validated |

---

## New Design Principles (v3 additions)

### P17: Regression Recovery (Grade C)

**Statement**: RSVP eliminates backward scanning (regression), which accounts for 10–15% of fixations in natural reading and serves comprehension repair. The system must provide a low-EF-demand mechanism for readers to recover context when comprehension breaks down.

**Evidence chain**:
- Regression in natural reading serves comprehension repair (Rayner, 1998 — foundational eye-movement review; not in v2 source list but referenced in Schotter & Rayner 2012 which is)
- ADHD readers cannot self-detect mind wandering and therefore cannot self-initiate recovery (Lanier 2021 — Grade B)
- Externally structured reading tasks attenuate ADHD comprehension deficits (Parks 2022 — Grade A)
- Low-WM readers fail to allocate strategic processing time without external support (Busler 2017 — Grade B)

**Grade rationale**: The component mechanisms are individually well-evidenced (B), but the specific intervention (progressive context reveal during RSVP with gradient-guided re-reading) is untested. Composite grade: C.

**Testable prediction (E-11)**: Users who use ContextReveal ≥ 1× per session will show higher comprehension scores than users who never zoom out, controlling for WPM.

---

### P18: Passive Comprehension Safeguard (Grade C)

**Statement**: When the system detects a likely comprehension interruption (pause event), it should silently provide a small context buffer by rewinding to a point slightly before the interruption, reducing the EF demand of deciding how far to rewind.

**Evidence chain**:
- Mind wandering in ADHD is unintentional, disruptive, and harder to self-detect (Lanier 2021 — Grade B)
- Pause events are a reasonable proxy for "something felt wrong" — the reader noticed discomfort but may not know exactly when comprehension broke (behavioral inference, no direct evidence — Grade D)
- External scaffolding should compensate for self-regulation failure (Barkley 1997 — Grade A; Parks 2022 — Grade A)

**Grade rationale**: The mechanism (auto-rewind on resume) is a conservative application of well-evidenced scaffolding principles. The specific 3-word rewind distance is an informed estimate. Grade: C.

**Testable prediction (E-12)**: Sessions with auto-rewind enabled will show ≥5% higher comprehension scores than sessions without, on passages with high mind-wandering potential (long, moderate-difficulty text).

---

## New Components

### Component: ContextReveal

---
**Version**: 1.0
**Evidence basis**: Principle 17 (Grade C), Principle 5 (Grade A), Principle 2 (Grade B)

---

#### Purpose

Regression recovery during RSVP reading. When the reader senses they've lost the thread, a swipe-up gesture pauses the stream and progressively reveals surrounding context — first 3 words, then 5, then the full sentence — with a gradient-guided re-reading sweep that externalizes gaze direction. This replaces the unconscious micro-regressions that RSVP eliminates.

**When to use**: During active reading, triggered by swipe-up gesture.
**When NOT to use**: Never auto-triggered in v3.0. Never during paused state (pause already shows static context). Never in library/settings.

#### Anatomy

- **Context phrase**: The surrounding words displayed horizontally (3-word tier) or as a wrapped phrase (5-word and sentence tiers), centered in the reading viewport
- **Position marker**: The word the reader was on when they triggered ContextReveal, highlighted with full anchor color on its ORP character
- **Gradient sweep**: A moving highlight that advances word-by-word through the displayed context at a fixed recovery pace
- **Dim overlay**: The 3D room dims slightly (identical to pause fog but at 60% intensity) to visually separate the recovery mode from active reading

#### Tiers

| Tier | Trigger | Words Shown | Layout | Sweep Behavior |
|---|---|---|---|---|
| **Micro** | First swipe-up | Current word ± 1 (3 words total) | Single line, current word's ORP anchor at viewport center | Word-by-word highlight, 400ms per word (150 WPM) |
| **Clause** | Second swipe-up (while in Micro) | Current word ± 2 (5 words total) | Single line or soft-wrap, centered | Gradient sweep: current word = full anchor color on ORP char; ±1 words = 40% anchor color on ORP char; others = stageText |
| **Sentence** | Third swipe-up (while in Clause) | Full current sentence | Wrapped text block, centered vertically | Gradient sweep as Clause tier, across full sentence |

#### Gradient Sweep Specification

The gradient sweep externalizes left-to-right gaze guidance during context recovery. It advances automatically at a fixed pace.

**Sweep rendering per word:**

| Position relative to sweep focus | ORP character treatment | Body text treatment |
|---|---|---|
| Focus word (sweep is here) | Full `stageAnchor` color, `type-weight-bold` | `stageText` color, `type-weight-regular` |
| ±1 word from focus | `stageAnchor` at 40% opacity, `type-weight-regular` | `stageText` at 70% opacity |
| All other words | `stageText` at 50% opacity | `stageText` at 50% opacity |

**Sweep timing:**
- Fixed rate: 400ms per word (150 WPM). This is not tied to the reader's WPM setting.
- Rationale: Recovery mode. The reader zoomed out because comprehension broke. 150 WPM is slow enough for careful re-reading. The fixed rate avoids requiring the reader to make a speed decision during a moment of confusion.
- The sweep auto-advances. Tap anywhere to pause the sweep (word stays highlighted at current position). Tap again to resume sweep.
- When the sweep reaches the last displayed word, it holds on that word indefinitely.

**ORP in multi-word display:**

- **Micro tier (3 words)**: The current word's ORP anchor character is pinned to the viewport horizontal center (same position as single-word RSVP). Surrounding words are positioned naturally relative to the current word using measured glyph widths. This preserves the reader's eye position.
- **Clause and Sentence tiers (5+ words)**: Words are displayed as a centered, wrapped text block. No fixed ORP anchor point — the spatial anchoring shifts to a "reading a phrase" mode. Each word's ORP character is highlighted during its sweep turn, but the reader's gaze follows left-to-right reading patterns, not a fixed focal point.

#### Navigation Within ContextReveal

| Gesture | Action | Effect on Resume Position |
|---|---|---|
| Swipe right (while zoomed) | Shift the context window backward by 1 word | Resume position moves backward by 1 word |
| Swipe left (while zoomed) | Shift the context window forward by 1 word | Resume position moves forward by 1 word |
| Swipe up (while zoomed) | Advance to next tier (Micro → Clause → Sentence) | No change to resume position |
| Swipe down | Dismiss ContextReveal, resume RSVP | RSVP resumes from the leftmost word currently visible in the context window |
| Tap | Pause/resume the gradient sweep | No change to resume position |

**Resume behavior**: When the reader dismisses ContextReveal (swipe down), RSVP resumes from the **leftmost word currently visible** in the context window. If the reader swiped right multiple times to navigate backward, they'll re-read those words in RSVP mode. This makes ContextReveal function as both a display tool and a navigation tool.

#### Transition Animations

| Transition | Animation | Duration | Evidence |
|---|---|---|---|
| Enter ContextReveal (single word → Micro) | Current word stays at ORP position; ±1 words fade in from 0% opacity, sliding in from ±20px | 200ms, easeOut | P6: smooth, non-jarring transition |
| Tier advance (Micro → Clause → Sentence) | New words fade in at edges; existing words reposition smoothly | 250ms, easeInOut | P6 |
| Exit ContextReveal (back to RSVP) | Context words fade out; single-word RSVP resumes with standard A-001 breathe | 150ms, easeOut then immediate RSVP resume | P8: fast return to single-task mode |
| Dim overlay enter/exit | Fog overlay at 60% of pause-fog opacity, same timing as A-006/A-007 | 200ms / 150ms | Consistent with existing pause behavior |

**Reduced motion**: When `isReducedMotion == true`, all ContextReveal transitions are instant (no fade, no slide). Words appear/disappear immediately. Gradient sweep still advances at 400ms per word (the timing is functional, not decorative — it controls reading pace).

#### States

| State | Visual Description | Trigger |
|---|---|---|
| **Micro** | 3 words visible, sweep active or paused, dim overlay | First swipe-up during reading |
| **Clause** | 5 words visible, gradient sweep active or paused | Second swipe-up while in Micro |
| **Sentence** | Full sentence visible, gradient sweep active or paused | Third swipe-up while in Clause |
| **Sweep Paused** | Gradient holds on current word, all words visible | Tap while in any tier |
| **Navigating** | Context window shifting (via swipe left/right) | Swipe left/right while in any tier |

#### Tokens Consumed

| Token | Usage |
|---|---|
| `color-stage-text` | Non-focus words |
| `color-stage-anchor` | Focus word ORP character + gradient |
| `color-stage-pause-overlay` | Dim overlay (at 60% of standard pause opacity) |
| `type-family-reading-default` (or user-selected) | All displayed words |
| `type-weight-bold` | Focus word ORP character only |
| `type-weight-regular` | All other text |

#### Interaction Summary

| Event | Response | Timing |
|---|---|---|
| Swipe up (reading) | RSVP pauses → Micro tier appears | 200ms transition |
| Swipe up (Micro) | Advance to Clause tier | 250ms transition |
| Swipe up (Clause) | Advance to Sentence tier | 250ms transition |
| Swipe up (Sentence) | No action (already at maximum tier) | — |
| Swipe down (any tier) | Dismiss → resume RSVP from leftmost visible word | 150ms transition |
| Swipe right (any tier) | Shift window back 1 word, reset sweep to new leftmost | Immediate |
| Swipe left (any tier) | Shift window forward 1 word, reset sweep to new leftmost | Immediate |
| Tap (any tier) | Pause/resume gradient sweep | Immediate |

#### Accessibility

- **Screen reader**: Announce the full context phrase on ContextReveal entry. Announce "Context: [phrase]. Swipe down to resume reading." On tier advance, re-announce the expanded phrase.
- **Keyboard**: Up arrow = enter/advance tier. Down arrow = dismiss. Left/right = shift window. Space = pause/resume sweep.
- **Cognitive accommodation**: ContextReveal externalizes regression — the reader doesn't need to decide how far to rewind, just swipe up and the system shows them where they are. The gradient sweep externalizes gaze direction during recovery.

#### Do / Don't

| Do | Don't | Why (Principle) |
|---|---|---|
| Pause RSVP immediately on swipe-up (before animation completes) | Let RSVP continue during the zoom-out transition | P17: The reader is already confused — don't advance words while they're trying to recover |
| Show the position marker on the word they were reading | Highlight the first word of the sentence | P17: "You are here" orientation is the first thing a confused reader needs |
| Use a fixed 150 WPM sweep rate | Tie sweep rate to the reader's WPM setting | Recovery mode should be slow and comfortable, not performance-matched |
| Resume from leftmost visible word after navigation | Resume from the word where ContextReveal was triggered | If the reader navigated backward, they want to re-read from that point |
| Keep the 3D room visible (dimmed) behind the context | Replace the room with a flat background during ContextReveal | Visual continuity — the reader should feel they're still "in the room," just pausing to look around |

#### First-Use Onboarding

**Must** (P10, Grade B — discoverability for ADHD users): The first time the reader performs a swipe-up during reading, show a brief overlay (3 seconds, auto-dismiss) explaining the progressive zoom:

> "Swipe up to see surrounding words. Swipe again for more context. Swipe down to resume."

This overlay appears once per installation. After dismissal (auto or tap), the gesture works silently.

**Implementation**: Store a `hasSeenContextRevealOnboarding` boolean in `AppConfig`. Check on first swipe-up. Show overlay, then proceed to Micro tier when overlay dismisses.

---

### Component: ReadingGoalPresets

---
**Version**: 1.0
**Evidence basis**: Principle 10 (Grade B), Principle 1 (Grade A)

---

#### Purpose

Reframes the product around reading goals rather than speed. Provides curated bundles of settings that optimize for different reading intentions, reducing the decision burden for new users and communicating that comprehension — not speed — is the product's value.

**When to use**: First launch (onboarding), and accessible via Settings.
**When NOT to use**: Never forced during an active reading session.

#### Anatomy

Three preset cards displayed during onboarding and in the Settings panel:

| Preset | WPM | Per-Word Timing | Room Intensity | Parallax | Target Use Case |
|---|---|---|---|---|---|
| **Deep Read** | 200 | On | Auto | Subtle | Study material, complex text, learning. "Take your time with difficult material." |
| **Comfortable** | 250 | On | Auto | Subtle | General reading, articles, books. "Your everyday reading pace." |
| **Quick Scan** | 350 | On (simplified: length modifiers only, no frequency) | Minimal | Off | Familiar material, review, skimming. "Get the gist of material you already know." |

#### Behavior

- **Onboarding**: After the user loads their first PDF, present the three presets as tappable cards before the first reading session. Each card shows the preset name, a one-sentence description, and the WPM value. The user taps one to apply it. A "Customize later in Settings" link is visible below the cards.
- **Settings integration**: A "Reading Goal" selector at the top of the Primary Settings section. Selecting a preset updates WPM, per-word timing, room intensity, and parallax to the preset values. The user can then modify individual settings — doing so changes the preset indicator to "Custom."
- **Persistence**: The selected preset (or "Custom") is stored in `AppConfig`. Individual settings always reflect the actual values, regardless of which preset was used as a starting point.

#### Design Rationale

The presets serve two functions:

1. **Decision scaffolding for ADHD users** (P10): Instead of configuring 4+ settings on first launch, the user makes one choice about their reading intention. This reduces Hick's Law decision complexity from log₂(N) across multiple controls to log₂(4) on a single question.

2. **Reframing the value proposition**: "Deep Read" at 200 WPM communicates that *slower is a valid, intentional choice*. "Quick Scan" explicitly labels high-speed reading as "scanning," not "better reading." This aligns the product surface with the evidence: comprehension is the value, speed is a tool.

#### Tokens Consumed

Shell surface tokens. Preset cards use `RunThruDecorations.raisedDecoration(RunThruSurface.shell)`.

#### Interaction

| Event | Response | Timing |
|---|---|---|
| Tap preset card (onboarding) | Apply preset settings, dismiss onboarding, begin reading | `timing-transition-normal` (300ms) |
| Tap preset in Settings | Update WPM, per-word timing, room intensity, parallax to preset values | Immediate (settings update) |
| Modify any setting after selecting preset | Preset indicator changes to "Custom" | Immediate |

#### Accessibility

- **Screen reader**: Announce preset name and description on focus. "Deep Read: 200 words per minute. Take your time with difficult material."
- **Keyboard**: Arrow keys to navigate between presets. Enter to select.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Present presets as reading intentions ("Deep Read") | Present presets as speed tiers ("Slow / Medium / Fast") | Reframes around goals, not performance |
| Allow full customization after preset selection | Lock users into preset configurations | P10: User sovereignty |
| Show "Custom" when user modifies settings | Silently break the preset without indication | The user should know they've diverged from the recommended bundle |
| Default to "Comfortable" if user skips onboarding | Require preset selection to use the app | Never block reading behind configuration |

---

## Modified Components

### Modified: PacingEngine — Auto-Rewind on Resume (P18)

**Change type**: New behavior added to existing component.

#### Specification

When the reader resumes from a pause (tap to resume), the RSVP position automatically rewinds by 3 words before resuming playback. The reader re-encounters the 3 words immediately preceding their pause point, then continues forward from where they paused.

**Implementation:**

```dart
/// In WordTimerNotifier.play() — called on resume from pause:
void play() {
  if (_wasPaused) {
    // Auto-rewind: back up 3 words (or to start of document)
    final rewindTarget = (_currentIndex - autoRewindWords).clamp(0, _currentIndex);
    _currentIndex = rewindTarget;
    _wasPaused = false;
  }
  _scheduleNext();
}
```

**Constants:**

| Token | Value | Type | Evidence |
|---|---|---|---|
| `timing-auto-rewind-words` | `3` | `int` | P18 (Grade C): 3 words covers the typical micro-regression span in natural reading. Enough to re-establish local context without feeling like significant backward progress. |

**Behavioral rules:**

1. Auto-rewind applies on every resume-from-pause. No exceptions.
2. If the reader is within the first 3 words of the document, rewind to word 0.
3. Auto-rewind does NOT apply on first play (beginning of a session). Only on resume after pause.
4. Auto-rewind does NOT apply when exiting ContextReveal — ContextReveal has its own resume-position logic (leftmost visible word).
5. The rewind is silent — no visual indication that words are being re-presented. The reader simply sees 3 "familiar" words before reaching new content. This is consistent with P16 (invisible adaptation).

**User control:**

- **Not user-toggleable in v3.0.** The rewind is small enough (3 words = ~700ms at 250 WPM) that it's imperceptible as a "feature" — it just feels like a smooth re-entry. If analytics show users rapidly re-pausing after resume (indicating the rewind is disorienting), add a toggle in v3.1.
- **Evaluation hook (E-12)**: A/B test with auto-rewind on vs. off. Compare comprehension scores on long-form passages.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Rewind silently — no "rewinding..." indicator | Show a backward-scrolling animation or countdown | P16: Invisible adaptation. The reader should feel a smooth re-entry, not a mechanical rewind. |
| Apply on every resume-from-pause | Apply only on "long" pauses or skip on "short" pauses | Simplicity. Duration-based thresholds add complexity and edge cases. 3 words at any WPM is <1 second of re-reading — never harmful. |
| Clamp to word 0 at document start | Show an error or skip rewind if <3 words available | Graceful degradation |

---

### Modified: WordDisplay (Parallax Variant) — A-013 Adaptive Timing

**Change type**: Critical fix from cognitive ergonomics evaluation. Red finding.

#### Problem

A-013 (depth bounce-in: 160ms base + 6ms × (N−1) glyph stagger) exceeds per-word display time at ≥350 WPM for common words. The bounce-in animation is still running when the next word arrives, creating visual stutter where no word reaches its stable resting state.

#### Fix

Add a WPM-dependent animation selection:

```dart
/// In ParallaxWordPainter or animation selection logic:
Animation selectWordTransition(int wpm, int charCount, int displayMs) {
  if (wpm > 300) {
    // Above 300 WPM: fall back to A-001 (80ms, 1.5% scale pulse)
    // Eliminates timing overrun entirely
    return A001_BREATHE;
  }
  
  // At 200–300 WPM: cap A-013 to 60% of display time
  final maxAnimMs = (displayMs * 0.6).round();
  final staggerTotal = 6 * (charCount - 1);
  final cappedBase = (maxAnimMs - staggerTotal).clamp(40, 160);
  
  return A013_BOUNCE_IN.withBase(cappedBase);
}
```

**Effect by speed tier (after fix):**

| WPM | Word | Animation Used | Anim (ms) | Display (ms) | Stable (ms) | Status |
|---|---|---|---|---|---|---|
| 250 | "the" (3) | A-013 (capped) | 132 + 12 = 144 | 240 | 96 | ✅ OK |
| 250 | "reading" (7) | A-013 (capped) | 108 + 36 = 144 | 240 | 96 | ✅ OK |
| 350 | "the" (3) | A-001 | 80 | 171 | 91 | ✅ OK |
| 350 | "reading" (7) | A-001 | 80 | 171 | 91 | ✅ OK |
| 500 | "the" (3) | A-001 | 80 | 120 | 40 | ✅ OK |

**Rationale**: Above 300 WPM, the reading task is cognitively demanding enough that peripheral depth novelty provides no benefit (Yerkes-Dodson: at high cognitive load, reduce stimulation). The temporal scaffold is preserved by A-001; only the depth motion is lost.

At 200–300 WPM, the 60% cap guarantees ≥40% of display time is stable — enough for word-form recognition even at reduced WM capacity. The 40ms minimum base duration preserves the bounce-in's perceptibility.

---

### Modified: ParallaxRoom — Adaptive Intensity Hysteresis + Rolling Window

**Change type**: High-priority fix from cognitive ergonomics evaluation. Yellow finding.

#### Problem

The room intensity adapts per-sentence based on average character count. In text with alternating simple and complex sentences (common in academic prose), the room oscillates between Rich and Minimal every 1–2 sentences. Even with the 3–5 second fade, the cumulative oscillation pattern becomes noticeable and distracting.

#### Fix: Two Changes

**1. Rolling window (replaces per-sentence evaluation):**

```dart
/// Replace per-sentence difficulty evaluation with rolling window
class _RoomIntensityController {
  static const int _windowSize = 5; // sentences
  final List<double> _recentDifficultyScores = [];
  
  double get smoothedDifficulty {
    if (_recentDifficultyScores.isEmpty) return 0.5; // default moderate
    return _recentDifficultyScores.reduce((a, b) => a + b) / 
           _recentDifficultyScores.length;
  }
  
  void onSentenceComplete(double sentenceDifficulty) {
    _recentDifficultyScores.add(sentenceDifficulty);
    if (_recentDifficultyScores.length > _windowSize) {
      _recentDifficultyScores.removeAt(0);
    }
    _evaluateIntensityChange();
  }
}
```

**2. Hysteresis (minimum hold time between transitions):**

```dart
DateTime? _lastIntensityChange;
static const Duration _hysteresisHold = Duration(seconds: 30);

void _evaluateIntensityChange() {
  if (_lastIntensityChange != null && 
      DateTime.now().difference(_lastIntensityChange!) < _hysteresisHold) {
    return; // Too soon — hold current intensity
  }
  
  final target = _intensityFromDifficulty(smoothedDifficulty);
  if (target != _currentIntensity) {
    _transitionTo(target); // 3–5 second fade per v2 spec
    _lastIntensityChange = DateTime.now();
  }
}
```

**Effect**: The room adapts to sustained difficulty changes (a dense technical section vs. a dialogue section) but ignores sentence-level noise. At 250 WPM, 30 seconds ≈ 125 words ≈ 8–10 sentences. The room changes at most twice per minute.

#### Additional Change: Flag Difficulty Threshold as Grade D

The v2 spec uses "avg word length ≥ 9 chars" as the high-difficulty trigger and "≤ 4 chars" as low-difficulty. These thresholds are **not empirically validated** for room-intensity switching.

**v3 reclassification**: The difficulty proxy thresholds are Grade D (extrapolated, no direct evidence). They are tunable constants, not hard constraints:

| Token | Value | Grade | Notes |
|---|---|---|---|
| `room-difficulty-threshold-high` | `9.0` (avg chars/word) | **D** | Informed estimate. Treat as tunable. Monitor via E-13. |
| `room-difficulty-threshold-low` | `4.0` (avg chars/word) | **D** | Informed estimate. Treat as tunable. |
| `room-hysteresis-hold-seconds` | `30` | **C** | ~125 words at 250 WPM. Should be long enough to prevent oscillation without being so long the room feels static. |
| `room-difficulty-window-size` | `5` (sentences) | **C** | Smooths single-sentence spikes. |

---

### Modified: SettingsPanel — Anchor Contrast Warning

**Change type**: Medium-priority fix from cognitive ergonomics evaluation. Yellow finding.

#### Problem

Users can select anchor colors (indices 1–5: Blazing Orange, Marigold, Buttercup, Limelight, Green Glow) that have as low as 3:1 contrast on the warm stage background. The ORP anchor becomes indistinguishable at speed, silently eliminating the fixation-guidance benefit. The user may attribute difficulty to their own attention deficit — particularly harmful for ADHD users.

#### Fix: Two Additions

**1. Real-time contrast preview:**

When the user selects an anchor color, show a word preview on the stage background with the selected color applied to the ORP character. This is a live rendering of how the anchor will look during reading — same font, same background color, same weight treatment.

**2. Contrast-aware inline warning:**

| Contrast Level | Warning | Visual Treatment |
|---|---|---|
| ≥ 4.5:1 (AA) | None | Standard color picker selection ring |
| 3:1 – 4.49:1 | "This color may be hard to see at speed" | Yellow caution indicator on the color swatch |
| < 3:1 | "This color is very hard to see — consider a darker option" | Red warning indicator + auto-apply text shadow |

**3. Auto text-shadow for low-contrast anchors:**

When the selected anchor color has < 4.5:1 contrast on `stageBase`, automatically apply a 0.5px text shadow in `stageText` color behind the anchor character during reading. This preserves the user's color choice while ensuring the character is distinguishable.

```dart
/// In WordDisplay rendering logic:
Paint? anchorShadow;
if (anchorContrastRatio < 4.5) {
  anchorShadow = Paint()
    ..color = RunThruTokens.stageText.withOpacity(0.3)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.5);
}
```

**Rationale**: The shadow adds a guaranteed-contrast boundary without overriding the user's color preference (P10 sovereignty). The contrast preview gives informed consent (consistent with DT-2 WPM warning pattern).

---

### Modified: WPMControl — Advisory Text Shortening

**Change type**: Low-priority fix from cognitive ergonomics evaluation. Yellow finding.

#### Problem

The >350 WPM advisory is a two-sentence paragraph displayed during an active motor task (dial adjustment), creating dual-task interference.

#### Fix

Replace the advisory text:

| v2 | v3 |
|---|---|
| "Above 350 WPM, deep comprehension may decrease. This speed works well for scanning familiar material." | "Best for scanning familiar text" |

The red color change already communicates risk. The shortened text (5 words, ~1 WM chunk) can be processed in a peripheral glance during the motor task without significant dual-task interference.

**Alternative enhancement** (implement if feasible): At the 350 WPM threshold crossing, fire a haptic warning buzz AND shift the ring color to red. Show the full advisory text only when the user **releases** the dial above 350. This separates the motor and language tasks temporally.

---

### Modified: SettingsPanel — Room-Off Baseline Condition ("None")

**Change type**: New option added to existing control.

#### Change

The Parallax Intensity segmented control gains a fourth option:

| v2 Options | v3 Options |
|---|---|
| Off / Subtle / Full | **None** / Off / Subtle / Full |

| Option | Behavior | Purpose |
|---|---|---|
| **None** (new) | Flat warm background (`stageBase`), no 3D room, no parallax, no cube, no breathe animation. Word displays on a clean, neumorphic-edged surface. | A/B baseline condition. Also serves users who prefer minimal visuals. |
| Off | 3D room renders statically (no parallax, no breathe). Depth cues visible. | Reduced stimulation with spatial context. |
| Subtle | 3D room with gentle parallax (≤2.5% displacement) and slow breathe. | Default. Moderate peripheral engagement. |
| Full | 3D room with full parallax (≤5% displacement) and breathe. | Maximum peripheral engagement. |

**"None" rendering specification:**

When parallax is set to None, the reading viewport renders:
- Background: `stageBase` (#ede3d2) fill, edge-to-edge
- Word: Rendered using the non-parallax `WordPainter` (2D), not `ParallaxWordPainter`
- Neumorphic frame: Subtle inset shadow around viewport edges (consistent with shell aesthetic)
- Progress hairline: Unchanged
- No room geometry, no marble, no grid lines, no vignette, no fog overlay on pause (use simple dimming instead)

This is the visual equivalent of "a clean white page" (but in the warm neumorphic palette). It serves as the scientific control condition for evaluating whether the 3D room contributes to or detracts from reading outcomes.

**Evaluation hook (E-3 updated)**: Updated from v2. Now tests four conditions instead of three: None / Off / Subtle / Full. The inverted-U prediction should show Subtle > None AND Subtle > Full for session duration. If None ≥ Subtle, the room is not providing measurable engagement value.

---

### Modified: Evaluation Hooks — ORP Third A/B Condition

**Change type**: Updated from v2 DT-4.

#### Change

The ORP A/B test now includes three conditions:

| Condition | Alignment | Anchor Treatment | Purpose |
|---|---|---|---|
| **ORP + Bold + Color** (default) | ORP-aligned | Bold weight + anchor color | v2 default — tests the full ORP treatment |
| **ORP + Color Only** (new) | ORP-aligned | Anchor color only (regular weight) | Isolates whether bold weight helps or hurts holistic word-form recognition |
| **Center-Aligned** (control) | Horizontally centered | Anchor color on ORP position (but word is centered, not ORP-aligned) | Control — tests whether ORP alignment itself matters |

**Feature flag**: `orpCondition` enum in `AppConfig` with values `orpBoldColor`, `orpColorOnly`, `centerAligned`. Default: `orpBoldColor`. Not user-facing in v3.0 — controlled by A/B testing infrastructure.

**Updated prediction (E-7)**: ORP+BoldColor and ORP+ColorOnly should both show ≥5% improvement on inference questions vs. Center-Aligned, especially for words ≥7 characters. If ORP+ColorOnly outperforms ORP+BoldColor, the bold treatment may be disrupting word-form perception and should be removed.

---

## New Evaluation Hooks

Added to the v2 evaluation hook table:

| ID | Prediction | Metric | Where to Measure | Method | Threshold |
|---|---|---|---|---|---|
| E-11 | Users who use ContextReveal ≥1× per session score higher on comprehension | Comprehension score × ContextReveal usage | ComprehensionCheck + ContextReveal trigger count in analytics | Correlation analysis, controlling for WPM and passage difficulty | Positive correlation (r ≥ 0.15) between ContextReveal usage and comprehension, controlling for WPM |
| E-12 | Auto-rewind on resume improves comprehension on long passages | Comprehension score × auto-rewind condition | ComprehensionCheck + A/B flag for auto-rewind | A/B test: auto-rewind on vs. off | ≥5% improvement on inference questions for passages > 2000 words |
| E-13 | Room difficulty thresholds produce meaningful intensity variation | Distribution of room intensity states per session | Analytics: room intensity state × duration | Histogram of time spent in each intensity state | 60–80% Moderate, 10–20% each Minimal/Rich (not 95%+ in one state, which would indicate thresholds are miscalibrated) |
| E-14 | Reading goal presets reduce time-to-first-read | Time from app install to first reading session start | Analytics: install timestamp → first session start timestamp | Cohort analysis: preset onboarding vs. no onboarding | ≥20% faster time-to-first-read with preset onboarding |
| E-15 | "None" room condition provides baseline for room value | Session duration and comprehension by room condition | Analytics: parallax setting × session metrics | 4-way comparison: None / Off / Subtle / Full | Subtle > None for session duration (if not, room is not providing value) |

---

## Updated Evidence Chain Index (v3 additions)

| Spec Decision | Token/Component | Principle | Evidence Grade | Key Sources |
|---|---|---|---|---|
| ContextReveal (progressive zoom-out) | ContextReveal component | P17 | C | Schotter 2012, Lanier 2021, Parks 2022, Busler 2017 |
| Gradient sweep at 150 WPM | ContextReveal sweep timing | P17, P5 | C | Recovery mode — slower than reading pace by design |
| Auto-rewind 3 words on resume | PacingEngine, `timing-auto-rewind-words` | P18 | C | Lanier 2021, Barkley 1997, Parks 2022 |
| Reading goal presets (Deep/Comfortable/Quick Scan) | ReadingGoalPresets component | P1, P10 | B | Reframing: comprehension evidence (P1 Grade A) applied to preset design |
| Room-off "None" condition | SettingsPanel, ParallaxRoom | P6, P15 | — | A/B baseline — no evidence claim; this IS the control condition |
| A-013 adaptive timing by WPM | WordDisplay (parallax), animation selection | P6 | A | Cognitive ergonomics evaluation: temporal binding framework |
| Room intensity hysteresis (30s hold) | ParallaxRoom, `room-hysteresis-hold-seconds` | P7 | C | Cognitive ergonomics evaluation: change blindness / Yerkes-Dodson |
| Room difficulty rolling window (5 sentences) | ParallaxRoom, `room-difficulty-window-size` | P7 | C | Smooths sentence-level noise in difficulty estimation |
| Difficulty threshold flagged Grade D | `room-difficulty-threshold-high/low` | P7 | **D** | No empirical validation of threshold values |
| Anchor contrast warning + auto-shadow | SettingsPanel, WordDisplay | P14, P10 | C | WCAG extrapolation + visual span theory |
| WPM advisory shortened to 5 words | WPMControl | P1 | A | Cognitive ergonomics evaluation: dual-task interference |
| ORP third A/B condition (color-only) | Evaluation hook E-7 | P14 | D | Cognitive ergonomics evaluation DT-4: isolate bold vs. alignment effects |

---

## New Timing Tokens (v3 additions)

Add to `lib/design/timing_tokens.dart`:

```dart
abstract final class RunThruTiming {
  // ... existing v2 tokens unchanged ...

  // ── Auto-Rewind (P18 — Grade C) ──────────────────────────────
  static const int autoRewindWords = 3;  // Words to rewind on resume-from-pause

  // ── ContextReveal (P17 — Grade C) ────────────────────────────
  static const int contextRevealSweepMs = 400;       // ms per word in gradient sweep (150 WPM)
  static const double contextRevealDimOpacity = 0.6;  // × pause fog opacity
  static const int contextRevealMicroWords = 3;       // ±1 from current = 3 total
  static const int contextRevealClauseWords = 5;      // ±2 from current = 5 total
  static const Duration contextRevealEnter = Duration(milliseconds: 200);
  static const Duration contextRevealTierAdvance = Duration(milliseconds: 250);
  static const Duration contextRevealExit = Duration(milliseconds: 150);

  // ── Room Intensity (updated from v2) ─────────────────────────
  static const int roomHysteresisHoldSeconds = 30;    // Min seconds between intensity changes
  static const int roomDifficultyWindowSize = 5;      // Rolling window: sentences
  static const double roomDifficultyThresholdHigh = 9.0;  // Grade D — tunable
  static const double roomDifficultyThresholdLow = 4.0;   // Grade D — tunable

  // ── A-013 Adaptive Timing (ergonomics fix) ───────────────────
  static const int a013FallbackWpmThreshold = 300;    // Above this: use A-001 instead of A-013
  static const double a013MaxDisplayFraction = 0.6;   // A-013 duration ≤ 60% of display time
  static const int a013MinBaseDuration = 40;          // Minimum base ms for capped A-013
}
```

---

## Updated Gesture Map (complete)

| Gesture | Context | Action |
|---|---|---|
| Tap | Reading | Pause / Resume (with 3-word auto-rewind on resume) |
| Tap | ContextReveal | Pause / Resume gradient sweep |
| Swipe left | Reading | Skip to next sentence |
| Swipe left | ContextReveal | Shift context window forward 1 word |
| Swipe right | Reading | Rewind to previous sentence |
| Swipe right | ContextReveal | Shift context window backward 1 word |
| Swipe up | Reading | Enter ContextReveal (Micro tier) |
| Swipe up | ContextReveal (Micro) | Advance to Clause tier |
| Swipe up | ContextReveal (Clause) | Advance to Sentence tier |
| Swipe up | ContextReveal (Sentence) | No action |
| Swipe down | ContextReveal (any tier) | Exit ContextReveal, resume RSVP from leftmost visible word |

**Discoverability note**: 7 gestures total. The core reading gestures (tap, swipe-left, swipe-right) are standard and intuitive. ContextReveal gestures (swipe-up/down) are discoverable via the first-use onboarding overlay. No gesture requires more than one finger. No gesture conflicts with system gestures (swipe-down from top = notification center, but reading mode uses `SystemUiMode.immersiveSticky` which suppresses this).

---

## Implementation Priority Order

For v3.0 development, implement in this order (highest impact per effort first):

| Priority | Change | Effort | Impact | Blocking? |
|---|---|---|---|---|
| 1 | A-013 adaptive timing fix | ~5 lines | Fixes broken parallax reading at ≥350 WPM | **Yes — ship-blocking for parallax mode** |
| 2 | Auto-rewind on resume | ~10 lines in `WordTimerNotifier` | Addresses regression gap with zero UI changes | No |
| 3 | WPM advisory text shortening | Text change only | Reduces dual-task interference | No |
| 4 | Room intensity hysteresis + rolling window | ~15 lines of state management | Eliminates oscillation in academic/technical text | No |
| 5 | Anchor contrast warning + auto-shadow | UI addition to color picker + rendering logic | Prevents silent ORP degradation | No |
| 6 | Room-off "None" option | 1 rendering branch + settings update | Enables A/B validation of room value | No |
| 7 | Reading Goal presets | New component + onboarding flow | Reframes product, reduces first-launch friction | No |
| 8 | ORP third A/B condition | Feature flag + rendering branch | Enables research on bold treatment | No |
| 9 | ContextReveal | New component (medium complexity) | Addresses regression gap comprehensively | No |

**Rationale**: Items 1–5 are fixes to existing features — low effort, high confidence. Items 6–8 are validation infrastructure — low effort, needed for evidence-based iteration. Item 9 (ContextReveal) is the only medium-complexity addition and should be implemented last to benefit from learnings during items 1–8.

---

## Appendix C: v3 Glossary Additions

| Term | Definition |
|---|---|
| **ContextReveal** | Progressive zoom-out feature for regression recovery during RSVP. Swipe-up reveals surrounding words in tiers (3 → 5 → sentence) with a gradient-guided re-reading sweep. |
| **Gradient Sweep** | A moving word-by-word highlight in ContextReveal that externalizes gaze direction during context recovery. Advances at 150 WPM with anchor-color intensity gradient on focus ±1 words. |
| **Auto-Rewind** | Silent 3-word backstep on resume-from-pause. Compensates for ADHD mind-wandering detection gap by providing automatic context recovery at pause points. |
| **Reading Goal Presets** | Curated setting bundles (Deep Read / Comfortable / Quick Scan) that optimize for reading intention rather than speed. |
| **Hysteresis (room intensity)** | Minimum 30-second hold time between room intensity transitions, preventing oscillation from sentence-level difficulty variation. |
| **Rolling Window (difficulty)** | 5-sentence moving average for text difficulty estimation, replacing per-sentence evaluation to smooth noise. |
| **Room-Off / "None"** | Parallax intensity setting that renders a flat background with no 3D room. Serves as the A/B control condition for evaluating room value. |

---

*v3.0 specification adds 2 new design principles, 2 new components, 7 component modifications, 5 new evaluation hooks, and 9 new timing tokens. All changes are backward-compatible with v2 implementation. Total evidence base: 37 peer-reviewed sources (unchanged) + 2 new principles grounded in the existing source pool.*

*Next steps: Implement Priority 1 (A-013 fix) immediately. Priorities 2–5 in the next sprint. Priorities 6–9 in the following sprint. Begin user testing with 5–10 ADHD adults after Priority 5 is complete — before building ContextReveal.*
