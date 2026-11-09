# RunThru Data Layer — The Three Rings

> The result of the 2026-06 scale-architecture overhaul. The starting state
> and decision log live in `scale-architecture-snapshot.md`. The
> phase-by-phase change record is `SCALE_READINESS.md` at the repo root.

## The three rings

```
┌─────────────────────────────────────────────────┐
│  Ring 3 — Integrations                          │
│  Drive · Instapaper · Clipboard · Share · Files │
│  Future: Confluence · ReadWise · Pocket         │
│  Pattern: durable queue, coalescing, bounded    │
├─────────────────────────────────────────────────┤
│  Ring 2 — Content Store                         │
│  Sectioned, lazy, sha256-keyed                  │
│  Chunks handed to edge AI without copying       │
│  Cache: one policy, one budget, LRU by read     │
├─────────────────────────────────────────────────┤
│  Ring 1 — Reading Engine                        │
│  WordTimer · Pacing · Progress                  │
│  O(1) per tick, always. Ring 2 feeds it.        │
│  No extraction, no network, no JSON here.       │
└─────────────────────────────────────────────────┘
```

**Ring 1 is sealed.** `WordTimer` receives a word count, a synchronous word
source, and (optionally) a difficulty-multiplier source. It does not know
about files, caches, models, or networks. Its tick loop is O(1) and is not
to be modified.

**Ring 2 is the only way to obtain book text.** Readers, the range picker,
and future on-device models all call the same store. Where words came from
is invisible past this boundary.

**Ring 3 integrations all share one shape:**
`inbound content → size guard → deduplicate → enqueue → persist → extract → Ring 2.`
`InstapaperSyncQueue` is the reference implementation of the durable-queue
half of that shape; Drive (`DriveLocalStore` + streaming download) and the
`EdgeAiQueue` stub both follow it.

## Identity — content hash is the name of a book

`BookIdentity` (`lib/services/book_identity.dart`):

```dart
BookIdentity(
  contentHash: 'sha256-of-raw-file-bytes',  // THE identity
  sourceId:    'local' | 'drive:<fileId>' | 'instapaper:<id>',
  displayName: 'user visible, never identity',
)
```

* Hashes are computed once per `(path, size, mtime)` by
  `ContentIdentityService` and memoised in `content_index.json` — startup
  never re-reads bytes for known files. The hash is settled "for free"
  right after extraction, when the bytes are hot.
* Dedup is **never by filename**. Two different `book.pdf` files coexist;
  the same bytes under two paths collapse to one entry
  (`PreprocessingQueue._registerHash`, `FolderScannerService.scanSources`).
* Bookmarks (`BookmarkStore`) and progress (`ReadingProgress`) carry the
  hash, so they survive re-imports that change the path.
* Content not yet fully downloaded uses
  `BookIdentity.provisionalHash(sourceId, locator)` and is upgraded on
  completion. The content store refuses provisional identities.

## Ring 2 — ContentStore API

`lib/services/content_store/content_store.dart`. Layout on disk:

```
<appSupport>/content_store/index.json               bookId → lastReadAt/size
<appSupport>/content_store/<bookId>/manifest.json   BookMetadata
<appSupport>/content_store/<bookId>/section_0000.json.gz
```

```dart
final store = ref.read(contentStoreProvider);

// Metadata without text:
final meta = await store.getMetadata(bookId);     // BookMetadata?
final n    = await store.getSectionCount(bookId); // int

// Bounded text windows (~1500 words, sentence-aligned):
final section = await store.getSection(bookId, i); // Section?
store.prefetchSection(bookId, i + 1);              // fire-and-forget

// Iteration (what a summariser uses):
var cursor = await store.openCursor(bookId, 0);
while (cursor != null) {
  await model.process(cursor.section.rawText);
  cursor = await cursor.next();
}

// Ingestion (Ring 3 → Ring 2), idempotent:
await store.putDocument(identity, extractedDocument);

// Model output path:
await store.annotateSection(bookId, i, {'difficultyPerWord': [...]});
```

Writing order inside `putDocument` is **sections first, manifest last** — a
manifest's presence marks a fully ingested book, so crashes mid-write can't
produce a half-readable book, and re-running ingestion is a no-op.

`getDocument(bookId)` assembles the full book and is session-scoped only
(the reader materialises one book per session). Background code must use
`getSection`.

## Cache policy — one budget, one eviction

`ContentCachePolicy` (`lib/services/content_cache_policy.dart`):

* Total budget: 150 MB on low-end mobile (≤4 cores), 300 MB elsewhere.
* `PdfCache` (legacy gzip doc cache) and `ContentStore` share that budget:
  the store evicts with `enforceBudget(total, reservedBytes: pdfCacheUsage)`.
* Eviction is LRU **by last read**, at section-file granularity; manifests
  survive so metadata keeps working. Evicted text re-extracts on demand.
* `cacheStatsProvider` exposes "used X of Y MB" for debug/settings UI.
* Rule: no storage layer gets a private budget. Every cache has an eviction
  policy and tests for it.

## Extraction pipeline (local books)

```
scan (path dedup + memoised-hash dedup, O(1) per entry)
  → preview: pages 1–3 on the main isolate (pdfrx FFI constraint)
  → phase 2: chunks of 25 pages, each chunk:
       per-chunk 30s timeout, cooperative cancel between pages
       commit: partial doc → preview cache, progress → BookManifestStore
  → done: full doc → PdfCache + ContentStore (write-through migration)
```

* `BookManifestStore` remembers page counts — a cold start with a 200-book
  library opens zero PDFs.
* A 600-page book extracts across as many launches as it needs; retries
  resume from the last committed chunk, never from page 3.
* **Reading is the host; extraction is a guest.** While
  `WordTimer.isPlaying`, the queue starts no new work and in-flight
  completions yield at the next chunk boundary (scheduling, not killing).
* Queue state holds **metadata only**. Only the actively read book has its
  document materialised, and the reading screens release it on dispose
  (`PreprocessingQueue.releaseDocument`). Idle memory is O(library count),
  not O(library words).

## Bookmarks and progress

* `BookmarkStore` (`lib/store/bookmark_store.dart`): one SharedPreferences
  entry per bookmark (`runthru_bm_<path>`) — a position save writes one
  small record. Entries carry the content hash and re-key themselves after
  re-imports. Legacy config-blob bookmarks were migrated once and remain in
  the config read-only as the rollback path. **Never add a bookmark writer
  to `ConfigNotifier` again.**
* `ReadingProgress`: capped at 500 records, hash-aware dedupe.
* Removing a source sets `kPrunePendingKey`; the next scan prunes local
  bookmarks/progress whose path and hash exist in no remaining source.
  Remote ids (`instapaper://…`) are never touched by the prune.

## Integration pattern (the Instapaper shape)

Every integration converges on:

1. **Size guard** before bytes move (Drive: 200 MB PDF / 50 MB EPUB).
2. **Stream to disk**, never `bodyBytes`, for binary payloads
   (`GoogleDriveClient.downloadSelectedFileTo`).
3. **Persist under content hash** (`DriveLocalStore`) + ingest into Ring 2 —
   "Continue Reading" is local after the first import.
4. **Deterministic temp cleanup** — on success, on failure, and a startup
   sweep of `runthru-drive-*` older than 24 h.
5. **Bounded listing** — `listDriveFiles` caps at 500; search narrows.
6. **Durable queue** for writes/long work, coalescing per key, transient
   errors retained, permanent errors dropped with a log line
   (`InstapaperSyncQueue`, `EdgeAiQueue`).

A future Confluence/ReadWise/Pocket source is "just another Ring 3 path
that produces sections in Ring 2" — copy the Drive/Instapaper shape.

## Edge AI extension points

To ship on-device summarization or difficulty scoring:

1. Implement `ModelProcessor` (`lib/services/edge_ai_queue.dart`) — it
   receives a `SectionProcessingRequest` plus a `Section` (`words`,
   `rawText`, `SectionMetadata`) and returns an annotations map.
2. Swap it into `edgeAiQueueProvider` (replacing `NoopModelProcessor`).
3. Enqueue work: `edgeAiQueue.enqueue(SectionProcessingRequest(...))` —
   durable, coalescing, drains in the background.
4. Results persist via `ContentStore.annotateSection` into
   `SectionMetadata.modelAnnotations`.
5. Pacing picks up `modelAnnotations['difficultyPerWord']` through
   `WordTimerNotifier.attachDifficultySource` — used only when attached.

Ring 1 never calls a model. The reading engine reads annotations if they
exist; otherwise nothing changes.

## Memory model during reading

In RAM while a word is flashing: one book's word/sentence lists (the active
session's document), the pacing config, UI state, and at most a handful of
sections in the store's memory LRU (cap 6). No other book's text, no queue
copies of completed books, no config-blob churn.
