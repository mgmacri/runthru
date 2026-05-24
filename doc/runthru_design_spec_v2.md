# RunThru v2.0 — UX/UI Design Specification

**Product**: RunThru v2.0 — Speed Reading with 3D Neumorphic Cube Viewport
**Spec Version**: 1.0.0
**Date**: 2026-04-01
**Platform**: Flutter (Dart) — iOS 16+, Android API 28+, Desktop (Windows/macOS), Web (experimental)
**Primary Test Device**: iPhone 12 Pro (390×844 @ 3x, 6.1")

---

## Change Log

| Version | Date | Summary |
|---|---|---|
| 1.0.0 | 2026-04-01 | Initial specification generated from 16 evidence-graded design principles (37 peer-reviewed sources) |

---

## Table of Contents

1. [Overview](#1-overview)
2. [Design Philosophy](#2-design-philosophy)
3. [Design Tokens](#3-design-tokens)
4. [Layout System](#5-layout-system)
5. [Component Library](#4-component-library)
6. [Motion System](#6-motion-system)
7. [Accessibility System](#7-accessibility-system)
8. [Design Tension Resolutions](#8-design-tension-resolutions)
9. [Implementation Notes](#9-implementation-notes)
10. [Evaluation Hooks](#10-evaluation-hooks)
11. [Appendix A: Evidence Chain Index](#appendix-a-evidence-chain-index)
12. [Appendix B: Glossary](#appendix-b-glossary)

---

## 1. Overview

### Product Purpose

RunThru is a cross-platform speed-reading application that presents PDF documents word-at-a-time using the RSVP (Rapid Serial Visual Presentation) method with ORP (Optimal Recognition Point) anchoring. The flagship visual feature is a 3D neumorphic cube interior rendered via CustomPainter, with optional head-tracking parallax that creates a "magic window" depth illusion.

### Core Value Proposition

RunThru helps ADHD and neurotypical readers read more effectively — not by showing words faster, but by **externalizing executive function**. It removes the self-regulation demands (when to move eyes, how fast to go, where on the page) that cause mind wandering and re-reading. At 250 WPM with zero mind wandering, effective throughput exceeds 400 WPM with 30% mind-wandering time.

### Target Users

| Persona | Characteristics | Priority Features |
|---|---|---|
| **ADHD Adult Reader** | WM deficits mediate reading difficulty; 2–3× mind-wandering rate; cannot self-detect mind wandering; self-regulation failure is core deficit | External pacing scaffold, single-task mode, progress externalization, per-word timing adaptation |
| **Focused Reader** | Neurotypical reader wanting distraction-free reading | Clean environment, customizable WPM, comfortable typography |
| **Mobile Reader** | Reads on phone during commute/breaks | Portrait-only reading, compact UI, touch controls |

### Platforms and Devices

- **Primary**: iPhone 12 Pro (390×844 @ 3x, 6.1")
- **Secondary**: Standard Android flagship (~6.1–6.7", 1080×2400)
- **Tertiary**: Desktop (Windows/macOS) for development and extended sessions
- **Experimental**: Web (Chrome)
- **Orientation**: Portrait only for reading mode; library/settings may rotate on tablet
- **Minimum OS**: iOS 16, Android API 28

---

## 2. Design Philosophy

RunThru's design exists at the intersection of three evidence-grounded commitments: **cognitive load reduction**, **ambient engagement**, and **executive function externalization**.

The reading experience must feel like **looking into a quiet, warm room where words appear naturally**. The 3D neumorphic cube is not decoration — it is a peripheral attention scaffold that sustains focus without competing for the cognitive resources needed to process each word. The room exists in peripheral vision. The word is sacred. During active reading, nothing in the user's foveal field competes with the current word for processing time. The marble walls, soft gradients, and gentle parallax shift create ambient visual interest that keeps the wandering mind tethered without demanding conscious attention — the engagement equivalent of background music in a café.

The pacing engine is the actual intervention. Everything else — the 3D room, ORP alignment, anchor highlighting — enhances the core mechanism of **externally controlled, cognitively adaptive timing**. ADHD readers cannot self-regulate reading pace. They cannot detect when they've drifted. They cannot allocate more time to complex words. The system does all of this silently, presenting each word for precisely the duration the reader's working memory needs. The user controls the experience parameters (speed, font, visual intensity). The system handles the moment-to-moment cognitive scaffolding. This distinction — macro control for the user, micro adaptation by the system — resolves the tension between the autonomy users need and the executive function support they require.

The visual language is warm neumorphism: soft shadows on antique-white surfaces, rounded forms, and a muted palette that signals calm competence. The 3D interior extends this into depth — polished marble walls with subtle veining, etched grid lines receding toward a warm focal glow. The aesthetic must communicate: this is a tool that respects your cognition and takes your reading seriously. It is neither clinical nor playful. It is a quiet, well-designed room where you sit down and read.

---

## 3. Design Tokens

### 3.1 Timing Tokens (Highest Priority)

Timing tokens define the per-word pacing algorithm. This IS the product — every value has an evidence chain.

#### 3.1.1 Base Formula

The base display duration for a word at a given WPM:

```
baseMs = 60000 / wpm
```

At the default 250 WPM: `baseMs = 60000 / 250 = 240ms`

#### 3.1.2 Per-Word Modifier Algorithm

Each word's actual display time is computed by applying multiplicative and additive modifiers to the base duration:

```
displayMs = max(timingWordFloorMs, baseMs × lengthModifier × frequencyModifier + punctuationPauseMs)
```

**Worked Examples at 250 WPM (baseMs = 240ms):**

| Word | Chars | Length Mod | Freq Mod | Punct Pause | Raw ms | Clamped ms |
|---|---|---|---|---|---|---|
| `"the"` | 3 | ×1.0 | ×1.0 (top-quartile) | 0 | 240 | 240 |
| `"reading"` | 7 | ×1.0 | ×1.0 | 0 | 240 | 240 |
| `"beautiful"` | 9 | ×1.3 | ×1.0 | 0 | 312 | 312 |
| `"confabulation"` | 13 | ×1.5 | ×1.2 (bottom-quartile) | 0 | 432 | 432 |
| `"world."` | 6 | ×1.0 | ×1.0 | +150 (period) | 390 | 390 |
| `"However,"` | 8 | ×1.3 | ×1.0 | +100 (comma) | 412 | 412 |
| `"I"` | 1 | ×1.0 | ×1.0 | 0 | 240 | 240 |

**At 400 WPM (baseMs = 150ms):**

| Word | Chars | Length Mod | Freq Mod | Punct Pause | Raw ms | Clamped ms |
|---|---|---|---|---|---|---|
| `"the"` | 3 | ×1.0 | ×1.0 | 0 | 150 | 150 |
| `"confabulation"` | 13 | ×1.5 | ×1.2 | 0 | 270 | 270 |
| `"it,"` | 2 | ×1.0 | ×1.0 | +100 | 250 | 250 |

**At 500 WPM (baseMs = 120ms) — hitting the floor:**

| Word | Chars | Length Mod | Freq Mod | Punct Pause | Raw ms | Clamped ms |
|---|---|---|---|---|---|---|
| `"a"` | 1 | ×1.0 | ×1.0 | 0 | 120 | **120** (floor) |
| `"confabulation"` | 13 | ×1.5 | ×1.2 | 0 | 216 | 216 |

#### 3.1.3 Token Table — Timing

| Token | Value | Type | Evidence | Rationale |
|---|---|---|---|---|
| `timing-word-base-formula` | `60000 / wpm` | Derived (ms) | P1 (Grade A): Acklin 2017, Di Nocera 2018 | Standard WPM-to-interval conversion |
| `timing-word-default-wpm` | `250` | `int` | P1 (Grade A): comprehension preserved ≤350 WPM; 250 is conservative default | **Must** default to 250. Current codebase defaults to 300 — **this is a spec-mandated change.** |
| `timing-word-min-wpm` | `100` | `int` | P10 (Grade B): user sovereignty over sensory parameters | Lower bound for user adjustment |
| `timing-word-max-wpm` | `500` | `int` | P1 (Grade A): comprehension collapses above 350; 500 allows informed override | Upper bound for user adjustment. See soft warning at 350. |
| `timing-word-floor-ms` | `120` | `int (ms)` | P3 (Grade B): Vitu 2001, Potter 2018, Schotter 2012 | **Should** never display a word for less than 120ms. Prevents subliminal presentation. Not user-adjustable. |
| `timing-word-length-threshold-medium` | `8` | `int (chars)` | P2 (Grade B): Primativo 2016, Sweller 2010 | Words ≥ 8 characters receive lengthModifier |
| `timing-word-length-threshold-long` | `12` | `int (chars)` | P2 (Grade B) | Words ≥ 12 characters receive higher lengthModifier |
| `timing-word-length-modifier-medium` | `1.3` | `double` | P2 (Grade B): starting estimate from processing-time literature | ×1.3 for words with 8–11 chars |
| `timing-word-length-modifier-long` | `1.5` | `double` | P2 (Grade B) | ×1.5 for words with ≥12 chars |
| `timing-word-frequency-modifier-rare` | `1.2` | `double` | P2 (Grade B): Primativo 2016, Brysbaert 2005 | ×1.2 for bottom-quartile frequency words. Requires frequency lookup table (e.g., SUBTLEX-US). If unavailable, omit this modifier — character count alone provides substantial benefit. |
| `timing-word-punctuation-comma-ms` | `100` | `int (ms)` | P2 (Grade B): simulates prosodic pause | Additive pause after `,` `;` `:` |
| `timing-word-punctuation-period-ms` | `150` | `int (ms)` | P2 (Grade B) | Additive pause after `.` `?` `!` |
| `timing-word-punctuation-paragraph-ms` | `250` | `int (ms)` | P2 (Grade B) | Additive pause at paragraph boundaries |
| `timing-wpm-warning-threshold` | `350` | `int` | P1 (Grade A): Di Nocera 2018 — inferential comprehension degrades above 350 | **Must** display soft advisory when user sets WPM > 350 |

#### 3.1.4 Dart Implementation — Timing Constants

```dart
/// lib/design/timing_tokens.dart
abstract final class RunThruTiming {
  // ── Word Pacing (P1, P2, P3 — Grade A/B) ──────────────────────
  static const int defaultWpm = 250;          // P1: MUST default to 250
  static const int minWpm = 100;              // P10: user range lower bound
  static const int maxWpm = 500;              // P1: user range upper bound
  static const int wpmWarningThreshold = 350; // P1: soft advisory trigger
  static const int wordFloorMs = 120;         // P3: absolute minimum display

  // ── Length Modifiers (P2 — Grade B) ────────────────────────────
  static const int lengthThresholdMedium = 8;
  static const int lengthThresholdLong = 12;
  static const double lengthModifierMedium = 1.3;
  static const double lengthModifierLong = 1.5;

  // ── Frequency Modifier (P2 — Grade B) ────────────────────────
  static const double frequencyModifierRare = 1.2;

  // ── Punctuation Pauses (P2 — Grade B) ─────────────────────────
  static const int punctuationCommaMs = 100;    // , ; :
  static const int punctuationPeriodMs = 150;   // . ? !
  static const int punctuationParagraphMs = 250; // ¶

  // ── UI Transitions (aesthetic choices) ────────────────────────
  static const Duration transitionInstant = Duration(milliseconds: 50);
  static const Duration transitionFast = Duration(milliseconds: 150);
  static const Duration transitionNormal = Duration(milliseconds: 300);
  static const Duration transitionSlow = Duration(milliseconds: 500);
  static const Duration debounceInput = Duration(milliseconds: 200);

  /// Compute display duration for a single word.
  ///
  /// [word] — the word to display (may include punctuation).
  /// [wpm] — the user's set WPM.
  /// [isRareWord] — true if the word is in the bottom frequency quartile.
  ///   Pass false if no frequency table is available.
  /// [isParagraphEnd] — true if this word ends a paragraph.
  static int wordDisplayMs(
    String word, {
    required int wpm,
    bool isRareWord = false,
    bool isParagraphEnd = false,
  }) {
    final baseMs = 60000.0 / wpm;

    // ── Length modifier ──
    final stripped = word.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final len = stripped.length;
    double lengthMod = 1.0;
    if (len >= lengthThresholdLong) {
      lengthMod = lengthModifierLong;
    } else if (len >= lengthThresholdMedium) {
      lengthMod = lengthModifierMedium;
    }

    // ── Frequency modifier ──
    final freqMod = isRareWord ? frequencyModifierRare : 1.0;

    // ── Punctuation pause ──
    int punctMs = 0;
    if (isParagraphEnd) {
      punctMs = punctuationParagraphMs;
    } else if (word.contains(RegExp(r'[.?!]$'))) {
      punctMs = punctuationPeriodMs;
    } else if (word.contains(RegExp(r'[,;:]$'))) {
      punctMs = punctuationCommaMs;
    }

    final rawMs = baseMs * lengthMod * freqMod + punctMs;
    return rawMs.round().clamp(wordFloorMs, rawMs.round().clamp(wordFloorMs, 9999));
  }
}
```

### 3.2 Color Tokens

The existing `RunThruTokens` in `lib/design/tokens.dart` defines the authoritative color palette. The spec validates this palette against the evidence and adds semantic mappings.

#### 3.2.1 Surface World Rule

**Must** (P6, Grade A; P7, Grade B): Two surface worlds exist and must never be mixed.

| World | Purpose | Base Token | Light Shadow | Dark Shadow |
|---|---|---|---|---|
| **Shell** | Library, settings, navigation chrome | `shellBase` (#ede3d2) | `shellLightShadow` (#f4f5f0) | `shellDarkShadow` (#ddd5c7) |
| **Stage** | Reading viewport, 3D cube, word display | `stageBase` (#ede3d2) | `stageLightShadow` (#f4f5f0) | `stageDarkShadow` (#ddd5c7) |

Note: Shell and stage share the same base palette values. The separation is semantic — they must not reference each other's tokens in code, enabling future divergence.

#### 3.2.2 Token Table — Color

| Token | Hex | Usage | Evidence |
|---|---|---|---|
| **Reading Stage** | | | |
| `color-stage-base` | `#ede3d2` | Reading viewport background | Aesthetic choice — warm off-white reduces visual fatigue relative to pure white |
| `color-stage-text` | `#2e272a` | Word display text | P6 (Grade A): high contrast on stage surface for foveal processing. Contrast ratio ≈ 10.5:1 on #ede3d2 |
| `color-stage-anchor` | `#c71f2d` | ORP anchor character highlight | P14 (Grade D): ORP character must be visually distinct. Red chosen for maximal chromatic contrast against warm neutrals. Contrast ratio ≈ 5.8:1 on #ede3d2. |
| `color-stage-progress` | `#149c88` | Progress indicator | P9 (Grade B): externalized EF. Sea green — positive, calm, distinct from anchor red |
| `color-stage-pause-overlay` | `#ccd5d5d8` | Pause fog overlay | P8 (Grade B): single-task mode. Translucent to signal "paused" without hiding context |
| `color-stage-wpm-badge` | `#625d5d` | WPM display text | Aesthetic choice — muted, peripheral |
| **UI Shell** | | | |
| `color-shell-base` | `#ede3d2` | Shell background | Aesthetic choice |
| `color-shell-text-primary` | `#2e272a` | Primary shell text | WCAG AA (≥ 4.5:1) guaranteed |
| `color-shell-text-secondary` | `#625d5d` | Secondary text / captions | WCAG AA on #ede3d2: ≈ 4.7:1 |
| `color-shell-accent` | `#4c7e86` | Interactive elements, links | Aesthetic choice — Brittany Blue, calm authority |
| `color-shell-processing` | `#fdac53` | Processing/queued status | Semantic: amber = in progress |
| `color-shell-ready` | `#149c88` | Ready/success status | Semantic: green = complete |
| `color-shell-error` | `#ed5656` | Error status | Semantic: red = error |
| `color-shell-on-error` | `#f4f5f0` | Text on error background | WCAG AA on #ed5656 |
| **3D Cube Interior** | | | |
| `color-cube-base` | `#f5f0ea` | Cube interior base | Aesthetic choice — warm marble white |
| `color-cube-back-wall` | `#ede8e2` | Back wall (word surface) | Slightly cooler than base — depth cue |
| `color-cube-side-walls` | `#e8e0d8` | Left/right walls | Warmer gray — receding depth |
| `color-cube-top-wall` | `#f0ebe5` | Ceiling | Lightest — light source implication |
| `color-cube-bottom-wall` | `#e2dad0` | Floor | Darkest — gravity, grounding |
| `color-cube-edge-glow` | `#faf7f4` | Neumorphic edge highlights | Aesthetic choice |
| **WPM Dial Gradient** | | | |
| `color-wpm-low` | `#4c7e86` | ≤ 300 WPM zone | P1 (Grade A): green zone — full comprehension |
| `color-wpm-mid` | `#fdac53` | 301–350 WPM zone | P1 (Grade A): yellow zone — degradation begins |
| `color-wpm-high` | `#ed5656` | > 350 WPM zone | P1 (Grade A): red zone — soft advisory triggered |

#### 3.2.3 Anchor Color Palette

12 user-selectable anchor highlight colors (P10, Grade B — user sovereignty over sensory parameters):

| Index | Name | Hex | Min Contrast on #ede3d2 |
|---|---|---|---|
| 0 | Hot Coral | (default from tokens) | ≥ 4.5:1 |
| 1 | Blazing Orange | | ≥ 3:1 |
| 2 | Marigold | | ≥ 3:1 |
| 3 | Buttercup | | ≥ 3:1 |
| 4 | Limelight | | ≥ 3:1 |
| 5 | Green Glow | | ≥ 3:1 |
| 6 | Sea Green | | ≥ 4.5:1 |
| 7 | Brilliant Blue | | ≥ 4.5:1 |
| 8 | Turkish Sea | | ≥ 4.5:1 |
| 9 | Fuscia Purple | | ≥ 4.5:1 |
| 10 | Radiant Orchid | | ≥ 4.5:1 |
| 11 | High Risk Red | | ≥ 4.5:1 |

Note: Some warm/light colors (indices 1–5) may not meet AA contrast on the warm stage background. **Consider** providing an accessibility warning if the user selects a low-contrast anchor color, or applying a text shadow/outline to maintain legibility. This is a Grade C recommendation (no direct evidence — extrapolated from WCAG).

### 3.3 Typography Tokens

#### 3.3.1 Font Family Strategy

| Context | Font | Evidence |
|---|---|---|
| Shell UI | Bricolage Grotesque | Aesthetic choice — geometric sans-serif, modern, readable at UI sizes. **Must** use per rules 2 and 8. |
| Reading stage (default) | Bricolage Grotesque | Default — user-selectable per P10. |
| Reading stage (user options) | See `RunThruTypography.availableFonts` | P10 (Grade B): user sovereignty. 22 options including serif, sans-serif, and monospace. |

**ORP Typography Constraint**: The ORP algorithm (P14, Grade D) requires calculating the pixel offset of a specific character index. Variable-width fonts require character-level measurement at render time via `TextPainter`. The current implementation handles this by measuring individual glyphs and positioning them relative to a fixed ORP anchor point. **No monospace font is required** — the glyph-measurement approach works with any font, though monospace fonts would simplify the calculation.

#### 3.3.2 Token Table — Typography

| Token | Value | Usage | Evidence |
|---|---|---|---|
| `type-family-shell` | `'BricolageGrotesque'` | All shell UI text | Rule 8 — hard constraint |
| `type-family-reading-default` | `'BricolageGrotesque'` | Reading word display default | P10 (Grade B): user-configurable |
| `type-size-display` | `32.0` | Page titles | Aesthetic choice |
| `type-size-title` | `20.0` | Section headers | Aesthetic choice |
| `type-size-body` | `16.0` | Body text, labels | Aesthetic choice — standard mobile body size |
| `type-size-caption` | `12.0` | Secondary info, timestamps | Aesthetic choice |
| `type-size-badge` | `24.0` | Numeric badges (library cards) | Aesthetic choice |
| `type-size-stage-badge` | `14.0` | WPM badge during reading | P8 (Grade B): small, peripheral, non-distracting |
| `type-weight-regular` | `FontWeight.w400` | Body text | Standard |
| `type-weight-medium` | `FontWeight.w500` | Titles, emphasis | Standard |
| `type-weight-semibold` | `FontWeight.w600` | Display text, badges | Standard |
| `type-weight-bold` | `FontWeight.w700` | ORP anchor character | P14 (Grade D): anchor must be visually distinct — weight contrast is the primary method |
| `type-lineheight-tight` | `1.2` | Display text, badges | Standard |
| `type-lineheight-normal` | `1.5` | Body text | Readability standard |
| `type-lineheight-reading` | `1.0` | Reading word display | Single word — no line spacing needed |
| `type-reading-word-color` | `stageText` (#2e272a) | Non-anchor characters | P6 (Grade A) |
| `type-reading-anchor-color` | `stageAnchor` (#c71f2d) | ORP anchor character | P14 (Grade D) |

#### 3.3.3 3D Typography Constants

| Token | Value | Evidence |
|---|---|---|
| `type-3d-extrusion-depth-factor` | `0.08` (× fontSize) | Aesthetic choice — "felt, not seen" extrusion |
| `type-3d-bevel-radius` | `0.5` | Aesthetic choice |
| `type-3d-extrusion-layers` | `6` | Aesthetic choice — smooth gradient |
| `type-3d-layer-darken-factor` | `0.15` per layer | Aesthetic choice |

### 3.4 Spacing Tokens

| Token | Value | Usage |
|---|---|---|
| `space-unit` | `4.0` | Base unit |
| `space-xs` | `4.0` (1 unit) | Tight internal gaps |
| `space-sm` | `8.0` (2 units) | Standard internal gaps |
| `space-md` | `16.0` (4 units) | Standard padding |
| `space-lg` | `24.0` (6 units) | Section spacing |
| `space-xl` | `32.0` (8 units) | Large section breaks |
| `space-2xl` | `48.0` (12 units) | Major layout divisions |
| `space-3xl` | `64.0` (16 units) | Screen-level margins |

### 3.5 Elevation Tokens

| Token | Value | Usage | Evidence |
|---|---|---|---|
| **Neumorphic Shadows** | | | |
| `elevation-small-offset` | `4.0` | Small neumorphic elements | Aesthetic choice |
| `elevation-small-blur` | `8.0` | | |
| `elevation-standard-offset` | `6.0` | Standard cards, buttons | Aesthetic choice |
| `elevation-standard-blur` | `12.0` | | |
| `elevation-large-offset` | `10.0` | Large panels, modals | Aesthetic choice |
| `elevation-large-blur` | `20.0` | | |
| **3D Depth** | | | |
| `depth-eye-distance` | `10.0` room units | Off-axis projection eye depth | Aesthetic choice — calibrated for natural parallax feel |
| `depth-room-depth` | `12.0` room units | Room Z-axis extent | Aesthetic choice |
| `depth-text-fraction` | `0.15` (15% of room depth) | Word Z-position | Aesthetic choice — forward of back wall for raised appearance |
| `depth-parallax-max-displacement` | `5%` of viewport dimensions | Maximum parallax shift | P6 (Grade A), P15 (Grade D): keeps room shift in peripheral vision. **Must** not exceed 5%. |
| `depth-grid-spacing` | `2.0` room units | Floor grid line spacing | Aesthetic choice |
| `depth-unit-scale` | `100.0` pixels/room unit | Projection scale | Derived from screen size (auto-calculated) |

### 3.6 Breakpoint Tokens

| Token | Value | Usage |
|---|---|---|
| `breakpoint-sm` | `320.0` | Small phones (SE) |
| `breakpoint-md` | `375.0` | Standard phones |
| `breakpoint-lg` | `428.0` | Large phones / small tablets |
| `breakpoint-xl` | `768.0` | Tablets |
| `breakpoint-2xl` | `1024.0` | Desktop |

Reading mode is portrait-locked and fullscreen on all breakpoints. Layout adaptation is primarily for the library/settings shell.

---

## 4. Layout System

### 4.1 Reading Mode Layout

**Must** (P8, Grade B): During active reading, the UI shows ONLY the word inside the 3D cube. No shell chrome is visible.

```
┌──────────────────────────────┐
│                              │
│   ┌────────────────────────┐ │
│   │     CUBE VIEWPORT      │ │
│   │                        │ │
│   │   ┌──────────────────┐ │ │
│   │   │   BACK WALL      │ │ │
│   │   │                  │ │ │
│   │   │   con•fab•u•la   │ │ │ ← Word at ORP anchor point
│   │   │                  │ │ │
│   │   └──────────────────┘ │ │
│   │                        │ │
│   │   [ambient progress]   │ │ ← Subtle floor gradient (P9)
│   └────────────────────────┘ │
│                              │
│        [•] WPM badge         │ ← Peripheral, low-contrast (P8)
└──────────────────────────────┘
```

- The cube viewport fills the screen edge-to-edge in reading mode
- System UI is hidden (`SystemUiMode.immersiveSticky`)
- Back wall is inset by `_insetFraction = 0.18` (18%) from viewport edges, creating the 3D wall perspective
- Word is positioned at `depth-text-fraction` (15%) of room depth — forward of back wall
- Progress indicator is integrated into room geometry (see SessionProgress component)

### 4.2 Paused State Layout

**Should** (P8, P9): When the user pauses, controls fade in over 200ms:

```
┌──────────────────────────────┐
│                              │
│   ┌────────────────────────┐ │
│   │  [fog overlay]         │ │ ← stagePauseOverlay
│   │                        │ │
│   │   con•fab•u•la         │ │ ← Word remains visible (dimmed)
│   │                        │ │
│   │     ▶ Resume           │ │ ← Tap anywhere to resume
│   │                        │ │
│   └────────────────────────┘ │
│                              │
│   [← Back]     [⚙ Speed]    │ ← Controls fade in
│                              │
│   12% complete • 250 WPM     │ ← Externalized EF (P9)
│   1,240 words read           │ │
└──────────────────────────────┘
```

### 4.3 Shell Layout (Library / Settings)

```
┌──────────────────────────────┐
│   RunThru                 │ ← Title (display style)
│──────────────────────────────│
│                              │
│   ┌──────────┐ ┌──────────┐ │
│   │ PDF Card │ │ PDF Card │ │ ← Neumorphic raised cards
│   │ Title    │ │ Title    │ │
│   │ Status   │ │ Status   │ │
│   └──────────┘ └──────────┘ │
│                              │
│   ┌──────────┐ ┌──────────┐ │
│   │ PDF Card │ │ PDF Card │ │
│   └──────────┘ └──────────┘ │
│                              │
│──────────────────────────────│
│  📚   🔍   📊   ⚙         │ ← Bottom nav (4 tabs)
└──────────────────────────────┘
```

- Grid: 2 columns on phone, 3 on tablet, 4+ on desktop
- Gutters: `space-md` (16px)
- Edge margins: `space-md` (16px) on phone, `space-xl` (32px) on tablet+
- Card aspect ratio: ~4:3 (aesthetic choice)
- Cards use `RunThruDecorations.raisedDecoration(RunThruSurface.shell)`

### 4.4 Information Density Rules

**Should** (P8, Grade B): Minimize extraneous elements.

- **Reading mode**: Maximum 2 elements visible (word + ambient progress). WPM badge is optional and auto-hides after 3 seconds of reading.
- **Paused mode**: Maximum 5 elements (word, resume hint, back button, speed control, session stats)
- **Shell**: Standard density — no specific constraint beyond platform conventions. Cards should have generous whitespace (minimum `space-sm` internal padding).

### 4.5 Reading Zone Specification

The word display area (back wall of the cube) is defined by the off-axis projection:

- Back wall width on screen: `viewportWidth × (1 - 2 × _insetFraction)` ≈ 64% of viewport width
- Word target width: 80% of back wall screen width (from `BackWallFontSizer`)
- Reference word for sizing: 12 characters ("COMPENSATION")
- Font size is dynamically computed to fill the target width
- Font size clamp: [16.0, 600.0] for parallax; [28.0, 400.0] for non-parallax
- Single word per display event — no multi-line layout

---

## 5. Component Library

### 5.1 Component: WordDisplay

---
**Version**: 1.0
**Evidence basis**: Principle 2 (Grade B), Principle 3 (Grade B), Principle 6 (Grade A), Principle 13 (Grade C), Principle 14 (Grade D)

---

#### Purpose

The core reading component. Renders a single word at its calculated ORP position inside the 3D focal plane, with the anchor character highlighted and word transitions animated. This is the most important component in the app — everything else supports it.

**When to use**: Always during active reading.
**When NOT to use**: Never outside the reading viewport.

#### Anatomy

- **Pre-anchor segment**: Characters before the ORP index, rendered in `stageText` color at `type-weight-regular`
- **Anchor character**: The single ORP character, rendered in `stageAnchor` color at `type-weight-bold`
- **Post-anchor segment**: Characters after the ORP index, rendered in `stageText` color at `type-weight-regular`
- **Anchor focal point**: A fixed horizontal screen position where the anchor character's center always aligns. Words shift left/right so the anchor character is always at the same X coordinate.
- **Warm glow** (parallax variant only): Subtle blur-16 glow behind each glyph using `roomTextGlow`
- **Vignette** (parallax variant only): Warm radial gradient overlay

#### ORP Calculation Rules

The ORP position is calculated per `lib/core/orp.dart`:

```
1. Strip leading/trailing punctuation from the word
2. anchorIndex = (strippedLength + 1) ~/ 2    // 1-indexed, slightly left of center
3. Offset by leading punctuation count to get position in original word
```

**Examples:**

| Word | Stripped | Length | ORP Index (1-based) | Anchor Char |
|---|---|---|---|---|
| `"the"` | `"the"` | 3 | 2 | `h` |
| `"reading"` | `"reading"` | 7 | 4 | `d` |
| `"confabulation"` | `"confabulation"` | 13 | 7 | `u` |
| `"Hello,"` | `"Hello"` | 5 | 3 | `l` |
| `"(yes)"` | `"yes"` | 3 | 2 → offset +1 = 3 in original | `e` |
| `"I"` | `"I"` | 1 | 1 | `I` |

**Anchor alignment**: The anchor character's horizontal center is pinned to the horizontal center of the viewport (non-parallax) or to the projected text position's center (parallax). All other characters are positioned relative to the anchor, using measured glyph widths.

#### Tokens Consumed

| Token | Usage |
|---|---|
| `color-stage-text` | Non-anchor characters |
| `color-stage-anchor` (or user-selected from anchor palette) | Anchor character |
| `type-family-reading-default` (or user-selected) | Font family |
| `type-weight-regular` | Non-anchor weight |
| `type-weight-bold` | Anchor weight |
| `type-lineheight-reading` | Line height (1.0) |
| `timing-word-base-formula` + modifiers | Display duration |
| `timing-word-floor-ms` | Minimum display time |
| `depth-text-fraction` | Z-position in room (parallax variant) |

#### States

| State | Visual Description | Trigger |
|---|---|---|
| **Displaying** | Word visible, anchor highlighted, position stable | Word timer tick |
| **Transitioning** | Brief scale breathe (A-001: 80ms, 1.5% scale pulse) | New word arrives |
| **Depth Bounce-In** (parallax only) | Word slides forward from behind with SubtleBounceIn (A-013: 160ms, 4% overshoot, per-glyph 6ms stagger) | New word arrives |
| **Paused** | Word remains visible, dimmed by pause fog overlay | User pauses |
| **Finished** | Last word remains displayed, finish overlay appears | `isFinished == true` |

#### Variants

| Variant | When to Use | Differences from Default |
|---|---|---|
| **WordPainter** (non-parallax) | Free tier / legacy reading screen | 2D rendering, `dynamicFontSize()`, no depth bounce, no glow |
| **ParallaxWordPainter** (parallax) | Premium parallax reading screen | 3D projected, `BackWallFontSizer`, depth bounce-in (A-013), warm glow, vignette, per-glyph stagger |

#### Interaction Specification

| Event | Response | Timing |
|---|---|---|
| Word timer tick | Swap word, trigger transition animation | A-001 (80ms) or A-013 (160ms) |
| Tap anywhere | Toggle pause (P8) | Immediate (`timing-transition-instant`) |
| Swipe left | Skip to next sentence | `timing-transition-fast` (150ms) |
| Swipe right | Rewind to previous sentence | `timing-transition-fast` (150ms) |

#### Accessibility

- **WCAG level**: AA
- **Relevant criteria**: 1.4.3 (Contrast Minimum — anchor on stage surface), 1.4.6 (Enhanced Contrast — body text on stage surface), 2.3.1 (Three Flashes — word transitions must not flash)
- **Cognitive accommodation**: ORP anchoring reduces saccade planning load (P14). External pacing removes self-regulation burden (P5). Per-word timing adapts to complexity (P2).
- **Screen reader**: **Must** announce each word sequentially when reading mode is active. Screen reader users experience standard text flow, not word-at-a-time. Provide a "read full text" mode for assistive technology.
- **Keyboard**: Space = play/pause. Left/right arrows = rewind/skip sentence. Up/down = adjust WPM by ±10.

#### Responsive Behavior

| Breakpoint | Adaptation |
|---|---|
| All | Font size computed dynamically to fill 80% of back wall width. No fixed breakpoint adaptation — continuous scaling. |
| `breakpoint-sm` (320px) | Font size clamp lower bound applies (16px parallax, 28px non-parallax) |
| `breakpoint-2xl` (1024px+) | Font size clamp upper bound applies (600px parallax, 400px non-parallax) |

#### Do / Don't

| Do | Don't | Why (Principle) |
|---|---|---|
| Pin anchor char to fixed focal point | Center the word horizontally | P14: ORP alignment requires the eye to stay at a consistent fixation point |
| Render only the word — nothing else in the foveal zone | Add progress bars, WPM text, or icons near the word | P6: Ambient-only visual environment. The word is sacred. |
| Use measured glyph widths for positioning | Assume character widths from font metrics tables | Variable-width fonts require runtime measurement |
| Apply per-word timing modifiers silently | Show "this word is getting extra time" feedback | P16: Adaptation must be invisible to the reader |
| Check `isReducedMotion(context)` for transitions | Assume animations are always enabled | Rule 5: every animation must check reduced motion |

---

### 5.2 Component: PacingEngine

---
**Version**: 1.0
**Evidence basis**: Principle 1 (Grade A), Principle 2 (Grade B), Principle 3 (Grade B), Principle 5 (Grade A), Principle 16 (Grade D)

This is a logical component, not a visual one. It computes per-word display duration.

---

#### Purpose

The timing algorithm that determines how long each word displays. This is the core intervention mechanism — it substitutes for the executive function that ADHD readers lack for pace self-regulation. The engine controls micro decisions (per-word timing) while the user controls macro parameters (target WPM).

**When to use**: Always during reading playback.
**When NOT to use**: Never exposed directly to the user.

#### Algorithm Specification

```dart
/// Compute the display duration for word at `index` in `words`.
///
/// Parameters:
///   words — the full word list
///   index — current word index
///   wpm — user's target WPM
///   isRareWord — frequency lookup result (false if no table)
///
/// Returns: display duration in milliseconds
int computeDisplayMs(List<String> words, int index, int wpm, {bool isRareWord = false}) {
  final word = words[index];
  
  // Detect paragraph boundary (double newline or explicit marker)
  final isParagraphEnd = _isParagraphBoundary(words, index);
  
  return RunThruTiming.wordDisplayMs(
    word,
    wpm: wpm,
    isRareWord: isRareWord,
    isParagraphEnd: isParagraphEnd,
  );
}
```

#### Drift Correction

The existing `WordTimerNotifier` implements drift correction:

1. Record `_lastTick` timestamp after each word advance
2. Compute elapsed vs. expected interval
3. Adjust next delay: `delay = (interval - drift).clamp(1, interval * 2)`
4. Skip drift correction on first tick after play/resume

**Spec change required**: The current `intervalMs` getter uses a flat `60000 / wpm`. This **should** be replaced with the per-word formula from `RunThruTiming.wordDisplayMs()`, so each word gets its own computed duration. Drift correction must work against the per-word interval, not a fixed interval.

#### Adaptive Difficulty Hooks (Future — Grade D)

**Explore** (P7, P16): Future iterations could add sentence-level adaptation:

- Compute running text difficulty proxy: average character count of current sentence, word frequency distribution, punctuation density
- If sentence difficulty exceeds threshold: reduce base WPM by 10–15% for that sentence
- Transition between difficulty levels must be gradual (spread over 3–5 words)
- Never expose this adaptation to the user

This is not specified for v2.0 implementation but the timing architecture should accommodate it.

#### Integration with Riverpod

The `WordTimerNotifier` (StateNotifier) must be updated to:
1. Accept a `List<String>` of words and per-word metadata
2. Compute per-word duration using `RunThruTiming.wordDisplayMs()`
3. Feed the computed duration into the drift-corrected timer
4. Expose `currentDisplayMs` in state for debugging/analytics

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Compute per-word duration silently | Show timing variation to the user | P16: invisible adaptation |
| Enforce the 120ms floor for every word | Allow sub-120ms display at any WPM | P3: prevents subliminal presentation |
| Apply punctuation pauses after sentence-ending marks | Add pauses inside words or at word boundaries without punctuation | P2: prosodic pause simulation |
| Use drift correction against per-word intervals | Use drift correction against a fixed interval | Per-word timing means each interval differs |

---

### 5.3 Component: ParallaxRoom

---
**Version**: 1.0
**Evidence basis**: Principle 6 (Grade A), Principle 7 (Grade B), Principle 11 (Grade C), Principle 15 (Grade D)

---

#### Purpose

The 3D environment surrounding the word. Renders the neumorphic marble cube interior with perspective depth, parallax head tracking, and subtle ambient animation. Functions as a **peripheral attention scaffold** — sustains attention without competing with word processing.

**When to use**: Premium reading mode (parallax reading screen).
**When NOT to use**: Free tier (uses static cube viewport instead). Never render room elements in the foveal zone during active reading.

#### Anatomy

- **Back wall**: Warm marble surface with center light glow, marble veining (8 primary + 5 background veins via quadratic beziers). The word renders ON this wall.
- **Side walls** (left, right, floor, ceiling): Gradient-shaded surfaces receding in perspective. Floor has etched grid lines.
- **Grid lines**: Transversal rings (far→near) and longitudinal lines on floor. Subtle marble tile seam aesthetic.
- **Marble veining**: Organic curves across all surfaces using `marbleVeinPrimary` and `marbleVeinSecondary` colors.
- **Ambient light pool**: Radial glow from center of back wall using `marbleSurfaceGlow`.
- **Vignette**: Warm, soft radial darkening at edges.
- **Fog overlay** (paused state): `stagePauseOverlay` with walls dimming by `15%` opacity.

#### Tokens Consumed

| Token | Usage |
|---|---|
| `color-cube-*` | All wall surfaces |
| `color-marble-*` | Veining and surface glow |
| `color-room-*` | Grid lines, background, fog |
| `depth-eye-distance` | Off-axis projection |
| `depth-room-depth` | Room Z extent |
| `depth-parallax-max-displacement` | Maximum parallax shift (5%) |
| `depth-grid-spacing` | Floor grid density |

#### States

| State | Visual Description | Trigger |
|---|---|---|
| **Active** | Full room visible, parallax responding, cube breathing (A-011) | Reading is playing |
| **Paused** | Fog overlay, walls dim 15%, parallax frozen | User pauses |
| **Building** | Walls reveal progressively (`buildProgress` 0→1) | Initial room construction animation |
| **Reduced Intensity** | Static room, no breathe, no grid animation, muted gradients | High text difficulty (P7) OR user preference |
| **Static** | No parallax, no breathe, no ambient animation | `isReducedMotion == true` OR parallax set to "off" |

#### Adaptive Visual Intensity (P7, Grade B)

**Should** implement 3 intensity levels tied to text difficulty:

| Level | Trigger | Room Behavior |
|---|---|---|
| **Minimal** | High text difficulty (avg word length in current sentence ≥ 9 chars) OR user override | Static walls, no breathe animation, no grid line animation, minimal gradient variation |
| **Moderate** (default) | Normal text difficulty | Subtle breathe (A-011: 8s cycle, ±1.5°), gentle parallax, grid lines visible |
| **Rich** | Low text difficulty (avg word length ≤ 4 chars) OR user override | Full parallax response, breathe animation, grid line depth shimmer, marble vein highlights |

Transitions between levels **must** be gradual (fade over 3–5 seconds / 10–20 words at 250 WPM). Sudden visual changes would be distracting (violates P6).

#### Parallax Behavior

| Input Source | Platform | Behavior |
|---|---|---|
| Pointer/mouse hover | Desktop | Head position mapped from mouse position within window. Smooth interpolation. |
| IMU/gyroscope | Mobile | Device tilt mapped to head position. Low-pass filtered to remove jitter. |
| Camera face detection | All (opt-in) | OpenCV head position mapped to room offset. Requires explicit user permission. Enhancement only. |
| None | Any | Room renders at center position. No parallax shift. Fully functional without tracking. |

**Maximum displacement**: ≤5% of viewport dimensions in any direction (P6, Grade A). At 390px width, maximum shift = ±19.5px.

**Word position**: The word is **NEVER** affected by parallax. Only the room moves. The word is spatially locked at the focal point. (P6, Grade A — hard constraint.)

#### Accessibility

- **WCAG level**: AA for contrast of room elements against each other (not critical — room is peripheral)
- **Cognitive accommodation**: Room is the peripheral engagement channel (P15). Must never demand conscious attention during reading (P6).
- **Reduced motion**: When `isReducedMotion == true`, disable all room animation (breathe, parallax, grid shimmer). Room renders as a static 3D scene. The room's value as a depth cue persists without animation.
- **Motion sensitivity**: Parallax intensity is user-adjustable (off / subtle / full). Off = flat 2D surface with neumorphic edges.

#### Do / Don't

| Do | Don't | Why (Principle) |
|---|---|---|
| Keep all visual events in peripheral vision (>2° from word center) | Render high-contrast elements near the word position | P6: The word is sacred — no foveal competition |
| Use slow animations (>2000ms cycle) | Use rapid flashing, pulsing, or sudden visual changes | P6: No sudden visual events during reading |
| Reduce room intensity when text is difficult | Maintain full visual richness regardless of content | P7: Seductive details are more harmful when cognitive load is high |
| Respond to user head movement (parallax) | Auto-animate the room independently of user input | P15: User-driven novelty reduces seductive details risk |
| Provide "off" option for parallax | Require head tracking for reading | P10: User sovereignty; P15: Parallax is always optional |

---

### 5.4 Component: ReadingChrome

---
**Version**: 1.0
**Evidence basis**: Principle 8 (Grade B), Principle 9 (Grade B)

---

#### Purpose

The minimal UI visible during active reading — progress indicator, WPM display, and pause/exit controls. Manages the tension between single-task mode (P8: hide everything) and externalized EF (P9: show progress).

#### Anatomy

- **WPM Badge**: Small `stageBadge` style text showing current WPM. Positioned bottom-center, below the cube. Uses `stageWpmBadge` color.
- **Progress Hairline**: A thin (1–2px) line along the bottom edge of the viewport. Fills left-to-right as reading progresses. Uses `stageProgress` color at reduced opacity (30–50%).
- **Pause Controls** (visible only when paused): Resume button, speed adjustment, exit/back button, session stats.

#### States

| State | Visible Elements | Trigger |
|---|---|---|
| **Reading (first 3s)** | WPM badge + progress hairline | Reading starts or resumes |
| **Reading (after 3s)** | Progress hairline only | 3 seconds of uninterrupted reading. WPM badge fades out. |
| **Paused** | All controls + session stats | User taps to pause |
| **Finished** | Finish overlay with session summary | Last word displayed |

#### Tokens Consumed

| Token | Usage |
|---|---|
| `color-stage-wpm-badge` | WPM text color |
| `color-stage-progress` | Progress hairline color |
| `color-stage-pause-overlay` | Fog overlay |
| `type-size-stage-badge` | WPM badge font size |
| `timing-transition-fast` | Control fade in/out |

#### Interaction

| Event | Response | Timing |
|---|---|---|
| Tap (during reading) | Pause — fog overlays, controls fade in | A-006 (200ms) |
| Tap resume | Resume — fog clears, controls fade out | A-007 (150ms) |
| 3s reading without pause | WPM badge fades out | `timing-transition-normal` (300ms) |
| Tap back/exit | Navigate to library | `timing-transition-normal` (300ms) |

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Auto-hide WPM badge after 3s | Keep WPM visible throughout reading | P8: Single-task mode — minimize visible elements |
| Use hairline (1–2px) progress indicator | Use a thick progress bar | P8: Progress must be ambient, not attention-grabbing |
| Show session stats on pause only | Show stats during reading | P8: No metrics during active reading |
| Use `stageProgress` at 30–50% opacity | Use full-opacity progress bar | P6: Ambient-only visual environment |

---

### 5.5 Component: WPMControl

---
**Version**: 1.0
**Evidence basis**: Principle 1 (Grade A), Principle 10 (Grade B)

---

#### Purpose

The speed adjustment interface. Allows the user to set their target WPM within the evidence-supported range. Provides visual feedback at comprehension boundaries.

#### Anatomy

- **WPM Dial** (existing `WpmDial3D`): Concentric neumorphic rings. Ring gradient maps to comprehension zones.
- **Numeric display**: Current WPM value, center of dial.
- **Adjustment gesture**: Rotational gesture on dial OR vertical drag.
- **Comprehension zone indicator**: Gradient color shift on dial ring:
  - Green zone (`color-wpm-low`): 100–300 WPM
  - Yellow zone (`color-wpm-mid`): 301–350 WPM
  - Red zone (`color-wpm-high`): 351–500 WPM
- **Soft advisory**: Text warning that appears when WPM exceeds 350.

#### States

| State | Visual Description | Trigger |
|---|---|---|
| **Default** | Dial showing current WPM in green zone | WPM ≤ 300 |
| **Caution** | Dial ring shifts to yellow/amber | 301 ≤ WPM ≤ 350 |
| **Warning** | Dial ring shifts to red. Advisory text appears below: *"Above 350 WPM, deep comprehension may decrease. This speed works well for scanning familiar material."* | WPM > 350 |
| **Adjusting** | Dial animates with user input, haptic feedback at zone boundaries | User dragging/rotating |

#### Tokens Consumed

| Token | Usage |
|---|---|
| `color-wpm-low` / `mid` / `high` | Dial ring gradient |
| `timing-wpm-warning-threshold` | Advisory trigger point (350) |
| `timing-word-min-wpm` / `max-wpm` | Input range bounds |
| `timing-word-default-wpm` | Initial value (250) |
| `type-size-badge` | WPM numeric display |

#### Interaction

| Event | Response | Timing |
|---|---|---|
| Drag on dial | WPM changes continuously. Haptic tick at each 10 WPM step. | Immediate |
| Cross 350 WPM threshold | Haptic warning buzz. Advisory text fades in. Ring color shifts to red. | `timing-transition-fast` |
| Drop below 300 WPM | Ring color shifts to green. Advisory (if visible) fades out. | `timing-transition-fast` |
| Keyboard up/down | Adjust by ±10 WPM per press | Immediate |

#### Accessibility

- **Screen reader**: Announce current WPM value. Announce zone change: "Entering caution zone" at 300, "Entering warning zone — deep comprehension may decrease above 350 words per minute" at 350.
- **Keyboard**: Up/down arrows adjust WPM by ±10. Page up/down adjust by ±50.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Show the soft advisory at > 350 WPM | Hard-cap WPM at 350 | P1: Users must be informed, not restricted. P10: User sovereignty. |
| Use gradient color to communicate comprehension zones | Use only numeric values without visual feedback | P1: The 350 WPM boundary is a hard constraint from Grade A evidence |
| Default to 250 WPM | Default to 300 WPM (current codebase value) | **P1 (Grade A): Must default to 250.** This is a required change from the current 300 default. |

---

### 5.6 Component: SettingsPanel

---
**Version**: 1.0
**Evidence basis**: Principle 10 (Grade B)

---

#### Purpose

The customization surface for all user-adjustable parameters. Uses progressive disclosure to prevent overwhelm (P10: neurodiverse users can be overwhelmed by dense settings).

#### Anatomy — Primary Settings (always visible)

| Setting | Control Type | Range | Default | Evidence |
|---|---|---|---|---|
| **Reading Speed (WPM)** | Slider + numeric | 100–500 | 250 | P1, P10 (Grade A/B) |
| **Font Size** | Slider | 0.5× – 2.0× | 1.0× | P10 (Grade B) |
| **Font Family** | Dropdown/picker | `RunThruTypography.availableFonts` (22 options) | Bricolage Grotesque | P10 (Grade B) |
| **Parallax Intensity** | Segmented control: Off / Subtle / Full | 3 options | Subtle | P15 (Grade D), P10 (Grade B) |

#### Anatomy — Secondary Settings (progressive disclosure — "Advanced" section)

| Setting | Control Type | Range | Default | Evidence |
|---|---|---|---|---|
| **Reduced Motion** | Toggle | On/Off | Off (follows system) | Rule 5, P6 |
| **Per-Word Timing** | Toggle | On/Off | On | P2 (Grade B) |
| **Anchor Color** | Color picker (12 colors) | Palette indices 0–11 | 0 (Hot Coral / High Risk Red) | P10, P14 |
| **Room Intensity** | Segmented: Minimal / Auto / Rich | 3 options | Auto | P7 (Grade B) |
| **3D Text Extrusion** | Toggle | On/Off | On | Aesthetic choice |

#### Tokens Consumed

Shell surface tokens exclusively. **Must** use `RunThruSurface.shell` decorations.

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Group settings by frequency of use (primary visible, advanced hidden) | Show all settings at once in a flat list | P10: ADHD users can be overwhelmed by dense settings |
| Use the system's reduced-motion setting as the default | Force reduced motion on or off | Respect platform accessibility preferences |
| Show the WPM warning gradient on the speed slider | Only show the warning after the value is set | P1: Real-time feedback at comprehension boundaries |

---

### 5.7 Component: SessionProgress

---
**Version**: 1.0
**Evidence basis**: Principle 9 (Grade B), Principle 12 (Grade C)

---

#### Purpose

Externalizes reading progress so the user doesn't need to hold "where am I?" in working memory. Provides ambient feedback during reading and detailed stats on pause.

#### Anatomy

**During reading** (ambient):
- **Progress hairline**: 1–2px line at viewport bottom. `stageProgress` at 30–50% opacity. Fills left-to-right proportional to word index / total words.
- No numeric display during reading (P8).

**On pause** (detailed):
- **Percentage**: "12% complete"
- **Words read**: "1,240 words read"
- **Current WPM**: "250 WPM"
- **Session time**: "4 min reading"

**On session end** (summary):
- Words read this session
- Time spent reading
- Estimated % of document completed
- Reading consistency: "You've read 4 of the last 7 days" (P12, Grade C — non-punitive framing)

#### Do / Don't

| Do | Don't | Why |
|---|---|---|
| Use continuous progress (smooth fill) | Use stepped milestones ("Chapter 1 of 5") | P9: Continuous progress reduces "where am I?" anxiety |
| Frame consistency as positive fact ("4 of 7 days") | Frame as pressure ("Don't break your 4-day streak!") | P12: Non-punitive engagement. Punitive gamification triggers shame cycles in ADHD users. |
| Show summary after reading, not during | Overlay stats on the reading viewport | P8: Single-task mode during reading |

---

### 5.8 Component: ContentLoader

---
**Version**: 1.0
**Evidence basis**: None directly — standard UX practice

---

#### Purpose

How PDF content enters the app. Handles folder scanning, file selection, and preprocessing pipeline feedback.

#### Anatomy

- **Folder picker**: Native file picker dialog → stores folder path in `AppConfig.pdfFolderPath`
- **PDF card grid**: Library view showing all discovered PDFs with processing status
- **Status indicators**: Per-PDF status badge using semantic colors:
  - `shellProcessing` (amber): Processing / queued
  - `shellReady` (green): Ready to read
  - `shellError` (red): Extraction failed
- **Error handling**: Toast/snackbar with neumorphic styling for file errors. Non-blocking.

#### Processing Pipeline Feedback

PDF extraction runs in Isolates (Rule 11). The `PreprocessingQueue` manages parallel workers. User feedback:

| State | Visual | Interaction |
|---|---|---|
| Pending | Gray badge, no progress | — |
| Queued | Amber badge, position indicator | — |
| Processing | Neumorphic pulse animation (A-008: 1200ms) | Cancel available |
| Preview | Partial results available, amber + checkmark | Tap to read (partial) |
| Ready | Green badge | Tap to read |
| Error | Red badge + error message | Tap for details, retry option |

**Must** NOT use `CircularProgressIndicator` or `LinearProgressIndicator` (Rule 15). Use neumorphic pulse (A-008) or water ripple (A-012) for loading states.

---

### 5.9 Component: LibraryView

---
**Version**: 1.0
**Evidence basis**: Principle 8 (Grade B) — library is the shell, not the reading environment

---

#### Purpose

The user's reading history and queued content. Entry point to reading.

#### Anatomy

- **PDF cards**: Neumorphic raised cards in a grid layout
- **Card content**: File name (title style), processing status badge, reading progress (if any), last read date
- **Empty state**: Prompt to select a folder with friendly illustration
- **Tab position**: First tab in bottom navigation

#### Information Hierarchy (per card)

1. **File name** (primary — `title` style)
2. **Reading progress** (secondary — progress bar or "42% read")
3. **Processing status** (tertiary — badge)
4. **Last read** (quaternary — `caption` style, relative date)

#### Layout

- 2-column grid on phone (`breakpoint-sm` to `breakpoint-lg`)
- 3-column grid on tablet (`breakpoint-xl`)
- 4+ column grid on desktop (`breakpoint-2xl`)
- Card spacing: `space-md` (16px)

---

### 5.10 Component: ComprehensionCheck (Future — Grade C)

---
**Version**: 0.1 (specification only — not for v2.0 implementation)
**Evidence basis**: Principle 12 (Grade C), Principle 1 (Grade A — testable prediction)

---

#### Purpose

Optional post-reading or periodic comprehension feedback. Enables the testable predictions from the design principles (e.g., "users at 250 WPM should achieve ≥80% on inference questions").

**Consider** implementing for v2.1. Spec provided for planning purposes.

#### Design Constraints

- **Must** be optional — never forced. ADHD users may find mandatory quizzes anxiety-inducing.
- **Should** use 2–3 questions per reading session, not exhaustive assessment
- **Must** use inference-level questions (not just literal recall) per P1 testable prediction
- **Must** NOT gamify results (no scores, leaderboards, streaks). Just: "You got 2 of 3 — nice!"
- Results can feed into adaptive pacing (P16) by adjusting default WPM recommendation

---

## 6. Motion System

### 6.1 Motion Principles

Motion in RunThru serves three functions, in priority order:

1. **Temporal scaffolding**: Word transitions communicate pacing rhythm. The breathe animation (A-001) provides a subtle pulse that keeps the reader's visual system engaged without conscious processing. This is the highest-priority use of motion.
2. **Spatial communication**: The parallax effect and cube transitions communicate spatial relationships — you are looking into a room, words exist in space. This reinforces the ambient engagement channel (P15).
3. **Feedback**: Card press/release (A-002/003), dial animations (A-004/005), and status transitions (A-009) provide interaction feedback. Standard UX motion.

**Motion is never decorative.** Every animation has a functional purpose. If an animation cannot be explained in terms of scaffolding, spatial communication, or feedback, it should not exist.

### 6.2 Animation Specifications

The existing animation system (A-001 through A-013) is validated by the evidence:

| Anim | Name | Duration | Curve | Purpose | Evidence |
|---|---|---|---|---|---|
| A-001 | Word advance breathe | 80ms | easeOut | Temporal scaffold — marks word transition | P6 (Grade A): ambient-only, imperceptible |
| A-002 | Card press | 100ms | easeIn | Feedback — tactile press response | Aesthetic choice |
| A-003 | Card release | 150ms | Spring(m:1, s:800, d:22) | Feedback — elastic release | Aesthetic choice |
| A-004 | Dial emerge | 220ms | Spring(m:1, s:500, d:18), 8% overshoot | Feedback — dial appears | Aesthetic choice |
| A-005 | Dial dismiss | 180ms | easeIn | Feedback — dial disappears | Aesthetic choice |
| A-006 | Pause fog in | 200ms | easeIn | State change — reading→paused | P8 (Grade B): mode transition |
| A-007 | Resume clear fog | 150ms | easeOut | State change — paused→reading | P8 (Grade B) |
| A-008 | Processing pulse | 1200ms | easeInOut | Feedback — loading state | Rule 15: replaces CircularProgressIndicator |
| A-009 | Status to ready | 400ms | easeOut | Feedback — processing complete | Aesthetic choice |
| A-010 | Cube rotate transition | 300ms | easeInOut | Spatial — navigation transition | Aesthetic choice |
| A-011 | Cube breathe (idle) | 8000ms | sine wave ±1.5° | Ambient engagement — peripheral visual interest | P11 (Grade C): moderate visual novelty sustains attention |
| A-012 | Water ripple loading | 2400ms | easeOut, 3 rings, 800ms stagger | Feedback — loading state variant | Rule 15: replaces LinearProgressIndicator |
| A-013 | Word depth bounce-in | 160ms | SubtleBounceIn (4% overshoot, per-glyph 6ms stagger) | Temporal scaffold — word arrival depth cue | P11 (Grade C): subtle novelty |

### 6.3 Timing Curves

| Curve | Easing | Usage |
|---|---|---|
| `easeOut` | Decelerating | Word transitions, mode exits — things settling |
| `easeIn` | Accelerating | Mode entries, presses — things starting |
| `easeInOut` | S-curve | Navigation transitions, processing pulse |
| `Spring(mass, stiffness, damping)` | Physics-based | Card release, dial emerge — organic feel |
| `SubtleBounceIn` | Custom: quadratic ease to 1.04, settle to 1.0 | Word depth bounce — imperceptible at reading speed |
| `sine wave` | Continuous oscillation | Cube breathe — ambient, never-ending |

### 6.4 Ambient Motion Rules

| Rule | Specification | Evidence |
|---|---|---|
| Cycle duration minimum | ≥ 2000ms for any looping ambient animation | P6 (Grade A): no rapid visual events |
| Maximum concurrent ambient animations | 2 (cube breathe + parallax shift) | Performance budget + P6 |
| Foveal exclusion zone | No animated elements within 2° visual angle of the word center (~30px at arm's length) | P6 (Grade A) |
| Contrast ceiling for animated elements | Animated room elements must have ≤ 3:1 contrast ratio against adjacent room surfaces | P6 (Grade A): prevents attention capture |
| Parallax smoothing | Low-pass filter on head position input. Cutoff: 2Hz. No sudden jerks. | P6 (Grade A) |

### 6.5 Reduced Motion Behavior

**Must** (Rule 5): Every animation checks `isReducedMotion(context)`.

When reduced motion is enabled:

| Animation | Reduced-Motion Behavior |
|---|---|
| A-001 (word breathe) | Disabled — word appears instantly |
| A-011 (cube breathe) | Disabled — cube is static |
| A-013 (word depth bounce) | Disabled — word appears at final position |
| Parallax shift | Disabled — room renders at center |
| A-006/007 (fog) | Instant opacity change (no animation) |
| A-010 (cube rotate) | Instant position change |
| All others | Duration → `Duration.zero` (instant) |

The room still renders as a 3D scene (providing depth cue value) but nothing moves.

### 6.6 Performance Budget

- **Maximum concurrent animations**: 3 (word transition + cube breathe + parallax interpolation)
- **All animations on GPU thread** where possible: use `Transform` widgets and `CustomPainter` with `shouldRepaint` optimization
- **TextPainter pool**: Max 3 painters, never allocated in `paint()` (Rule 9)
- **Frame budget**: Target 16.67ms per frame (60 FPS). Word rendering is the critical path — room rendering can drop to 30 FPS on older devices without noticeable impact.

---

## 7. Accessibility System

### 7.1 WCAG Compliance

| Criterion | Level | Status | Implementation |
|---|---|---|---|
| 1.4.3 Contrast (Minimum) | AA | **Must** | Body text on stage: ≈10.5:1. Anchor on stage: ≈5.8:1. Shell text: ≈10.5:1. |
| 1.4.6 Contrast (Enhanced) | AAA | **Should** for body text | Body text exceeds 7:1 threshold |
| 1.4.11 Non-text Contrast | AA | **Must** | Interactive controls ≥ 3:1 against background |
| 2.3.1 Three Flashes | A | **Must** | Word transitions at 500 WPM = ~4.2 words/sec. Each transition is a single word swap, not a flash. At maximum speed, verify no seizure-triggering patterns. |
| 2.4.7 Focus Visible | AA | **Must** | Keyboard focus ring on all interactive elements |
| 1.3.1 Info and Relationships | A | **Must** | Screen reader announces word sequence, reading progress |

### 7.2 Cognitive Accessibility Matrix

| EF Domain | ADHD Deficit | System Support | Component | Principle |
|---|---|---|---|---|
| **Working Memory** | Cannot hold pace, position, and comprehension simultaneously | System handles pace (PacingEngine), externalizes position (SessionProgress) | PacingEngine, SessionProgress | P5 (Grade A), P9 (Grade B) |
| **Self-Regulation** | Cannot self-detect mind wandering, cannot self-pace | External pacing removes self-regulation burden entirely | PacingEngine, WordDisplay | P5 (Grade A) |
| **Attention** | 2–3× mind-wandering rate, centrality deficit | Peripheral engagement scaffold (ParallaxRoom), single-task mode eliminates distractions | ParallaxRoom, ReadingChrome | P6 (Grade A), P8 (Grade B), P11 (Grade C) |
| **Planning** | Cannot plan reading sessions, estimate completion | Session stats, progress externalization, reading consistency feedback | SessionProgress | P9 (Grade B), P12 (Grade C) |
| **Inhibition** | Latches onto peripheral details instead of central content | Single-word display forces linear processing, removes peripheral text | WordDisplay | P13 (Grade C) |

### 7.3 Sensory Customization Surface

**Should** (P10, Grade B): Users must control these sensory parameters:

| Parameter | Range | Default | Location | Evidence |
|---|---|---|---|---|
| WPM | 100–500 | 250 | Primary settings | P1, P10 |
| Font family | 22 options | Bricolage Grotesque | Primary settings | P10 |
| Font size | 0.5×–2.0× | 1.0× | Primary settings | P10 |
| Parallax intensity | Off / Subtle / Full | Subtle | Primary settings | P10, P15 |
| Reduced motion | On / Off | System default | Secondary settings | Rule 5 |
| Anchor color | 12 colors | Hot Coral (#c71f2d) | Secondary settings | P10 |
| Per-word timing | On / Off | On | Secondary settings | P2, P10 |
| Room intensity | Minimal / Auto / Rich | Auto | Secondary settings | P7, P10 |

### 7.4 Default-to-Safe

For every adaptive parameter, the safe (conservative) default is specified:

| Parameter | Conservative Default | Why Safe |
|---|---|---|
| WPM | 250 | Below 350 comprehension ceiling by 100 WPM margin |
| Parallax | Subtle (not Full) | Reduces motion sensitivity risk |
| Room intensity | Auto (adaptive) | Reduces visual load when text is difficult |
| Per-word timing | On | Provides the WM scaffolding ADHD users need |
| Font | Bricolage Grotesque | Legible sans-serif, good at all sizes |

---

## 8. Design Tension Resolutions

### DT-1: Engagement-Comprehension Boundary

---
**Severity**: Critical
**Competing Principles**:
- **Principle 6** (Grade A): Ambient-only visual environment — the word is sacred. Seductive details reduce comprehension 15–25%.
- **Principle 11** (Grade C): Moderate visual novelty sustains attention — both zero and high stimulation are suboptimal.

**Conflict**: The 3D room must be visually interesting enough to prevent mind wandering but simple enough to avoid competing with word processing.

**Resolution Pattern**: Context-Dependent Switching + User Override

**Implementation**:
- **Default state**: Moderate room intensity — subtle cube breathe (8s cycle), gentle parallax, grid lines visible. No elements near the word compete for attention.
- **Adaptation trigger**: Running text difficulty proxy (average character count of current sentence). High difficulty (≥9 chars average) → room intensity reduces to Minimal. Low difficulty (≤4 chars) → room may increase to Rich.
- **User override**: Settings → Room Intensity: Minimal / Auto / Rich. User preference always wins.
- **Fallback**: If no text difficulty signal is available, default to Moderate.

**Evaluation**:
- **Metric**: Session duration by room intensity setting (inverted-U expected)
- **Threshold**: Users with Subtle parallax should show ≥10% longer sessions than Off or Full
- **Method**: Analytics: median session duration segmented by parallax intensity setting
- **Secondary metric**: Post-session recall probe ("Did you notice room visual changes during reading?"). Target: <20% positive recall (room was peripheral, not focal).

---

### DT-2: Speed-Honesty Tradeoff

---
**Severity**: Critical
**Competing Principles**:
- **Principle 1** (Grade A): Comprehension collapses above 350 WPM
- **Principle 10** (Grade B): User sovereignty — users control speed

**Conflict**: The product implies speed as a value prop, but the evidence shows comprehension is the real value.

**Resolution Pattern**: Conservative Default + Informed Override

**Implementation**:
- **Default state**: 250 WPM. WPM dial shows green zone.
- **Adaptation trigger**: User adjusts WPM above 350: soft advisory appears, dial shifts to red.
- **User override**: No hard cap. Users can set up to 500 WPM after seeing the advisory.
- **Fallback**: Advisory is always available — not dismissible permanently.

**Evaluation**:
- **Metric**: Distribution of set WPM values across user base
- **Threshold**: ≥60% of users should be in the 200–350 WPM range (indicating defaults and advisory are effective)
- **Method**: Analytics: WPM distribution histogram
- **Secondary**: Comprehension check scores (when implemented) segmented by WPM setting

---

### DT-3: Structure-Agency Balance

---
**Severity**: Important
**Competing Principles**:
- **Principle 5** (Grade A): External pacing is the core intervention — system must control timing
- **Principle 10** (Grade B): User sovereignty — users must feel in control

**Conflict**: The system makes pacing decisions for the user, but the user must not feel controlled.

**Resolution Pattern**: Layered Control (macro user / micro system)

**Implementation**:
- **Default state**: System auto-advances words with per-word timing modulation. User has set WPM to 250.
- **User macro controls**: WPM slider, font, parallax intensity, per-word timing toggle
- **System micro decisions**: Per-word display duration (length/frequency/punctuation modifiers), adaptive room intensity
- **Escape valve**: Pause anytime (tap), rewind (swipe right), skip (swipe left). External pacing removes the burden, not the ability.
- **User override**: Per-word timing can be toggled off (flat interval) via settings. All macro parameters adjustable.

**Evaluation**:
- **Metric**: Per-word timing toggle usage
- **Threshold**: ≥80% of users should leave per-word timing on (indicating it feels natural and helpful)
- **Method**: Analytics: percentage of sessions with per-word timing enabled

---

### DT-4: ORP Extrapolation Gap

---
**Severity**: Important
**Competing Principles**:
- **Principle 14** (Grade D): ORP anchoring is theoretically the strongest feature — 30+ years of OVP research
- **Gap 1**: No study has tested ORP-anchored RSVP vs. center-aligned RSVP

**Conflict**: The strongest theoretical feature has no direct empirical validation in its application context.

**Resolution Pattern**: Designed Experiment

**Implementation**:
- **Default state**: ORP-anchored alignment. Anchor character bolded and highlighted.
- **A/B capability**: Build a feature flag for center-aligned mode. When enabled, words are centered horizontally and the anchor character is still highlighted but not at a fixed position.
- **Measurement**: Log alignment mode × reading completion rate × optional comprehension check scores
- **User override**: Not user-facing in v2.0. A/B testing is internal/research-facing.

**Evaluation**:
- **Metric**: Comprehension quiz scores by alignment condition, moderated by word frequency
- **Threshold**: ORP should show ≥5% improvement on inference questions, especially for words ≥7 characters
- **Method**: A/B test with embedded comprehension probes (v2.1+)

---

## 9. Implementation Notes

### 9.1 Flutter/Dart Specific Guidance

#### State Management (Riverpod)

| Provider | Type | Purpose |
|---|---|---|
| `configProvider` | `AsyncNotifierProvider<ConfigNotifier, AppConfig>` | Persistent user settings (WPM, font, folder, anchors) |
| `wordTimerProvider` | `StateNotifierProvider.autoDispose<WordTimerNotifier, WordTimerState>` | Per-session word timer with drift correction |
| `pdfListProvider` | `FutureProvider` | Scanned PDF library watching folder path |
| `preprocessingQueueProvider` | `StateNotifierProvider<PreprocessingQueue, ...>` | Parallel PDF extraction workers |

**Required change**: `AppConfig.defaultWpm` must change from `300` to `250` to comply with P1 (Grade A).

**Required change**: `WordTimerNotifier` must integrate per-word display duration from `RunThruTiming.wordDisplayMs()` instead of using flat `intervalMs`.

#### Rendering Architecture

- All 3D rendering via `CustomPainter` — no game engine dependency
- `TextPainterPool` (max 3) for word rendering — never allocate in `paint()`
- Off-axis projection via `RoomConfig.fromScreen()` + `project()` 
- Parallax input: `HeadPositionNotifier` normalizes pointer/IMU/camera sources

#### Build and Codegen

- Riverpod providers using `@riverpod` annotation require `dart run build_runner build` after changes
- Generated files (`*.g.dart`) must never be manually edited
- CI build numbers auto-managed by Codemagic — never set `+N` in `pubspec.yaml`

#### Performance Constraints

- PDF extraction **must** run in Isolates (30s timeout) — never on main event loop
- Section store I/O (JSON read/write to `pdf_store/<hash>/`) **must** run in Isolates
- PreprocessingQueue adapts worker count: 2 (web) / 6 (mobile) / 12 (desktop)
- Frame budget: 16.67ms at 60 FPS. Word rendering is critical path.

### 9.2 Design System Integration

All design system imports **must** go through `lib/design/design.dart` barrel export:

```dart
import 'package:runthru/design/design.dart';
```

New timing tokens should be added as a new file `lib/design/timing_tokens.dart` and re-exported through the barrel.

**Hard rules** (never violate):
1. No raw `Color(0xFF...)` outside `tokens.dart`
2. No hardcoded `TextStyle` in widgets — use `RunThruTypography`
3. No hardcoded `BoxDecoration` shadows — use `RunThruDecorations`
4. No hardcoded 3D material constants — use `RunThruMaterials`
5. No `CircularProgressIndicator`, `LinearProgressIndicator`, `RefreshIndicator` — use neumorphic pulse (A-008) or water ripple (A-012)
6. No `Navigator.push()` — use go_router
7. No `setState()` for global/shared state — use Riverpod

### 9.3 Timing Token Implementation Checklist

1. Create `lib/design/timing_tokens.dart` with `RunThruTiming` class
2. Export through `lib/design/design.dart`
3. Update `AppConfig.defaultWpm` from `300` to `250`
4. Update `WordTimerNotifier` to use `RunThruTiming.wordDisplayMs()` per word
5. Update `WordTimerNotifier._scheduleNext()` to use per-word interval instead of flat interval
6. Add soft advisory UI to WPM control when threshold exceeded
7. Add WPM zone gradient to dial (green / yellow / red)

---

## 10. Evaluation Hooks

For each testable prediction from the design principles, here is where the measurement should occur and what metric to capture:

| ID | Prediction | Metric | Where to Measure | Method | Threshold |
|---|---|---|---|---|---|
| E-1 | Users at 250 WPM ≥80% on inference questions | Comprehension score by WPM | ComprehensionCheck component (v2.1+) | In-app quiz after reading sessions | ≥80% at 250 WPM; ≥15% lower at 400 WPM |
| E-2 | Per-word timing improves comprehension on mixed-difficulty passages | Comprehension score by timing mode | ComprehensionCheck + per-word timing toggle in analytics | A/B: per-word timing on vs. off | 5–10% improvement on inference questions for difficult sections |
| E-3 | Subtle parallax gives longest session duration (inverted-U) | Median session duration by parallax setting | Analytics: session start/end timestamps × parallax intensity setting | Segmented analytics | Subtle > Off AND Subtle > Full (inverted-U shape) |
| E-4 | Users cannot recall room events during reading (room was peripheral) | Post-session recall probe responses | Post-session survey (optional, periodic) | "Did you notice visual changes in the room while reading?" | <20% positive recall |
| E-5 | Single-task mode reduces mind wandering | Self-reported mind-wandering frequency | Post-session questionnaire | Toolbar visible vs. hidden comparison (within-subjects) | Lower mind-wandering with toolbar hidden |
| E-6 | Reading consistency feedback improves retention | 14-day retention by feature exposure | Analytics: return visits × session summary exposure | Cohort analysis | Session summary viewers ≥10% higher 14-day retention |
| E-7 | ORP alignment improves recognition for long/rare words | Recognition accuracy by alignment × word length × frequency | A/B test with embedded recognition probes | Lexical decision task at word boundaries | 15–30ms faster recognition for ORP, especially ≥7 chars |
| E-8 | Users who customize ≥1 parameter show higher 7-day retention | Return rate by customization behavior | Analytics: settings change events × return visits | Cohort analysis | Customizers ≥10% higher 7-day retention |
| E-9 | ≥60% of users remain in 200–350 WPM range | WPM distribution | Analytics: WPM setting at session start | Distribution histogram | ≥60% in green/yellow zone |
| E-10 | ≥80% of users leave per-word timing enabled | Per-word timing toggle state | Analytics: toggle state at session start | Percentage calculation | ≥80% enabled |

---

## Appendix A: Evidence Chain Index

| Spec Decision | Token/Component | Principle | Evidence Grade | Key Sources |
|---|---|---|---|---|
| Default WPM = 250 | `timing-word-default-wpm` | P1 | A | Acklin 2017, Di Nocera 2018, Benedetto 2015 |
| WPM range 100–500 | `timing-word-min-wpm`, `timing-word-max-wpm` | P1, P10 | A, B | Acklin 2017, Primativo 2016 |
| Soft advisory at 350 WPM | `timing-wpm-warning-threshold`, WPMControl | P1 | A | Di Nocera 2018 |
| 120ms display floor | `timing-word-floor-ms` | P3 | B | Vitu 2001, Potter 2018, Schotter 2012 |
| Per-word length modifiers (×1.3 at 8 chars, ×1.5 at 12 chars) | `timing-word-length-modifier-*` | P2 | B | Primativo 2016, Sweller 2010, Busler 2017 |
| Per-word frequency modifier (×1.2 for rare words) | `timing-word-frequency-modifier-rare` | P2 | B | Primativo 2016, Brysbaert 2005 |
| Punctuation pauses (+100ms comma, +150ms period, +250ms paragraph) | `timing-word-punctuation-*-ms` | P2 | B | P2 informed estimate from prosodic literature |
| ORP anchor alignment | WordDisplay, `lib/core/orp.dart` | P14 | D | O'Regan 1992, Brysbaert 2005, Vitu 1990, Schotter 2012 |
| Anchor character bold + color highlight | `type-weight-bold`, `color-stage-anchor` | P14 | D | OVP research extrapolation |
| External pacing (auto-advance) | PacingEngine, WordTimerNotifier | P5 | A | Barkley 1997, Kofler 2019, Parks 2022 |
| Single-word display (not phrases) | WordDisplay | P13 | C | Miller 2013, Lee 2024, Lanier 2021 |
| Single-task reading mode (no chrome) | ReadingChrome | P8 | B | Spiel 2022, Skulmowski 2022, Miller 2013 |
| Ambient-only room (no foveal competition) | ParallaxRoom, depth-parallax-max-displacement ≤5% | P6 | A | Park 2015, Mayer 2001, Cutting 2024 |
| Adaptive room intensity by text difficulty | ParallaxRoom states | P7 | B | Park 2011, Andreessen 2021, Sweller 2010 |
| Cube breathe 8000ms cycle | A-011 | P11 | C | Amini 2018, Guan 2025 |
| Parallax as peripheral engagement | ParallaxRoom | P15 | D | Amini 2018, Guan 2025 (extrapolated) |
| User-controllable WPM, font, parallax | SettingsPanel | P10 | B | Motti 2019, Spiel 2022, Primativo 2016 |
| Progress externalization (hairline + pause stats) | SessionProgress | P9 | B | Barkley 1997, Spiel 2022, Xu 2025 |
| Non-punitive engagement feedback | SessionProgress session end | P12 | C | Dai 2025, Baxter 2025, Spiel 2022 |
| Reduced motion support | All animations | Rule 5 | B | Platform accessibility best practice |
| Shell font = Bricolage Grotesque | `type-family-shell` | Rule 8 | N/A | Project design rule |
| Two surface worlds (stage/shell never mixed) | All surface token usage | Rule 7 | N/A | Project design rule |
| Neumorphic raised/inset shadows | `RunThruDecorations` | N/A | Aesthetic | Warm, approachable, non-clinical aesthetic |
| Warm marble 3D interior | `color-cube-*`, `color-marble-*` | N/A | Aesthetic | "Quiet, well-designed room" design philosophy |
| WPM dial zone gradient (green/yellow/red) | `color-wpm-*` | P1 | A | Visual mapping of evidence-based thresholds |
| 12 anchor color options | Anchor color palette | P10 | B | User sovereignty over sensory parameters |

---

## Appendix B: Glossary

| Term | Definition |
|---|---|
| **RSVP** | Rapid Serial Visual Presentation — words shown one at a time at a fixed focal point |
| **ORP** | Optimal Recognition Point — the calculated best fixation position within a word (slightly left of center), derived from OVP research |
| **OVP** | Optimal Viewing Position — the psycholinguistic finding that word recognition peaks when the eye fixates slightly left of word center |
| **WPM** | Words Per Minute — the user's target reading speed |
| **WM** | Working Memory — the cognitive system for temporarily holding and manipulating information. Key deficit in ADHD. |
| **EF** | Executive Function — higher-order cognitive processes including WM, self-regulation, planning, and inhibition |
| **CLT** | Cognitive Load Theory — framework distinguishing intrinsic (task-inherent), extraneous (interface-imposed), and germane (learning-productive) cognitive load |
| **Seductive Details Effect** | Finding that visually interesting but task-irrelevant content reduces comprehension by consuming WM |
| **Centrality Deficit** | ADHD-specific tendency to attend to peripheral details at the expense of central/important information |
| **Neumorphic** | Design style using soft extruded/inset shadows on same-colored surfaces to create subtle depth |
| **Parallax** | Motion effect where foreground and background elements move at different rates, creating depth illusion |
| **Magic Window** | The effect of the 3D room — as if looking through the phone screen into a real room that responds to head movement |
| **Off-Axis Projection** | Perspective projection where the viewpoint is not centered, used to create the parallax effect based on head position |
| **TextPainter Pool** | Reusable pool of 3 Flutter TextPainter objects to avoid allocation during paint() calls |
| **SubtleBounceIn** | Custom animation curve with 4% overshoot — designed to be "felt, not seen" at reading speed |
| **Drift Correction** | Algorithm in WordTimerNotifier that adjusts scheduling to compensate for timer inaccuracy and frame drops |
| **Isolate** | Dart's concurrency primitive — a separate memory-isolated thread for CPU-intensive work off the main event loop |
| **Riverpod** | State management library for Flutter. All global/shared state in RunThru uses Riverpod providers. |
| **go_router** | Declarative routing library for Flutter. All navigation in RunThru uses go_router. |
| **Build Runner** | Dart code generation tool. Required after modifying `@riverpod`-annotated providers. Outputs `.g.dart` files. |
| **Grade A/B/C/D** | Evidence confidence grades: A = hard constraint (meta-analysis/3+ replications), B = strong default (1–2 well-designed studies), C = hypothesis (single study/emerging), D = extrapolated (no direct evidence, inferred from theory) |

---

*Specification generated from 16 evidence-graded design principles sourced from 37 peer-reviewed publications.*
*Next steps: Implement timing tokens (`lib/design/timing_tokens.dart`), update default WPM to 250, integrate per-word timing into WordTimerNotifier.*
