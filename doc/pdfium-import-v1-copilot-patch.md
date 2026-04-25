# Speedy Boy — Copilot Instructions: PDFium Import v1 Patch

Apply these changes to `.github/copilot-instructions.md` on top of the existing v4 content.

---

## New Rules (29–35)

29. **pdfrx stays primary.** All PDF text extraction and page rendering goes through `pdfrx`. `pdfrx_engine` (raw FFI) is investigation-only — never add it as a direct dependency without a benchmark proving `pdfrx`'s API is insufficient for a specific capability. Mark each investigation case with `// PDFIUM-FLAG — benchmark required before adopting pdfrx_engine`.

30. **pdfrx on main isolate only.** `pdfrx` uses FFI — never call `PdfDocument.openFile()`, `page.loadText()`, `page.loadStructuredText()`, or any FFI-backed pdfrx method inside `Isolate.run()` or `Isolate.spawn()`. Extract structured data on the main isolate, serialize to plain Dart objects (`PageAnalysis`, `TextBlockData`), then pass to classification isolates.

31. **Classification in isolates.** `ClassificationEngine.classify()` runs in `Isolate.run()` with serializable input (`List<PageAnalysis>`) and output (`ClassificationResult`). No pdfrx handles, `PdfRect`, `PdfPageText`, or any FFI objects cross isolate boundaries.

32. **ExtractionProfile per document.** Classification user overrides are persisted as `profile.json` in `pdf_store/<hash>/` alongside the section cache. On re-import, reuse the stored profile (skip auto-prompt). Never auto-apply one document's profile to a different document.

33. **Confidence threshold for prompts.** Only show detections in the auto-prompt UI when confidence ≥ 0.6. Below that threshold, silently apply the default disposition. This prevents information overload.

34. **Import summary is non-blocking.** If the user dismisses the import summary (Back button or swipe), apply default dispositions and proceed to reading. Never force the user through the full import flow to start reading.

35. **Rect-height font heuristic.** Approximate font size from median `PdfRect` height of a fragment's `charRects`. Heading detection uses a ≥20% size delta from the dominant body font size. Do not add `pdfrx_engine` for `FPDFText_GetFontInfo` without a benchmark proving the rect-height heuristic is insufficient (precision < 0.90 or recall < 0.85).

36. **Serialize before isolate boundary.** Before passing extracted data to `Isolate.run()`, convert all pdfrx types (`PdfPageText`, `PdfPageTextFragment`, `PdfRect`) to plain Dart objects (`PageAnalysis`, `TextBlockData`). Never send FFI-backed objects across isolate boundaries.

37. **Dispose PdfDocument promptly.** Always dispose `PdfDocument` handles in a `finally` block after extraction. Never hold document handles open across screen transitions or across the import flow lifecycle.

38. **Page number sequentiality required.** A standalone number in body text is NOT a page number. Classification as `pageNumber` requires the candidate to be in a header/footer zone AND part of a monotonically increasing sequence across pages (gaps ≤ 2).

39. **Odd/even page headers separate.** Header and footer detection must analyze odd and even pages independently. Many printed books use different headers on odd vs even pages (recto vs verso).

40. **Import summary uses shell surface world.** The import summary screen is shell chrome — use only `shellSurface`, `shellSurfaceVariant`, `shellAccent`, `shellText`, `shellTextSecondary` tokens. Never use `stage*` tokens on the import screen (Rule 7 enforcement).

---

## Changes to Existing Rules

### Rule 8 Clarification (Do/Don't #8 update)

The original PDFium design spec's Do/Don't #8 says "Run extraction in an isolate — never block the UI thread." This conflicts with the FFI constraint.

**Clarified**: pdfrx FFI extraction runs on the main isolate (unavoidable). Classification and assembly run in compute isolates. The extraction itself is async (`Future`-based) so it does not block the UI thread's event loop — it yields between pages. The heavy CPU work (cross-page comparison, string matching) runs in true isolates.

---

## New Design System Files (PDFium Import v1)

```
lib/services/classification_engine.dart → ClassificationEngine (Isolate.run entry point)
lib/services/extraction_profile.dart    → ExtractionProfile, FootnoteHandling models
lib/services/text_assembler.dart        → TextAssembler: classified blocks → ExtractedDocument
lib/screens/import_summary_screen.dart  → Auto-prompt UI (detection cards, toggles)
lib/store/import_state.dart             → ImportState, ImportPhase, Riverpod notifier
```

---

## New Enums (in `lib/services/models.dart`)

```dart
enum BlockClassification {
  bodyText, heading, runningHeader, runningFooter, pageNumber,
  footnote, blockQuote, listItem, marginalia, placeholder, unknown,
}

enum BlockDisposition { include, exclude, askUser }
```

## New Enum (in `lib/services/extraction_profile.dart`)

```dart
enum FootnoteHandling { skip, inline, endOfChapter }
```

---

## New Route

| Route | Screen | Parameters |
|-------|--------|------------|
| `/import-summary` | ImportSummaryScreen | `extra: String` (filePath) |

---

## New SpeedyBoyTiming Tokens (PDFium Import v1)

```dart
// ── PDFium Import: Auto-Prompt UI ──
// P34 Grade D — tunable: detection card appearance animation
static const int importCardFadeMs = 200;
// P34 Grade D — tunable: neumorphic pulse cycle during extraction/classification
static const int importProgressPulseMs = 1200;
// P10 Grade C — max wait before assembly timeout (matches existing _extractionTimeout pattern)
static const int importAssemblyTimeoutMs = 30000;
```

---

## Modified Files Summary

| File | Change |
|------|--------|
| `lib/services/pdf_extractor.dart` | Replace `pdfExtract()` internals with `loadStructuredText()` pipeline. Add `extractStructured()` returning `List<PageAnalysis>`. |
| `lib/services/models.dart` | Add `TextBlockData`, `PageAnalysis`, `BlockClassification`, `BlockDisposition`, `ClassifiedBlock`, `DetectedPattern`, `ClassificationResult` |
| `lib/services/preprocessing_queue.dart` | Wire classification → user review → assembly phases after full extraction |
| `lib/services/section_store.dart` | Add `saveProfile()` / `loadProfile()` for `ExtractionProfile` persistence |
| `lib/navigation/app_router.dart` | Add `/import-summary` route |
| `lib/design/timing_tokens.dart` | Add 3 import-related timing tokens |

---

## Updated Skill → Task Mapping (PDFium Import additions)

| Domain | Skill File | Import Tasks |
|--------|-----------|--------------|
| State management | `flutter-managing-state` | ImportState notifier, import flow lifecycle |
| Riverpod providers | `riverpod-providers` | importStateProvider creation |
| Riverpod auto-dispose | `riverpod-auto-dispose` | Import state cleanup after navigation away |
| Layout | `flutter-building-layouts` | Import summary screen, detection cards |
| Theming | `flutter-theming-apps` | Shell surface world compliance on import UI |
| Concurrency | `flutter-handling-concurrency` | Isolate.run for ClassificationEngine, pdfrx main-thread extraction |
| Testing | `flutter-testing-apps` | Classification unit tests, assembly tests, widget tests |
| Navigation | `flutter-implementing-navigation-and-routing` | /import-summary route, library→import→reading flow |
| Databases | `flutter-working-with-databases` | ExtractionProfile persistence in section store |

---

## Import Summary UI — Surface World Compliance

The import summary screen is **shell chrome** (not the reading stage). All styling uses shell surface world tokens:

| Element | Token |
|---------|-------|
| Background | `SpeedyBoyTokens.shellSurface` |
| Card surface | `SpeedyBoyTokens.shellSurfaceVariant` |
| Card shadow | `SpeedyBoyDecorations.raisedDecoration(shellSurface, sizeSmall)` |
| Title text | `SpeedyBoyTypography.titleMedium` with `SpeedyBoyTokens.shellText` |
| Body text | `SpeedyBoyTypography.bodyMedium` with `SpeedyBoyTokens.shellTextSecondary` |
| Selected toggle | `SpeedyBoyTokens.shellAccent` |
| Import button | `SpeedyBoyDecorations.raisedDecoration(shellAccent, sizeMedium)` |
| Progress pulse | Neumorphic pulse animation (existing `A-008` from `animations.dart`) |
