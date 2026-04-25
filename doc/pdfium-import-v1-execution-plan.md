# Speedy Boy — PDFium Import v1 Execution Plan

**Created**: 2026-04-07
**Tasks**: 24 across 5 sprints, organized into 12 work sessions
**Tools**: VS Code + GitHub Copilot (Chat + Edits mode)
**Codebase**: Clean, matches v4 Sprint 6 completion state

---

## Tool Strategy

### When to Use Which Mode

| Mode | Use For | Why |
|------|---------|-----|
| **Copilot Chat** | Single-file creation, pure logic, tests, benchmarks | Tight context → precise output |
| **Copilot Edits** | Multi-file changes, pipeline wiring, integration | Can see + edit multiple files simultaneously |
| **Manual** | Benchmark analysis, PDF collection, visual verification | Requires human judgment |

### Context Window Golden Rule

**Maximum per prompt**: 2–3 skill files + the target source files + the relevant copilot rules. Every session below specifies exactly what to include.

### Skill References

```
#file:.claude/skills/flutter-handling-concurrency/SKILL.md     → Isolate patterns
#file:.claude/skills/flutter-managing-state/SKILL.md           → Riverpod notifiers
#file:.claude/skills/riverpod-providers/SKILL.md               → Provider creation
#file:.claude/skills/riverpod-auto-dispose/SKILL.md            → Auto-dispose lifecycle
#file:.claude/skills/flutter-building-layouts/SKILL.md         → Import summary UI
#file:.claude/skills/flutter-theming-apps/SKILL.md             → Token compliance
#file:.claude/skills/flutter-testing-apps/SKILL.md             → Unit/widget tests
#file:.claude/skills/flutter-implementing-navigation-and-routing/SKILL.md → go_router
#file:.claude/skills/flutter-building-forms/SKILL.md           → Toggle controls
#file:.claude/skills/flutter-working-with-databases/SKILL.md   → Profile persistence
```

---

## Skill → Task Cluster Map

```
┌─────────────────────────────────┐
│ EXTRACTION LAYER                │
│ flutter-handling-concurrency    │──→ pdfrx main-isolate extraction,
│                                 │    Isolate.run() for classification,
│                                 │    pipeline orchestration
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ STATE LAYER                     │
│ flutter-managing-state          │──→ ImportNotifier, ImportState
│ riverpod-providers              │──→ importStateProvider
│ riverpod-auto-dispose           │──→ Import state cleanup
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ UI LAYER                        │
│ flutter-building-layouts        │──→ Import summary screen, cards
│ flutter-theming-apps            │──→ Shell surface world compliance
│ flutter-building-forms          │──→ Toggle controls
│ flutter-implementing-navigation │──→ /import-summary route
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ TESTING LAYER                   │
│ flutter-testing-apps            │──→ All test files
│ riverpod-testing                │──→ Provider overrides in widget tests
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ PERSISTENCE LAYER               │
│ flutter-working-with-databases  │──→ ExtractionProfile in SectionStore
└─────────────────────────────────┘
```

---

## Sprint 0: Research Spikes

**Goal**: Validate that `loadStructuredText()` is performant and that the rect-height font heuristic is accurate enough. These benchmarks gate all subsequent work.

**Estimated time**: ~2 hours

### Session 0.1: pdfrx API Benchmarks

**Mode**: Copilot Chat
**Tasks**: TASK-200, TASK-201

**Context to include**:
```
#file:.claude/skills/flutter-testing-apps/SKILL.md
#file:lib/services/pdf_extractor.dart
#file:doc/pdfium-import-v1-design-spec.md  (§5.6 only — font estimation)
```

**Prompt strategy**:
1. First prompt: "Create a benchmark test that opens a PDF, calls `page.loadText()` and `page.loadStructuredText()` on every page, and records per-page latency. Use Stopwatch. Save as `test/services/pdfrx_benchmark_test.dart`."
2. Second prompt: "Create a benchmark test that extracts fragment charRects from `loadStructuredText()`, computes median rect height per fragment, and identifies headings using a ≥20% delta from the dominant size. Save as `test/services/font_heuristic_benchmark_test.dart`."
3. **Manual step**: Run benchmarks on 3–5 personal PDFs. Record results. Make go/no-go decision.

**Exit criteria**:
- [ ] `loadStructuredText()` < 50ms/page on average
- [ ] Rect-height heading detection precision ≥ 0.90, recall ≥ 0.85
- [ ] If either fails: document findings and decide whether to investigate pdfrx_engine

**Decision gate**: If benchmarks fail, stop and reassess. If they pass, proceed to Sprint 1.

---

## Sprint 1: Data Models + Enhanced Extraction

**Goal**: Create all data models and replace `pdfExtract()` with structured extraction. The existing pipeline must still produce `ExtractedDocument` (backward compatible).

**Estimated time**: ~3.5 hours

### Session 1.1: Data Models

**Mode**: Copilot Chat
**Tasks**: TASK-202, TASK-203, TASK-204

**Context to include**:
```
#file:.claude/skills/flutter-managing-state/SKILL.md
#file:lib/services/models.dart
#file:doc/pdfium-import-v1-design-spec.md  (§5.2 — Data Structures)
```

**Prompt strategy**:
1. "Add `TextBlockData` and `PageAnalysis` classes to `lib/services/models.dart` following the design spec §5.2. Include `toJson()`/`fromJson()` for `TextBlockData`."
2. "Add `BlockClassification`, `BlockDisposition`, `ClassifiedBlock`, `DetectedPattern`, and `ClassificationResult` to `lib/services/models.dart` per the design spec."
3. "Create `lib/services/extraction_profile.dart` with `FootnoteHandling` enum and `ExtractionProfile` class. Include JSON round-trip methods and `applyTo(ClassificationResult)` method."

**Exit criteria**:
- [ ] All models compile
- [ ] No pdfrx imports in new models
- [ ] `dart analyze lib/` = 0 issues

### Session 1.2: Enhanced Extraction + Tests

**Mode**: Copilot Edits
**Tasks**: TASK-205, TASK-206

**Context to include**:
```
#file:.claude/skills/flutter-handling-concurrency/SKILL.md
#file:lib/services/pdf_extractor.dart
#file:lib/services/models.dart  (updated from 1.1)
#file:doc/pdfium-import-v1-design-spec.md  (§5.6 — font estimation)
```

**Prompt strategy**:
1. "Add `extractStructured(String filePath)` function to `pdf_extractor.dart` that uses `page.loadStructuredText()` and returns `List<PageAnalysis>`. Fall back to `loadText()` if structured extraction fails. Compute `estimatedFontSize` from median charRect height. Modify `pdfExtract()` to use `extractStructured()` internally (identity transform for now — all blocks treated as bodyText). Keep backward-compatible `ExtractedDocument` output."
2. "Create `test/services/text_block_data_test.dart` and `test/services/extraction_profile_test.dart` with round-trip serialization tests, computed property tests, and `applyTo()` logic tests."

**Exit criteria**:
- [ ] `extractStructured()` returns `List<PageAnalysis>`
- [ ] `pdfExtract()` still returns `ExtractedDocument`
- [ ] All existing tests still pass
- [ ] ≥8 new unit tests pass
- [ ] `dart analyze lib/` = 0 issues

---

## Sprint 2: Classification Engine

**Goal**: Build the cross-page classification engine that runs in `Isolate.run()`. All detection algorithms implemented and tested.

**Estimated time**: ~6.5 hours

### Session 2.1: Engine Scaffold + Dominant Font

**Mode**: Copilot Chat
**Tasks**: TASK-207, TASK-208

**Context to include**:
```
#file:.claude/skills/flutter-handling-concurrency/SKILL.md
#file:lib/services/models.dart
#file:doc/pdfium-import-v1-design-spec.md  (§5.5 — font detection)
```

**Prompt strategy**:
1. "Create `lib/services/classification_engine.dart` with a top-level `classify(List<PageAnalysis> pages)` function that returns `ClassificationResult`. This function will be called via `Isolate.run()`. Include no pdfrx imports. Set up the pipeline skeleton: dominant font detection → zone setup → (stub detectors) → result assembly."
2. "Implement `_detectDominantFontSize()` — collects all fragment `estimatedFontSize` values, rounds to 0.5pt buckets, returns the statistical mode."

**Exit criteria**:
- [ ] `classify()` compiles and is isolate-safe (top-level function, no FFI)
- [ ] Dominant font detection returns correct mode on simple test data
- [ ] `dart analyze lib/` = 0 issues

### Session 2.2: Header/Footer + Page Number Detection

**Mode**: Copilot Chat
**Tasks**: TASK-209, TASK-210

**Context to include**:
```
#file:lib/services/classification_engine.dart  (from 2.1)
#file:doc/pdfium-import-v1-design-spec.md  (§5.3 — header/footer algorithm)
```

**Prompt strategy**:
1. "Implement `_detectHeadersFooters()` in `classification_engine.dart` per the design spec §5.3. Include `_levenshteinRatio()` helper. Separate odd/even pages. Require ≥3 pages AND ≥50% of group. Produce `DetectedPattern` entries."
2. "Implement `_detectPageNumbers()` — filter header/footer candidates matching page number regexes, validate sequential ordering (gaps ≤ 2), require ≥50% page coverage, confidence 0.90."

**Exit criteria**:
- [ ] Header/footer detection handles odd/even pages separately
- [ ] Levenshtein ratio computed correctly
- [ ] Page numbers validated for sequentiality
- [ ] `dart analyze lib/` = 0 issues

### Session 2.3: Body Column + Tests

**Mode**: Copilot Chat
**Tasks**: TASK-211, TASK-212

**Context to include**:
```
#file:.claude/skills/flutter-testing-apps/SKILL.md
#file:lib/services/classification_engine.dart  (from 2.2)
#file:doc/pdfium-import-v1-design-spec.md  (§5.4 — column detection)
```

**Prompt strategy**:
1. "Implement body column detection and heading classification in `classification_engine.dart` per the design spec §5.4. Fragments outside body column → marginalia. Fragments with fontSize ≥ 1.2× dominant → heading. Remaining → bodyText."
2. "Create `test/services/classification_engine_test.dart` with ≥10 test cases covering: dominant font, header/footer detection, page numbers, headings, marginalia, small PDFs, empty documents, Levenshtein ratio."

**Exit criteria**:
- [ ] Full classification pipeline works end-to-end on mock data
- [ ] ≥10 tests pass
- [ ] `flutter test test/services/classification_engine_test.dart` = all green
- [ ] `dart analyze` = 0 issues

---

## Sprint 3: Text Assembly + Integration

**Goal**: Build the text assembler and wire the full pipeline into PreprocessingQueue. Integration test validates end-to-end.

**Estimated time**: ~5.5 hours

### Session 3.1: Assembler + Pipeline Wiring

**Mode**: Copilot Edits (multi-file: assembler + queue + extractor)
**Tasks**: TASK-213, TASK-214, TASK-215

**Context to include**:
```
#file:.claude/skills/flutter-handling-concurrency/SKILL.md
#file:lib/services/models.dart
#file:lib/services/pdf_extractor.dart
#file:lib/services/preprocessing_queue.dart
#file:lib/services/extraction_profile.dart
#file:lib/services/classification_engine.dart
#file:doc/pdfium-import-v1-design-spec.md  (§8 — Text Assembly, §9 — Integration)
```

**Prompt strategy**:
1. "Create `lib/services/text_assembler.dart` with `assemble(ClassificationResult, ExtractionProfile)` → `ExtractedDocument`. Implement text cleaning: dehyphenation (preserve compound words where both fragments ≥3 chars), whitespace normalization, Unicode NFC, page-break stitching. Skip excluded blocks. Use existing `_textToSentences()` pattern for sentence splitting. Insert PageBoundary markers."
2. "Wire the new pipeline into `preprocessing_queue.dart`: after Phase 2 full extraction, run `Isolate.run(() => classify(pages))`, then `assemble()` with default ExtractionProfile. Store result via SectionStore. Flag documents with high-confidence detections for import summary."

**Exit criteria**:
- [ ] Assembler produces `ExtractedDocument` from classified blocks
- [ ] Text cleaning rules implemented
- [ ] Pipeline wired: extract → classify → assemble
- [ ] Classification runs in `Isolate.run()`
- [ ] Preview phase unchanged
- [ ] `dart analyze lib/` = 0 issues

### Session 3.2: Integration Tests

**Mode**: Copilot Chat
**Tasks**: TASK-216

**Context to include**:
```
#file:.claude/skills/flutter-testing-apps/SKILL.md
#file:lib/services/text_assembler.dart
#file:lib/services/classification_engine.dart
```

**Prompt strategy**:
1. "Create `test/services/text_assembler_test.dart` with tests for: correct sentence assembly from mock ClassifiedBlocks, excluded blocks omitted, page boundaries at page transitions, dehyphenation, whitespace normalization, ligature replacement, page-break stitching."
2. "Create `integration_test/pdf_import_test.dart` that opens a real PDF, runs the full pipeline (extractStructured → classify → assemble), and verifies the output ExtractedDocument has sentences without known header/footer text."

**Exit criteria**:
- [ ] ≥8 assembler unit tests pass
- [ ] ≥1 integration test validates end-to-end pipeline
- [ ] `flutter test` = all green (existing tests unbroken)

---

## Sprint 4: Auto-Prompt UI

**Goal**: Build the import summary screen with Riverpod state management, detection cards, toggles, and library integration.

**Estimated time**: ~5.5 hours

### Session 4.1: Riverpod State + Route

**Mode**: Copilot Edits (multi-file: state + screen + router)
**Tasks**: TASK-217, TASK-218

**Context to include**:
```
#file:.claude/skills/riverpod-providers/SKILL.md
#file:.claude/skills/riverpod-auto-dispose/SKILL.md
#file:.claude/skills/flutter-building-layouts/SKILL.md
#file:lib/store/import_state.dart  (will be created)
#file:lib/navigation/app_router.dart
#file:doc/pdfium-import-v1-design-spec.md  (§7 — Auto-Prompt UI)
```

**Prompt strategy**:
1. "Create `lib/store/import_state.dart` with `ImportPhase` enum, `ImportState` class, and `ImportNotifier` (AsyncNotifier, auto-dispose). Methods: `startImport(filePath)`, `updateOverride(classification, disposition)`, `confirmImport()`, `dismiss()`. `startImport` runs pdfrx extraction on main isolate, then classification in `Isolate.run()`."
2. "Create `lib/screens/import_summary_screen.dart` as a ConsumerStatefulWidget. Add `/import-summary` route to `app_router.dart`. Screen watches importStateProvider, shows neumorphic pulse during extraction/classification, shows detection list during review, navigates to /read on ready."

**Exit criteria**:
- [ ] ImportNotifier manages full import lifecycle
- [ ] Auto-dispose cleans up when screen exits
- [ ] Route registered at `/import-summary`
- [ ] Screen renders correctly for each phase
- [ ] No Material loading widgets (Rule 15)
- [ ] `dart analyze lib/` = 0 issues

### Session 4.2: Detection Cards + Toggles

**Mode**: Copilot Chat
**Tasks**: TASK-219, TASK-220, TASK-223

**Context to include**:
```
#file:.claude/skills/flutter-building-layouts/SKILL.md
#file:.claude/skills/flutter-theming-apps/SKILL.md
#file:lib/screens/import_summary_screen.dart  (from 4.1)
#file:lib/design/tokens.dart
#file:lib/design/decorations.dart
#file:doc/pdfium-import-v1-design-spec.md  (§7.2–7.5 — styling)
```

**Prompt strategy**:
1. "Add detection summary cards to `import_summary_screen.dart`: scrollable list of DetectedPattern cards sorted by impact. Each card shows icon + description + page count + sample text. Use `SpeedyBoyDecorations.raisedDecoration(shellSurface, sizeSmall)` for card styling. Typography from `SpeedyBoyTypography`."
2. "Add toggle controls to each detection card: binary [Ignore/Keep] for noise types, [Skip/Keep] for footnotes. Toggle calls `importNotifier.updateOverride()`. Add 'Import Now' button that calls `confirmImport()`. Show reading time estimates."
3. "Add `saveProfile()` and `loadProfile()` to `SectionStore` for ExtractionProfile persistence. Run I/O in `Isolate.run()`."

**Exit criteria**:
- [ ] Cards rendered with correct styling
- [ ] Toggles update import state
- [ ] Import button triggers confirm flow
- [ ] Profile persistence works
- [ ] Shell surface world compliance
- [ ] `dart analyze lib/` = 0 issues

### Session 4.3: Library Wiring + Widget Tests

**Mode**: Copilot Edits
**Tasks**: TASK-221, TASK-222

**Context to include**:
```
#file:.claude/skills/flutter-implementing-navigation-and-routing/SKILL.md
#file:.claude/skills/flutter-testing-apps/SKILL.md
#file:.claude/skills/riverpod-testing/SKILL.md
#file:lib/screens/library_screen.dart
#file:lib/screens/import_summary_screen.dart
#file:lib/navigation/app_router.dart
```

**Prompt strategy**:
1. "Update `library_screen.dart`: when user taps a PDF, check for stored ExtractionProfile. If none exists and classification detected patterns with confidence ≥ 0.6, navigate to `/import-summary`. If profile exists or no patterns, navigate directly to `/read`. Add long-press 'Re-import with options' that clears profile and shows import summary."
2. "Create `test/screens/import_summary_screen_test.dart` with ≥7 widget tests: extracting phase shows progress, reviewing phase shows cards, cards only for confidence ≥ 0.6, toggles update state, Import Now navigates, Back dismisses, shell tokens used."

**Exit criteria**:
- [ ] Library correctly routes to import summary or reading screen
- [ ] Long-press re-import option works
- [ ] ≥7 widget tests pass
- [ ] `flutter test` = all green
- [ ] `dart analyze lib/` = 0 issues

---

## Post-Sprint Verification

After all sessions complete, run the full verification checklist:

```bash
dart analyze lib/                    # Zero warnings
flutter test                         # All pass (existing + new)
```

### Cross-Reference Checklist

| Check | Status |
|-------|--------|
| Every component in design spec §5–8 has tasks in the backlog | |
| Every Do/Don't in design spec §12 maps to a copilot patch rule (29–35) | |
| Every task appears in exactly one execution plan session | |
| All timing tokens in copilot patch appear in design spec | |
| All new files in copilot patch match task backlog CREATE actions | |
| Output model shape matches existing `ExtractedDocument` | |
| No pdfrx imports in classification_engine.dart | |
| No Isolate.run() calls contain pdfrx FFI | |
| All UI uses shell surface world tokens (not stage) | |
| All animations check isReducedMotion | |
| No CircularProgressIndicator or LinearProgressIndicator | |

---

## Dependency Graph

```
TASK-200 ──────────────────────────────────────────────── (independent)
TASK-201 ──────────────────────────────────────────────── (independent)

TASK-202 ──┬── TASK-203 ──── TASK-204 ──── TASK-206
           │        │             │
           │        │             └── TASK-213 ──┐
           │        │                            │
           └── TASK-205 ──┐      TASK-207 ──┐    │
                          │           │     │    │
                          │    TASK-208 ─── TASK-211   │
                          │           │               │
                          │    TASK-209 ── TASK-210    │
                          │           │               │
                          │    TASK-212 (tests all)    │
                          │                           │
                          └── TASK-214 ───────────────┤
                                    │                 │
                               TASK-215               │
                                    │                 │
                               TASK-216 ──────────────┘
                                    │
                               TASK-217 ── TASK-218
                                              │
                                         TASK-219
                                              │
                                         TASK-220
                                              │
                                    ┌────────┤
                                    │        │
                               TASK-221  TASK-222

TASK-223 ──── (depends on TASK-204 only, can run in parallel)
```

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|-----------|
| `loadStructuredText()` significantly slower than `loadText()` | M1 blocked | TASK-200 benchmark. If >100ms/page, test `loadText()` with charRects-only approach. |
| Rect-height heading heuristic accuracy < 90% | M2 degraded | TASK-201 benchmark. If below threshold, flag pdfrx_engine investigation for Phase 2. |
| Levenshtein comparison O(N²) on large PDFs | M2 slow | Pre-hash normalized candidates. Use hash-based comparison for O(1) matching; only compute full Levenshtein for hash-collision tiebreaking. |
| pdfrx `loadStructuredText()` returns null on some PDFs | M1 degraded | Fallback to `loadText()` per page. Already handled in TASK-205. |
| Import summary screen adds friction to reading flow | UX regression | Non-blocking design (Rule 34). Dismiss applies defaults. Profile persistence prevents repeat prompts. |
| Classification false positives on body text as headers | Reading quality | Conservative defaults: only classify as header with ≥3-page match AND ≥50% group coverage. User override available. |
