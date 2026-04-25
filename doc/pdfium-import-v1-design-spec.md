# Speedy Boy — PDFium Smart Import Design Spec (v1)

**Version**: 1.0
**Feature**: PDF Import with Intelligent Noise Classification
**Status**: Active
**Scope**: Milestones M1–M3 (Skeleton + Classification Engine + Auto-Prompt UI)
**Depends on**: Speedy Boy v4 core (RSVP engine, PreprocessingQueue, SectionStore)
**Out of scope**: M4–M8 (visual region selector, manual text selection, profile persistence, chapter-skip navigation, RTL/CJK edge cases)

---

## 1. Problem Statement

Speedy Boy extracts text from PDFs using `pdfrx`'s `page.loadText()` — a simple full-page text dump. This approach imports everything: body prose, headers, footers, page numbers, watermarks, captions, and decorative text. The result is a polluted RSVP stream where the reader encounters "CHAPTER 12" and "Page 147" as words to speed-read. This is the #1 user complaint for PDF imports.

This spec defines a **smart import pipeline** that uses `pdfrx`'s structured text APIs to decompose PDF pages into semantic regions, classify them as signal (body text, headings) or noise (headers, footers, page numbers), and let the user confirm or override those classifications before feeding clean text into the existing RSVP pipeline.

### What Changes

| Before | After |
|--------|-------|
| `page.loadText()` → flat text dump | `page.loadStructuredText()` → text blocks with bounding boxes + reading order |
| No classification | Cross-page heuristics classify each block as body/heading/header/footer/pageNumber/etc. |
| No user input during import | Auto-prompt UI shows detections and lets user accept/reject |
| Headers/footers/page numbers pollute RSVP | Noise excluded by default; user can override |
| Output: `ExtractedDocument` | Output: same `ExtractedDocument` (backward compatible) |

---

## 2. Goals and Non-Goals

### Goals (M1–M3)

1. Replace `pdfExtract()` with structured extraction using `page.loadStructuredText()`.
2. Classify text blocks as body text, headings, running headers, running footers, page numbers, footnotes, or unknown.
3. Implement cross-page heuristics: repeating header/footer detection, page number sequence validation, dominant font detection, body column detection.
4. Present an auto-prompt import summary screen where users confirm or override detections.
5. Produce the same `ExtractedDocument` output shape consumed by the existing RSVP engine.
6. Persist an `ExtractionProfile` per document so re-imports don't require reconfiguration.

### Non-Goals (M1–M3)

- Visual region selection with overlay colors (M4).
- Manual text selection with drag handles (M5).
- Chapter-skip navigation integration (M7).
- Multi-column layout detection (M8 — single-column assumed for v1).
- RTL/CJK text layout adaptation (M8).
- OCR of image-only PDFs.
- Structure tree access via `pdfrx_engine` FFI (Phase 2 investigation — see §11).

---

## 3. Package Architecture

### Decision: pdfrx stays primary

`pdfrx` (^2.2.24) is already the app's PDF package. It provides:

| Capability | pdfrx API | Notes |
|-----------|-----------|-------|
| Full-page text | `page.loadText()` → `PdfPageRawText.fullText` | Current approach |
| Structured text + reading order | `page.loadStructuredText()` → `PdfPageText.fragments` | **New** — the upgrade path |
| Character bounding boxes | `PdfPageRawText.charRects: List<PdfRect>` | Per-character positioning |
| Text direction | `PdfPageTextFragment.direction` → `PdfTextDirection` | LTR, RTL, VRTL, unknown |
| Fragment-level bounding boxes | `PdfPageTextFragment.bounds: PdfRect` | Block-level positioning |
| Page rendering | `PdfViewer.file()` widget | Used by `range_picker_screen.dart` |
| Document loading | `PdfDocument.openFile()` | FFI — main isolate only |

### pdfrx_engine: Investigation Only

`pdfrx_engine` (0.3.9, transitive dependency) exposes raw PDFium FFI bindings. It is **not** used in M1–M3. Three capabilities are flagged for Phase 2 investigation, each requiring a benchmark before adoption:

| Capability | pdfrx Gap | Workaround | Benchmark Gate |
|-----------|-----------|------------|----------------|
| Per-character font info (`FPDFText_GetFontInfo`) | pdfrx only gives `PdfRect` height as font-size proxy | Heading detection via rect-height delta (≥20% above body median) | Compare heading detection accuracy on 5 untagged PDFs: rect-height vs FFI font query. Accept rect-height if ≥90% accuracy. |
| Structure tree (`FPDF_StructTree_*`) | pdfrx does not expose structure tree walking | Spatial heuristics only (header/footer zones, font-size delta) | Compare classification accuracy on 3 well-tagged PDFs: heuristics-only vs structure-tree-assisted. |
| Page geometry boxes (CropBox/TrimBox) | pdfrx may not expose these | Use full page dimensions for all spatial analysis | Low priority — only matters for scanned PDFs with bleed artifacts. |

### Isolate Architecture

pdfrx uses FFI — all calls must happen on the **main isolate**. The pipeline splits work:

```
Main Isolate                          Compute Isolate
─────────────                         ─────────────────
pdfrx: PdfDocument.openFile()
  │
  ├── page.loadStructuredText()
  │   → PdfPageText per page
  │
  ├── Serialize to List<PageAnalysis>
  │   (plain Dart objects, no FFI handles)
  │
  ├──────── Isolate.run(classify) ───────▶ ClassificationEngine
  │                                        ├── Header/footer detection
  │                                        ├── Page number detection
  │                                        ├── Dominant font analysis
  │                                        ├── Body column detection
  │                                        └── Returns List<ClassifiedPage>
  │◀──────────────────────────────────────
  │
  ├── TextAssembler: classified blocks
  │   → ExtractedDocument
  │
  └── document.dispose()
```

**Critical constraint**: No `PdfDocument`, `PdfPage`, `PdfPageText`, or `PdfRect` objects cross the isolate boundary. The main isolate serializes extracted data into plain Dart objects (`PageAnalysis`, `TextBlockData`) before sending to the classification isolate.

---

## 4. PDF Element Taxonomy

Every element type classified into **Exclude** (noise), **Preserve** (signal), or **Conditional** (user-decided).

### 4.1 Exclude by Default (Noise)

| Element | Detection Strategy | Confidence |
|---------|-------------------|------------|
| **Running headers** | Text fragments in top 12% of page height that repeat (fuzzy match, Levenshtein ratio ≥ 0.70) across ≥3 consecutive pages. | Medium (0.65–0.85) |
| **Running footers** | Text fragments in bottom 12% of page height with same fuzzy-match criterion. | Medium (0.65–0.85) |
| **Page numbers** | Isolated text fragments matching regex (`/^\s*\d+\s*$/`, `/^\s*[ivxlcdm]+\s*$/i`, `/^\s*-\s*\d+\s*-\s*$/`) in header/footer zones AND forming a monotonically increasing sequence (gaps ≤ 2). | High (0.90) if sequential |
| **Placeholder/garbage** | Text fragments where >60% of characters are non-printable or consist of repeated identical glyphs. | Medium (0.70) |
| **Bare URLs** | Text fragments matching `https?://\S+` or `www\.\S+`. Strip URL; if surrounding text is meaningful prose, preserve the prose. | High (0.90) |

### 4.2 Preserve Always (Signal)

| Element | Detection Strategy | How to Preserve |
|---------|-------------------|-----------------|
| **Body paragraphs** | Fragments using the dominant font size (statistical mode of fragment rect heights), within the body column, not in header/footer zones. | Extract as sequential text. Insert `\n\n` between paragraphs. |
| **Logical headings** | Fragments with rect height > body median by ≥20%, typically preceded/followed by vertical whitespace. | Emit as text. Mark as heading in `ClassifiedBlock` for future chapter-navigation integration. |
| **Footnotes** | Fragments in bottom zone with font size ≤ body font size, preceded by a superscript number referencing body text. | User preference: inline, end-of-chapter, or skip. Default: skip for M1–M3. |
| **Lists** | Fragments with bullet/number prefix patterns and consistent indent. | Flatten to sequential text: "1. First. 2. Second." |
| **Block quotes** | Fragments with consistent left-margin offset > body text margin. | Preserve inline. |

### 4.3 Conditional (User-Decided)

| Element | Default Disposition | Shown in Auto-Prompt? |
|---------|--------------------|-----------------------|
| **Footnotes** | Exclude | Yes — "23 footnotes found: [Skip] [Keep]" |
| **Marginalia** (text outside body column) | Exclude | Yes, if confidence ≥ 0.6 |
| **Copyright page** | Exclude | No — silently excluded |
| **Index / glossary** | Exclude | No — silently excluded |
| **Code blocks** (monospaced fragments) | Include | No — silently included |

---

## 5. Detection Engine Architecture

### 5.1 Two-Pass Pipeline (M1–M3)

Pass 3 (user confirmation) from the original spec maps to the auto-prompt UI. Passes 1 and 2 remain.

```
Pass 1: Structured Extraction (per-page, main isolate)
  ├─ Open document via pdfrx: PdfDocument.openFile()
  ├─ For each page:
  │   ├─ page.loadStructuredText() → PdfPageText
  │   ├─ Extract fragment data: text, bounds, charRects, direction
  │   ├─ Compute approximate font size per fragment: median(charRect.height)
  │   └─ page resources released after extraction
  ├─ Serialize to List<PageAnalysis> (plain Dart objects)
  └─ document.dispose()

Pass 2: Cross-Page Classification (compute isolate)
  ├─ Compute dominant font size (statistical mode across all fragments)
  ├─ Define spatial zones: header (top 12%), footer (bottom 12%), body (middle)
  ├─ Detect repeating headers (fuzzy cross-page string match, odd/even pages separate)
  ├─ Detect repeating footers (same algorithm)
  ├─ Detect page number sequences (regex + sequentiality validation)
  ├─ Classify headings (font size ≥ 1.2× body median)
  ├─ Classify remaining fragments as body text
  ├─ Assign confidence scores (0.0–1.0) to each classification
  └─ Output: ClassificationResult (list of ClassifiedBlock per page + detected patterns)
```

### 5.2 Data Structures

All structures are serializable (no FFI handles). They live in `lib/services/models.dart` alongside existing models.

```dart
/// Serializable representation of a PDF text fragment extracted by pdfrx.
/// Created from PdfPageTextFragment on the main isolate, then passed
/// to the classification isolate.
class TextBlockData {
  const TextBlockData({
    required this.pageIndex,
    required this.fragmentIndex,
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.estimatedFontSize,
    required this.direction,
  });

  final int pageIndex;
  final int fragmentIndex;
  final String text;

  /// Bounding box in PDF coordinate space (origin bottom-left, Y-up).
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Approximate font size derived from median character rect height.
  final double estimatedFontSize;

  /// Text direction: 'ltr', 'rtl', 'vrtl', or 'unknown'.
  final String direction;

  double get width => right - left;
  double get height => top - bottom;

  /// Vertical center of the fragment in PDF coordinates.
  double get centerY => (top + bottom) / 2;

  Map<String, Object?> toJson() => {
    'pageIndex': pageIndex,
    'fragmentIndex': fragmentIndex,
    'text': text,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'estimatedFontSize': estimatedFontSize,
    'direction': direction,
  };

  factory TextBlockData.fromJson(Map<String, Object?> json) {
    return TextBlockData(
      pageIndex: json['pageIndex'] as int,
      fragmentIndex: json['fragmentIndex'] as int,
      text: json['text'] as String,
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
      estimatedFontSize: (json['estimatedFontSize'] as num).toDouble(),
      direction: json['direction'] as String? ?? 'ltr',
    );
  }
}

/// All extracted data for a single page, ready for classification.
class PageAnalysis {
  const PageAnalysis({
    required this.pageIndex,
    required this.pageWidth,
    required this.pageHeight,
    required this.fragments,
  });

  final int pageIndex;
  final double pageWidth;
  final double pageHeight;
  final List<TextBlockData> fragments;
}

/// Classification applied to a text block after cross-page analysis.
enum BlockClassification {
  bodyText,
  heading,
  runningHeader,
  runningFooter,
  pageNumber,
  footnote,
  blockQuote,
  listItem,
  marginalia,
  placeholder,
  unknown,
}

/// Whether a classified block should be included in the RSVP output.
enum BlockDisposition {
  include,    // Fed into RSVP
  exclude,    // Suppressed
  askUser,    // Needs confirmation in auto-prompt UI
}

/// A text block with its classification and confidence.
class ClassifiedBlock {
  const ClassifiedBlock({
    required this.block,
    required this.classification,
    required this.disposition,
    required this.confidence,
    this.detectionReason,
  });

  final TextBlockData block;
  final BlockClassification classification;
  final BlockDisposition disposition;

  /// 0.0–1.0 confidence in the classification.
  final double confidence;

  /// Human-readable reason shown in auto-prompt UI.
  /// e.g., "Repeats on 290/312 pages" or "Matches page number sequence".
  final String? detectionReason;
}

/// A detected cross-page pattern surfaced to the user in auto-prompt.
class DetectedPattern {
  const DetectedPattern({
    required this.type,
    required this.description,
    required this.pageCount,
    required this.totalPages,
    required this.defaultDisposition,
    required this.confidence,
    this.sampleText,
  });

  final BlockClassification type;

  /// Human-readable description, e.g., "Running header: THINKING, FAST AND SLOW"
  final String description;

  /// Number of pages where this pattern was detected.
  final int pageCount;

  final int totalPages;

  /// The system's recommended disposition.
  final BlockDisposition defaultDisposition;

  final double confidence;

  /// Sample text from the first occurrence.
  final String? sampleText;
}

/// Full classification result for a document.
class ClassificationResult {
  const ClassificationResult({
    required this.classifiedPages,
    required this.detectedPatterns,
    required this.dominantFontSize,
    required this.totalPages,
  });

  /// Classified blocks grouped by page index.
  final Map<int, List<ClassifiedBlock>> classifiedPages;

  /// Cross-page patterns to show in auto-prompt UI.
  final List<DetectedPattern> detectedPatterns;

  /// The statistical mode of fragment font sizes across the document.
  final double dominantFontSize;

  final int totalPages;
}
```

### 5.3 Header/Footer Detection Algorithm

```
Input: List<PageAnalysis> for pages [0..N]
Constants:
  headerZoneRatio = 0.12  (top 12% of page height)
  footerZoneRatio = 0.12  (bottom 12% of page height)
  minConsecutivePages = 3
  levenshteinThreshold = 0.70

1. For each page, compute zones:
   headerZoneTop = pageHeight × (1 - headerZoneRatio)  // PDF coords: Y-up
   footerZoneBottom = pageHeight × footerZoneRatio

2. Collect candidate fragments per page:
   candidate_headers[page] = fragments where centerY ≥ headerZoneTop
   candidate_footers[page] = fragments where centerY ≤ footerZoneBottom

3. Separate odd and even pages (books often use different headers):
   odd_headers  = candidate_headers for odd page indices
   even_headers = candidate_headers for even page indices
   (same for footers)

4. For each candidate group (odd_headers, even_headers, odd_footers, even_footers):
   a. Normalize each candidate: lowercase, strip whitespace, strip digits
   b. For each normalized string S:
      - Count pages where S appears (fuzzy: Levenshtein ratio ≥ 0.70)
      - If count ≥ minConsecutivePages AND count/groupSize ≥ 0.5:
        → Classify as runningHeader/runningFooter
        → confidence = levenshteinRatio × (count / totalPages)
        → Create DetectedPattern with sampleText

5. Page number sub-detection within header/footer candidates:
   a. Regex patterns: /^\s*(\d+)\s*$/, /^\s*[ivxlcdm]+\s*$/i,
      /^\s*page\s+\d+\s*$/i, /^\s*-\s*\d+\s*-\s*$/
   b. Extract numeric values from matching fragments
   c. Sort by page index → validate monotonically increasing with gaps ≤ 2
   d. If valid sequence covering ≥50% of pages:
      → Classify as pageNumber (confidence = 0.90)
```

### 5.4 Body Column Detection Algorithm

```
Input: All PageAnalysis objects.

1. For each page, compute text bounding box:
   leftMargin[page] = min(fragment.left) across all fragments
   rightMargin[page] = max(fragment.right) across all fragments

2. Compute dominant margins (statistical mode ±2% of page width):
   dominantLeft = mode(leftMargin, tolerance = pageWidth × 0.02)
   dominantRight = mode(rightMargin, tolerance = pageWidth × 0.02)

3. Body column = (dominantLeft, footerZoneBottom, dominantRight, headerZoneTop)

4. Fragments with centerX outside the body column AND not classified
   as heading → flag as marginalia (confidence = 0.50, disposition = askUser)
```

**Note**: Multi-column detection is deferred to M8. For M1–M3, all pages are treated as single-column.

### 5.5 Dominant Font Size Detection

```
Input: All TextBlockData fragments across all pages.

1. Collect estimatedFontSize from every fragment (excluding empty text)
2. Round to nearest 0.5pt for bucketing
3. Compute frequency histogram
4. dominantFontSize = bucket with highest frequency
5. Heading threshold = dominantFontSize × 1.20
   Fragments with estimatedFontSize ≥ headingThreshold → classify as heading
```

### 5.6 Estimating Font Size from pdfrx

pdfrx's `PdfPageTextFragment` contains `charRects: List<PdfRect>`. Each `PdfRect` has `top` and `bottom` in PDF coordinate space (Y-up, origin bottom-left). The estimated font size for a fragment:

```dart
double estimateFontSize(List<PdfRect> charRects) {
  if (charRects.isEmpty) return 0.0;
  // Use median height to be robust against outlier characters (e.g., superscripts)
  final heights = charRects
      .map((r) => (r.top - r.bottom).abs())
      .where((h) => h > 0)
      .toList()
    ..sort();
  if (heights.isEmpty) return 0.0;
  return heights[heights.length ~/ 2]; // median
}
```

This is an approximation — `PdfRect.height` ≈ font size in PDF points, but may differ for fonts with unusual ascent/descent metrics. The ≥20% heading threshold provides margin for error.

---

## 6. Extraction Profile

An `ExtractionProfile` captures user overrides and is persisted alongside the document's section cache for reproducible re-imports.

```dart
/// How to handle footnotes in the RSVP output.
enum FootnoteHandling { skip, inline, endOfChapter }

/// Per-document extraction profile — stores user overrides.
class ExtractionProfile {
  const ExtractionProfile({
    this.globalRules = const {},
    this.ignorePageNumbers = true,
    this.ignoreRunningHeaders = true,
    this.ignoreRunningFooters = true,
    this.footnoteHandling = FootnoteHandling.skip,
  });

  /// User overrides: classification → disposition.
  /// Only entries the user explicitly changed are stored.
  final Map<BlockClassification, BlockDisposition> globalRules;

  final bool ignorePageNumbers;
  final bool ignoreRunningHeaders;
  final bool ignoreRunningFooters;
  final FootnoteHandling footnoteHandling;

  /// Merge user overrides into a ClassificationResult.
  /// Returns a new result with dispositions updated per the profile.
  ClassificationResult applyTo(ClassificationResult result) {
    // Apply global rules to each classified block
    // Respect per-classification disposition overrides
    // ...
  }

  Map<String, Object?> toJson() => { /* serialization */ };
  factory ExtractionProfile.fromJson(Map<String, Object?> json) => /* ... */;
}
```

**Persistence**: Stored as `profile.json` in the document's `pdf_store/<hash>/` directory alongside `manifest.json` and section files. On re-import, if a profile exists, offer to reuse it.

---

## 7. Auto-Prompt UI (Import Summary Screen)

### 7.1 Component Overview

After Pass 2 completes, the system navigates to `/import-summary` showing detected patterns and user controls.

```
┌─────────────────────────────────────────────┐
│  Import: "Thinking, Fast and Slow"          │
│                                             │
│  ◽ 312 pages analyzed                      │
│  ◽ ~89,400 words (est. 5.3 hours at 280    │
│    WPM)                                     │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │ ⚙ Page numbers on every page       │    │
│  │   [Ignore ✓]  [Keep]               │    │
│  ├─────────────────────────────────────┤    │
│  │ ⚙ Running header: "THINKING, FA…"  │    │
│  │   on 290/312 pages                 │    │
│  │   [Ignore ✓]  [Keep]               │    │
│  ├─────────────────────────────────────┤    │
│  │ ⚙ Running footer on 285/312 pages  │    │
│  │   [Ignore ✓]  [Keep]               │    │
│  ├─────────────────────────────────────┤    │
│  │ ⚙ 23 footnotes found               │    │
│  │   [Skip ✓]  [Keep]                 │    │
│  └─────────────────────────────────────┘    │
│                                             │
│         [Import Now]                        │
└─────────────────────────────────────────────┘
```

### 7.2 Behavioral Rules

1. Only show detections with confidence ≥ 0.6. Below that, silently apply default disposition.
2. Sort detections by impact: page numbers → headers → footers → footnotes → other.
3. Default selections match the system's recommended dispositions (Ignore for noise, Skip for footnotes).
4. "Import Now" applies current selections, assembles `ExtractedDocument`, and navigates to the reading screen.
5. If the user presses Back/dismisses, apply defaults and proceed — never force the user through the full flow.
6. Show estimated reading time: total words ÷ user's current WPM.
7. Show reading time saved: "(Ignoring headers saves ~3 minutes)".

### 7.3 State Machine

```
┌──────────────┐
│  Extracting   │ ← pdfrx loadStructuredText() in progress
│  (progress %) │
└──────┬───────┘
       │ extraction complete
       ▼
┌──────────────┐
│  Classifying  │ ← Isolate.run(classify) in progress
└──────┬───────┘
       │ classification complete
       ▼
┌──────────────┐
│  Reviewing    │ ← User sees auto-prompt UI
│              │ ← User toggles dispositions
└──────┬───────┘
       │ "Import Now" or Back
       ▼
┌──────────────┐
│  Assembling   │ ← TextAssembler builds ExtractedDocument
└──────┬───────┘
       │ assembly complete
       ▼
┌──────────────┐
│  Ready        │ ← Navigate to reading screen
└──────────────┘
```

### 7.4 Riverpod State

```dart
enum ImportPhase { extracting, classifying, reviewing, assembling, ready, error }

class ImportState {
  const ImportState({
    required this.filePath,
    this.phase = ImportPhase.extracting,
    this.extractionProgress = 0.0,
    this.classificationResult,
    this.userOverrides = const {},
    this.errorMessage,
  });

  final String filePath;
  final ImportPhase phase;
  final double extractionProgress;  // 0.0–1.0
  final ClassificationResult? classificationResult;
  final Map<BlockClassification, BlockDisposition> userOverrides;
  final String? errorMessage;
}
```

### 7.5 Styling

- All colors via `SpeedyBoyTokens` — shell surface world (this is chrome, not the reading stage).
- Card backgrounds: `SpeedyBoyDecorations.raisedDecoration(shellSurface, SpeedyBoyDecorations.sizeSmall)`.
- Toggle buttons: segmented control per detection, styled with `shellAccent` for selected state.
- Typography: `SpeedyBoyTypography.bodyMedium` for descriptions, `SpeedyBoyTypography.titleMedium` for the document title.
- "Import Now" button: `SpeedyBoyDecorations.raisedDecoration(shellAccent, SpeedyBoyDecorations.sizeMedium)`.
- Progress states: neumorphic pulse animation, `importProgressPulseMs = 1200` cycle (no `CircularProgressIndicator` — Rule 15). // P34 Grade D — tunable
- Detection card fade-in: `importCardFadeMs = 200`. // P34 Grade D — tunable
- Assembly timeout: `importAssemblyTimeoutMs = 30000` (matches existing `_extractionTimeout` pattern). // P10 Grade C
- All animations check `isReducedMotion(context)` (Rule 5).

---

## 8. Text Assembly

After the user confirms dispositions, `TextAssembler` converts classified blocks into the existing `ExtractedDocument` format.

### 8.1 Assembly Rules

1. Iterate classified blocks in page order, then reading order within each page.
2. Skip blocks where final disposition is `exclude`.
3. For `include` blocks: split text into sentences using existing `_textToSentences()` logic.
4. Insert `PageBoundary` markers at page transitions (preserving existing behavior).
5. Apply text cleaning rules before sentence splitting.

### 8.2 Text Cleaning Rules

| Rule | Implementation | Notes |
|------|---------------|-------|
| **Dehyphenation** | If a word at fragment end has a trailing hyphen and the next fragment starts with a lowercase letter, join the fragments and remove the hyphen. | Exception: preserve hyphens where both fragments are ≥3 characters (likely compound word). |
| **Whitespace normalization** | Collapse multiple spaces to single space. Collapse 3+ newlines to double newline. | Standard text cleaning. |
| **Unicode normalization** | NFC normalization. Replace ligatures (ﬁ→fi, ﬂ→fl). | PDFium usually handles this, but some fonts don't. |
| **Page-break stitching** | If the last word of page N and the first word of page N+1 form a continuous sentence (no paragraph break), join with a single space. | Check: does the page end mid-sentence? (no terminal punctuation) |
| **URL stripping** | Remove text matching `https?://\S+` or `www\.\S+`. | Already classified as exclude; this is a safety net. |

### 8.3 Output Shape

The assembler produces `ExtractedDocument` with `sentences`, `pageBoundaries`, and `totalPages` — identical to the current `pdfExtract()` output. The RSVP engine, word timer, sentence resolver, and bookmark system require **zero changes**.

---

## 9. Integration with PreprocessingQueue

### 9.1 Pipeline Change

The current `PreprocessingQueue` uses a 2-phase model:
1. **Phase 1 (Preview)**: Extract pages 0–2 for quick display.
2. **Phase 2 (Background Completion)**: Extract remaining pages.

For smart import, the pipeline becomes:
1. **Phase 1 (Preview)**: Extract pages 0–2 using `loadStructuredText()` — produce a quick `ExtractedDocument` for immediate display (no classification yet).
2. **Phase 2 (Full Extraction)**: Extract ALL pages with `loadStructuredText()` — produce `List<PageAnalysis>`.
3. **Phase 3 (Classification)**: Run `ClassificationEngine.classify()` in `Isolate.run()` — produce `ClassificationResult`.
4. **Phase 4 (User Review)**: Navigate to `/import-summary` if patterns detected with confidence ≥ 0.6. Otherwise, auto-apply defaults and skip.
5. **Phase 5 (Assembly)**: `TextAssembler` produces final `ExtractedDocument` from user-confirmed dispositions.

The preview phase (1) still uses the existing simple extraction so the user gets instant feedback in the library. Full classification only runs when the user opens a PDF for reading.

### 9.2 When to Show Import Summary

- **First import of a document**: Always show if detections exist with confidence ≥ 0.6.
- **Re-import with existing profile**: Skip summary — reuse the stored `ExtractionProfile`.
- **User explicitly requests**: Settings toggle or long-press option in library to "Re-import with options".

---

## 10. Performance Constraints

| Metric | Target | Measured Against |
|--------|--------|-----------------|
| `loadStructuredText()` per page | < 50ms | Benchmark on 5 test PDFs (TASK-200) |
| Classification (Pass 2, 300 pages) | < 2 seconds | Compute isolate, O(N) per heuristic |
| Text assembly | < 500ms | String operations only |
| Import summary render | < 100ms | Neumorphic card list |
| Memory (loaded document) | < 100MB for 1000 pages | Release page resources after extraction |

**Key optimization**: Release `PdfPageText` handles after extracting data from each page. Don't hold all pages' structured text in memory simultaneously — serialize to `PageAnalysis` and release.

---

## 11. Phase 2 Investigation Items (pdfrx_engine)

These items are **not in scope for M1–M3**. Each requires a benchmark before any code changes.

### 11.1 Per-Character Font Info

**What**: `FPDFText_GetFontInfo` via pdfrx_engine gives exact font family, weight, and size per character.

**Why**: Rect-height heuristic may misclassify headings in PDFs with unusual font metrics (large x-height, compressed ascenders).

**Benchmark methodology**: Extract 5 untagged PDFs with known heading structure. Compare heading detection accuracy between rect-height heuristic and FFI font query. Report precision/recall.

**Accept rect-height if**: Precision ≥ 0.90 AND recall ≥ 0.85.

### 11.2 Structure Tree Access

**What**: `FPDF_StructTree_GetForPage` gives tagged PDF structure elements (`<P>`, `<H1>`, `<Artifact>`, etc.).

**Why**: For well-tagged PDFs, structure tree gives authoritative classification (confidence 0.95) vs spatial heuristics (confidence 0.65–0.85).

**Benchmark methodology**: Process 3 well-tagged PDFs (government reports, accessible academic papers). Compare classification accuracy and user override rate between heuristics-only vs structure-tree-assisted.

**Adopt if**: Structure tree reduces user overrides by ≥30% on test PDFs.

### 11.3 Page Geometry Boxes

**What**: `FPDFPage_GetCropBox` / `FPDFPage_GetTrimBox` define effective page boundaries excluding bleed areas.

**Why**: Scanned PDFs may have dark edges or crop marks outside the trim area.

**Priority**: Low — only matters for scanned documents. Defer indefinitely unless users report scanner noise as a problem.

---

## 12. Do / Don't Table

| # | Do | Don't |
|---|---|---|
| 1 | Use `pdfrx` for all PDF text extraction and page rendering. | Add `pdfrx_engine` as a direct dependency without a benchmark proving pdfrx insufficient. |
| 2 | Call `PdfDocument.openFile()`, `page.loadStructuredText()` on the **main isolate** only. | Call any pdfrx/FFI method inside `Isolate.run()`. |
| 3 | Serialize extracted data to plain Dart objects before crossing isolate boundaries. | Pass `PdfPageText`, `PdfRect`, or any FFI handle to a compute isolate. |
| 4 | Run `ClassificationEngine.classify()` in `Isolate.run()` with serializable input/output. | Run CPU-bound classification logic on the main isolate. |
| 5 | Dispose `PdfDocument` handles promptly after extraction (in a `finally` block). | Hold document handles open across screens or across the import flow. |
| 6 | Estimate font size from `PdfRect` median height. | Assume `PdfRect` height equals font size exactly — use the ≥20% delta threshold for headings. |
| 7 | Validate page number sequences — a bare "42" in body text is not a page number. | Classify any lone integer as a page number. |
| 8 | Run header/footer detection independently for odd and even pages. | Assume headers are identical on all pages. |
| 9 | Let the user override every automated classification via the auto-prompt UI. | Make any classification irreversible. |
| 10 | Store `ExtractionProfile` per document in `pdf_store/<hash>/profile.json`. | Force the user to re-configure on every import. |
| 11 | Show auto-prompt only for detections with confidence ≥ 0.6. | Prompt for every low-confidence detection (information overload). |
| 12 | Apply default dispositions if the user dismisses the import summary. | Block reading until the user reviews every detection. |
| 13 | Produce `ExtractedDocument` (same shape the RSVP engine consumes). | Create a new output model that breaks the existing reading pipeline. |
| 14 | Dehyphenate line-end hyphens using fragment boundary detection. | Naively join all hyphenated words (breaks compound words like "well-known"). |
| 15 | Use shell surface world tokens for the import summary screen. | Use `stage*` tokens on the import summary (it's chrome, not the reading viewport). |
| 16 | Use neumorphic pulse for progress states (Rule 15). | Use `CircularProgressIndicator` or `LinearProgressIndicator`. |
| 17 | Check `isReducedMotion(context)` for all import UI animations (Rule 5). | Skip reduced-motion checks on progress animations. |

---

## 13. Edge Cases (M1–M3 Scope)

| Edge Case | Handling |
|-----------|---------|
| PDF with no text (image-only) | `pdfExtract()` already throws `UnsupportedPdfError`. No change. |
| PDF with mixed pages (some text, some image) | Process text pages; skip image-only pages. Existing probe logic (10 extra pages) preserved. |
| Very small PDF (1–3 pages) | Skip classification — not enough data for cross-page heuristics. Use simple extraction. |
| PDF where all text is in header/footer zone | Confidence will be low (<0.6) due to no body text reference. Classification defaults to `bodyText` for all fragments. No auto-prompt. |
| Password-protected PDF | pdfrx's `PdfDocument.openFile()` throws. Existing error handling catches this. |
| Malformed PDF | Wrap `loadStructuredText()` in try/catch per page. On failure, fall back to `loadText()` for that page. |
| `loadStructuredText()` returns empty | Fall back to `loadText()` for that page. |
| Extremely large PDF (>5000 pages) | Extraction progress shown via `NotificationService`. Allow user to cancel. |
| Re-import with existing profile | Skip auto-prompt; reuse stored profile. |

---

## 14. New Files

| File | Contents |
|------|----------|
| `lib/services/classification_engine.dart` | `ClassificationEngine.classify()` — runs in `Isolate.run()` |
| `lib/services/extraction_profile.dart` | `ExtractionProfile`, `FootnoteHandling` models + JSON serialization |
| `lib/services/text_assembler.dart` | `TextAssembler.assemble()` — classified blocks → `ExtractedDocument` |
| `lib/screens/import_summary_screen.dart` | Auto-prompt UI (detection cards, toggles, import button) |
| `lib/store/import_state.dart` | `ImportState`, `ImportPhase`, Riverpod notifier for import flow |

### Modified Files

| File | Change |
|------|--------|
| `lib/services/pdf_extractor.dart` | Replace `pdfExtract()` internals with `loadStructuredText()`. Add `extractStructured()` returning `List<PageAnalysis>`. Keep `extractPdfInIsolate()` as backward-compatible entry point that uses the new pipeline internally. |
| `lib/services/models.dart` | Add `TextBlockData`, `PageAnalysis`, `BlockClassification`, `BlockDisposition`, `ClassifiedBlock`, `DetectedPattern`, `ClassificationResult` |
| `lib/services/preprocessing_queue.dart` | Wire Phases 3–5 (classification → user review → assembly) after Phase 2 completes |
| `lib/navigation/app_router.dart` | Add `/import-summary` route with `ImportSummaryScreen` |
| `lib/design/design.dart` | No new exports needed (existing tokens suffice for import UI) |
| `lib/services/section_store.dart` | Add `saveProfile()` / `loadProfile()` for per-document `ExtractionProfile` persistence |

---

## 15. Milestones (M1–M3 Only)

| Milestone | Scope | Effort | Sprint |
|-----------|-------|--------|--------|
| **M0: Research Spikes** | Benchmark `loadStructuredText()` vs `loadText()`. Benchmark rect-height font heuristic accuracy. | S | Sprint 0 |
| **M1: Skeleton** | Data models. Replace `pdfExtract()` with `extractStructured()`. Unit tests. | M | Sprint 1 |
| **M2: Classification Engine** | `ClassificationEngine` with header/footer detection, page number detection, dominant font detection, body column detection. Runs in `Isolate.run()`. Unit tests. | L | Sprint 2 |
| **M3: Auto-Prompt UI** | Riverpod state. `/import-summary` route. Detection cards. Accept/reject toggles. Text assembly. Wire into library open flow. Widget tests. | L | Sprint 3–4 |
