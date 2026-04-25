# Speedy Boy v3.0 — Execution Plan

**Created**: 2026-04-01
**Tasks**: 52 across 5 sprints, organized into 26 work sessions
**Tools**: VS Code + GitHub Copilot (Chat + Edits mode)
**Codebase**: Clean, matches backlog scan

---

## Tool Strategy

### When to Use Which Mode

| Mode | Use For | Why |
|------|---------|-----|
| **Copilot Chat** | Single-file creation, pure logic, tests, questions | Tight context → precise output. Good for "create this one file" tasks. |
| **Copilot Edits** | Multi-file changes, integration tasks, wiring up providers | Can see + edit multiple files simultaneously. Essential when a change touches 2+ files. |
| **Manual** | Verification walkthroughs, `dart analyze`, visual checks | Some tasks are human-only. |

### How to Reference Skills in Copilot

**In Chat**: Use `#file:.claude/[skill-name].md` to pull a skill into context. Example:
```
#file:.claude/flutter-animating-apps.md
#file:lib/design/timing_tokens.dart

Create the selectWordTransition function per the v3 spec...
```

**In Edits**: Add skill files to the working set alongside the source files you're editing. The skill file gives Copilot the patterns; the source files give it the implementation target.

### Context Window Golden Rule

**Maximum per prompt**: 2–3 skill files + the target source files + the relevant copilot rules. Copilot Chat has ~8K tokens of usable context. Overloading it degrades output quality. Every session below specifies exactly what to include.

---

## Skill → Task Cluster Map

```
┌─────────────────────────────────┐
│ FOUNDATION LAYER                │
│ flutter-managing-state          │──→ All notifiers, all providers
│ riverpod-providers              │──→ Provider creation patterns
│ riverpod-consumers              │──→ Widget consumption (ref.watch)
│ riverpod-auto-dispose           │──→ ContextReveal notifier lifecycle
│ riverpod-testing                │──→ All test files with provider overrides
│ flutter-working-with-databases  │──→ ConfigNotifier SharedPreferences
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ ANIMATION LAYER                 │
│ flutter-animating-apps          │──→ A-013 timing, tier transitions,
│                                 │    sweep engine, dim overlay,
│                                 │    reduced motion checks
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ UI LAYER                        │
│ flutter-building-layouts        │──→ Overlay widget, preset cards,
│                                 │    settings sections
│ flutter-building-forms          │──→ Segmented controls, selectors
│ flutter-theming-apps            │──→ Token consumption, surface worlds
│ flutter-improving-accessibility │──→ Semantics, keyboard, screen reader
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ TESTING LAYER                   │
│ flutter-testing-apps            │──→ Widget tests, integration tests
│ riverpod-testing                │──→ Provider override patterns in tests
└─────────────────────────────────┘
```

---

## Sprint 1: Prerequisites & Critical Fixes

**Goal**: Create the timing token file and extend AppConfig with all v3 fields. These are zero-risk, zero-UI tasks that unblock everything else.

**Estimated time**: ~1.5 hours

---

### Session 1.1: Timing Tokens (TASK-001)

**Mode**: Copilot Chat
**Effort**: XS (~15 min)
**Skills**: None needed — this is pure constant definition
**Rules in play**: 10 (barrel export), 18 (evidence traceability), 23 (timing tokens)

**Open these files**:
- `lib/design/design.dart` (barrel file — you'll add an export)
- `lib/design/animations.dart` (reference for existing pattern)

**Prompt template** (paste into Copilot Chat):
```
#file:lib/design/design.dart
#file:lib/design/animations.dart

Create a new file `lib/design/timing_tokens.dart` containing an abstract final class
SpeedyBoyTiming with all v3 timing tokens. Follow the exact pattern used in animations.dart
for the class structure.

Every constant MUST have a traceability comment in the format: // P[N] Grade [X] — [rationale]

Tokens to include (exact names and values):
- autoRewindWords = 3 (P18 Grade C)
- contextRevealSweepMs = 400 (P17 Grade C)
- contextRevealDimOpacity = 0.6 (P17 Grade C)
- contextRevealMicroWords = 3 (P17 Grade C)
- contextRevealClauseWords = 5 (P17 Grade C)
- contextRevealEnter = Duration(milliseconds: 200) (P17 Grade C)
- contextRevealTierAdvance = Duration(milliseconds: 250) (P17 Grade C)
- contextRevealExit = Duration(milliseconds: 150) (P17 Grade C)
- roomHysteresisHoldSeconds = 30 (P7 Grade C)
- roomDifficultyWindowSize = 5 (P7 Grade C)
- roomDifficultyThresholdHigh = 9.0 (P7 Grade D — tunable)
- roomDifficultyThresholdLow = 4.0 (P7 Grade D — tunable)
- a013FallbackWpmThreshold = 300 (P6 Grade A)
- a013MaxDisplayFraction = 0.6 (P6 Grade A)
- a013MinBaseDuration = 40 (P6 Grade A)

Grade D tokens must have the comment: // Grade D — tunable

Then update lib/design/design.dart to export timing_tokens.dart.
```

**Verify before moving on**:
- [ ] File exists at `lib/design/timing_tokens.dart`
- [ ] All 15 token names match exactly
- [ ] All Grade D tokens have `// Grade D — tunable`
- [ ] `lib/design/design.dart` has `export 'timing_tokens.dart';`
- [ ] `dart analyze lib/design/timing_tokens.dart` → no issues

---

### Session 1.2: AppConfig v3 Fields (TASK-002 + TASK-003 + TASK-004)

**Mode**: Copilot Edits (3 files modified simultaneously)
**Effort**: S (~1 hour total for all 3 tasks)
**Skills**: `riverpod-providers`, `flutter-working-with-databases`
**Rules in play**: 13 (Riverpod), 18 (evidence traceability)

**Add to Edits working set**:
- `lib/store/models.dart`
- `lib/store/config.dart`
- `test/store/config_test.dart`

**Reference skills** (add to working set):
- `.claude/riverpod-providers.md`
- `.claude/flutter-working-with-databases.md`

**Prompt template** (paste into Copilot Edits):
```
I need 3 changes across these files for the Speedy Boy v3 upgrade:

1. In lib/store/models.dart — ADD these enums:
   - ParallaxIntensity { none, off, subtle, full }
   - ReadingGoalPreset { deepRead, comfortable, quickScan }
   - OrpCondition { orpBoldColor, orpColorOnly, centerAligned }

2. In lib/store/config.dart — ADD to AppConfig:
   - Field: parallaxIntensity (default: ParallaxIntensity.subtle)
   - Field: readingGoalPreset (default: null, nullable)
   - Field: orpCondition (default: OrpCondition.orpBoldColor)
   - Field: hasSeenContextRevealOnboarding (default: false)
   Update constructor, fromJson, toJson, and copyWith.
   fromJson MUST handle missing keys gracefully (backward compatible with existing stored configs).

   ADD to ConfigNotifier — 4 setter methods following the existing _synchronized pattern:
   - setParallaxIntensity(ParallaxIntensity intensity)
   - setReadingGoalPreset(ReadingGoalPreset? preset)
   - setOrpCondition(OrpCondition condition)
   - setHasSeenContextRevealOnboarding(bool seen)

3. In test/store/config_test.dart — ADD unit tests:
   - 'v3 fields default safely when JSON keys missing'
   - 'parallaxIntensity serializes and deserializes'
   - 'orpCondition serializes and deserializes'
   - 'readingGoalPreset null by default'
   - 'hasSeenContextRevealOnboarding defaults to false'
```

**Verify before moving on**:
- [ ] All 3 enums exist in models.dart with correct value order
- [ ] AppConfig constructor compiles with new fields
- [ ] `AppConfig.fromJson({})` produces valid defaults (no crash on empty JSON)
- [ ] JSON round-trip test passes
- [ ] All 4 setter methods follow `_synchronized` pattern
- [ ] `flutter test test/store/config_test.dart` → all pass
- [ ] `dart analyze lib/store/` → no issues

---

## Sprint 2: Priorities 1–5 (Critical Fixes & Ergonomics)

**Goal**: Fix the ship-blocking A-013 timing bug, add auto-rewind, WPM advisory, contrast safety, and the WCAG utility. This sprint makes the existing app production-ready.

**Estimated time**: ~5 hours

---

### Session 2.1: A-013 Adaptive Timing Logic + Tests (TASK-005 + TASK-006)

**Mode**: Copilot Chat (new file creation, pure logic)
**Effort**: S (~45 min)
**Skills**: `flutter-animating-apps`
**Rules in play**: 5 (reduced motion), 23 (timing tokens), 18 (evidence traceability)

**Open these files**:
- `lib/design/timing_tokens.dart` (token reference)
- `lib/design/animations.dart` (existing animation constants)

**Prompt template**:
```
#file:.claude/flutter-animating-apps.md
#file:lib/design/timing_tokens.dart
#file:lib/design/animations.dart

Create lib/core/word_transition.dart with:
- WordTransition enum: { a001Breathe, a013BounceIn }
- A function selectWordTransition({required int wpm, required int charCount, required int displayMs})
  that returns a record ({WordTransition transition, int baseDurationMs})

Logic:
- Above 300 WPM (SpeedyBoyTiming.a013FallbackWpmThreshold): return a001Breathe
  with baseDurationMs from SpeedyBoyAnimations.wordAdvanceDuration
- At or below 300 WPM: return a013BounceIn with duration capped at 60%
  (SpeedyBoyTiming.a013MaxDisplayFraction) of displayMs, accounting for glyph
  stagger (SpeedyBoyAnimations.glyphStaggerMs * (charCount - 1)),
  clamped to minimum 40ms (SpeedyBoyTiming.a013MinBaseDuration)

Add // P6 Grade A traceability comments on every branch.

Then create test/core/word_transition_test.dart with these tests:
- 'A-001 at 350 WPM for any word length'
- 'A-001 at 500 WPM for any word length'
- 'A-013 capped at 250 WPM for "the" (3 chars)'
- 'A-013 capped at 250 WPM for "reading" (7 chars)'
- 'A-013 base never below 40ms'
- 'A-013 uncapped when animation fits within display budget'
- '301 WPM triggers A-001 fallback'
- '300 WPM stays on A-013'
Use boundary values 300 and 301 explicitly.
```

**Verify**:
- [ ] >300 WPM → returns a001Breathe
- [ ] 200–300 WPM → returns a013BounceIn with capped base
- [ ] Base duration never below 40ms
- [ ] All 8 tests pass
- [ ] No hardcoded values — all from `SpeedyBoyTiming`

---

### Session 2.2: A-013 Integration into ParallaxRoom (TASK-007)

**Mode**: Copilot Edits (modifying existing complex file)
**Effort**: M (~45 min)
**Skills**: `flutter-animating-apps`, `riverpod-consumers`
**Rules in play**: 4 (no hardcoded 3D constants), 5 (reduced motion), 13 (Riverpod)

**Add to Edits working set**:
- `lib/three_d/parallax_room.dart`
- `lib/core/word_transition.dart` (just created)
- `lib/design/timing_tokens.dart`

**Reference skills**:
- `.claude/flutter-animating-apps.md`
- `.claude/riverpod-consumers.md`

**Prompt template**:
```
In parallax_room.dart, integrate the selectWordTransition function from
lib/core/word_transition.dart into the word-change handler.

When a new word is displayed:
1. Call selectWordTransition(wpm: currentWpm, charCount: word.length, displayMs: intervalMs)
2. If result is a001Breathe: fire only _wordController.forward(from: 0), skip _depthBounceController
3. If result is a013BounceIn: update _depthBounceController.duration to capped base + stagger,
   then forward(from: 0)

Read WPM from the Riverpod wordTimerProvider (use ref.watch or pass as widget parameter).

CRITICAL: The isReducedMotion(context) check MUST still apply — both animations skip under reduced motion.
Do NOT hardcode any timing values. All values from SpeedyBoyTiming and SpeedyBoyAnimations.
```

**Verify**:
- [ ] At >300 WPM, depth bounce controller does NOT fire
- [ ] At 200–300 WPM, depth bounce duration is dynamically capped
- [ ] Reduced motion check still present and functional
- [ ] No visual stutter at 350+ WPM (run app manually to verify)

---

### Session 2.3: Auto-Rewind on Resume (TASK-008 + TASK-009)

**Mode**: Copilot Edits (modifying word_timer.dart + adding tests)
**Effort**: S (~45 min)
**Skills**: `riverpod-providers`, `flutter-managing-state`
**Rules in play**: 18 (evidence traceability), 23 (timing tokens)

**Add to Edits working set**:
- `lib/core/word_timer.dart`
- `lib/design/timing_tokens.dart`
- `test/core/word_timer_test.dart`

**Prompt template**:
```
#file:.claude/riverpod-providers.md
#file:lib/design/timing_tokens.dart

In lib/core/word_timer.dart (WordTimerNotifier):
1. Add private flags: _wasPaused = false, _hasPlayedOnce = false
2. In play(): if _wasPaused && _hasPlayedOnce, rewind by SpeedyBoyTiming.autoRewindWords
   words (clamp to 0). Reset _wasPaused after rewinding. Set _hasPlayedOnce on first play.
3. In pause(): set _wasPaused = true
4. In loadDocument(): reset both flags to false
5. Add // P18 Grade C traceability comment

Auto-rewind is SILENT — no visual indicator, no extra state emissions for the rewind.

In test/core/word_timer_test.dart, add:
- 'auto-rewind subtracts 3 words on resume from pause'
- 'auto-rewind clamps to word 0 at document start'
- 'auto-rewind does not apply on first play'
- 'auto-rewind applies on every subsequent resume'
- 'auto-rewind resets on loadDocument'
- 'auto-rewind is silent — no extra state emissions for rewind'
```

**Verify**:
- [ ] Pause → resume rewinds 3 words
- [ ] Clamps to word 0 when near document start
- [ ] First play does NOT rewind
- [ ] `loadDocument()` resets both flags
- [ ] All 6 tests pass

---

### Session 2.4: WPM Advisory Text (TASK-010)

**Mode**: Copilot Chat (small settings screen addition)
**Effort**: XS (~15 min)
**Skills**: `flutter-building-layouts`, `flutter-theming-apps`
**Rules in play**: 1 (no raw colors), 2 (no hardcoded TextStyle), 7 (shell surface tokens)

**Open these files**:
- `lib/screens/settings_screen.dart`
- `lib/design/typography.dart` (reference)

**Prompt template**:
```
#file:lib/screens/settings_screen.dart
#file:lib/design/typography.dart

In the WPM slider section of settings_screen.dart, add conditional advisory text
that appears when WPM > 350:

Text('Best for scanning familiar text', style: SpeedyBoyTypography.caption())

Place it below the WPM value display. Style with shell surface tokens only.
Add Semantics so screen readers announce it.
The text must disappear when WPM returns to ≤350.

// P1 Grade A — shortened WPM advisory text
```

**Verify**:
- [ ] Advisory appears ONLY at >350 WPM
- [ ] Text is exactly "Best for scanning familiar text"
- [ ] Uses `SpeedyBoyTypography.caption()` (not hardcoded TextStyle)
- [ ] Uses shell surface tokens
- [ ] Disappears at ≤350

---

### Session 2.5: WCAG Contrast Utility (TASK-011 + TASK-012)

**Mode**: Copilot Chat (new utility file, pure math)
**Effort**: S (~35 min)
**Skills**: None needed — pure Dart math
**Rules in play**: 18 (evidence traceability)

**Open these files**:
- `test/design/contrast_audit_test.dart` (existing test code to extract from)

**Prompt template**:
```
#file:test/design/contrast_audit_test.dart

Extract the contrast ratio logic from the test file into a production utility.

Create lib/core/wcag_contrast.dart:
- abstract final class WcagContrast
- static double contrastRatio(Color fg, Color bg) — returns value ≥ 1.0
- static double relativeLuminance(Color color) — per WCAG 2.1
- Use dart:math pow() instead of the Taylor approximation in the test file

// P14 Grade C — anchor contrast safety net

Then create test/core/wcag_contrast_test.dart:
- 'white on black is 21:1'
- 'identical colors return 1:1'
- 'stageText on stageBase exceeds 7:1'
- 'stageAnchor on stageBase exceeds 3:1'
- 'known mid-contrast pair returns expected ratio'
```

**Verify**:
- [ ] White/black → 21.0
- [ ] Same color → 1.0
- [ ] Uses `dart:math` pow()
- [ ] All 5 tests pass

---

### Session 2.6: Anchor Contrast Warning + Auto-Shadow (TASK-013 + TASK-014 + TASK-015 + TASK-016)

**Mode**: Copilot Edits (settings screen + both painters + new test file)
**Effort**: M (~2 hours total)
**Skills**: `flutter-building-layouts`, `flutter-theming-apps`, `flutter-improving-accessibility`
**Rules in play**: 1 (no raw colors), 2 (no hardcoded TextStyle), 3 (no hardcoded shadows), 7 (surface worlds)

**This session has 4 tasks — do them in order within one Edits session.**

**Add to Edits working set**:
- `lib/screens/settings_screen.dart`
- `lib/core/wcag_contrast.dart` (just created)
- `lib/three_d/word_painter.dart`
- `lib/three_d/parallax_word_painter.dart`
- `lib/design/tokens.dart` (reference for anchor colors)

**Reference skills**:
- `.claude/flutter-building-layouts.md`
- `.claude/flutter-improving-accessibility.md`

**Sub-task A (TASK-013)**: Below anchor color palette in settings, add a live preview widget showing a sample word ("reading") on stageBase background with ORP character using selected anchor color. Preview updates on color change.

**Sub-task B (TASK-014)**: After color swatch selection, compute `WcagContrast.contrastRatio(anchorColor, stageBase)` and show:
- ≥4.5:1 → No warning
- 3:1–4.49:1 → Yellow caution: "This color may be hard to see at speed" (use `shellProcessing` token)
- <3:1 → Red danger: "This color is very hard to see — consider a darker option" (use `shellError` token)
Add Semantics for screen reader announcement.

**Sub-task C (TASK-015)**: In both WordPainter and ParallaxWordPainter, when anchor has <4.5:1 contrast against stageBase, apply 0.5px text shadow using `stageText` at 30% opacity behind anchor characters.

**Sub-task D (TASK-016)**: Create `test/design/anchor_contrast_test.dart` with 5 tests using actual anchor colors from `SpeedyBoyTokens.anchorColors`.

**Verify**:
- [ ] Live preview renders and updates on color change
- [ ] Warning tiers fire at correct thresholds
- [ ] Shadow appears on low-contrast anchors (e.g., Buttercup)
- [ ] Shadow absent on high-contrast anchors (e.g., Hot Coral)
- [ ] Shadow present in BOTH 2D and 3D painters
- [ ] All 5 tests pass

---

## Sprint 3: Priorities 4, 6, 7, 8 (Validation & Components)

**Goal**: Build room intensity adaptation, parallax settings, reading goal presets, and ORP A/B conditions. These are the user-facing feature additions.

**Estimated time**: ~7 hours

---

### Session 3.1: Room Intensity Controller (TASK-017 + TASK-018 + TASK-019)

**Mode**: Copilot Chat (new standalone class + tests)
**Effort**: S (~1 hour total)
**Skills**: `flutter-testing-apps`
**Rules in play**: 21 (Grade D = simple constant), 23 (timing tokens), 18 (evidence)

**Open these files**:
- `lib/design/timing_tokens.dart`

**Prompt template**:
```
#file:lib/design/timing_tokens.dart
#file:.claude/flutter-testing-apps.md

Create lib/core/room_intensity_controller.dart:
- RoomIntensityLevel enum: { minimal, moderate, rich }
- RoomIntensityController class with:
  - Injectable clock: DateTime Function()? clock parameter in constructor (for testability)
  - Rolling window of last 5 sentence difficulty scores
  - smoothedDifficulty getter (running average, default 0.5 when empty)
  - onSentenceComplete(double sentenceDifficulty) — adds to window, rolls if >5, evaluates
  - Hysteresis: blocks intensity transition within 30 seconds of last change
  - Thresholds: ≥9.0 avg → minimal, ≤4.0 avg → rich, else moderate
  - reset() clears all state
  - Use SpeedyBoyTiming constants for all thresholds and window size
  - // P7 Grade C/D traceability comments, Grade D tokens marked // Grade D — tunable

Create test/core/room_intensity_controller_test.dart:
- 'window fills with first 5 sentences'
- 'window rolls — oldest removed after 5th entry'
- 'smoothedDifficulty returns running average'
- 'empty window returns 0.5 default'
- 'high difficulty (≥9.0 avg chars) triggers minimal intensity'
- 'low difficulty (≤4.0 avg chars) triggers rich intensity'
- 'moderate difficulty stays moderate'
- 'hysteresis blocks intensity transition within 30 seconds'
- 'hysteresis allows transition after 30 seconds'
- 'single-sentence spike ignored by rolling average'
- 'reset clears all state'
Use the injectable clock for deterministic hysteresis tests. Test boundary values 4.0, 4.1, 8.9, 9.0.
```

**Verify**:
- [ ] Rolling window stores exactly 5 entries max
- [ ] Hysteresis uses injectable clock (not DateTime.now)
- [ ] All 11 tests pass
- [ ] Grade D thresholds annotated correctly

---

### Session 3.2: Parallax Intensity Settings UI (TASK-020 + TASK-023)

**Mode**: Copilot Edits
**Effort**: M (~1 hour)
**Skills**: `flutter-building-forms`, `flutter-theming-apps`, `flutter-improving-accessibility`
**Rules in play**: 1, 2, 3, 7 (shell surface tokens), 13 (Riverpod)

**Add to Edits working set**:
- `lib/screens/settings_screen.dart`
- `lib/store/config.dart` (for setParallaxIntensity)
- `lib/store/models.dart` (for ParallaxIntensity enum)

**Reference skills**:
- `.claude/flutter-building-forms.md`
- `.claude/flutter-improving-accessibility.md`

**Prompt**: Add a 4-segment neumorphic control (None / Off / Subtle / Full) in Primary Settings. Wire to `ConfigNotifier.setParallaxIntensity()`. Default: Subtle. Use `SpeedyBoyDecorations` for styling. Add Semantics labels per segment. Keyboard: arrow keys navigate, Enter selects. Then create `test/screens/parallax_intensity_test.dart` with 3 widget tests.

**Verify**:
- [ ] 4 segments in order: None, Off, Subtle, Full
- [ ] Default selection: Subtle
- [ ] Tapping persists via ConfigNotifier
- [ ] All 3 tests pass

---

### Session 3.3: Parallax Rendering Branches (TASK-021 + TASK-022)

**Mode**: Copilot Edits
**Effort**: M (~1.75 hours)
**Skills**: `flutter-animating-apps`, `riverpod-consumers`
**Rules in play**: 1, 3, 4, 5 (reduced motion), 7, 13

**Add to Edits working set**:
- `lib/screens/parallax_reading_screen.dart`
- `lib/three_d/parallax_room.dart`
- `lib/store/models.dart` (ParallaxIntensity reference)

**Prompt**: Read `parallaxIntensity` from `configProvider`. Implement 4 rendering branches:
- **None**: Flat stageBase background, 2D WordPainter, neumorphic inset frame, simple dimming on pause (no fog), no 3D room geometry
- **Off**: 3D room renders statically (headX=0, headY=0), no parallax motion, no breathe animation
- **Subtle**: Current behavior, parallax clamped to ≤2.5% displacement, breathe enabled
- **Full**: Current behavior, parallax up to ≤5% displacement, breathe enabled

Switching in settings updates the viewport immediately. Progress hairline always visible.

**Verify**:
- [ ] "None" → flat background, 2D painter, no room geometry
- [ ] "Off" → static room, no motion
- [ ] "Subtle" → gentle parallax
- [ ] "Full" → full parallax
- [ ] Settings change is reflected immediately

---

### Session 3.4: Reading Goal Presets Model + UI (TASK-024 + TASK-025)

**Mode**: Copilot Chat → then Edits for UI widget
**Effort**: M (~1.25 hours)
**Skills**: `flutter-building-layouts`, `flutter-theming-apps`, `flutter-improving-accessibility`
**Rules in play**: 1, 2, 3, 7 (shell surface tokens for cards)

**Step 1 (Chat)**: Create `lib/core/reading_goal_presets.dart` with ReadingGoalConfig model class and the 3 const presets:
- Deep Read: 200 WPM, Subtle parallax, "Take your time with difficult material."
- Comfortable: 250 WPM, Subtle parallax, "Your everyday reading pace."
- Quick Scan: 350 WPM, Off parallax, "Get the gist of material you already know."

**Step 2 (Edits)**: Create `lib/widgets/reading_goal_presets.dart` — 3 tappable cards using `SpeedyBoyDecorations.raisedDecoration(SpeedyBoySurface.shell)`. Each shows name, description, WPM. On tap, apply via ConfigNotifier + call onSelected callback. Present as reading intentions (Deep Read) NOT speed tiers (Slow). Semantics: full label per card. Keyboard: arrow keys between cards, Enter to select.

**Verify**:
- [ ] 3 cards: Deep Read, Comfortable, Quick Scan
- [ ] Correct WPM and parallax values
- [ ] Shell surface tokens (not stage)
- [ ] `SpeedyBoyDecorations` for styling
- [ ] Screen reader announces full label

---

### Session 3.5: Reading Goal Onboarding + Settings (TASK-026 + TASK-027 + TASK-028)

**Mode**: Copilot Edits
**Effort**: M (~2.25 hours)
**Skills**: `flutter-building-layouts`, `flutter-building-forms`, `riverpod-consumers`
**Rules in play**: 5 (reduced motion for card transitions), 7, 13

**Add to Edits working set**:
- `lib/screens/parallax_reading_screen.dart` (onboarding trigger point)
- `lib/screens/settings_screen.dart` (reading goal selector)
- `lib/widgets/reading_goal_presets.dart` (just created)
- `lib/store/config.dart`

**Prompt**: Two integration points:
1. **Onboarding (TASK-026)**: After first PDF load, before first reading session, show ReadingGoalPresets. "Customize later in Settings" link below. Tapping a card applies settings and begins reading. Skip → default to Comfortable. Show only once (persist via config). Reduced motion: instant card transitions. Never block reading.
2. **Settings (TASK-027)**: "Reading Goal" selector at top of Primary Settings. 3 presets + "Custom" indicator. Selecting a preset updates WPM + parallax intensity. Modifying any individual setting → show "Custom". Persist in AppConfig.

Then `test/widgets/reading_goal_presets_test.dart` (TASK-028) with 5 widget tests.

**Verify**:
- [ ] Onboarding shown once, then never again
- [ ] Skip defaults to Comfortable
- [ ] Settings shows 3 presets + Custom
- [ ] Manual WPM change → "Custom" indicator
- [ ] All 5 tests pass

---

### Session 3.6: ORP A/B Conditions (TASK-029 + TASK-030)

**Mode**: Copilot Edits
**Effort**: M (~1 hour)
**Skills**: `flutter-theming-apps`
**Rules in play**: 1, 2, 9 (TextPainter pool), 21 (Grade D simple)

**Add to Edits working set**:
- `lib/three_d/word_painter.dart`
- `lib/three_d/parallax_word_painter.dart`
- `lib/store/models.dart` (OrpCondition reference)

**Prompt**: Read `orpCondition` from AppConfig. Modify anchor rendering in BOTH painters:
- `orpBoldColor` (default): Bold + anchor color (existing, no change)
- `orpColorOnly`: Anchor color applied but regular weight (readingWord style + color override)
- `centerAligned`: Horizontally centered word, anchor color still on ORP position

Not user-facing in settings — controlled by A/B infrastructure. Pass OrpCondition as parameter to both painters. Add `test/core/orp_test.dart` with 3 tests.

**Verify**:
- [ ] Default behavior unchanged
- [ ] orpColorOnly → regular weight + color
- [ ] centerAligned → centered word
- [ ] Works in both 2D and 3D painters
- [ ] All 3 tests pass

---

## Sprint 4: Priority 9 — ContextReveal

**Goal**: Build the full ContextReveal comprehension recovery system. This is the largest feature — 16 tasks across 8 sessions. Work bottom-up: state → engine → rendering → gestures → integration.

**Estimated time**: ~10 hours

**⚠️ Architectural note**: ContextReveal is a state machine. Build the state model and notifier FIRST, test them in isolation, then layer rendering and gestures on top. Do NOT start with UI.

---

### Session 4.1: ContextReveal State + Notifier (TASK-031 + TASK-032)

**Mode**: Copilot Chat (new files, pure logic)
**Effort**: S (~55 min)
**Skills**: `riverpod-providers`, `riverpod-auto-dispose`, `flutter-managing-state`
**Rules in play**: 13 (Riverpod), 18 (evidence), 20 (CR state machine rules)

**Prompt**: Create `lib/core/context_reveal_state.dart` with ContextRevealTier enum (none, micro, clause, sentence) and ContextRevealState immutable class. State tracks: tier, sweepPosition, isSweepPaused, windowOffset, triggerWordIndex. Computed property `resumeWordIndex` returns leftmost visible word index. Include copyWith.

Then create `lib/core/context_reveal_notifier.dart` — a Riverpod StateNotifier<ContextRevealState> with auto-dispose. Methods: enter(int), advanceTier(), dismiss() → int, shiftWindowBack(), shiftWindowForward(), toggleSweepPause(), advanceSweep(). RSVP MUST pause the instant tier != none. advanceTier is no-op at sentence. dismiss returns resume word index. Navigation resets sweep.

**Verify**:
- [ ] Tier enum: none → micro → clause → sentence
- [ ] resumeWordIndex computed from leftmost visible word
- [ ] advanceTier no-op at sentence
- [ ] dismiss returns correct resume index
- [ ] Provider is auto-dispose

---

### Session 4.2: Gradient Sweep Engine (TASK-039)

**Mode**: Copilot Chat
**Effort**: S (~30 min)
**Skills**: `flutter-animating-apps`, `flutter-handling-concurrency`
**Rules in play**: 23 (timing tokens)

**Prompt**: Create `lib/core/gradient_sweep_engine.dart`. Fixed rate: 400ms per word (SpeedyBoyTiming.contextRevealSweepMs). Auto-advances through displayed words. Tap pauses/resumes. Holds on last word indefinitely (no loop, no auto-dismiss). Navigation resets sweep to new leftmost word. Use Timer or AnimationController.

**Verify**:
- [ ] 400ms per word advance rate
- [ ] Pause/resume toggleable
- [ ] Holds on last word
- [ ] Reset on navigation

---

### Session 4.3: Micro Tier Rendering (TASK-035)

**Mode**: Copilot Chat → Edits for wiring
**Effort**: M (~1.5 hours)
**Skills**: `flutter-building-layouts`, `flutter-theming-apps`, `flutter-animating-apps`
**Rules in play**: 1, 2, 5 (reduced motion), 7 (stage tokens for reading content)

**Prompt**: Create `lib/widgets/context_reveal_overlay.dart`. For Micro tier: display current word ± 1 (3 words total) in a single line. Current word's ORP anchor pinned to viewport horizontal center. Adjacent words positioned by measured glyph widths. Use `SpeedyBoyTypography.readingWord()` and `readingAnchor()`. Dim overlay at 60% of `stagePauseOverlay` opacity (SpeedyBoyTiming.contextRevealDimOpacity). Room visible behind overlay.

**Verify**:
- [ ] 3 words visible
- [ ] ORP anchor at viewport center
- [ ] Dim overlay at correct opacity
- [ ] Room visible behind

---

### Session 4.4: Clause + Sentence Tiers (TASK-036 + TASK-037)

**Mode**: Copilot Edits (extending overlay widget)
**Effort**: M (~1.75 hours)
**Skills**: `flutter-building-layouts`
**Rules in play**: 1, 2, 7

**Prompt**: Extend `context_reveal_overlay.dart`:
- **Clause**: current ± 2 (5 words). Centered block layout (not ORP-pinned). Soft-wrap when exceeding viewport width. Each word's ORP highlighted during sweep.
- **Sentence**: Full current sentence. Wrapped text block, centered vertically. Gradient sweep treats each word individually. Requires SentenceResolver for boundaries. Graceful wrapping for long sentences.

**Verify**:
- [ ] Clause shows 5 words, centered
- [ ] Sentence shows full sentence, wrapped
- [ ] Sweep highlights work in both tiers

---

### Session 4.5: Tier Transitions + Dim Overlay (TASK-038 + TASK-042)

**Mode**: Copilot Edits
**Effort**: M (~1.25 hours)
**Skills**: `flutter-animating-apps`
**Rules in play**: 5 (reduced motion — CRITICAL here), 23 (timing tokens)

**Prompt**: In `context_reveal_overlay.dart`:
- Enter (RSVP → Micro): 200ms easeOut, ±1 words fade in + slide ±20px
- Tier advance: 250ms easeInOut, new words fade at edges
- Exit: 150ms easeOut, then immediate RSVP resume
- Dim overlay: 200ms enter / 150ms exit
- Use SpeedyBoyTiming duration constants
- **CRITICAL**: Check `isReducedMotion(context)`. When true, ALL transitions instant. BUT 400ms/word sweep timing is PRESERVED (it's functional, not decorative).

**Verify**:
- [ ] Enter/advance/exit use correct durations
- [ ] Reduced motion → all transitions instant
- [ ] Reduced motion → sweep timing 400ms/word PRESERVED
- [ ] Uses SpeedyBoyTiming constants

---

### Session 4.6: Gesture Integration + Navigation (TASK-033 + TASK-041)

**Mode**: Copilot Edits
**Effort**: M (~1.5 hours)
**Skills**: `riverpod-consumers`, `flutter-animating-apps`
**Rules in play**: 13 (Riverpod), 20 (CR state machine)

**Add to Edits working set**:
- `lib/screens/parallax_reading_screen.dart`
- `lib/core/context_reveal_notifier.dart`
- `lib/widgets/context_reveal_overlay.dart`

**Prompt**: Wire gestures:
- Swipe up during reading → enter CR (pause RSVP immediately)
- Swipe up in CR → advanceTier
- Swipe down in CR → dismiss, resume RSVP from returned index
- Swipe left/right in CR → shift window, reset sweep to new leftmost
- Tap in CR → toggle sweep pause
- Existing gestures (tap pause/resume, sentence nav) ONLY active when NOT in CR
- Boundary: don't shift past word 0 or end of document

**Verify**:
- [ ] Swipe up enters CR
- [ ] Swipe up in tier advances
- [ ] Swipe down dismisses + resumes from leftmost visible word
- [ ] Left/right shifts window
- [ ] Existing gestures still work outside CR
- [ ] No gesture conflicts

---

### Session 4.7: Pacing + Onboarding + Accessibility (TASK-034 + TASK-043 + TASK-044)

**Mode**: Copilot Edits
**Effort**: M (~1.5 hours)
**Skills**: `riverpod-providers`, `flutter-improving-accessibility`
**Rules in play**: 5, 13, 18, 20

**Prompt**: Three changes:
1. **TASK-034**: In word_timer.dart, add `resumeFromContextReveal(int wordIndex)` that seekTo + play WITHOUT auto-rewind (_wasPaused = false before play). Swipe-down dismiss calls this instead of play().
2. **TASK-043**: On first swipe-up, check `hasSeenContextRevealOnboarding`. If false, show overlay: "Swipe up to see surrounding words. Swipe again for more context. Swipe down to resume." Auto-dismiss 3s or tap. Set flag true. Then proceed to Micro tier.
3. **TASK-044**: Accessibility: Screen reader announces context phrase on entry. "Swipe down to resume reading" on entry. Re-announce on tier advance. Keyboard: Up=enter/advance, Down=dismiss, Left/Right=shift, Space=pause/resume sweep.

**Verify**:
- [ ] CR exit does NOT auto-rewind
- [ ] Regular pause-resume STILL auto-rewinds
- [ ] Onboarding shown once, then never
- [ ] All keyboard shortcuts functional
- [ ] Screen reader announces on entry and tier change

---

### Session 4.8: Sweep Rendering + Tests (TASK-040 + TASK-045 + TASK-046)

**Mode**: Copilot Edits
**Effort**: M (~2 hours)
**Skills**: `flutter-theming-apps`, `flutter-testing-apps`, `riverpod-testing`
**Rules in play**: 1, 2, 7

**Prompt**: Wire gradient sweep styling in context_reveal_overlay.dart:
| Position | ORP char | Body text |
|----------|----------|-----------|
| Focus | Full stageAnchor, bold | stageText, regular |
| ±1 from focus | stageAnchor 40% opacity, regular | stageText 70% |
| Others | stageText 50% | stageText 50% |

Connect to sweep engine current position.

Then create tests:
- `test/core/context_reveal_test.dart` — 12 unit tests for sweep engine + state transitions
- `test/widgets/context_reveal_overlay_test.dart` — 6 widget tests for tier rendering

Use injectable timer for sweep timing tests. Use Riverpod overrides for widget tests.

**Verify**:
- [ ] Focus word has full anchor color + bold
- [ ] ±1 words dimmed appropriately
- [ ] All 12 unit tests pass
- [ ] All 6 widget tests pass

---

## Sprint 5: Integration Testing & Polish

**Goal**: End-to-end verification, token audit, reduced motion walkthrough, clean analyze.

**Estimated time**: ~4 hours

---

### Session 5.1: ContextReveal Integration Tests (TASK-047 + TASK-048)

**Mode**: Copilot Chat
**Effort**: L + S (~2.5 hours)
**Skills**: `flutter-testing-apps`, `riverpod-testing`

Create `integration_test/context_reveal_test.dart` — full flow: start reading → swipe up → verify onboarding → wait 3s → verify Micro (3 words) → swipe up → verify Clause (5 words) → swipe up → verify Sentence → swipe right twice → verify window shift → swipe down → verify resume from leftmost visible word.

Then in `test/core/word_timer_test.dart` add 2 tests: auto-rewind does NOT apply after CR exit, auto-rewind DOES apply on regular pause-resume after CR session.

---

### Session 5.2: Gesture Flow Integration (TASK-049)

**Mode**: Copilot Chat
**Effort**: M (~1.5 hours)
**Skills**: `flutter-testing-apps`

Create `integration_test/gesture_flow_test.dart` — test all 7 gestures: tap (pause/resume + auto-rewind), swipe left/right (sentence nav), swipe up (CR entry), swipe up in CR (tier advance), swipe left/right in CR (window shift), swipe down (CR dismiss + resume). Verify correct context (reading vs CR) determines behavior.

---

### Session 5.3: Token Audit + Reduced Motion (TASK-050 + TASK-051)

**Mode**: Manual
**Effort**: M (~1.25 hours)

**TASK-050**: Cross-reference every token name in the v3 spec against the codebase. Verify all timing tokens in SpeedyBoyTiming, all color tokens for ContextReveal, all typography styles for new components.

**TASK-051**: Manual walkthrough with reduced motion enabled:
1. A-001 word advance → instant
2. A-013 depth bounce → skipped
3. CR tier transitions → instant
4. Gradient sweep 400ms/word → PRESERVED
5. Pause fog transitions → instant
6. Card press/release → instant
7. No decorative motion anywhere

---

### Session 5.4: Clean Sweep (TASK-052)

**Mode**: Terminal + Manual
**Effort**: S (depends on findings)

```bash
dart analyze lib/
flutter test
```

Both must produce zero issues. Fix anything surfaced.

---

## Quick Reference: Session Index

| # | Session | Tasks | Mode | Time | Skills |
|---|---------|-------|------|------|--------|
| 1.1 | Timing tokens | 001 | Chat | 15m | — |
| 1.2 | AppConfig fields | 002-004 | Edits | 1h | riverpod-providers, flutter-working-with-databases |
| 2.1 | A-013 logic | 005-006 | Chat | 45m | flutter-animating-apps |
| 2.2 | A-013 integration | 007 | Edits | 45m | flutter-animating-apps, riverpod-consumers |
| 2.3 | Auto-rewind | 008-009 | Edits | 45m | riverpod-providers, flutter-managing-state |
| 2.4 | WPM advisory | 010 | Chat | 15m | flutter-building-layouts, flutter-theming-apps |
| 2.5 | WCAG contrast | 011-012 | Chat | 35m | — |
| 2.6 | Contrast UI + shadow | 013-016 | Edits | 2h | flutter-building-layouts, flutter-improving-accessibility |
| 3.1 | Room intensity | 017-019 | Chat | 1h | flutter-testing-apps |
| 3.2 | Parallax settings UI | 020, 023 | Edits | 1h | flutter-building-forms, flutter-improving-accessibility |
| 3.3 | Parallax rendering | 021-022 | Edits | 1.75h | flutter-animating-apps, riverpod-consumers |
| 3.4 | Reading goal model+UI | 024-025 | Chat→Edits | 1.25h | flutter-building-layouts, flutter-improving-accessibility |
| 3.5 | Reading goal integration | 026-028 | Edits | 2.25h | flutter-building-layouts, flutter-building-forms |
| 3.6 | ORP conditions | 029-030 | Edits | 1h | flutter-theming-apps |
| 4.1 | CR state + notifier | 031-032 | Chat | 55m | riverpod-providers, riverpod-auto-dispose |
| 4.2 | Sweep engine | 039 | Chat | 30m | flutter-animating-apps, flutter-handling-concurrency |
| 4.3 | Micro tier | 035 | Chat→Edits | 1.5h | flutter-building-layouts, flutter-theming-apps |
| 4.4 | Clause + sentence | 036-037 | Edits | 1.75h | flutter-building-layouts |
| 4.5 | Transitions + overlay | 038, 042 | Edits | 1.25h | flutter-animating-apps |
| 4.6 | Gestures + nav | 033, 041 | Edits | 1.5h | riverpod-consumers |
| 4.7 | Pacing + onboarding + a11y | 034, 043-044 | Edits | 1.5h | riverpod-providers, flutter-improving-accessibility |
| 4.8 | Sweep rendering + tests | 040, 045-046 | Edits | 2h | flutter-testing-apps, riverpod-testing |
| 5.1 | CR integration tests | 047-048 | Chat | 2.5h | flutter-testing-apps, riverpod-testing |
| 5.2 | Gesture flow test | 049 | Chat | 1.5h | flutter-testing-apps |
| 5.3 | Token audit + motion | 050-051 | Manual | 1.25h | — |
| 5.4 | Clean sweep | 052 | Terminal | varies | — |

**Total estimated**: ~28 hours across 26 sessions

---

## Critical Path (Ship-Blocking)

```
Session 1.1 (TASK-001) → Session 2.1 (TASK-005/006) → Session 2.2 (TASK-007)
     ↓                                                        ↓
  Timing tokens                                    A-013 fix integrated
                                                   into ParallaxRoom
                                                        ↓
                                                  SHIP GATE CLEARED
```

Everything else is important but non-blocking. If you need to ship fast, Sessions 1.1 → 2.1 → 2.2 is the minimum viable path (~1.75 hours).
