# RunThru — Architecture Snapshot (Phase 0 of the Scale Overhaul)

> Written 2026-06-11 before any code changes. This is the architectural
> contract for the scale-overhaul phases. The companion design doc
> `data_layer.md` is written at the end of the work and describes the
> *resulting* architecture; this file describes the *starting* state and the
> decisions taken.

## 1. Actual data flow today

### Local book: "scan folder" → "word flashes"

```
librarySourcesProvider (persisted source list, slim — good)
  → pdfListProvider (FutureProvider): FolderScannerService.scanSources()
      re-scans every source on every change; dedup by canonical path,
      plus lowercase-filename dedupe for owned folders
  → PreprocessingQueue._enqueueAll(): every scanned book queued immediately
      dedup key = lowercase filename (BK-4)
      _enqueueIfNew = O(n) scan per entry → O(n²) per scan cycle (BK-12)
  → _processPreview (up to 6 concurrent on MAIN isolate — pdfrx FFI, BK-3)
      cache hit (full)    → status ready, FULL ExtractedDocument kept in state
      cache hit (preview) → reopens the PDF just to count pages (every launch)
      miss → extract pages 1–3 on main isolate, 30s timeout
  → _completionQueue → _processBackgroundCompletion
      extracts pages 4..N in ONE shot under ONE 30s timeout (BK-7)
      .timeout() abandons but does not cancel the FFI loop
      retry restarts from page 3; 3 strikes → "Partial — pages 1–3 only"
  → PdfCache.save(): gzip JSON keyed by String.hashCode(path|mtime) (BK-11)
      50MB LRU budget — full library > 50MB ⇒ permanent re-extraction
      churn (BK-2); the unused SectionStore budget is 200MB
  → queue state Map<String, PdfEntry> holds EVERY completed document's
      full text FOREVER (BK-1). clearDocument() exists, never called.

ParallaxReadingScreen._initReading()
  → queue.prioritize(path) → reads entry.document from queue state
  → _loadDocument(doc):
      _fullDoc = doc                  (copy 0 — shared with queue state)
      _allDocWords = doc.allWords     (copy 1 — fresh flat list)
      _words = _allDocWords.sublist() (copy 2 — when a range is set)
  → WordTimer.loadDocument(totalWords) + attachWordSource(closure over _words)
  → timer ticks → wordNotifier → RSVP stage (this path is clean and fast)
```

### Drive file: "tap file" → "word flashes"

```
GoogleDriveImport.importFile()
  → client.downloadSelectedFile() → response.bodyBytes  (whole file in RAM, BK-9)
  → temp file runthru-drive-<id>-<name>                 (never deleted, BK-9)
  → pdfExtract(path) — FULL book, main isolate, NO timeout, no queue
  → GoogleDriveImportDone(document) → pushed via go_router `extra`
  → reading screen treats it like a clipboard doc (ephemeral)
  → nothing persisted: "Continue Reading" re-downloads + re-extracts (BK-9)
```

### Bookmarks / progress during reading

```
every word advance → BookmarkNotifier.updateIndex (memory only — fine)
every 5s          → updateBookmark() → re-serialize the ENTIRE AppConfig
                    (bookmarks for every book ever read, unbounded) and
                    rewrite the single SharedPreferences string (BK-5)
ReadingProgress    → same full-blob pattern, unbounded records (BK-14)
mobile re-import   → fresh microsecond-stamped dir ⇒ new path ⇒ orphaned
                    bookmark + progress (path is the identity — wrong)
```

## 2. Where memory accumulates and never releases

| Site | Growth | Released |
|---|---|---|
| `PreprocessingQueue.state[*].document` | O(total words of all extracted books) | never (BK-1) |
| Reading screen `_allDocWords` + `_words` slice | O(book) ×2 | on screen dispose |
| Range picker `_allWords` | O(book) | on screen dispose |
| `AppConfig.bookmarks` | O(books ever read) | never |
| `runthru_reading_progress` | O(items ever read) | never |
| Drive download `bodyBytes` | O(file size) | after extraction |

The dominant term is the queue map: it makes idle memory O(library), which
is the OOM machine. Everything else is bounded by one book / one file.

## 3. Reading-engine isolation boundary

**Today:** `WordTimer` is already nearly sealed — it takes a word count and a
synchronous `String? Function(int)` word source. It does no I/O, no JSON, no
extraction. Good. But the *screen* that feeds it reaches directly into queue
state (`entry.document`), config blob (bookmarks), and Drive import state.

**Target:** the screen obtains words only through the Ring 2 content store
(`SessionDocument` below). Where the words came from (local PDF, Drive copy,
Instapaper) is invisible past that point. WordTimer is untouched.

## 4. Assessment of SectionStore / SectionCache / CacheMigration

**Verdict: do not wire in — replace.** The layout idea (per-book directory,
manifest + numbered section files + LRU index) is right and is reused in the
new design, but the implementation has four disqualifying flaws:

1. **`fileHash` is not a content hash.** It is sha256(`path|mtime`). Mobile
   re-imports copy into a fresh microsecond-stamped directory, so the same
   book gets a new hash on every re-import — the exact identity bug
   (BK-4/BK-5) this layer is supposed to fix.
2. **Sections are uncompressed JSON** while the live cache learned the gzip
   lesson (5–10× smaller, isolate-encoded). 200MB of raw-JSON sections holds
   far less content than 200MB of gzip.
3. **`SectionCacheNotifier.resolveWord` is approximate** (average
   words-per-sentence heuristic) — off-by-a-section seeks for real books.
4. **`CacheMigration` is destructive**: it migrates only `*.json` (current
   cache files are `*.json.gz`, so it migrates nothing) and then deletes the
   entire `pdf_cache` directory — wiping every valid cache entry on every
   launch if anyone ever wires it up. It is a live trap (BK-6) and is
   deleted in Phase 1, not fixed: there is no old `*.json` format in the
   field to migrate (the gzip format shipped before any release), so the
   class has no job to do.

## 5. Content-hash book identity across the pipeline

```dart
class BookIdentity {
  final String contentHash;  // sha256 of raw file bytes (full digest)
  final String sourceId;     // 'local', 'drive:<fileId>', 'instapaper:<id>'…
  final String displayName;  // user-visible, mutable, NOT identity
}
```

- The hash is computed **once per (path, size, mtime)** in a background
  isolate and memoised in a small on-disk identity index
  (`content_index.json`: `path|size|mtime → contentHash`), so startup never
  re-reads file bytes for known files.
- Dedup key everywhere: `contentHash`. Two different `book.pdf` files
  coexist; the same book re-imported under a new path keeps its cache,
  bookmarks, and progress.
- Until bytes are fully present (mid-download), a provisional identity
  `prov:<sourceId>:<path>` is used and upgraded on completion.
- `pdf_cache` keys, section-store directories, bookmark keys, and progress
  keys all converge on `contentHash`.

## 6. Ring 2 — proposed ContentStore interface

```dart
/// Ring 2 — the only way anything (reader, range picker, future
/// summariser) obtains book text. Callers never see file paths, cache
/// keys, or extraction details.
abstract interface class ContentStore {
  /// Lightweight metadata — never loads text.
  Future<BookMetadata?> getMetadata(String bookId);

  /// Number of sections — never loads text.
  Future<int> getSectionCount(String bookId);

  /// One bounded word window (~200 sentences), from memory, disk, or
  /// on-demand extraction. The unit of caching and eviction.
  Future<Section?> getSection(String bookId, int sectionIndex);

  /// Fire-and-forget background load of an upcoming section.
  void prefetchSection(String bookId, int sectionIndex);

  /// Ingestion side (Ring 3 → Ring 2): persist an extracted document
  /// (or an incremental chunk of one) under its identity.
  Future<void> putDocument(BookIdentity identity, ExtractedDocument doc);

  /// Apply the cache policy (single budget, LRU by last-read).
  Future<void> enforceBudget();
}
```

`Section` carries `words`, `sentences`, `rawText`, and `SectionMetadata`
(word count, page range, `modelAnnotations` map) — the exact payload a
future on-device model receives. A difficulty model writes
`modelAnnotations['difficultyPerWord']`; the pacing engine reads it if
present. Ring 1 never calls a model.

## 7. Plan deltas vs. the review (and why)

- **CacheMigration is deleted, not repaired** — there is no legacy format in
  the field; a migration with nothing to migrate that can delete live data
  has negative value.
- **SectionStore/SectionCache are replaced, not wired** — see §4.
- **Phase 3 lands lazy loading at the store level first** (queue holds no
  text, reader fetches via store, sections persisted + evictable). Fully
  windowed in-session reading (BK-8's third copy) is staged behind the same
  interface; the session still materialises one copy of one book, which is
  bounded and is documented in SCALE_READINESS.md.
- **Instapaper queue shape** is adopted for Drive persistence (Phase 6) and
  the edge-AI queue stub (Phase 7), as the prompt directs.

## 8. What is healthy and untouched

WordTimer (O(1)/tick, drift-corrected); EPUB extraction (real isolates);
gzip codec + eviction in isolates; analytics cap; config write mutex;
Instapaper sync queue; ReadingProgressSync debounce; accessibility layer;
RSVP render path.
