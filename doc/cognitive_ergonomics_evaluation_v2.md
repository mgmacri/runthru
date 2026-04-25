# Cognitive Ergonomics Evaluation — Speedy Boy v2.0

**Evaluator**: Cognitive Ergonomics Evaluator (automated)
**Spec evaluated**: `speedy_boy_design_spec_v2.md` v1.0.0
**Date**: 2026-04-01
**Target user**: ADHD adults (18–45), WM ~2–3 chunks, 2–3× mind-wandering rate, distraction-heavy environments
**Primary device**: iPhone 12 Pro (390×844 @ 3x), portrait, touch input

---

## Scratchpad

**Framework application strategy**: The spec is a timing-critical RSVP product. The highest-risk surface is the temporal stack-up — where animation durations, display durations, and perceptual thresholds interact. Per-component evaluations will catch visual/cognitive issues, but the stack-up is where the hardest bugs hide.

**Expected critical issues**:
1. **A-013 (parallax word bounce-in) timing at high WPM**. At 160ms base + 6ms/glyph stagger, this animation has variable total duration that may exceed short-word display times at ≥350 WPM — and cuts deeply into stable viewing time even at 250 WPM default.
2. **Adaptive room intensity oscillation**. No hysteresis specified. If text alternates between simple and complex sentences, room intensity could oscillate rapidly despite the 3–5s fade.
3. **Low-contrast anchor color selection without enforcement**. Users can choose anchor colors that fail AA contrast. Combined with speed reading, the ORP anchor becomes invisible.

**Expected green zones**: Single-task reading mode, per-word adaptive timing, progress externalization, non-punitive engagement, parallax capping at 5%, cube breathe at 8000ms cycle, punctuation pauses. These are well-designed and evidence-grounded.

**Frameworks of highest relevance**:
- **Temporal Binding**: Calibrating animation durations against perceptual moment boundaries at each WPM tier
- **Cognitive Load Theory**: Extraneous load budget is halved for ADHD — every foveal element during reading must justify its existence
- **Attentional Blink**: At high WPM, inter-word intervals enter the blink window; transition salience determines whether the blink is triggered
- **Yerkes-Dodson**: The 3D room walks the tightrope between understimulation (mind wandering) and overstimulation (seductive details)
- **Hick's Law**: Settings panel decision complexity for ADHD users

---

## Component Evaluations

### WordDisplay (Non-Parallax Variant — A-001)

**Friction Level**: Green

**Framework Mapping**:
- **Visual Span Theory**: The word occupies the foveal zone exclusively. No competing elements within 2° visual angle. The ORP anchor fixes the eye at a consistent horizontal position, eliminating saccade planning load.
- **Cognitive Load Theory**: Extraneous load is near zero — the word is the only foveal content. The ORP split (pre-anchor / anchor / post-anchor) adds a small amount of visual segmentation, but this serves the germane goal of fixation guidance.
- **Temporal Binding**: A-001 (80ms, 1.5% scale pulse, easeOut) falls in the "snappy" perceptual category (50–100ms). At 1.5% scale, the motion is sub-pixel on most font sizes (e.g., 1.5% of 60px = 0.9px). The word is fully legible during the entire animation. This is temporal scaffolding — marking the word transition rhythmically — without consuming perceptual processing time.

**Cognitive Impact**: None adverse. The 1.5% scale breathe is below the threshold for motion-induced reading disruption. The word's full display duration is available for lexical access at all WPM tiers.

**Why this is load-bearing**: A-001's 80ms duration and sub-perceptual scale change are deliberately calibrated to work at all speeds without consuming the timing budget. Do not increase the duration, scale magnitude, or add opacity/position changes — any of these would create a timing conflict at high WPM.

---

### WordDisplay (Parallax Variant — A-013)

**Friction Level**: Red

**Friction Points**:
- A-013 (depth bounce-in: 160ms base + 6ms × (N−1) glyph stagger, 4% overshoot) creates variable-duration animations that **exceed the word display time at ≥350 WPM** for all common words, meaning the word never reaches its stable resting state before being replaced.
- Even at the 250 WPM default, common 5–7 character words have very tight headroom: for "reading" (7 chars), A-013 = 160 + 36 = 196ms; display = 240ms; stable viewing = 44ms. This is below the ~100ms threshold for comfortable lexical consolidation (Temporal Binding framework), though the word IS visible during the animation.

**Framework Mapping**:
- **Temporal Binding**: At 350 WPM, "the" (3 chars) gets 171ms display time. A-013 for 3 chars = 160 + 12 = 172ms. Animation duration (172ms) exceeds display time (171ms) by 1ms. The word **never reaches its final stable state**. At 500 WPM, the gap widens: 120ms display vs. 172ms animation = 52ms overrun.
- **Attentional Blink**: The 4% overshoot bounce-in is a higher-salience onset event than A-001's sub-pixel pulse. At high WPM where inter-word intervals are 120–171ms (inside the 200–500ms blink window), a salient transition could trigger the attentional blink on the following word. The per-glyph stagger amplifies this — it creates a visible left-to-right wave that is more salient than a uniform bounce.

**Cognitive Impact**: At ≥350 WPM, the parallax word display breaks temporal coherence. The word is still animating when the next word arrives, creating a jarring "word replaced mid-bounce" effect. For ADHD users with reduced temporal processing capacity, this is a perceptual coherence failure: the rhythm of word arrivals (which serves as temporal scaffolding) becomes unpredictable because some words bounce fully and others are interrupted.

At 250 WPM default, the issue is less severe but present: 5–7 character common words (the most frequent word length in English text) get only 44–68ms of post-animation stable viewing. The word is readable during the bounce-in (it's visible, just moving), so this is not a blocking failure at 250 WPM — but it degrades the "felt" quality of the rhythm.

**Timing details by speed tier and word length:**

| WPM | Word | Chars | Display (ms) | A-013 (ms) | Headroom (ms) | Status |
|---|---|---|---|---|---|---|
| 250 | "the" | 3 | 240 | 172 | +68 | Tight |
| 250 | "reading" | 7 | 240 | 196 | +44 | Very tight |
| 250 | "beautiful" | 9 | 312 | 208 | +104 | OK |
| 250 | "confabulation" | 13 | 432 | 232 | +200 | OK |
| 350 | "the" | 3 | 171 | 172 | **−1** | **FAIL** |
| 350 | "reading" | 7 | 171 | 196 | **−25** | **FAIL** |
| 350 | "confabulation" | 13 | 309 | 232 | +77 | OK |
| 500 | "the" | 3 | 120 | 172 | **−52** | **FAIL** |
| 500 | "reading" | 7 | 120 | 196 | **−76** | **FAIL** |
| 500 | "confabulation" | 13 | 216 | 232 | **−16** | **FAIL** |

**Optimization**:
- **Above 300 WPM**: Fall back from A-013 to A-001 (80ms, 1.5% scale pulse, no stagger, no depth bounce). This eliminates the timing overrun entirely. The temporal scaffold is preserved (A-001 still marks word transitions); only the depth novelty is lost, which is acceptable because at high WPM the reading task is demanding enough that peripheral novelty provides no benefit (Yerkes-Dodson: at high cognitive load, reduce stimulation).
- **At 200–300 WPM**: Cap A-013 total duration to `displayMs × 0.6` (animation never exceeds 60% of display time), computed as: `base = min(160, displayMs × 0.6 - 6 × (charCount - 1))`, clamped to a minimum of 40ms for perceptibility. This preserves the depth bounce-in at comfortable speeds while guaranteeing ≥40% of display time is stable.
- **Why this works**: Temporal Binding requires the perceptual system to distinguish word N from word N+1. When the animation for word N is still running at word N+1's onset, the two words blend into a single perceptual "moment," breaking the scaffolding function. By capping animation to 60% of display time, we guarantee ≥40% stable viewing — enough for word-form recognition even at reduced WM capacity. Above 300 WPM, eliminating depth motion entirely avoids the attentional blink risk from high-salience transitions at short intervals.

---

### ParallaxRoom

**Friction Level**: Green

**Framework Mapping**:
- **Yerkes-Dodson**: The room targets the sweet spot on the arousal curve for ADHD users. The marble aesthetic, warm palette, and slow animations provide enough peripheral stimulation to prevent mind wandering without overwhelming. The 8000ms cube breathe (A-011) and ≤5% parallax displacement are well below the attention-capture threshold for peripheral motion (~2Hz/500ms cycle would be concerning; 0.125Hz/8000ms is not).
- **Cognitive Load Theory**: Room elements are exclusively in peripheral and parafoveal vision. The foveal exclusion zone (no animated elements within 2° of word center) is explicitly enforced. Extraneous load contribution: near zero.
- **Visual Span Theory**: The ambient motion rules (≥2000ms cycle, ≤3:1 contrast for animated elements, 2Hz low-pass filter on parallax input) are precisely calibrated to avoid reflexive saccade triggering.
- **Change Blindness**: The parallax responds to user-initiated head movement, which means the user has motor-efference prediction of the room shift. This eliminates surprised-based attention capture — the brain predicted the motion because it initiated it.

**Cognitive Impact**: The room serves its stated purpose as a peripheral attention scaffold. The design correctly exploits the ADHD arousal paradox: enough ambient stimulation to prevent understimulation-driven mind wandering, directed through a channel (peripheral vision) that doesn't compete with the primary task (foveal word processing).

**Why this is load-bearing**: The parallax displacement cap (5%), the cube breathe cycle (8000ms), and the foveal exclusion zone are the three parameters that keep the room on the right side of the Yerkes-Dodson curve. Changing any of them toward higher stimulation would cross into seductive details territory (P7). Preserve these exact values.

---

### ReadingChrome

**Friction Level**: Green

**Friction Points**: None.

**Framework Mapping**:
- **Cognitive Load Theory**: During active reading, the chrome consists of exactly one visible element after 3 seconds — the progress hairline (1–2px, 30–50% opacity, viewport bottom edge). This is the minimum viable externalized EF. The WPM badge auto-hides after 3s, reducing visible element count from 2 to 1.
- **Visual Span Theory**: The progress hairline is at the viewport bottom edge — firmly in peripheral vision (>5° from word center at normal phone viewing distance). At 1–2px height and 30–50% opacity, its contrast against the stage surface is below the attention-capture threshold.
- **Change Blindness**: The WPM badge fades OUT over 300ms. Fade-out (reducing contrast) is change-blindness compatible — the visual system is poor at detecting disappearances, especially in peripheral vision. This is correctly engineered to avoid attention capture during the fade.

**Cognitive Impact**: Effectively zero extraneous load during reading. The hairline provides continuous progress feedback without demanding conscious attention — ADHD users can glance at it during natural micro-pauses in processing without being pulled toward it involuntarily.

**Why this is load-bearing**: The specification maximum of 2 elements during reading (word + hairline) after the 3-second WPM badge auto-hide is a hard constraint. Do not add any persistent visible element to reading mode — not a clock, not a percentage, not a chapter indicator. Each additional element costs WM capacity that ADHD users do not have to spare.

---

### WPMControl (WPM Dial)

**Friction Level**: Yellow

**Friction Points**:
- The soft advisory text at >350 WPM is a two-sentence paragraph: *"Above 350 WPM, deep comprehension may decrease. This speed works well for scanning familiar material."* During WPM adjustment — a kinesthetic rotational/drag interaction — the user must interrupt the motor task to read text. This creates **dual-task interference** (motor + language processing) at the exact moment the user is already making a decision (CLT + Hick's).

**Framework Mapping**:
- **Dual-Task Interference**: The dial adjustment is a motor task engaging visuospatial processing. The advisory text is a language processing task engaging the phonological loop. These use different WM subsystems (Baddeley's model), so interference is moderate, not severe. However, for ADHD users with impaired task-switching, even moderate dual-task demands can cause one task to be dropped (the user stops adjusting to read, or ignores the text to keep adjusting).
- **Hick's Law**: The dial itself is a continuous control (not discrete choices), so Hick's doesn't directly apply. Good design choice — a slider/dial reduces decision complexity vs. a dropdown with preset WPM values.

**Cognitive Impact**: The advisory text may go unread because it competes with the motor task. Users who are adjusting the dial are attending to the kinesthetic feedback (position, haptics) and the visual feedback (number, color gradient). A text paragraph is the wrong modality for conveying information during a motor interaction.

**Optimization**:
- **Shorten the advisory to ≤5 words**: "Best for scanning familiar text" or just "Scanning speed." The red color change already communicates danger/risk — the text should add information, not repeat the warning. Five words can be processed in a peripheral glance during the motor task.
- **Why this works**: Reducing text length from ~20 words to ~5 reduces phonological loop demand from ~4 chunks to ~1 chunk. A 1-chunk language task can be processed in parallel with a motor task without significant dual-task interference, even for ADHD users (Baddeley, 2003).
- **Alternative**: Use a non-text signal (haptic warning buzz + red color) at 350 WPM, and show the full advisory text only when the user **releases** the dial above 350. This separates the motor and language tasks temporally.

---

### SettingsPanel

**Friction Level**: Yellow

**Friction Points**:
- The font picker presents 22 options. For ADHD users, where decision paralysis onset is ~4–5 equiprobable options (Hick's Law + executive function deficit), 22 fonts in a picker is above the comfort zone. However, the severity is mitigated by three factors: (a) there is a strong default (Bricolage Grotesque), (b) font selection is a browsing/aesthetics task (not a performance-critical decision), and (c) the options are qualitatively distinct (different typefaces), not quantitatively confusing (different numbers).
- The progressive disclosure strategy (Primary vs. Advanced settings) is sound but the primary section still contains 4 controls: WPM slider, font size slider, font family picker, and parallax intensity. For an ADHD user opening settings for the first time, 4 controls with 2 sliders + 1 multi-option picker + 1 segmented control is at the upper edge of comfortable. Not over the line, but at the line.

**Framework Mapping**:
- **Hick's Law**: 22 font options → decision time ∝ log₂(23) ≈ 4.5 bits. With a strong default, the effective n is reduced — the user only actively considers fonts that look different from the default. In practice, users might compare 3–5 fonts, not all 22. The picker UI style matters: a scrollable list with live preview is less overwhelming than a 22-item grid.
- **Cognitive Load Theory**: The progressive disclosure (Primary + hidden Advanced) correctly segments the decision space. Primary = 4 decisions. Advanced = 5 more. This respects the ~4-chunk WM limit for ADHD users per interaction context.

**Cognitive Impact**: Minor — the font picker may cause a brief "too many options" reaction on first encounter, but the strong default + browsable format prevents paralysis. Most users will never change the font (E-8 metric expectation: those who customize ≥1 parameter show higher retention, implying most don't customize).

**Optimization**:
- **Group fonts into 3–4 categories** (e.g., Sans-Serif, Serif, Monospace, Display) with a tabbed or segmented filter above the picker. This reduces the visible option count at any moment to 5–8 fonts per category, well below the paralysis threshold. The initial view shows the "Recommended" category with 3–4 curated options.
- **Why this works**: Categorical pre-filtering reduces the effective n from 22 to 3–8 at any decision point (Hick's Law: log₂(9) ≈ 3.2 bits vs. log₂(23) ≈ 4.5 bits). More importantly, the categories provide decision scaffolding — the user first decides "what kind of font?" (3–4 options) then "which specific font?" (5–8 options). Two sequential simple decisions are easier than one complex decision for executive-function-impaired users.

---

### SessionProgress

**Friction Level**: Green

**Framework Mapping**:
- **Cognitive Load Theory (Germane load)**: Progress externalization offloads "where am I?" from WM to the environment. For ADHD users who cannot hold position + pace + comprehension simultaneously, this is a direct WM slot freed up.
- **Yerkes-Dodson**: The non-punitive session summary framing ("You've read 4 of the last 7 days" vs. "Don't break your streak!") avoids shame-triggered arousal spikes that cause ADHD users to disengage entirely. This is a critical design decision for the target population.

**Cognitive Impact**: Positive — reduces WM load during reading (hairline externalizes position) and avoids negative arousal at session end (non-punitive framing).

**Why this is load-bearing**: The non-punitive framing is essential. Any gamification (streaks, scores, badges) risks triggering the shame-avoidance cycle that causes ADHD users to abandon apps. The session summary must remain factual/positive. Never add loss-framed messaging ("You missed 3 days this week").

---

### ContentLoader / LibraryView

**Friction Level**: Green

**Framework Mapping**:
- **Cognitive Load Theory**: The library uses a standard card grid — a familiar, low-extraneous-load pattern. The information hierarchy (filename → progress → status → last read) is correctly ordered by importance.
- **Hick's Law**: The library is a browsing interface, not a forced-choice interface. Users scan for a specific PDF or browse casually. No decision paralysis risk because the action (tap to read) is uniform across all cards.

**Cognitive Impact**: Standard. The library is shell UI, not the reading intervention surface. It needs to be functional and not overwhelming — it achieves both.

---

### Adaptive Room Intensity (ParallaxRoom State Switching)

**Friction Level**: Yellow

**Friction Points**:
- **No oscillation damping specified.** The room intensity adapts based on average character count of the current sentence. If the text alternates between simple sentences ("I saw it.") and complex sentences ("The confabulated recollection persisted."), the intensity would oscillate between Rich and Minimal every 1–2 sentences. Even with a 3–5 second fade, frequent oscillation creates a pattern of visual change that could become noticeable and distracting over time.

**Framework Mapping**:
- **Change Blindness (failure case)**: Individual transitions are below JND (just noticeable difference) per frame — at 60fps over 3 seconds, each frame changes by ~0.5%, below the ~1–2% detection threshold. However, the *cumulative pattern* of oscillation IS detectable. If the room brightens and dims every 15–30 seconds, the user may develop a peripheral awareness of "the room is doing something," which could trigger conscious attention allocation — the opposite of the spec's intent.
- **Yerkes-Dodson**: The oscillation adds unpredictable variability to the peripheral stimulation channel. Unpredictable stimulation is more arousing than predictable stimulation (orienting response). This could push ADHD users above the optimal arousal point during already-difficult text passages.

**Cognitive Impact**: Moderate. In text with highly variable sentence complexity (common in academic/technical writing — the likely target for a speed reading tool), the room could oscillate several times per minute. Each oscillation is individually imperceptible, but the pattern over several minutes creates a "breathing" peripheral effect that the user may notice.

**Optimization**:
- **Add hysteresis with a minimum hold time.** Once the room transitions to a new intensity level, hold it for at least 30 seconds (approximately 125 words at 250 WPM, or ~8–10 sentences) before allowing another transition. Implementation: when the room intensity changes, set a `_lastIntensityChangeTimestamp` and only evaluate the difficulty trigger if `now - _lastIntensityChangeTimestamp > 30s`.
- **Use a rolling window instead of per-sentence difficulty.** Instead of computing difficulty on the current sentence alone, use a rolling window of the last 5 sentences. This smooths out sentence-to-sentence variability and only triggers transitions for sustained difficulty changes.
- **Why this works**: Hysteresis eliminates rapid oscillation by enforcing temporal separation between transitions. The rolling window eliminates the stimulus-response pattern where one complex sentence triggers a full room transition. Together, they ensure the room intensity adapts to sustained text difficulty shifts (novel section vs. dialog section) rather than sentence-level noise. This keeps the peripheral stimulation channel predictable (sub-threshold for orienting response).

---

### Anchor Color Palette (Low-Contrast Options)

**Friction Level**: Yellow

**Friction Points**:
- Anchor colors at indices 1–5 (Blazing Orange, Marigold, Buttercup, Limelight, Green Glow) have minimum contrast as low as 3:1 on the warm stage background (#ede3d2). The spec acknowledges this with a Grade C "consider" recommendation to add an accessibility warning. But **no enforcement mechanism is specified**.
- An ADHD user who selects Buttercup (#FFE135-like) as their anchor color will have an ORP character that is barely distinguishable from the surrounding text, especially at speed. The ORP benefit depends on the anchor being visually distinct (P14, Grade D). A low-contrast anchor negates the feature silently — the user won't know why words feel harder to track.

**Framework Mapping**:
- **Visual Span Theory**: The ORP anchor character must be visually distinct within the foveal zone to guide fixation. At 3:1 contrast, a single highlighted character amid 10.5:1 body text characters is a small chromatic signal competing with large luminance signals. At high reading speed, the perceptual system may fail to register the anchor character, reverting to center-of-word fixation (eliminating the ORP benefit).
- **Cognitive Load Theory**: If the anchor is barely visible, the user must work harder (extraneous effort) to locate the fixation point per word. This is the opposite of the feature's intent (germane load reduction via fixation guidance).

**Cognitive Impact**: For users who select a low-contrast anchor, the ORP feature silently degrades from "fixation guide" to "invisible" — especially at speeds above 250 WPM where each word gets limited viewing time. The user may not connect their reading difficulty to the color choice, because the effect is subtle and gradual.

**Optimization**:
- **Add a real-time contrast preview with a warning threshold.** When the user selects an anchor color, show a word preview on the stage background with the selected color. If the computed contrast ratio is below 4.5:1 (AA), display an inline warning: "This color may be hard to see at speed." If below 3:1 (AA minimum for large text), strengthen the warning: "This color is very hard to see — consider a darker option."
- **Apply a text shadow or outline to low-contrast anchor characters.** When the selected anchor color has <4.5:1 contrast on the stage surface, automatically add a 0.5px `stageText`-colored text shadow behind the anchor character. This preserves the user's color choice while ensuring the character is distinguishable.
- **Why this works**: The shadow/outline adds a guaranteed-contrast boundary around the anchor character without overriding the user's color preference (respecting P10 sovereignty). The contrast preview gives the user the information to make an informed choice (informed consent model, consistent with how DT-2 handles the WPM warning).

---

## Design Tension Resolution Evaluations

### DT-1: Engagement-Comprehension Boundary

**Resolution Soundness**: Partially Sound

**What works**: The three-tier intensity system (Minimal / Moderate / Rich) correctly maps to the Yerkes-Dodson curve for the ADHD arousal paradox. The user override is essential — individual arousal optima vary significantly within the ADHD population. The 3–5 second transition duration is below the change-detection threshold for peripheral vision. The spec correctly identifies that seductive details harm comprehension more when cognitive load is high (P7).

**Issues**:
1. **The text difficulty proxy (avg word length ≥ 9 chars for "high difficulty") is sentence-scoped, not window-scoped.** A single long jargon word in a short sentence (e.g., "The confabulation persisted" → avg 10.3 chars) triggers Minimal intensity for the whole sentence, even though the sentence is cognitively simple. Conversely, a sentence with many moderately complex words (e.g., "Several students evaluated potential responses" → avg 7.2 chars) stays at Moderate even though the cumulative processing demand is high.
2. **No hysteresis — oscillation risk.** Covered in the Adaptive Room Intensity component evaluation above.
3. **The boundary between stimulation levels is arbitrary.** ≥9 chars average is not evidence-grounded — no study has validated this threshold as a text difficulty proxy for room intensity switching. The spec does not flag this as Grade D or "explore," but it should be.

**Recommendation**: (a) Switch from per-sentence to a rolling 5-sentence window for the difficulty proxy, which smooths single-word spikes. (b) Add the 30-second hysteresis from the component optimization above. (c) Flag the ≥9 char threshold as Grade D / "explore" — it's an untested proxy, and the spec should acknowledge that explicitly so implementers know it's tunable.

---

### DT-2: Speed-Honesty Tradeoff

**Resolution Soundness**: Sound

**What works**: The conservative default (250 WPM) with a 100 WPM margin below the evidence ceiling (350 WPM) is exactly right. The no-hard-cap approach respects user sovereignty while the gradient color feedback (green → yellow → red) provides continuous, non-verbal risk communication. The WPM dial provides real-time visual feedback during adjustment — the user doesn't have to set a value and then discover it's risky.

**Issues**:
1. **Advisory text verbosity** — covered in WPMControl component evaluation (Yellow). The information content is valuable but the delivery format (mid-motor-task text) is suboptimal.
2. **Allowing 500 WPM creates a contradiction with the product's value proposition.** The product claims to help users read "more effectively, not faster" — but providing a 500 WPM maximum signals that very fast reading is a supported use case. Users who set 500 WPM will have a bad experience (comprehension collapses) and may blame the product rather than the speed. This is a product risk, not a cognitive ergonomics risk, so it's not flagged above Yellow. The 350 WPM advisory mitigates the worst case.

**Recommendation**: Shorten the advisory text as specified in the WPMControl optimization. No structural changes needed — the resolution is sound.

---

### DT-3: Structure-Agency Balance

**Resolution Soundness**: Sound

**What works**: The macro/micro split is well-defined and correctly calibrated. The user controls parameters that are stable across a session (WPM, font, parallax); the system controls parameters that vary per-word (display duration, room intensity). The escape valves (pause, rewind, skip) provide the user with moment-to-moment agency without requiring moment-to-moment self-regulation — a critical distinction for ADHD users.

The per-word timing toggle is an important safety valve. Users who perceive the timing variation as "the app is stuttering" can flatten it. The spec correctly predicts that ≥80% will leave it on (E-10), which means the adaptation is well-designed for most users.

**Issues**: None mechanistically significant. The "invisible adaptation" approach (P16) is the correct pattern — making the adaptation visible would add extraneous load ("why is this word staying longer?") and undermine the single-task mode.

**Recommendation**: No changes. This is well-designed.

---

### DT-4: ORP Extrapolation Gap

**Resolution Soundness**: Sound

**What works**: The spec is appropriately transparent about the evidence gap. The implementation strategy (ship with ORP + build A/B infrastructure) is the correct approach for a Grade D feature — you can't get evidence without shipping the feature, and the theoretical grounding (30+ years of OVP research) makes ORP the strongest available bet.

**Issues**:
1. The dual-distinction of the anchor character (bold weight **AND** color highlight) may be excessive for some users. In OVP research, the optimal viewing position is about fixation location, not visual salience at that location. The bold + color treatment makes the anchor character "pop" in a way that could disrupt holistic word-shape recognition — the Gestalt grouping of characters into a word form. However, this is speculative (no study has tested this), and the A/B test would surface it.
2. The A/B test should include a condition with "color only" (no bold) vs. "bold + color" vs. "center-aligned" to disentangle whether the ORP benefit (if any) comes from fixation guidance or anchor salience.

**Recommendation**: Add a third condition to the planned A/B test: ORP-aligned with color-only anchor (no bold). This isolates whether anchor saliency contributes to or detracts from the ORP effect. No implementation changes for v2.0.

---

## Temporal Stack-Up Analysis

### Critical Path Definition

For each word in the RSVP stream:

```
[Word N displayed] → [display duration = f(word, WPM, modifiers)] → [Word N+1 transition animation starts] → [animation settles] → [Word N+1 stable viewing] → ...
```

The transition animation (A-001 or A-013) co-occurs with the beginning of the display period — it's not sequential. The animation starts when the word appears and must complete within the word's display time.

### Non-Parallax Mode (A-001: 80ms, 1.5% scale)

A-001 is functionally instantaneous for reading purposes. The 1.5% scale change is sub-pixel on typical font sizes. The word is fully legible from frame 1.

| Speed Tier | WPM | Shortest Display (ms) | A-001 (ms) | "Animated" | "Stable" | Headroom | Status |
|---|---|---|---|---|---|---|---|
| Slow | 150 | 400 ("the") | 80 | 80 | 320 | 320 | ✅ OK |
| Default | 250 | 240 ("the") | 80 | 80 | 160 | 160 | ✅ OK |
| Warning | 350 | 171 ("the") | 80 | 80 | 91 | 91 | ✅ OK |
| Maximum | 500 | 120 ("the") | 80 | 80 | 40 | 40 | ✅ OK |

Note: "Stable" and "Headroom" columns understate the effective reading time because A-001's motion is imperceptible. The actual effective reading time equals the full display duration.

**Attentional blink check (A-001)**: At 350 WPM (171ms between word onsets), inter-word interval is inside the blink window (200–500ms). However, A-001's 1.5% scale pulse is below the salience threshold for target detection — it doesn't trigger the blink. At 500 WPM (120ms), the interval is below the blink window entirely, meaning the blink doesn't have time to engage. **PASS** — A-001 does not trigger the attentional blink at any speed.

**Reduced motion check (A-001)**: When disabled, A-001 becomes `Duration.zero` (instant). The word appears at final scale immediately. Display duration is unchanged (controlled by PacingEngine, which is independent of animation). **PASS**.

**Verdict**: Non-parallax timing is clean at all supported speeds.

---

### Parallax Mode (A-013: 160ms base + 6ms/glyph stagger)

A-013 is a depth bounce-in with 4% overshoot and per-glyph stagger. The word enters from behind the back wall and settles forward. Total duration = 160 + 6 × (charCount − 1).

| Speed Tier | WPM | Word | Chars | Display (ms) | A-013 (ms) | Completes? | Stable (ms) | Status |
|---|---|---|---|---|---|---|---|---|
| Slow | 150 | "the" | 3 | 400 | 172 | ✅ | 228 | OK |
| Slow | 150 | "confabulation" | 13 | 720 | 232 | ✅ | 488 | OK |
| Default | 250 | "the" | 3 | 240 | 172 | ✅ | 68 | ⚠️ Tight |
| Default | 250 | "reading" | 7 | 240 | 196 | ✅ | 44 | ⚠️ Very tight |
| Default | 250 | "chapter" | 7 | 240 | 196 | ✅ | 44 | ⚠️ Very tight |
| Default | 250 | "beautiful" | 9 | 312 | 208 | ✅ | 104 | OK |
| Warning | 350 | "the" | 3 | 171 | 172 | ❌ | −1 | **FAIL** |
| Warning | 350 | "reading" | 7 | 171 | 196 | ❌ | −25 | **FAIL** |
| Warning | 350 | "chapter" | 7 | 171 | 196 | ❌ | −25 | **FAIL** |
| Warning | 350 | "confabulation" | 13 | 309 | 232 | ✅ | 77 | OK |
| Maximum | 500 | "the" | 3 | 120 | 172 | ❌ | −52 | **FAIL** |
| Maximum | 500 | "reading" | 7 | 120 | 196 | ❌ | −76 | **FAIL** |
| Maximum | 500 | "confabulation" | 13 | 216 | 232 | ❌ | −16 | **FAIL** |

**Failure pattern**: At 350 WPM, any word without length modifiers (< 8 characters) fails. At 500 WPM, **all words** including 13-character words with length modifiers fail. The failure is: the bounce-in animation is literally still running when the next word replaces it.

**Attentional blink check (A-013)**: The 4% overshoot with per-glyph stagger is a moderate-salience onset event. At 350 WPM (171ms interval), this falls inside the attentional blink peaks (200–300ms). The bounce-in could trigger target detection, impairing processing of the immediately following word. Risk: **HIGH at 350+ WPM**.

**Reduced motion check (A-013)**: When disabled, word appears at final position immediately. Display duration unchanged. **PASS** — reduced motion users are unaffected by this issue.

**Drift correction check**: Drift correction adjusts the timer delay based on elapsed vs. expected time. When A-013 exceeds display time, the word is replaced before the animation completes, but the timer fires *at the correct time*. The animation is simply interrupted. Drift correction still works — it corrects scheduling, not animation completion. However, the interrupted animation creates visual artifacts (word mid-bounce is replaced by a new word that starts bouncing). **Not a drift correction failure, but a visual coherence failure.**

**Verdict**: Parallax mode timing **fails** at ≥350 WPM and is **marginal** at 250 WPM for common word lengths. This is the single highest-priority fix in the spec. See the WordDisplay (Parallax Variant) optimization above for the concrete fix.

---

### Per-Glyph Stagger Variability

A-013 uses a 6ms per-glyph stagger, making total animation duration dependent on word length. This creates variable animation durations that the drift correction system doesn't account for:

| Chars | Stagger Total (ms) | A-013 Total (ms) | Duration Variation |
|---|---|---|---|
| 1 ("I") | 0 | 160 | baseline |
| 3 ("the") | 12 | 172 | +12ms |
| 7 ("reading") | 36 | 196 | +36ms |
| 13 ("confabulation") | 72 | 232 | +72ms |

The 72ms range (160–232ms) means that long words have animations that take 45% longer than short words. However, long words also have longer display times (via length modifiers), so the failure is concentrated on **short words** — which are the most frequent words in English. At 250 WPM, the words most likely to fail the headroom check are "the," "a," "in," "of," "to" — the top 20 highest-frequency words in English, which are all 1–3 characters and appear every ~5 words in typical text.

**Impact**: In parallax mode at 250 WPM, approximately **20% of all words** (the short, frequent function words) will have <70ms of stable viewing time after A-013 completes. These words are individually easy to process (high-frequency, pattern-matched), so the reading impact is tolerable. But the rhythm disruption is real — every fifth word has a noticeably different animation-to-display ratio.

---

## Systemic Risks

### 1. A-013 × High WPM = Broken Parallax Reading (Red, Highest Priority)

**Components**: WordDisplay (parallax) + PacingEngine + Animation System
**Mechanism**: A-013 animation duration (160ms + 6ms/glyph stagger) exceeds per-word display time at ≥350 WPM for common words. The word's bounce-in animation is interrupted by the arrival of the next word, creating a visual stutter where no word ever reaches its stable resting state.
**Perceptual consequence**: The temporal scaffolding function of A-013 inverts — instead of providing a rhythmic "arrival cue" that marks each word's onset, it creates a continuous bouncing carousel where words blend together. For ADHD users relying on the external rhythm to maintain attention, this is a catastrophic failure of the scaffolding mechanism.
**Fix scope**: Modify the animation selection logic to fall back from A-013 to A-001 above 300 WPM. Alternatively, make A-013 duration adaptive: `min(160, displayMs × 0.6 - staggerTotal)`.

### 2. Room Intensity Oscillation from Sentence-Level Difficulty Proxy (Yellow)

**Components**: ParallaxRoom (adaptive states) + PacingEngine (text difficulty signal)
**Mechanism**: The difficulty proxy (avg character count per sentence) is evaluated on each new sentence. In text with alternating simple and complex sentences (common in academic prose: simple topic sentence → complex evidence sentence → simple transition sentence), the room oscillates between Rich and Minimal every 2–4 sentences. The 3–5 second fade prevents abrupt visual change, but the oscillation pattern over 2–3 minutes creates a detectable, unpredictable peripheral rhythm.
**Perceptual consequence**: The user develops a vague awareness that "something in the room is changing," which periodically triggers conscious attention allocation to the peripheral field — the exact mechanism the room is designed to avoid.
**Fix scope**: Add hysteresis (30s hold time) and rolling-window smoothing (5-sentence average). Low implementation cost, high ergonomic benefit.

### 3. Silent ORP Degradation from Low-Contrast Anchor Colors (Yellow)

**Components**: WordDisplay (anchor rendering) + SettingsPanel (anchor color picker)
**Mechanism**: Users select a warm/light anchor color (indices 1–5, ≥3:1 but <4.5:1 contrast) without understanding the consequence for reading at speed. The ORP anchor becomes indistinguishable from surrounding text at high WPM, silently eliminating the fixation-guidance benefit. The user experiences faster fatigue and worse tracking but cannot identify the cause because the feature degradation is gradual and the connection to color choice is non-obvious.
**Perceptual consequence**: Loss of the ORP benefit without user awareness. The user may attribute the difficulty to the app's pacing or to their own attention deficit — reinforcing negative self-attribution, which is particularly harmful for ADHD users.
**Fix scope**: Add contrast-aware warning in the color picker and optional automatic text-shadow on low-contrast anchors. Low implementation cost.

### 4. Compounding Peripheral Load at Rich Room Intensity (Green — No Action Needed)

**Components**: ParallaxRoom (Rich state) + A-011 (cube breathe) + parallax shift
**Assessed risk**: At Rich intensity with full parallax and cube breathe, the peripheral visual field has two concurrent animated elements (cube breathe at 0.125Hz + user-driven parallax). This is within the spec's maximum of 2 concurrent ambient animations.
**Why it's not a risk**: Both animations are slow (≥2000ms cycle), low-contrast (animated elements ≤3:1 against adjacent surfaces), and one is user-initiated (parallax). The combined arousal contribution is well within the Yerkes-Dodson optimal zone for peripheral stimulation. The spec's ambient motion rules (§6.4) correctly prevent this from becoming a risk.

---

## Top 3 Optimizations

### 1. Make A-013 adaptive to WPM (Red → Green)

**Fix**: Above 300 WPM, replace A-013 (160ms depth bounce + stagger) with A-001 (80ms, 1.5% scale pulse). Below 300 WPM, optionally cap A-013 to `displayMs × 0.6` to guarantee ≥40% stable viewing time.

**Impact**: Eliminates the highest-severity issue in the spec — the temporal stack-up failure that breaks parallax reading at common WPM settings. At 350 WPM, short words go from −25ms headroom (animation never completes) to +91ms headroom (A-001 completes with margin). At 500 WPM: from −76ms to +40ms.

**Framework**: Temporal Binding — ensures every word reaches its perceptually stable state before replacement, maintaining the rhythmic scaffolding that serves as the ADHD user's external executive function.

**Implementation**: In the animation selection logic for the parallax word painter, add a WPM check. If `wpm > 300`, use the A-001 breathe curve instead of A-013 bounce-in. This is a ~5-line conditional, no architectural changes required.

### 2. Add hysteresis + rolling window to adaptive room intensity (Yellow → Green)

**Fix**: (a) After a room intensity transition, enforce a 30-second hold before allowing the next transition. (b) Replace per-sentence difficulty proxy with a rolling 5-sentence window average.

**Impact**: Eliminates the oscillation risk for text with variable sentence complexity (academic, technical, and literary prose — the primary content type for a PDF reading app). The room becomes a stable peripheral scaffold that adapts to sustained content changes, not sentence-level noise.

**Framework**: Change Blindness (positive exploitation) — gradual, infrequent changes that stay below the detection threshold. Yerkes-Dodson — eliminates the unpredictable peripheral rhythm that could push ADHD users above optimal arousal.

**Implementation**: Add a `DateTime _lastIntensityChange` field and a `List<double> _recentDifficultyScores` buffer to the room state management. ~15 lines of logic.

### 3. Shorten WPM advisory + add contrast warnings to anchor picker (Yellow → Green)

**Fix**: (a) Reduce the >350 WPM advisory from two sentences to ≤5 words ("Best for scanning familiar text"). (b) Add inline contrast preview and warning in the anchor color picker when contrast < 4.5:1.

**Impact**: (a) Eliminates the dual-task interference between motor dial adjustment and text processing. The red color change already communicates risk; the text now adds actionable information without demanding sustained phonological processing. (b) Prevents silent ORP degradation by giving users an informed choice about low-contrast anchor colors, consistent with the informed-consent model used for WPM warnings.

**Framework**: (a) Dual-Task Interference / CLT — reduces phonological loop demand from ~4 chunks to ~1 chunk, below the interference threshold for concurrent motor tasks. (b) Visual Span Theory — ensures the ORP anchor character remains distinguishable in foveal processing at all supported speeds and anchor color choices.

---

## Green Validations

These components and decisions are cognitively well-designed. They are load-bearing — preserve them during implementation.

1. **Single-task reading mode (§4.1, §5.4)** — The maximum 2 visible elements during reading (word + progress hairline after 3s WPM badge auto-hide) is the most important UI decision in the spec. It eliminates extraneous load from the foveal field entirely. This directly addresses the ADHD centrality deficit: when there's nothing else to attend to, the centrality deficit has no task-irrelevant stimulus to latch onto. Do not add persistent visible elements to reading mode.

2. **Per-word adaptive timing (§3.1, §5.2)** — The length/frequency/punctuation modifier system is a well-designed WM scaffolding mechanism. It allocates more processing time to words that consume more WM capacity, silently compensating for the ADHD WM deficit. The invisibility of the adaptation (P16) prevents the user from attending to the timing variation — making it feel like their own natural reading rhythm.

3. **Progress hairline design (§5.4, §5.7)** — 1–2px height, 30–50% opacity, bottom viewport edge. This is exemplary ambient feedback: it externalizes progress (freeing a WM slot from "where am I?") without commanding any foveal attention. The continuous fill (vs. stepped milestones) avoids the perceptual discontinuity of discrete jumps.

4. **Parallax displacement cap at 5% (§3.5, §5.3)** — At 390px viewport width, maximum shift = ±19.5px. This keeps the room movement firmly in parafoveal/peripheral vision. Even during maximum head movement, the word's foveal processing is undisturbed because the room shift is too small to trigger a reflexive saccade.

5. **Cube breathe at 8000ms cycle (A-011)** — At 0.125Hz, this is well below the ~0.5Hz threshold where peripheral motion begins capturing attention (Franconeri & Simons, 2003). The ±1.5° rotation is sub-perceptual per frame. The breathe functions as ambient "aliveness" that sustains the sense of being in a warm room without demanding any processing.

6. **Non-punitive session feedback (§5.7)** — "You've read 4 of the last 7 days" vs. streak-based gamification. This is the single most ADHD-sensitive design decision in the spec. Streak mechanics exploit loss aversion, which triggers shame in ADHD users who inevitably break streaks. The factual, positive framing avoids this entirely. **Under no circumstances should this be changed to include streaks, scores, or loss-framed messaging.**

7. **120ms display floor (§3.1.3)** — This prevents subliminal presentation at any WPM setting. At 500 WPM, the floor ensures every word is consciously perceivable (Potter, 2018: ~100ms is the conscious perception threshold for words). The floor is correctly set at 120ms with a 20ms margin above the perception threshold — enough to absorb frame-timing jitter.

8. **Default 250 WPM (§3.1.3)** — Conservative by exactly 100 WPM below the Grade A evidence ceiling (350 WPM). This margin is large enough that first-time users have excellent comprehension (building confidence and app trust) without feeling the pace is "insultingly slow" (250 WPM is within normal silent reading range).

9. **Reduced motion is a complete, independent behavior set (§6.5)** — When enabled, every animation is disabled and the room renders as a static 3D scene. The timing system is unaffected. This is critical for users with vestibular sensitivity or motion-triggered migraines, and provides a complete, coherent experience without animation. No animation is assumed to have completed for any functional purpose.

10. **Word spatially locked during parallax (§5.3)** — "The word is NEVER affected by parallax. Only the room moves." This is the single most important rendering constraint. If the word moved with the room, the perceptual system would need to track a moving target while performing lexical access — a dual-task that would collapse at any speed above ~150 WPM.

---

*Evaluation complete. 2 Red findings, 4 Yellow findings, 10 Green validations. The highest-priority fix (A-013 timing at high WPM) is a ~5-line conditional in the animation selection logic. The second-priority fix (room intensity hysteresis) is ~15 lines of state management. Both are low-cost, high-impact changes that should be implemented before shipping.*
