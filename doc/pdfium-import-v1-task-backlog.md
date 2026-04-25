# Speedy Boy — PDFium Import v1 Task Backlog

**Generated**: 2026-04-07
**Spec version**: pdfium-import-v1
**Tasks**: 23 across 5 sprints (Sprint 0–4)
**Based on**: `doc/pdfium-import-v1-design-spec.md`

---

## Sprint 0: Research Spikes

### TASK-200: Benchmark `loadStructuredText()` vs `loadText()`
- **Priority**: 0 (prerequisite — informs all subsequent work)
- **Files**: `CREATE: test/services/pdfrx_benchmark_test.dart`, `lib/services/pdf_extractor.dart`
- **Action**: Write a test that opens 5 test PDFs (small <10 pages, medium ~100 pages, large ~500 pages, tagged/accessible, scanned/OCR'd) and measures wall-clock time for `page.loadText()` vs `page.loadStructuredText()` on every page. Record: per-page latency (mean, p95), total extraction time, text completeness (character count comparison), fragment count from structured extraction.
- **Acceptance criteria**:
  - [ ] Benchmark runs on at least 3 PDFs (can use personal PDF collection)
  - [ ] Per-page latency recorded for both APIs
  - [ ] Completeness comparison (does `loadStructuredText()` miss any text that `loadText()` captures?)
  - [ ] Results documented as test output or markdown comment
  - [ ] Decision recorded: is `loadStructuredText()` latency acceptable (< 50ms/page)?
- **Skill references**: `flutter-handling-concurrency`, `flutter-testing-apps`
- **Effort**: S (~1 hour)
- **Depends on**: Nothing

---

### TASK-201: Benchmark rect-height font heuristic accuracy
- **Priority**: 0 (prerequisite)
- **Files**: `CREATE: test/services/font_heuristic_benchmark_test.dart`
- **Action**: For 3 untagged PDFs with known heading structure, extract all fragments via `loadStructuredText()`, compute `estimatedFontSize` from median `charRect` height, apply the ≥20% delta heuristic, and compare detected headings against ground truth (manually labeled). Report precision and recall.
- **Acceptance criteria**:
  - [ ] Benchmark runs on at least 3 PDFs with identifiable headings
  - [ ] Precision and recall computed per PDF
  - [ ] If precision ≥ 0.90 AND recall ≥ 0.85: rect-height confirmed sufficient
  - [ ] If below threshold: document which PDFs fail and why; flag pdfrx_engine investigation
  - [ ] Results documented
- **Skill references**: `flutter-testing-apps`
- **Effort**: S (~1 hour)
- **Depends on**: Nothing

---

## Sprint 1: Data Models + Enhanced Extraction

### TASK-202: Create serializable text block models
- **Priority**: 1
- **Files**: `lib/services/models.dart`
- **Action**: Add the following classes to `lib/services/models.dart`:
  - `TextBlockData` — serializable representation of a PDF text fragment (pageIndex, fragmentIndex, text, left/top/right/bottom, estimatedFontSize, direction). Include `toJson()` and `fromJson()`.
  - `PageAnalysis` — all extracted data for a single page (pageIndex, pageWidth, pageHeight, List<TextBlockData> fragments).
- **Acceptance criteria**:
  - [ ] `TextBlockData` has all fields from design spec §5.2
  - [ ] `TextBlockData.toJson()` / `fromJson()` round-trips correctly
  - [ ] `PageAnalysis` groups fragments by page
  - [ ] `dart analyze lib/` passes
- **Skill references**: `flutter-managing-state`
- **Effort**: S (~30 min)
- **Depends on**: Nothing

---

### TASK-203: Create classification enums and ClassifiedBlock
- **Priority**: 1
- **Files**: `lib/services/models.dart`
- **Action**: Add:
  - `enum BlockClassification { bodyText, heading, runningHeader, runningFooter, pageNumber, footnote, blockQuote, listItem, marginalia, placeholder, unknown }`
  - `enum BlockDisposition { include, exclude, askUser }`
  - `ClassifiedBlock` — wraps `TextBlockData` with classification, disposition, confidence (0.0–1.0), and optional detectionReason string.
  - `DetectedPattern` — cross-page pattern for auto-prompt UI (type, description, pageCount, totalPages, defaultDisposition, confidence, sampleText).
  - `ClassificationResult` — full result: `Map<int, List<ClassifiedBlock>> classifiedPages`, `List<DetectedPattern> detectedPatterns`, `double dominantFontSize`, `int totalPages`.
- **Acceptance criteria**:
  - [ ] All enums match design spec §5.2
  - [ ] `ClassifiedBlock` links to `TextBlockData` (not pdfrx types)
  - [ ] `DetectedPattern` has all fields for auto-prompt UI rendering
  - [ ] `ClassificationResult` is fully serializable (no FFI references)
  - [ ] `dart analyze lib/` passes
- **Skill references**: `flutter-managing-state`
- **Effort**: S (~30 min)
- **Depends on**: TASK-202

---

### TASK-204: Create ExtractionProfile model
- **Priority**: 1
- **Files**: `CREATE: lib/services/extraction_profile.dart`
- **Action**: Create:
  - `enum FootnoteHandling { skip, inline, endOfChapter }`
  - `ExtractionProfile` — per-document user overrides: `Map<BlockClassification, BlockDisposition> globalRules`, `bool ignorePageNumbers`, `bool ignoreRunningHeaders`, `bool ignoreRunningFooters`, `FootnoteHandling footnoteHandling`. Include `toJson()`, `fromJson()`, and `applyTo(ClassificationResult)` method that updates dispositions per user choices.
- **Acceptance criteria**:
  - [ ] JSON round-trip preserves all fields
  - [ ] `applyTo()` correctly overrides dispositions in a `ClassificationResult`
  - [ ] Default profile: ignorePageNumbers=true, ignoreRunningHeaders=true, ignoreRunningFooters=true, footnoteHandling=skip
  - [ ] `dart analyze lib/` passes
- **Skill references**: `flutter-managing-state`, `flutter-working-with-databases`
- **Effort**: S (~30 min)
- **Depends on**: TASK-203

---

### TASK-205: Replace `pdfExtract()` with structured extraction
- **Priority**: 1
- **Files**: `lib/services/pdf_extractor.dart`
- **Action**: Add `extractStructured(String filePath)` function that:
  1. Opens PDF via `PdfDocument.openFile(filePath)`
  2. For each page: calls `page.loadStructuredText()` (falls back to `page.loadText()` on failure)
  3. Converts `PdfPageText.fragments` → `List<TextBlockData>` with estimated font size from median charRect height
  4. Returns `List<PageAnalysis>` — plain Dart objects, no FFI handles
  5. Disposes document in `finally` block

  Modify `pdfExtract()` to use `extractStructured()` internally:
  - Extract structured data
  - Run classification in `Isolate.run()` (placeholder — full classification in Sprint 2)
  - Assemble to `ExtractedDocument` (placeholder — full assembly in Sprint 3)
  - For Sprint 1: classification/assembly are identity transforms (all blocks → bodyText → same output as before)

  Keep `extractPdfInIsolate()` and `extractPdfPagesInIsolate()` signatures unchanged (backward compatible).
- **Acceptance criteria**:
  - [ ] `extractStructured()` returns `List<PageAnalysis>` with fragment data from `loadStructuredText()`
  - [ ] Font size estimated from median `charRect.height` per fragment
  - [ ] Falls back to `loadText()` if `loadStructuredText()` returns null/empty
  - [ ] `pdfExtract()` still produces `ExtractedDocument` (same output shape)
  - [ ] No pdfrx FFI calls inside `Isolate.run()`
  - [ ] Document disposed in `finally` block
  - [ ] `dart analyze lib/` passes
  - [ ] Existing tests still pass (`flutter test test/services/`)
- **Skill references**: `flutter-handling-concurrency`
- **Effort**: M (~1.5 hours)
- **Depends on**: TASK-202

---

### TASK-206: Unit tests for data models
- **Priority**: 1
- **Files**: `CREATE: test/services/text_block_data_test.dart`, `CREATE: test/services/extraction_profile_test.dart`
- **Action**: Test:
  - `TextBlockData` JSON round-trip (all fields preserved)
  - `TextBlockData` computed properties (width, height, centerY)
  - `ExtractionProfile` JSON round-trip
  - `ExtractionProfile.applyTo()` correctly overrides dispositions
  - `BlockClassification` and `BlockDisposition` enum serialization
- **Acceptance criteria**:
  - [ ] ≥8 test cases covering serialization, computed properties, apply logic
  - [ ] All tests pass
  - [ ] `dart analyze test/` passes
- **Skill references**: `flutter-testing-apps`
- **Effort**: S (~30 min)
- **Depends on**: TASK-202, TASK-203, TASK-204

---

## Sprint 2: Classification Engine

### TASK-207: Create ClassificationEngine with isolate entry point
- **Priority**: 2
- **Files**: `CREATE: lib/services/classification_engine.dart`
- **Action**: Create `ClassificationEngine` with:
  - Static `classify(List<PageAnalysis> pages)` → `ClassificationResult` — the top-level function called via `Isolate.run()`
  - Internal pipeline: dominant font detection → spatial zone setup → header/footer detection → page number detection → heading classification → body text classification → result assembly
  - All input/output is plain Dart (no FFI handles)
  - `// P[N] Grade [X]` traceability comments on all thresholds
- **Acceptance criteria**:
  - [ ] `classify()` is a top-level function (isolate-safe)
  - [ ] Accepts `List<PageAnalysis>`, returns `ClassificationResult`
  - [ ] Contains no pdfrx imports
  - [ ] Skeleton pipeline structure present (individual detectors can be stubs)
  - [ ] `dart analyze lib/` passes
- **Skill references**: `flutter-handling-concurrency`
- **Effort**: M (~1 hour)
- **Depends on**: TASK-203

---

### TASK-208: Implement dominant font detection
- **Priority**: 2
- **Files**: `lib/services/classification_engine.dart`
- **Action**: Implement `_detectDominantFontSize(List<PageAnalysis> pages)`:
  1. Collect `estimatedFontSize` from every `TextBlockData` (skip empty text)
  2. Round to nearest 0.5pt for bucketing
  3. Return the bucket with highest frequency
  4. Heading threshold = result × 1.20
- **Acceptance criteria**:
  - [ ] Returns the statistical mode of fragment font sizes
  - [ ] Rounding to 0.5pt prevents floating-point scatter
  - [ ] Empty/whitespace-only fragments excluded
  - [ ] `dart analyze lib/` passes
- **Skill references**: None
- **Effort**: S (~30 min)
- **Depends on**: TASK-207

---

### TASK-209: Implement header/footer detection
- **Priority**: 2
- **Files**: `lib/services/classification_engine.dart`
- **Action**: Implement `_detectHeadersFooters(List<PageAnalysis> pages)` per design spec §5.3:
  1. Define zones: top 12% = header, bottom 12% = footer
  2. Collect candidate fragments per page
  3. Separate odd/even pages
  4. Fuzzy-match candidates across pages (Levenshtein ratio ≥ 0.70)
  5. Require ≥3 consecutive pages AND ≥50% of group
  6. Produce `DetectedPattern` entries for auto-prompt UI
  7. Classify matching fragments as `runningHeader` / `runningFooter`

  Implement `_levenshteinRatio(String a, String b)` helper.
- **Acceptance criteria**:
  - [ ] Header zone = top 12% of page height
  - [ ] Footer zone = bottom 12% of page height
  - [ ] Odd and even pages analyzed separately
  - [ ] Fuzzy match threshold = 0.70 Levenshtein ratio
  - [ ] Requires ≥3 pages AND ≥50% of group
  - [ ] Produces `DetectedPattern` with sampleText
  - [ ] Confidence = levenshteinRatio × (matchCount / totalPages)
  - [ ] `dart analyze lib/` passes
- **Skill references**: None
- **Effort**: L (~2 hours)
- **Depends on**: TASK-207

---

### TASK-210: Implement page number detection
- **Priority**: 2
- **Files**: `lib/services/classification_engine.dart`
- **Action**: Implement `_detectPageNumbers(...)` per design spec §5.3 step 5:
  1. Filter header/footer candidates matching page number regexes
  2. Extract numeric values
  3. Validate monotonically increasing sequence (gaps ≤ 2)
  4. If valid sequence covers ≥50% of pages: classify as `pageNumber` (confidence 0.90)
  5. Produce `DetectedPattern` entry
- **Acceptance criteria**:
  - [ ] Matches patterns: bare integer, roman numerals, "Page N", "N of M", "- N -"
  - [ ] Validates sequential ordering (gaps ≤ 2)
  - [ ] Requires ≥50% page coverage
  - [ ] Confidence = 0.90 for valid sequences
  - [ ] Standalone numbers in body text NOT classified as page numbers
  - [ ] `dart analyze lib/` passes
- **Skill references**: None
- **Effort**: M (~1 hour)
- **Depends on**: TASK-209

---

### TASK-211: Implement body column detection and heading classification
- **Priority**: 2
- **Files**: `lib/services/classification_engine.dart`
- **Action**: Implement:
  1. `_detectBodyColumn(List<PageAnalysis> pages)`: compute dominant left/right margins (mode ±2% tolerance). Fragments outside body column → `marginalia` (confidence 0.50, askUser).
  2. Heading classification: fragments with `estimatedFontSize ≥ dominantFontSize × 1.20` → `heading` (confidence 0.75).
  3. Remaining unclassified fragments in body column → `bodyText` (confidence 0.85).
- **Acceptance criteria**:
  - [ ] Body column computed from margin statistics
  - [ ] Marginalia flagged for fragments outside body column
  - [ ] Headings detected by ≥20% font size delta
  - [ ] Remaining fragments default to bodyText
  - [ ] All classifications have appropriate confidence scores
  - [ ] `dart analyze lib/` passes
- **Skill references**: None
- **Effort**: M (~1 hour)
- **Depends on**: TASK-208

---

### TASK-212: Unit tests for ClassificationEngine
- **Priority**: 2
- **Files**: `CREATE: test/services/classification_engine_test.dart`
- **Action**: Create mock `PageAnalysis` data and test:
  1. Dominant font detection picks the most common font size
  2. Header detected when same text appears in top 12% across 5+ pages
  3. Footer detected when same text appears in bottom 12% across 5+ pages
  4. Page numbers detected for sequential integers in footer zone
  5. Page numbers NOT detected for non-sequential numbers
  6. Headings detected for fragments with font size ≥1.2× body
  7. Marginalia flagged for fragments outside body column
  8. Small PDF (1–3 pages) produces no cross-page classifications
  9. Levenshtein ratio computed correctly for fuzzy matching
  10. Empty document produces empty result
- **Acceptance criteria**:
  - [ ] ≥10 test cases
  - [ ] All tests pass
  - [ ] Mock data covers: tagged-equivalent, untagged, edge cases
  - [ ] `dart analyze test/` passes
- **Skill references**: `flutter-testing-apps`
- **Effort**: L (~2 hours)
- **Depends on**: TASK-207, TASK-208, TASK-209, TASK-210, TASK-211

---

## Sprint 3: Text Assembly + Integration

### TASK-213: Create TextAssembler
- **Priority**: 3
- **Files**: `CREATE: lib/services/text_assembler.dart`
- **Action**: Create `TextAssembler.assemble()`:
  1. Accept `ClassificationResult` + `ExtractionProfile` (user overrides)
  2. Apply profile overrides to dispositions
  3. Iterate classified blocks in page order, then reading order within page
  4. Skip blocks with `exclude` disposition
  5. Apply text cleaning: dehyphenation, whitespace normalization, Unicode NFC, page-break stitching
  6. Split cleaned text into sentences using existing `_textToSentences()` logic
  7. Insert `PageBoundary` markers at page transitions
  8. Return `ExtractedDocument` (same shape as current pipeline)
- **Acceptance criteria**:
  - [ ] Output is `ExtractedDocument` with `sentences`, `pageBoundaries`, `totalPages`
  - [ ] Excluded blocks are omitted
  - [ ] Dehyphenation: line-end hyphens removed; compound-word hyphens preserved (both fragments ≥3 chars)
  - [ ] Whitespace normalized (multiple spaces → single, 3+ newlines → double)
  - [ ] Page-break stitching: mid-sentence page breaks joined seamlessly
  - [ ] `dart analyze lib/` passes
- **Skill references**: `flutter-handling-concurrency`
- **Effort**: M (~1.5 hours)
- **Depends on**: TASK-203, TASK-204

---

### TASK-214: Wire new pipeline into PreprocessingQueue
- **Priority**: 3
- **Files**: `lib/services/preprocessing_queue.dart`, `lib/services/pdf_extractor.dart`
- **Action**: Update the preprocessing pipeline:
  1. Phase 1 (Preview) remains unchanged — quick `loadText()` for first 3 pages
  2. Phase 2 (Background Completion) now uses `extractStructured()` to get `List<PageAnalysis>` for all pages
  3. Phase 3 (Classification) runs `Isolate.run(() => ClassificationEngine.classify(pages))`
  4. Phase 4 (Assembly) uses `TextAssembler.assemble()` with default `ExtractionProfile`
  5. Store `ExtractedDocument` via existing section store
  6. If stored profile exists, apply it; otherwise use defaults
  7. Auto-prompt trigger: if `classificationResult.detectedPatterns` is non-empty with confidence ≥ 0.6, flag the document for import summary (Sprint 4 wires the UI)
- **Acceptance criteria**:
  - [ ] Preview phase still works for fast library display
  - [ ] Full extraction uses `loadStructuredText()`
  - [ ] Classification runs in `Isolate.run()`
  - [ ] Assembly produces `ExtractedDocument` stored via SectionStore
  - [ ] Existing profile reused on re-import
  - [ ] No pdfrx FFI calls in isolate
  - [ ] `dart analyze lib/` passes
  - [ ] Existing preprocessing tests still pass
- **Skill references**: `flutter-handling-concurrency`
- **Effort**: L (~2 hours)
- **Depends on**: TASK-205, TASK-207, TASK-213

---

### TASK-215: Text cleaning rules
- **Priority**: 3
- **Files**: `lib/services/text_assembler.dart`
- **Action**: Implement text cleaning helper functions:
  1. `dehyphenate(String current, String next)`: if `current` ends with hyphen and `next` starts lowercase, join and remove hyphen. Exception: preserve if both fragments ≥3 characters (compound word heuristic).
  2. `normalizeWhitespace(String text)`: collapse multiple spaces → single, 3+ newlines → double newline.
  3. `normalizeUnicode(String text)`: NFC normalization. Replace ﬁ→fi, ﬂ→fl ligatures.
  4. `stitchPageBreak(String lastWord, String firstWord)`: if last word has no terminal punctuation, join with single space.
- **Acceptance criteria**:
  - [ ] Dehyphenation removes line-end hyphens but preserves "well-known"
  - [ ] Whitespace normalized consistently
  - [ ] Ligatures replaced
  - [ ] Page break stitching joins mid-sentence breaks
  - [ ] Unit tests for each helper (in TASK-216)
  - [ ] `dart analyze lib/` passes
- **Skill references**: None
- **Effort**: S (~45 min)
- **Depends on**: TASK-213

---

### TASK-216: Integration test: full pipeline
- **Priority**: 3
- **Files**: `CREATE: integration_test/pdf_import_test.dart`, `CREATE: test/services/text_assembler_test.dart`
- **Action**:
  - Unit tests for `TextAssembler`: cleaning rules, assembly with mock ClassificationResult, excluded blocks omitted, page boundaries correct.
  - Integration test: open real PDF → `extractStructured()` → `ClassificationEngine.classify()` → `TextAssembler.assemble()` → verify `ExtractedDocument` has sentences without page numbers/headers.
- **Acceptance criteria**:
  - [ ] Unit test: assembler produces correct sentences from mock data
  - [ ] Unit test: excluded blocks omitted
  - [ ] Unit test: page boundaries placed at page transitions
  - [ ] Unit test: dehyphenation, whitespace, ligature cleaning verified
  - [ ] Integration test: end-to-end pipeline produces clean text
  - [ ] `flutter test` passes
- **Skill references**: `flutter-testing-apps`
- **Effort**: M (~1.5 hours)
- **Depends on**: TASK-213, TASK-214, TASK-215

---

## Sprint 4: Auto-Prompt UI

### TASK-217: Create Riverpod state for import flow
- **Priority**: 4
- **Files**: `CREATE: lib/store/import_state.dart`
- **Action**: Create:
  - `enum ImportPhase { extracting, classifying, reviewing, assembling, ready, error }`
  - `ImportState` — holds filePath, phase, extractionProgress (0.0–1.0), ClassificationResult?, user overrides map, errorMessage.
  - `ImportNotifier` (AsyncNotifier, auto-dispose) — methods: `startImport(filePath)`, `updateOverride(BlockClassification, BlockDisposition)`, `confirmImport()`, `dismiss()`.
  - `startImport()` orchestrates: extract → classify → set phase to `reviewing`.
  - `confirmImport()` applies overrides → assemble → persist profile → set phase to `ready`.
  - `dismiss()` applies defaults → assemble → set phase to `ready`.
- **Acceptance criteria**:
  - [ ] `ImportNotifier` is auto-dispose (cleans up when import screen exits)
  - [ ] `startImport()` runs extraction on main isolate, classification in `Isolate.run()`
  - [ ] Phase transitions are correct
  - [ ] User overrides applied before assembly
  - [ ] Profile persisted on confirm
  - [ ] Dismiss applies defaults without user review
  - [ ] `dart analyze lib/` passes
- **Skill references**: `riverpod-providers`, `riverpod-auto-dispose`, `flutter-managing-state`
- **Effort**: M (~1.5 hours)
- **Depends on**: TASK-214

---

### TASK-218: Create `/import-summary` route and screen scaffold
- **Priority**: 4
- **Files**: `CREATE: lib/screens/import_summary_screen.dart`, `lib/navigation/app_router.dart`
- **Action**:
  - Add `/import-summary` route to `app_router.dart` with `extra: String` (filePath parameter).
  - Create `ImportSummaryScreen` (ConsumerStatefulWidget):
    - Watches `importStateProvider`
    - Shows progress during extracting/classifying phases (neumorphic pulse — no CircularProgressIndicator)
    - Shows detection list during reviewing phase
    - Shows assembly progress during assembling phase
    - Navigates to `/read?path=...` when phase = ready
  - Shell surface world tokens only (Rule 7, copilot patch Rule 29+)
  - Check `isReducedMotion(context)` for all animations (Rule 5)
- **Acceptance criteria**:
  - [ ] Route registered at `/import-summary`
  - [ ] Screen navigates correctly from library
  - [ ] Progress state uses neumorphic pulse (no Material loading widgets)
  - [ ] Shell surface world tokens only
  - [ ] All animations respect reduced motion
  - [ ] Back button dismisses and applies defaults
  - [ ] `dart analyze lib/` passes
- **Skill references**: `flutter-building-layouts`, `flutter-implementing-navigation-and-routing`
- **Effort**: M (~1 hour)
- **Depends on**: TASK-217

---

### TASK-219: Implement detection summary cards
- **Priority**: 4
- **Files**: `lib/screens/import_summary_screen.dart`
- **Action**: During the `reviewing` phase, render a scrollable list of detection cards:
  - Title: document title (from metadata or first heading fragment)
  - Stats: "N pages analyzed", "~X words (est. Y hours at Z WPM)"
  - Detection cards: one per `DetectedPattern` with confidence ≥ 0.6
  - Each card: icon + description + page count + sample text
  - Sorted by impact: pageNumber → runningHeader → runningFooter → footnote → marginalia → other
  - Cards use `SpeedyBoyDecorations.raisedDecoration(shellSurface, sizeSmall)`
  - Typography: `SpeedyBoyTypography.bodyMedium` for descriptions, `.titleMedium` for document title
- **Acceptance criteria**:
  - [ ] Detection cards rendered for patterns with confidence ≥ 0.6
  - [ ] Cards sorted by impact order
  - [ ] Sample text shown (truncated if > 50 chars)
  - [ ] Page count context (e.g., "on 290/312 pages")
  - [ ] Neumorphic card styling per design system
  - [ ] Typography from `SpeedyBoyTypography`
  - [ ] `dart analyze lib/` passes
- **Skill references**: `flutter-building-layouts`, `flutter-theming-apps`
- **Effort**: M (~1 hour)
- **Depends on**: TASK-218

---

### TASK-220: Implement accept/reject toggles per detection
- **Priority**: 4
- **Files**: `lib/screens/import_summary_screen.dart`, `lib/store/import_state.dart`
- **Action**: Add toggle controls to each detection card:
  - Binary toggle: [Ignore ✓] / [Keep] for headers, footers, page numbers
  - Tri-state toggle: [Skip ✓] / [Keep] for footnotes
  - Toggling calls `importNotifier.updateOverride(classification, disposition)`
  - "Import Now" button at bottom: calls `importNotifier.confirmImport()`
  - Default selections match `DetectedPattern.defaultDisposition`
  - Reading time estimate shown below cards
  - Reading time delta shown: "Ignoring headers saves ~3 minutes"
- **Acceptance criteria**:
  - [ ] Each detection card has working toggle
  - [ ] Toggle state persisted in `ImportState.userOverrides`
  - [ ] "Import Now" triggers confirm flow
  - [ ] Default selections are pre-set correctly
  - [ ] Reading time estimate displayed
  - [ ] Time saved estimate displayed
  - [ ] Toggle uses `shellAccent` token for selected state
  - [ ] `dart analyze lib/` passes
- **Skill references**: `flutter-building-layouts`, `flutter-building-forms`
- **Effort**: M (~1 hour)
- **Depends on**: TASK-219

---

### TASK-221: Wire import summary into library PDF open flow
- **Priority**: 4
- **Files**: `lib/screens/library_screen.dart`, `lib/services/preprocessing_queue.dart`
- **Action**: When a user taps a PDF in the library:
  1. If the document has a stored `ExtractionProfile`: skip import summary → navigate directly to `/read?path=...` (existing behavior, just uses smart-extracted data).
  2. If no profile exists AND background classification detected patterns with confidence ≥ 0.6: navigate to `/import-summary` instead of `/read`.
  3. If no profile exists AND no significant patterns detected: navigate directly to `/read` (defaults applied silently).
  4. Add long-press option "Re-import with options" that always shows import summary (clears stored profile).
- **Acceptance criteria**:
  - [ ] First-time open with detections → goes to import summary
  - [ ] First-time open without detections → goes directly to reading
  - [ ] Re-open with stored profile → goes directly to reading
  - [ ] Long-press "Re-import" → clears profile, shows import summary
  - [ ] Navigation uses go_router (Rule 14)
  - [ ] `dart analyze lib/` passes
- **Skill references**: `flutter-implementing-navigation-and-routing`
- **Effort**: M (~1 hour)
- **Depends on**: TASK-218, TASK-220

---

### TASK-222: Widget tests for import summary screen
- **Priority**: 4
- **Files**: `CREATE: test/screens/import_summary_screen_test.dart`
- **Action**: Test:
  1. Extracting phase shows progress indicator (neumorphic pulse)
  2. Reviewing phase shows detection cards
  3. Detection cards only shown for patterns with confidence ≥ 0.6
  4. Toggle changes update import state
  5. "Import Now" triggers confirm and navigates
  6. Back button triggers dismiss and navigates
  7. Shell surface world tokens used (no stage tokens)
- **Acceptance criteria**:
  - [ ] ≥7 widget tests
  - [ ] All tests pass
  - [ ] Provider overrides used for mock data (Riverpod testing pattern)
  - [ ] `dart analyze test/` passes
- **Skill references**: `flutter-testing-apps`, `riverpod-testing`
- **Effort**: M (~1 hour)
- **Depends on**: TASK-218, TASK-219, TASK-220

---

## Sprint 4 Bonus: Profile Persistence

### TASK-223: Add profile persistence to SectionStore
- **Priority**: 4
- **Files**: `lib/services/section_store.dart`
- **Action**: Add two methods to `SectionStore`:
  - `saveProfile(String fileHash, ExtractionProfile profile)` — writes `profile.json` to `pdf_store/<hash>/`
  - `loadProfile(String fileHash)` → `ExtractionProfile?` — reads `profile.json`, returns null if not found
  - Both run file I/O via `Isolate.run()` (Rule 11)
- **Acceptance criteria**:
  - [ ] Profile saved as JSON in document's store directory
  - [ ] Profile loaded on re-import
  - [ ] Returns null for missing profile (no crash)
  - [ ] File I/O in isolate
  - [ ] `dart analyze lib/` passes
- **Skill references**: `flutter-handling-concurrency`, `flutter-working-with-databases`
- **Effort**: S (~30 min)
- **Depends on**: TASK-204
