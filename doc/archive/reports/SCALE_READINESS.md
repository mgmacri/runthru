# SCALE_READINESS — Data & Processing Foundation Overhaul

Date: 2026-06-11 · Branch: main · Verification: `dart analyze --fatal-infos`
→ **0 issues**, `flutter test` → **984 passed, 0 failed**.
(`scripts/verify_release_readiness.sh` referenced by the work order does not
exist in this repo — no such script was ever checked in; analyze + tests are
the enforced gates.)

## Manual QA plan

Automated checks prove the code compiles and the unit/widget contracts hold.
The first manual pass should not be random clicking; it should target lifecycle,
real files, real Drive, app restarts, force-kills, cache pressure, and
user-perceived reading behavior. These are the places most likely to regress
despite a clean analyzer and passing tests.

### P0 — must test before committing

1. **Clean install / first launch / onboarding**

   Reset the app fully, then run it fresh:

   ```bash
   adb -s emulator-5554 shell am force-stop com.runthru.app
   adb -s emulator-5554 shell pm clear com.runthru.app
   adb -s emulator-5554 uninstall com.runthru.app
   flutter clean
   flutter pub get
   flutter run -d emulator-5554 \
     --enable-impeller \
     --dart-define-from-file=dart_defines/development.json
   ```

   Verify onboarding appears only on true first launch, all slides advance,
   Skip and Finish work, no blank/black screen appears after completion, reading
   goal presets are reachable from onboarding and settings, and relaunch does
   not show onboarding again unless app data is cleared.

2. **Local import identity: same filename, different books**

   Import two different PDFs both named `book.pdf` from different folders.
   Verify both appear separately, open to their own text, keep separate
   bookmarks/progress, and removing one source does not remove the other's
   usable state.

3. **Re-import identity: same book, new path**

   Import a PDF, read for 1-2 minutes, exit, copy/move the exact same bytes to
   a different folder, and import again. Verify it resumes existing
   bookmark/progress, cache is reused or quickly available, and the library does
   not create a confusing duplicate unless duplicate sources are intentional.

4. **Active-book memory / lifecycle**

   Use two large PDFs. Open A, read, return to library, open B, return, reopen
   A, and repeat. Verify no stale words flash between books, positions remain
   correct, memory does not climb forever, and the app stays responsive.

5. **Large PDF / long extraction**

   Import a 300-600 page PDF. Background/foreground during preprocessing,
   force-stop mid-extraction, relaunch, and open once content is available.
   Verify no whole-book timeout, partial progress survives relaunch, page count
   comes from manifests, the app remains usable, and extraction does not run
   aggressively while reading is playing.

6. **Reading stays king**

   While a large book is preprocessing, open another book and start RSVP
   playback. Verify playback is smooth, WPM changes respond immediately, there
   is no visible chunk-boundary jank, extraction yields while reading is active,
   and background extraction continues after pausing.

7. **Bookmark force-kill recovery**

   Read for 30-60 seconds, then force-kill:

   ```bash
   adb shell am force-stop com.runthru.app
   ```

   Relaunch and verify resume is within roughly the last few seconds of the
   visible word, with no reset to start and no jump to another book/location.
   Repeat for local PDF, EPUB, Drive-imported file, and Instapaper article when
   configured.

8. **Drive import / Continue Reading**

   Test Google Drive with a small PDF, small EPUB, PDF over 200 MB, EPUB over
   50 MB, and an unsupported file type. Verify supported files import,
   oversized/unsupported files fail gracefully before full download, Continue
   Reading survives force-kill, reopening does not re-download, airplane mode
   can open previously imported Drive files, and temp files do not accumulate
   after failed imports.

### P1 — strongly recommended before internal testing

9. **Cache pressure / eviction**

   Import enough large files to exceed the low-end cache budget. Verify no
   crash, older cached sections/files evict, manifests remain, recently read
   books stay warm, evicted books reopen via rehydrate/re-extract, and any cache
   stats UI reports plausible usage.

10. **Source removal / orphan prune**

    Add a folder source with several books, read/bookmark a few, then remove the
    source. Verify removed books leave the active library, unrelated books
    remain, orphaned bookmarks/progress are eventually pruned, and re-adding the
    source restores usable entries without identity corruption.

11. **Reading mode regression sweep**

    On one normal imported book, test RSVP/single-word mode, sentence mode,
    paragraph mode, full-page mode, swipe up/down transitions, WPM dial,
    pause/play, back navigation, font size controls, and range picker behavior.
    Duplicate common-word range selection may still choose the first occurrence;
    treat that as an expected limitation unless it got worse.

12. **Neurodivergent UX / accessibility mission checks**

    Verify pause->play auto-rewinds exactly 3 words and clamps to 0,
    ContextReveal swipe-up enters sentence view, ContextReveal resume returns to
    the correct word without regular auto-rewind, Atkinson Hyperlegible is
    default or clearly selectable, reduced motion disables animations, WPM dial
    long-press hint is discoverable, focus mode removes chrome, and onboarding
    hints announce with live-region semantics.

13. **TalkBack / VoiceOver pass**

    Enable Android TalkBack (and VoiceOver on iOS when available). Verify
    onboarding is navigable, reading controls have meaningful labels,
    back/fullscreen/font/WPM controls are reachable, WPM can be adjusted without
    sight, focus mode leaves an accessible exit path, completion overlays
    announce, and core reading flow has no meaningless unlabeled controls.

14. **Offline / bad network**

    Use airplane mode and flaky network. Verify local books open offline,
    previously imported Drive files open offline, new Drive imports fail
    gracefully, Instapaper failures show humane errors, the app does not stick
    in permanent loading, and retry works after network restoration.

15. **Startup with a large library**

    Use 50-100 files if possible. Verify startup does not feel like it opens
    every PDF, the library appears quickly, page counts/statuses populate from
    manifests, scrolling remains smooth, and failed files show bounded readable
    errors.

### P2 — final polish pass

16. **Release-readiness smoke**

    Build the release bundle:

    ```bash
    flutter build appbundle --release \
      --dart-define=INSTAPAPER_CONSUMER_KEY=test \
      --dart-define=INSTAPAPER_CONSUMER_SECRET=test
    ```

    Verify no debug banner, no debug-only UI, privacy policy still matches real
    data flows, purchase stub is not treated as GA-ready, and release notes are
    accurate.

### Shortest useful manual pass

Run these first if time is tight: clean install onboarding; same-name different
PDFs; same PDF from new path; A/B/A memory lifecycle; 600-page extraction with
force-kill/resume; reading while extraction runs; bookmark force-kill recovery;
Drive import/offline reopen/oversized rejection; cache pressure; TalkBack on
onboarding and reading controls.

## Verdict

**The engine now scales by design, not by luck.** Idle memory is
O(library count), reading memory is O(one book), every byte of cached text
sits under one budgeted, evictable, content-hash-keyed store, and every
integration funnels through the same durable-queue shape. A 100-book library
no longer pre-loads 100 books of text into the heap; a 600-page scan no
longer dies at a 30-second timeout; a re-imported book keeps its bookmark.
The edge-AI seams (section payloads, annotation channel, durable model
queue, pacing hook) are wired and tested with a no-op processor.

## Phase-by-phase changes

| Phase | What landed |
|---|---|
| 0 | `doc/architecture/scale-architecture-snapshot.md` — data-flow audit, SectionStore verdict (replace, don't wire), Ring 2 interface contract |
| 1 | Deleted destructive `CacheMigration`; queue no longer retains documents (background workers store metadata only, `releaseDocument()` on reader dispose, rehydrate-from-cache in `prioritize`) |
| 2 | `BookIdentity` + `ContentIdentityService` (memoised sha256), O(1) enqueue dedup, hash-aware duplicate collapse in queue and scanner, `ContentCachePolicy` (150/300 MB single budget) + `CacheStats`, isolate-safe budget capture in `PdfCache` |
| 3 | Ring 2 `ContentStore` (gzip sections ~1500 words, manifest-last crash-safe writes, memory LRU, prefetch, budget eviction that spares manifests); dead `SectionStore`/`SectionCache` deleted; migrate-on-touch from legacy `pdf_cache` + dry-run report; library screen rebuilt per-tile (BK-10) |
| 4 | 25-page chunked phase-2 with per-chunk timeout, cooperative cancel between pages, durable per-chunk commits (`BookManifestStore`); page-count manifest (no PDF reopening at startup); extraction yields while `WordTimer.isPlaying` |
| 5 | `BookmarkStore` (per-entry writes, hash re-keying, one-time config migration with rollback); `ReadingProgress` capped at 500 + hash dedupe; source-removal prune of orphaned bookmarks/progress |
| 6 | Drive: size guard (200 MB PDF / 50 MB EPUB), streaming download to disk, persisted local copies + store ingestion (local "Continue Reading"), deterministic temp cleanup + startup sweep, 500-result listing cap |
| 7 | `Section`/`SectionCursor` contract, `ContentStore.annotateSection`, `EdgeAiQueue` (Instapaper shape, no-op processor), `WordTimer.attachDifficultySource` pacing hook |
| 8 | `doc/architecture/data_layer.md`, CLAUDE.md rules 11–19, this report |

## Acceptance criteria (review findings)

| Item | Status | How |
|---|---|---|
| BK-1 queue retains all text | **Fixed** | Background entries carry no document; release on dispose; tests prove A's text gone after closing A |
| BK-2 50 MB LRU thrash | **Fixed** | Single 150/300 MB policy across `PdfCache` + `ContentStore`; LRU by last-read; eviction tests |
| BK-3 main-isolate extraction ×6 | **Mitigated** | pdfrx FFI still pins extraction to the main isolate (library constraint), but: no extraction during reading, chunked work with yields, page counts from manifest (no startup reopen storm) |
| BK-4 filename dedup collapse | **Fixed** | Hash-based identity in queue + scanner; coexistence and collapse tests |
| BK-5 bookmarks in config blob | **Fixed** | `BookmarkStore`, per-entry writes, hash re-keying, migration + rollback |
| BK-6 CacheMigration live trap | **Fixed** | Deleted (nothing to migrate; it deleted valid cache); dead section layer removed |
| BK-7 30s whole-book cap | **Fixed** | Per-chunk timeout, durable chunk commits, resume across launches, cancel token stops abandoned loops |
| BK-8 ~3 flat word-list copies | **Partially fixed / deferred** | Queue's copy is gone (shared reference + release). The reading session still materialises one full book (see Deferrals) |
| BK-9 Drive unbounded/unpersisted | **Fixed** | Size guard, streaming, local copies, temp cleanup, listing cap; tests for each |
| BK-10 whole-queue library watch | **Fixed** | Per-tile `select` watch + `pdfFailedCountProvider` |
| BK-11 String.hashCode cache key | **Fixed at the system level** | Durable storage (ContentStore, bookmarks, progress) keys on sha256. Legacy `PdfCache` keeps its key to avoid a second cache invalidation; it is now a warm-tier whose misses fall back to the ContentStore, not to re-extraction |
| BK-12 O(n²) enqueue | **Fixed** | `_enqueuedKeys` set, O(1) |
| BK-13 multi-KB log line | **Fixed** | Bounded 3-name sample |
| BK-14 unbounded progress records | **Fixed** | 500-record cap, hash dedupe, prune |

## Memory model during reading

One book's sentence/word lists (the active session), pacing data, UI state,
≤6 store sections in the memory LRU. Background books: status + progress
structs only. Bookmark saves write one ~150-byte record, not the config.

## Known remaining issues (deliberate deferrals)

1. **In-session windowed reading (rest of BK-8).** The reader still loads
   the full active book (one copy; bounded by one book, ~5–20 MB for very
   large books). Sentence navigation, ContextReveal, and range slicing in
   `parallax_reading_screen.dart` (3,000 lines) assume random access to the
   whole document. The ContentStore section API was designed so a windowed
   `SessionWordSource` can replace this without interface changes; doing it
   inside this overhaul would have been a high-risk rewrite of the most
   accessibility-sensitive screen for a per-book (not per-library) win.
2. **`PdfCache` re-keying.** Kept its `path|mtime` hashCode key as a warm
   tier to avoid invalidating every user's cache twice in one release.
   Books flow into the sha256-keyed ContentStore on touch; once a release
   has soaked, `PdfCache` can be dropped entirely (extraction would then
   write sections directly).
3. **Preview-phase writes still go to `PdfCache`.** Partial (chunk) commits
   use the preview cache; only complete books enter the ContentStore. Folding
   partials into the store is the natural follow-on to deferral 2.
4. **`Section.rawText` joins with single spaces** — fine for model input
   and RSVP; not a faithful reconstruction of source whitespace.

## Roadmap notes

* **Confluence / ReadWise / Pocket**: implement a Ring 3 client with the
  Drive shape (size guard → stream → hash → `DriveLocalStore`-style copy →
  `ContentStore.putDocument`) and a durable sync queue with the Instapaper
  shape. No Ring 1 or Ring 2 changes.
* **On-device summarization**: implement `ModelProcessor`, swap it into
  `edgeAiQueueProvider`, enqueue `SectionProcessingRequest`s; results land
  in `modelAnnotations` and surface wherever the UI wants them.
* **Difficulty-adaptive pacing**: a difficulty model writes
  `modelAnnotations['difficultyPerWord']`; the reader wires
  `SectionMetadata.difficultyPerWord` into
  `WordTimer.attachDifficultySource`. The hook and tests already exist.
