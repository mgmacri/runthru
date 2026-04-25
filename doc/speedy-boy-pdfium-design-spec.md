# Speedy Boy — PDFium Text Extraction Design Spec

**Version**: 0.1 (Draft)
**Feature**: PDF Import with Intelligent Region Selection
**Author**: Claude (AI-assisted specification)
**Status**: Proposal
**Depends on**: Speedy Boy v3 core (RSVP engine, PacingEngine, WordProcessor)

---

## 1. Problem Statement

Speedy Boy currently accepts plain text input. Users who want to speed-read books, papers, or reports must manually copy-paste text out of PDFs — losing formatting cues, importing garbage (page numbers, headers, footers, watermarks), and spending minutes on what should be a one-tap import. PDFs are the dominant format for books and technical documents, so native PDF support is a prerequisite for real-world adoption.

The core challenge is not *rendering* a PDF — it's *extracting the right text* from one. A book PDF contains a mix of body prose (what the reader wants) and structural/decorative noise (what they don't). This spec defines how Speedy Boy uses PDFium to decompose a PDF page into semantic regions, classify them as signal or noise, and let the user confirm or override those classifications before feeding clean text into the existing RSVP pipeline.

---

## 2. Goals and Non-Goals

### Goals
1. Import a PDF and extract **body text** suitable for RSVP reading — paragraph prose in logical reading order.
2. Automatically detect and suppress common noise elements (headers, footers, page numbers, decorative content).
3. Provide three tiers of user control: **auto-prompt**, **visual region selection**, and **manual text selection**.
4. Preserve **logical reading order** across pages, including handling of multi-column layouts.
5. Preserve structural elements the reader needs: chapter headings, alt text, table of contents.
6. Work across the full spectrum of PDFs: tagged/accessible, untagged, and scanned-then-OCR'd.

### Non-Goals
- Full PDF rendering/viewing (this is an import pipeline, not a reader).
- PDF annotation, editing, or form filling.
- OCR of image-only PDFs (out of scope for v1; flagged for v2).
- DRM-protected or encrypted PDF handling beyond basic password entry.
- Rendering PDFs inline in the Speedy Boy reading viewport — extracted text feeds into the existing RSVP word display.

---

## 3. Package Selection

### Recommendation: `pdfrx` + `pdfrx_engine` (PDFium-backed)

| Criterion | pdfrx/pdfrx_engine | pdfium_bindings | syncfusion_flutter_pdf |
|---|---|---|---|
| Platform coverage | Android, iOS, Windows, macOS, Linux, Web | Desktop + manual binary management | Android, iOS, Web |
| Text extraction with bounds | Yes (via PDFium FPDFText API) | Yes (raw FFI) | Yes (proprietary) |
| Character-level bounding boxes | Yes | Yes | Yes |
| Structure tree access | Via pdfrx_engine low-level API | Via raw FFI | No |
| Text selection support | Native (added in recent versions) | Manual | No |
| Page rendering for visual selection | Built-in widget | Render-to-image only | Built-in widget |
| License | Apache 2.0 (PDFium) | Apache 2.0 | Commercial |
| Maintenance | Active (2026 releases) | Active | Active |
| Flutter widget layer | Yes (PdfViewer) | No | Yes |

**Decision**: Use `pdfrx` for the visual selection UI (page rendering, hit testing) and `pdfrx_engine` for the headless text extraction pipeline. This gives us both a widget for the import flow and direct access to PDFium's `FPDFText_*` APIs for character-level extraction.

**Fallback**: On iOS/macOS, optionally use `pdfrx_coregraphics` to reduce binary size, but note it is experimental and may have text extraction limitations. Default to PDFium for correctness.

---

## 4. PDF Element Taxonomy

This section classifies every element type a PDF may contain into **Exclude** (noise), **Preserve** (signal), and **Conditional** (depends on context or user preference).

### 4.1 Exclude by Default (Noise)

These elements disrupt RSVP reading flow and should be suppressed unless the user explicitly includes them.

| Element | Detection Strategy | Confidence | Notes |
|---|---|---|---|
| **Running headers** | Spatial: text in top N% of page that repeats across ≥3 consecutive pages (fuzzy match allowing page-varying chapter titles). Tagged PDF: `<Artifact>` with `Type=Pagination, Subtype=Header`. | High (tagged), Medium (heuristic) | Chapter-title headers vary per chapter — use fuzzy matching with Levenshtein distance ≤ 30% of string length. |
| **Running footers** | Spatial: text in bottom N% of page that repeats across ≥3 consecutive pages. Tagged PDF: `<Artifact>` with `Type=Pagination, Subtype=Footer`. | High (tagged), Medium (heuristic) | Same fuzzy logic as headers. |
| **Page numbers** | Regex on isolated text blocks: bare integers, roman numerals (`i`, `ii`, `xiv`), or patterns like `Page N`, `N of M`, `- N -`. Must appear in header/footer zone AND be sequential across pages. Tagged PDF: `<Artifact>` with `Type=Pagination`. | High | Must validate sequentiality — a standalone number "42" in body text is *not* a page number. |
| **Decorative images** | Tagged PDF: images with `Role=Background` or `Role=Pagination` in structure tree, or images with no alt text that span >80% of page width/height (likely borders/backgrounds). Untagged: images whose bounding box overlaps <5% with any text region. | Medium | If an image has alt text, it is NOT decorative — preserve the alt text. |
| **Repeated logos** | Image fingerprinting: hash the rendered bitmap of each image; if the same hash appears on >50% of pages, classify as logo. Spatial: image in header/footer zone that repeats. | Medium | Only suppress if in header/footer zone OR on >50% of pages. A logo on the title page only should be preserved (as alt text if available). |
| **Marginalia / marginal notes** | Spatial: text outside the body text column bounding box (i.e., in the left/right margin zone), with font size ≤ body font size. Not in the main text flow. | Low | Dangerous heuristic — some academic texts put critical cross-references in margins. Default to visual-selection confirmation for anything flagged as marginalia. |
| **Interactive form fields** | PDFium `FPDFPage_HasFormFieldAtPoint` / `FPDF_GetFormType`. Any widget annotation with empty value. | High | If a form field has a filled value, extract the value text. |
| **Document metadata** | `FPDF_GetMetaText` — Title, Author, Subject, Keywords, Creator, Producer, CreationDate, ModDate. Never rendered as reading text. | High | Store metadata separately for display in the import summary, but never feed into RSVP. |
| **Hyperlinks / URL footnotes** | PDFium `FPDFLink_LoadWebLinks` — extract URL text. Regex for bare URLs in body text (`https?://...`, `www.`). | High | Strip the URL itself. If the link has anchor text that is meaningful prose (e.g., "see the original study"), preserve the anchor text, strip the URL. |
| **Placeholder / garbage text** | Text blocks where >60% of characters are non-printable, or consist of repeated glyphs (e.g., `□□□□□`), or are common placeholder strings ("Lorem ipsum" in a non-design document). | Medium | Aggressive filtering is OK here — placeholder text has zero reading value. |
| **Crop marks / bleed boxes** | Spatial: thin lines or marks within 5mm of the `MediaBox` boundary that fall outside the `TrimBox` or `CropBox`. PDFium: compare `MediaBox` vs `CropBox` geometry. | High | Use `CropBox` (or `TrimBox` if available) as the effective page boundary. Everything outside it is print production artifact. |
| **Scanner noise** | Spatial: dark regions along page edges (within 3% of page boundary) with no associated text. Grayscale analysis of rendered edge strips. | Low | Only relevant for scanned PDFs. Defer to v2 with OCR integration. For v1, flag and let user confirm. |

### 4.2 Preserve Always (Signal)

These elements are essential for reading comprehension and/or RSVP navigation.

| Element | Detection Strategy | How to Preserve |
|---|---|---|
| **Body paragraphs** | Primary text flow: largest contiguous text regions by area, within the body column, using the dominant font size/family. Tagged PDF: `<P>` elements. | Extract as sequential text. Insert paragraph breaks (`\n\n`) between paragraphs. |
| **Logical headings (H1–H6)** | Tagged PDF: `<H1>` through `<H6>` structure elements. Untagged: text blocks with font size > body font size by ≥20%, bold weight, preceded/followed by vertical whitespace. | Emit as text with a preceding marker (e.g., `## Chapter Title`) so the RSVP engine can use them for navigation bookmarks. Pause briefly at headings (configurable). |
| **Alt text on meaningful images** | Tagged PDF: `/Alt` attribute on `<Figure>` structure elements. PDFium: `FPDF_StructElement_GetAltText`. | Inject alt text inline at the image's position: `[Image: {alt text}]`. User can toggle this off. |
| **Table of contents** | Tagged PDF: `<TOC>` / `<TOCI>` structure elements. Heuristic: pages where >70% of lines contain a title + dot leader + page number pattern, typically in the first 5% of the document. Bookmarks: `FPDFBookmark_GetFirstChild` tree. | Extract as navigable chapter list. Use as the primary chapter-boundary map for skip-forward/backward gestures in the RSVP engine. Do NOT feed ToC text into RSVP body — it's metadata. |
| **Footnotes / endnotes (content)** | Tagged PDF: `<Note>` structure elements. Heuristic: superscript number in body text followed by matching number + text at page bottom (footnote) or document end (endnote), with font size ≤ body font size. | User preference: inline at point of reference, collected at chapter end, or omitted. Default: omit from RSVP flow, show as expandable annotation in import preview. |
| **Block quotes** | Tagged PDF: `<BlockQuote>`. Heuristic: indented text blocks with consistent left margin offset > body text margin. | Preserve inline. Optionally insert visual markers: `> quoted text`. |
| **Lists (ordered and unordered)** | Tagged PDF: `<L>`, `<LI>`, `<Lbl>`, `<LBody>`. Heuristic: text blocks with consistent bullet/number prefix patterns and hanging indent. | Flatten to sequential text: "1. First item. 2. Second item." for RSVP consumption. |
| **Tables (data)** | Tagged PDF: `<Table>`, `<TR>`, `<TH>`, `<TD>`. Heuristic: grid-aligned text blocks with consistent column spacing. | Complex problem. v1: serialize row-by-row as `"Header1: Value1, Header2: Value2"`. Flag tables in import preview for user to include/exclude. |
| **Captions** | Tagged PDF: `<Caption>`. Heuristic: short text block immediately below/above an image or table, with font style differing from body. | Preserve inline at position. Prefix with `[Caption: ...]` if user has alt text display enabled. |

### 4.3 Conditional (User-Decided)

| Element | Default | Why Conditional |
|---|---|---|
| **Chapter epigraphs** | Include | Some readers find them distracting; others consider them essential context. |
| **Pull quotes / sidebars** | Exclude | Often duplicate body text. But in magazines/textbooks they may be unique content. |
| **Code blocks** | Include | Essential in technical books, useless in novels. Auto-detect by monospaced font. |
| **Mathematical notation** | Include (as LaTeX or Unicode approximation) | RSVP is poorly suited to math. Warn user. |
| **Index / glossary** | Exclude | Reference material, not sequential reading. |
| **Acknowledgments / dedication** | Include | Short, part of the book experience. |
| **Copyright page** | Exclude | Legal boilerplate. |

---

## 5. Detection Engine Architecture

### 5.1 Three-Pass Pipeline

The extraction pipeline runs in an isolate to keep the UI responsive.

```
Pass 1: Structural Analysis (per-page, parallelizable)
  ├─ Load page via pdfrx_engine
  ├─ Extract ALL text blocks with character-level bounding boxes
  ├─ Extract structure tree (if tagged PDF)
  ├─ Extract images with positions and alt text
  ├─ Extract form fields
  ├─ Extract links (web + internal)
  ├─ Compute page geometry: MediaBox, CropBox, TrimBox, BleedBox
  └─ Output: List<PageAnalysis> (raw data, no classification yet)

Pass 2: Cross-Page Classification (sequential, needs all pages)
  ├─ Detect repeating headers/footers (fuzzy string match across pages)
  ├─ Detect page number sequences (regex + sequentiality validation)
  ├─ Detect repeated logos (image hash frequency)
  ├─ Detect body text column boundaries (statistical mode of text block positions)
  ├─ Detect dominant font (most frequent font family + size = "body font")
  ├─ Detect ToC pages (heuristic scoring)
  ├─ Build chapter map from bookmarks OR ToC OR heading hierarchy
  └─ Output: List<ClassifiedPage> (each text block tagged with element type + include/exclude)

Pass 3: User Confirmation (interactive)
  ├─ Present import preview with classified regions highlighted
  ├─ Auto-prompt for detected patterns ("We found page numbers — ignore them?")
  ├─ Allow visual region selection overrides
  ├─ Allow manual text selection overrides
  └─ Output: ExtractionProfile (final include/exclude map, reusable across pages)
```

### 5.2 Key Data Structures

```dart
/// A single text block extracted from a PDF page.
class PdfTextBlock {
  final int pageIndex;
  final Rect boundingBox;           // In PDF coordinate space (origin bottom-left)
  final String text;
  final String fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final bool isItalic;
  final List<CharacterBox> characters; // Per-character bounding boxes
  final int charStartIndex;         // Index in PDFium's page character array
  final int charEndIndex;
}

/// Classification applied to a text block after cross-page analysis.
enum BlockClassification {
  bodyText,
  heading,
  runningHeader,
  runningFooter,
  pageNumber,
  footnote,
  endnote,
  caption,
  blockQuote,
  listItem,
  tableCell,
  tocEntry,
  codeBlock,
  marginalia,
  placeholder,
  hyperlink,
  altText,
  pullQuote,
  epigraph,
  unknown,
}

enum BlockDisposition {
  include,       // Will be fed into RSVP
  exclude,       // Suppressed
  askUser,       // Needs confirmation
}

class ClassifiedBlock {
  final PdfTextBlock block;
  final BlockClassification classification;
  final BlockDisposition disposition;
  final double confidence;          // 0.0–1.0
  final String? detectionReason;    // Human-readable explanation
}

/// Reusable extraction profile — applies to all pages of a document.
class ExtractionProfile {
  final Map<BlockClassification, BlockDisposition> globalRules;
  final List<RegionOverride> regionOverrides;  // User-defined spatial overrides
  final List<TextOverride> textOverrides;      // User-defined text selection overrides
  final bool ignorePageNumbers;
  final bool ignoreRunningHeaders;
  final bool ignoreRunningFooters;
  final FootnoteHandling footnoteHandling;
  // Serializable — save per-document for re-import.
}
```

### 5.3 Header/Footer Detection Algorithm (Detail)

This is the most nuanced heuristic because false positives destroy reading flow and false negatives pollute it.

```
Input: List<PageAnalysis> for pages [0..N]

1. Define header zone: top 12% of CropBox height.
   Define footer zone: bottom 12% of CropBox height.

2. For each page, collect all text blocks whose bounding box centroid
   falls within the header zone → candidate_headers[page].
   Same for footer zone → candidate_footers[page].

3. For each candidate string S on page P:
   a. Normalize: lowercase, strip whitespace, strip digits.
   b. Compare against candidates on pages P-1, P+1, P-2, P+2
      using Levenshtein ratio.
   c. If ratio ≥ 0.70 on ≥ 3 consecutive pages → classify as
      running header/footer (confidence = ratio × page_count/total_pages).

4. Special cases:
   - Chapter title headers: may change at chapter boundaries.
     Group pages by chapter (from bookmark/ToC), run detection
     within each chapter independently.
   - Odd/even page headers: compare odd pages separately from
     even pages (common in printed books).
   - First page of chapter: often has no header. Don't penalize
     detection for missing headers on chapter-start pages.

5. Page number sub-detection within header/footer candidates:
   - Regex: /^\s*(\d+)\s*$/ or /^\s*[ivxlcdm]+\s*$/i
     or /^\s*page\s+\d+\s*$/i or /^\s*-\s*\d+\s*-\s*$/
   - Validate: extracted numbers must form a monotonically
     increasing (or decreasing for RTL) sequence with gaps ≤ 2.
   - If valid sequence: classify as pageNumber with high confidence.
```

### 5.4 Body Column Detection Algorithm

```
Input: All text blocks across all pages.

1. For each page, compute the bounding box of ALL text blocks.
2. Compute the left margin (min x across blocks) and right margin
   (max x+width across blocks) for each page.
3. Take the statistical mode of left margins (±2% of page width
   tolerance) → dominant left margin.
4. Same for right margin → dominant right margin.
5. Body column = rect(dominant_left, header_zone_bottom,
                      dominant_right, footer_zone_top).

6. Multi-column detection:
   a. Within body column, compute x-position histogram of all
      text block left edges.
   b. If histogram shows 2+ distinct peaks separated by a gap
      > 5% of page width → multi-column layout.
   c. For 2-column: split body column at the gap midpoint.
   d. Reading order: left column top-to-bottom, then right column
      top-to-bottom (for LTR text). Reverse for RTL.
   e. IMPORTANT: some pages may be single-column (e.g., chapter
      starts). Detect per-page, not globally.

7. Anything outside the body column(s) AND not classified as
   heading/footnote/caption → flag as marginalia candidate.
```

---

## 6. User Interaction Model

Three tiers of control, layered so the user can be as hands-off or hands-on as they want.

### 6.1 Tier 1: Auto-Prompt (Default)

After Pass 2 completes, the system presents a summary screen:

```
┌─────────────────────────────────────────────┐
│  PDF Import: "Thinking, Fast and Slow"      │
│                                             │
│  📄 312 pages analyzed                      │
│  ✅ Body text extracted (est. 4.2 hours     │
│     at your current 280 WPM)                │
│                                             │
│  We detected:                               │
│  ┌─────────────────────────────────────┐    │
│  │ 📍 Page numbers on every page       │    │
│  │    [Ignore] [Keep]                  │    │
│  ├─────────────────────────────────────┤    │
│  │ 📍 Running header: "THINKING, FAST  │    │
│  │    AND SLOW" on 290/312 pages       │    │
│  │    [Ignore] [Keep]                  │    │
│  ├─────────────────────────────────────┤    │
│  │ 📍 Running footer: chapter titles   │    │
│  │    on 285/312 pages                 │    │
│  │    [Ignore] [Keep]                  │    │
│  ├─────────────────────────────────────┤    │
│  │ 📍 23 footnotes found              │    │
│  │    [Inline] [End of Chapter] [Skip] │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  [Preview First Page]  [Import Now]         │
└─────────────────────────────────────────────┘
```

**Behavioral Rules:**

1. Only prompt for detections with confidence ≥ 0.6. Below that, silently apply the default disposition.
2. Group related detections (e.g., "headers and footers" together if both are present).
3. Show the most impactful detections first (page numbers > headers > footers > footnotes > marginalia).
4. Remember user choices per-document AND offer "Apply to all future imports" for each choice.
5. If the PDF is well-tagged (structure tree present), reduce prompts — trust the tags.
6. Show estimated reading time impact: "Ignoring headers saves ~3 minutes of reading time."

### 6.2 Tier 2: Visual Region Selection

Accessed via "Preview First Page" or by tapping any page thumbnail in the import flow.

The visual selector renders the PDF page as a bitmap (via `pdfrx` PdfViewer) with **colored overlay regions** highlighting each classified zone.

```
Color Legend (use SpeedyBoyColors tokens):
  - Green overlay (20% opacity): body text (included)
  - Red overlay (20% opacity): excluded regions
  - Yellow overlay (20% opacity): askUser regions
  - Blue outline: currently selected region
```

**Drill-Down Interaction Model:**

This is the key innovation. Instead of requiring precise touch targeting, the visual selector uses a **progressive drill-down**:

1. **First tap** on any point on the page: selects the **largest classified region** containing that point. The region highlights with a blue border and shows a floating label: `"Running Footer — Excluded"` with `[Include]` / `[Exclude]` toggle buttons.

2. **Second tap** on the already-selected region: drills down to the **next smaller region** nested within it, or to the individual text block level. Label updates accordingly.

3. **Third tap** (if applicable): drills down to the text-line level within the block.

4. **Tap outside** the selected region: deselects, returns to page overview.

5. **Long press**: opens a context menu with all overlapping regions at that point, listed from largest to smallest, for direct selection.

**State Machine:**

```
           ┌─────────┐
    tap     │  Page   │ ← tap outside
  outside ──│ Overview│──────────────────────┐
            └────┬────┘                      │
                 │ tap on region             │
                 ▼                           │
           ┌──────────┐                      │
           │ Region   │── tap on selected ──▶│
           │ Selected │   region             │
           └────┬─────┘                      │
                │ tap on selected            │
                │ region (drill)             │
                ▼                            │
           ┌──────────┐                      │
           │  Block   │── tap on selected ──▶│
           │ Selected │   block (drill)      │
           └────┬─────┘                      │
                │ tap on selected            │
                │ block (drill)              │
                ▼                            │
           ┌──────────┐                      │
           │  Line    │─────────────────────▶│
           │ Selected │  tap outside         │
           └──────────┘                      │
```

**Multi-Page Application:**

When the user changes a region's disposition on one page, prompt:
- "Apply to this page only"
- "Apply to all pages" (updates ExtractionProfile globally)
- "Apply to similar pages" (e.g., all odd pages, or all pages in this chapter)

### 6.3 Tier 3: Manual Text Selection

For fine-grained control when heuristics fail.

**Activation:** Double-tap a word in the rendered page view.

**Behavior:**

1. Double-tap a word → the word highlights and selection handles appear (standard iOS/Android text selection UX).
2. Drag handles to expand selection start/end.
3. Selected text gets a floating toolbar: `[Include in Reading] [Exclude from Reading] [Cancel]`.
4. The selection creates a `TextOverride` in the `ExtractionProfile` — a bounding box with a disposition that overrides any heuristic classification.
5. Manual selections are stored with page-relative coordinates (percentage of CropBox dimensions) so they survive re-imports at different render scales.

**Implementation:**

Use `FPDFText_GetCharIndexAtPos` to map touch coordinates → character index, then `FPDFText_GetCharBox` to highlight individual characters. Build selection by expanding character range with drag handles.

---

## 7. PDFium API Usage Map

Which PDFium APIs (via `pdfrx_engine`) are needed for each capability:

| Capability | PDFium API | Header |
|---|---|---|
| Load document | `FPDF_LoadDocument`, `FPDF_LoadMemDocument` | `fpdfview.h` |
| Page count | `FPDF_GetPageCount` | `fpdfview.h` |
| Page geometry | `FPDF_GetPageWidth`, `FPDF_GetPageHeight`, `FPDFPage_GetMediaBox`, `FPDFPage_GetCropBox`, `FPDFPage_GetTrimBox`, `FPDFPage_GetBleedBox` | `fpdfview.h`, `fpdf_transformpage.h` |
| Load text page | `FPDFText_LoadPage` | `fpdf_text.h` |
| Character count | `FPDFText_CountChars` | `fpdf_text.h` |
| Character bounding box | `FPDFText_GetCharBox`, `FPDFText_GetLooseCharBox` | `fpdf_text.h` |
| Character at position | `FPDFText_GetCharIndexAtPos` | `fpdf_text.h` |
| Extract text by range | `FPDFText_GetText` | `fpdf_text.h` |
| Extract text by bounds | `FPDFText_GetBoundedText` | `fpdf_text.h` |
| Text rectangles | `FPDFText_CountRects`, `FPDFText_GetRect` | `fpdf_text.h` |
| Font info | `FPDFText_GetFontSize`, `FPDFText_GetFontInfo` | `fpdf_text.h` |
| Generated chars (spaces/newlines) | `FPDFText_IsGenerated` | `fpdf_text.h` |
| Hyphenation detection | `FPDFText_IsHyphen` | `fpdf_text.h` |
| Unicode mapping errors | `FPDFText_HasUnicodeMapError` | `fpdf_text.h` |
| Web links | `FPDFLink_LoadWebLinks`, `FPDFLink_CountWebLinks`, `FPDFLink_GetURL` | `fpdf_text.h` |
| Text search | `FPDFText_FindStart`, `FPDFText_FindNext`, `FPDFText_GetSchResultIndex` | `fpdf_text.h` |
| Structure tree | `FPDF_StructTree_GetForPage`, `FPDF_StructElement_GetType`, `FPDF_StructElement_GetAltText`, `FPDF_StructElement_CountChildren` | `fpdf_structtree.h` |
| Bookmarks | `FPDFBookmark_GetFirstChild`, `FPDFBookmark_GetNextSibling`, `FPDFBookmark_GetTitle`, `FPDFBookmark_GetDest` | `fpdf_doc.h` |
| Metadata | `FPDF_GetMetaText` | `fpdf_doc.h` |
| Form fields | `FPDF_GetFormType`, `FPDFPage_HasFormFieldAtPoint` | `fpdf_formfill.h` |
| Page rendering | Via `pdfrx` widget (wraps `FPDF_RenderPageBitmap`) | `fpdfview.h` |
| Image objects | `FPDFPage_CountObjects`, `FPDFPage_GetObject`, `FPDFPageObj_GetType`, `FPDFImageObj_GetBitmap` | `fpdf_edit.h` |

### 7.1 Isolate Strategy

PDFium is **not thread-safe** — all calls to a given document must happen on a single thread. However, different documents can be processed on different isolates.

```
Main Isolate (UI)
  │
  ├── Import Isolate (spawned per import)
  │     ├── Pass 1: page-by-page extraction (sequential per doc)
  │     ├── Pass 2: cross-page classification (CPU-bound)
  │     └── Sends classified data back via SendPort
  │
  └── UI renders preview from classified data
       └── User overrides sent back to import isolate for re-extraction
```

Use `pdfrx_engine`'s built-in mutex support (`PdfiumServiceMutex`) when multiple isolates might touch PDFium, even though we plan single-isolate-per-document.

---

## 8. Handling the PDF Spectrum

### 8.1 Well-Tagged PDFs (Best Case)

If `FPDF_StructTree_GetForPage` returns a valid tree:

1. Walk the structure tree. Map PDF structure types to `BlockClassification`:
   - `<P>` → bodyText
   - `<H>`, `<H1>`–`<H6>` → heading
   - `<Artifact>` → check subtype (Pagination → header/footer/pageNumber; Background → decorative)
   - `<Figure>` → check alt text; if present → altText; if absent → decorative image
   - `<Note>` → footnote
   - `<BlockQuote>` → blockQuote
   - `<L>`, `<LI>` → listItem
   - `<Table>`, `<TR>`, `<TD>`, `<TH>` → tableCell
   - `<TOC>`, `<TOCI>` → tocEntry
   - `<Code>` → codeBlock
   - `<Caption>` → caption
   - `<Span>` with `Role=Header` → runningHeader

2. Trust tags over heuristics. Set confidence = 0.95 for tag-based classifications.
3. Still run spatial heuristics as a sanity check — if tags and heuristics disagree, flag for user review.

### 8.2 Untagged PDFs (Common Case)

No structure tree. Fall back entirely to the spatial heuristics from Section 5.3/5.4.

1. Run font analysis to identify body font (statistical mode).
2. Run header/footer detection.
3. Run column detection.
4. Classify headings by font size delta from body font.
5. Set confidence = 0.5–0.8 depending on heuristic strength.
6. Present more prompts in the auto-prompt tier.

### 8.3 Scanned/OCR'd PDFs

Text is present but character positions may be imprecise. Indicators:
- All fonts are "unnamed" or synthetic.
- Character bounding boxes are unusually uniform (grid-aligned from OCR).
- `FPDFText_HasUnicodeMapError` returns true frequently.

Strategy:
1. Detect OCR'd status in Pass 1 by sampling character metadata.
2. Widen spatial tolerances for all heuristics (e.g., header zone → 15% instead of 12%).
3. Flag to user: "This appears to be a scanned document. Text quality may vary."
4. Reduce confidence scores by 20% across the board.

### 8.4 Image-Only PDFs (v1: Unsupported)

If `FPDFText_CountChars` returns 0 on all pages:
- Display: "This PDF contains only images with no extractable text. OCR support is planned for a future update."
- Offer nothing. Do not attempt client-side OCR in v1.

---

## 9. Output: Clean Text for RSVP

After all three passes, the final output is a `ReadingDocument` that the existing RSVP engine consumes.

```dart
class ReadingDocument {
  final String title;                // From metadata or first heading
  final String? author;              // From metadata
  final List<Chapter> chapters;      // From ToC/bookmarks/heading analysis
  final ExtractionProfile profile;   // For re-import
  final PdfMetadata sourceMetadata;  // For display, not reading
}

class Chapter {
  final String title;
  final int startPage;               // Source PDF page (for reference)
  final List<ReadingBlock> blocks;   // Ordered reading content
}

class ReadingBlock {
  final BlockClassification type;    // heading, bodyText, footnote, etc.
  final String text;                 // Clean text, ready for WordProcessor
  final int sourcePage;
  final Rect sourceRegion;           // For "show me where this was" feature
}
```

**Text Cleaning Rules (applied during final assembly):**

1. **Dehyphenation**: If `FPDFText_IsHyphen` is true for a character at line end, join the word fragments and remove the hyphen. Exception: preserve hyphens in compound words (check against a dictionary or use the heuristic that both fragments are ≥3 characters).
2. **Whitespace normalization**: Collapse multiple spaces to single space. Collapse multiple newlines to double newline (paragraph break).
3. **Unicode normalization**: NFC normalization. Replace common ligatures (ﬁ → fi, ﬂ → fl) if PDFium hasn't already.
4. **Smart quote normalization**: Normalize curly quotes to straight quotes (or vice versa, configurable).
5. **Page-break stitching**: If the last word on page N and the first word on page N+1 form a sentence (no paragraph break between them), join seamlessly with a single space.
6. **Encoding errors**: If `FPDFText_HasUnicodeMapError` is true for a character, replace with `�` and log. If >5% of characters in a block have errors, flag the block as low-quality.

---

## 10. Integration Points with Speedy Boy v3

| Speedy Boy Component | Integration |
|---|---|
| **WordProcessor** (`lib/engine/word_processor.dart`) | `ReadingDocument` → existing `processText()` pipeline. Chapters map to sentence-boundary segmentation. |
| **PacingEngine** (`lib/engine/pacing_engine.dart`) | No changes needed. It operates on word arrays from WordProcessor. |
| **AppConfig** (`lib/models/app_config.dart`) | Add `ExtractionProfile` persistence. Add `defaultPdfImportSettings` for "Apply to all future imports" preferences. |
| **Navigation gestures** | Swipe-left/right now also respects chapter boundaries from the PDF's ToC. Add chapter-skip gesture (double-swipe or long-swipe). |
| **Settings panel** | Add "PDF Import Defaults" section: default footnote handling, default header/footer behavior, always-ask vs auto-decide. |
| **Onboarding** | On first PDF import, show a one-time walkthrough of the three tiers. |

---

## 11. Performance Constraints

| Metric | Target | Rationale |
|---|---|---|
| Pass 1 (per page) | < 50ms | 300-page book should analyze in < 15 seconds. |
| Pass 2 (full document) | < 2 seconds for 500 pages | Cross-page comparison is O(N) per heuristic. |
| Memory (loaded document) | < 100MB for 1000-page PDF | PDFium loads lazily; only text pages + structure tree should be in memory. Release `FPDFText_ClosePage` after extraction. |
| Import preview render | < 100ms per page at screen resolution | Use pdfrx's built-in tile rendering. Don't render all pages upfront — lazy load on scroll. |
| Final text assembly | < 500ms | String concatenation is fast; the bottleneck is Pass 1/2. |

**Optimization Notes:**
- Release `FPDF_TEXTPAGE` handles after extracting data from each page in Pass 1 — don't hold all pages open.
- Cache image hashes — don't re-render images for fingerprinting on every page. Hash the raw image object bytes if accessible, or render once at low resolution (64×64).
- Cross-page string comparison: pre-compute normalized candidate hashes for O(1) comparison instead of O(N²) Levenshtein.

---

## 12. Do / Don't Table

| # | Do | Don't |
|---|---|---|
| 1 | Use structure tree tags when available — they are authoritative. | Ignore tags and rely only on spatial heuristics. |
| 2 | Validate page number sequences — a bare "42" in body text is not a page number. | Classify any lone integer as a page number. |
| 3 | Use CropBox/TrimBox as effective page boundary. | Use MediaBox for spatial analysis (includes bleed area). |
| 4 | Run header/footer detection independently for odd and even pages. | Assume headers are identical on all pages. |
| 5 | Preserve alt text from meaningful images. | Strip all image-related content. |
| 6 | Let the user override every automated classification. | Make any classification irreversible. |
| 7 | Store ExtractionProfile per-document for reproducible re-imports. | Force the user to re-configure on every import. |
| 8 | Run extraction in an isolate — never block the UI thread. | Call PDFium APIs on the main isolate. |
| 9 | Release PDFium handles (text page, document) promptly after extraction. | Hold open all pages simultaneously. |
| 10 | Dehyphenate words split across lines. | Naively join all line-end words (breaks compound words). |
| 11 | Handle multi-column layouts with correct reading order. | Assume all PDFs are single-column. |
| 12 | Gracefully handle encrypted/DRM PDFs with a clear error message. | Crash or hang on password-protected documents. |
| 13 | Show extraction confidence to user in visual selector. | Present all classifications as equally certain. |
| 14 | Treat footnote handling as a user preference (inline / end / skip). | Force one footnote strategy. |
| 15 | Feed ToC structure into RSVP navigation (chapter skip). | Treat ToC text as body reading content. |

---

## 13. Edge Cases and Known Risks

| Edge Case | Handling |
|---|---|
| PDF with no text (image-only) | Detect, inform user, block import in v1. |
| PDF with mixed pages (some text, some scanned) | Process text pages normally; flag image-only pages as gaps. |
| Right-to-left text (Arabic, Hebrew) | PDFium extracts in logical order. Ensure column detection reverses reading order. Flag for testing. |
| Vertical text (CJK) | PDFium handles GSUB tables for vertical glyphs. Spatial heuristics for columns need adaptation (rows instead of columns). Flag for testing. |
| PDF with embedded fonts that have no ToUnicode mapping | `FPDFText_HasUnicodeMapError` will fire. Warn user; text may be garbled. |
| Extremely large PDFs (>5000 pages) | Stream Pass 1 — show progress. Allow user to import a page range. |
| Password-protected PDFs | Prompt for password. On failure, show error. Do not store passwords. |
| Linearized (fast web view) PDFs | No special handling needed — PDFium handles transparently. |
| PDF with JavaScript | Ignore. Do not execute embedded JS. |
| Malformed PDFs | Wrap all PDFium calls in try/catch. On per-page failure, skip the page and log. Never crash the app. |

---

## 14. Open Questions

1. **pdfrx_engine access depth**: Does `pdfrx_engine` expose `FPDFText_GetFontInfo` and structure tree APIs, or do we need `pdfium_bindings` for direct FFI? Requires API audit.
2. **Footnote boundary detection in untagged PDFs**: The heuristic (superscript number + matching bottom text) has high false-positive risk in academic papers with many numbered references. May need ML-based classification in v2.
3. **Multi-column reading order on mixed-layout pages**: Some textbooks have single-column text with two-column figures. Need page-region-level column detection, not whole-page.
4. **Reflow vs. positional extraction**: Should we use `FPDFText_GetText` (logical order, PDFium's best guess) or `FPDFText_GetBoundedText` (spatial, our column logic)? Recommend: use logical order for tagged PDFs, spatial for untagged.
5. **License implications of bundling PDFium binaries**: PDFium is Apache 2.0, but verify that the `pdfium-binaries` prebuilts carry the same license.

---

## 15. Milestones

| Milestone | Scope | Effort |
|---|---|---|
| **M1: Skeleton** | Package integration, load PDF, extract raw text (no classification), display in RSVP. | S |
| **M2: Pass 1 + 2** | Structural analysis, cross-page classification, header/footer/page number detection. | L |
| **M3: Auto-Prompt UI** | Import summary screen with detected patterns and user choices. | M |
| **M4: Visual Region Selector** | Page rendering with overlay regions, drill-down selection, disposition toggles. | L |
| **M5: Manual Text Selection** | Double-tap word selection, drag handles, text overrides. | M |
| **M6: Profile Persistence** | Save/load ExtractionProfile per document, "Apply to all" preferences. | S |
| **M7: Integration** | Chapter map → RSVP navigation, heading pauses, reading time estimation. | M |
| **M8: Edge Cases** | Multi-column, RTL, OCR'd PDFs, large documents, error handling. | L |
