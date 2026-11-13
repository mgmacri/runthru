import 'dart:async';
import 'dart:collection';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/services/book_identity.dart';
import 'package:runthru/services/book_manifest_store.dart';
import 'package:runthru/services/content_cache_policy.dart';
import 'package:runthru/services/content_identity.dart';
import 'package:runthru/services/content_store/content_store.dart';
import 'package:runthru/services/document_classifier.dart';
import 'package:runthru/services/device_capability.dart';
import 'package:runthru/services/epub_extractor.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/notification_service.dart';
import 'package:runthru/services/pdf_cache.dart';
import 'package:runthru/services/pdf_extractor.dart';
import 'package:runthru/features/reading/providers/reading_progress_provider.dart';
import 'package:runthru/store/bookmark_store.dart';
import 'package:runthru/store/library_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hyper-parallel PDF preprocessing queue with adaptive worker pool,
/// progressive extraction (preview → full), and priority preemption.
class PreprocessingQueue extends StateNotifier<Map<String, PdfEntry>> {
  PreprocessingQueue(this._ref) : super({}) {
    _maxWorkers = _ref.read(deviceCapabilityProvider).maxWorkers;
    _currentMaxWorkers = _maxWorkers;
    scheduleMicrotask(_init);
  }

  final Ref _ref;

  late final ContentIdentityService _identity = _ref.read(
    contentIdentityProvider,
  );

  late final BookManifestStore _manifest = _ref.read(bookManifestStoreProvider);

  /// Pages (or EPUB chapters) extracted per phase-2 chunk. Each chunk gets
  /// its own timeout and durable commit. Mutable for tests/tuning.
  static int completionChunkPages = 25;

  /// Phase 1 queue — preview extraction (pages 1–3).
  final _previewQueue = Queue<String>();

  /// Phase 2 queue — background completion (remaining pages).
  final _completionQueue = Queue<String>();

  /// Tracks actively running workers by filePath.
  final _activeWorkers = <String>{};

  /// O(1) dedup index of enqueued canonical path keys (BK-12).
  final _enqueuedKeys = <String>{};

  /// Resolved content hashes: canonical path key → sha256.
  final _hashByPath = <String, String>{};

  /// Reverse index for duplicate-content collapse: sha256 → path key.
  final _pathByHash = <String, String>{};

  /// The priority file currently being processed (if any).
  String? _priorityFile;

  late final int _maxWorkers;
  late int _currentMaxWorkers;

  bool _isPaused = false;

  final _progressController = StreamController<PdfEntry>.broadcast();

  Stream<PdfEntry> get progress => _progressController.stream;

  /// Whether a priority preemption is currently in progress.
  bool get isPriorityProcessing => _priorityFile != null;

  /// Number of files that failed permanently.
  int get failedCount =>
      state.values.where((e) => e.status == PdfStatus.permanentlyFailed).length;

  /// Number of files with transient errors.
  int get errorCount =>
      state.values.where((e) => e.status == PdfStatus.error).length;

  /// Overall progress across all PDFs.
  OverallProgress get overallProgress {
    final total = state.length;
    final completed = state.values
        .where(
          (e) =>
              e.status == PdfStatus.ready ||
              e.status == PdfStatus.permanentlyFailed ||
              e.status == PdfStatus.unsupported,
        )
        .length;
    return OverallProgress(completed: completed, total: total);
  }

  Timer? _notificationTimer;

  void _init() {
    // Configure the shared cache budget before any extraction writes.
    _ref.read(contentCachePolicyProvider);
    _ref.listen(pdfListProvider, (previous, next) {
      next.when(data: _enqueueAll, loading: () {}, error: (_, __) {});
    });
    // Initial enqueue
    final entries = _ref.read(pdfListProvider);
    entries.when(data: _enqueueAll, loading: () {}, error: (_, __) {});
  }

  void _enqueueAll(List<PdfEntry> entries) {
    appLog('preprocessing', 'enqueueAll — ${entries.length} files');
    for (final entry in entries) {
      _enqueueIfNew(entry);
    }
    _startNotificationUpdates();
    _fillWorkers();
    unawaited(_maybePruneOrphans(entries));
  }

  /// After a source removal, prunes bookmarks/progress for books that exist
  /// in no remaining source. Async and non-blocking — runs after a scan.
  Future<void> _maybePruneOrphans(List<PdfEntry> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(kPrunePendingKey) ?? false)) return;

      final activePaths = {for (final e in entries) e.filePath};
      final activeHashes = <String>{};
      for (final e in entries) {
        final hash = await _identity.knownHashFor(e.filePath);
        if (hash != null) activeHashes.add(hash);
      }
      if (!mounted) return;

      final bookmarks = _ref.read(bookmarkStoreProvider.notifier);
      await _ref.read(bookmarkStoreProvider.future);
      final prunedBookmarks = await bookmarks.pruneMissingLocal(
        activePaths: activePaths,
        activeHashes: activeHashes,
      );
      if (!mounted) return;
      final progress = _ref.read(readingProgressProvider.notifier);
      await _ref.read(readingProgressProvider.future);
      final prunedProgress = await progress.pruneMissingLocal(
        activePaths: activePaths,
        activeHashes: activeHashes,
      );

      await prefs.setBool(kPrunePendingKey, false);
      appLog(
        'preprocessing',
        'orphan prune complete bookmarks=$prunedBookmarks '
            'progress=$prunedProgress',
      );
    } on Object catch (e) {
      appLog('preprocessing', 'orphan prune failed: $e');
    }
  }

  /// Enqueue entries from a streaming multi-directory scan.
  void enqueueEntry(PdfEntry entry) {
    _enqueueIfNew(entry);
    _fillWorkers();
  }

  void _enqueueIfNew(PdfEntry entry) {
    // Identity rule: dedup by canonical path now (O(1)), upgraded to
    // content hash as hashes resolve — never by filename, which collapses
    // distinct books that happen to share a name (BK-4).
    final key = canonicalPathKey(entry.filePath);
    if (!_enqueuedKeys.add(key)) {
      appLog('preprocessing', 'enqueue skipped duplicate key=$key');
      return;
    }
    state = {
      ...state,
      entry.filePath: entry.copyWith(status: PdfStatus.queued),
    };
    _previewQueue.add(entry.filePath);
    appLog('preprocessing', 'enqueue file=${entry.fileName}');
    // Cheap (stat + index lookup) identity check — collapses re-imported
    // copies whose content hash is already known.
    unawaited(_resolveKnownIdentity(entry.filePath));
  }

  /// Looks up a memoised content hash for [filePath] and collapses the entry
  /// if that content is already queued under another path.
  Future<void> _resolveKnownIdentity(String filePath) async {
    try {
      final hash = await _identity.knownHashFor(filePath);
      if (hash == null || !mounted) return;
      _registerHash(filePath, hash);
    } on Object catch (e) {
      appLog('preprocessing', 'identity lookup failed: $e');
    }
  }

  /// Computes (if needed) and registers the content hash after extraction —
  /// the bytes were just read anyway, so hashing here is nearly free.
  Future<void> _upgradeIdentity(String filePath) async {
    try {
      final hash = await _identity.ensureHash(filePath);
      if (hash == null || !mounted) return;
      _registerHash(filePath, hash);
    } on Object catch (e) {
      appLog('preprocessing', 'identity upgrade failed: $e');
    }
  }

  DateTime _lastBudgetEnforce = DateTime.fromMillisecondsSinceEpoch(0);

  /// Write-through into the Ring 2 content store (and incremental migration
  /// of legacy PdfCache entries on touch). Idempotent per content hash.
  Future<void> _ingestToStore(String filePath, ExtractedDocument doc) async {
    try {
      await _upgradeIdentity(filePath);
      final hash = contentHashOf(filePath);
      if (hash == null || !mounted) return;
      final store = _ref.read(contentStoreProvider);
      if (await store.hasBook(hash)) {
        _touch(filePath);
        return;
      }
      final fileName = filePath.split(RegExp(r'[/\\]')).last;
      await store.putDocument(
        BookIdentity(
          contentHash: hash,
          sourceId: 'local',
          displayName: fileName,
        ),
        doc,
      );
      _touch(filePath);
      // Enforce the shared budget, at most once a minute — eviction scans
      // directories and shouldn't run per book during a bulk extraction.
      final now = DateTime.now();
      if (now.difference(_lastBudgetEnforce).inSeconds >= 60) {
        _lastBudgetEnforce = now;
        if (!mounted) return;
        final policy = _ref.read(contentCachePolicyProvider);
        final reserved = await PdfCache.totalUsageBytes();
        await store.enforceBudget(
          policy.totalBudgetBytes,
          reservedBytes: reserved,
        );
      }
    } on Object catch (e) {
      appLog('preprocessing', 'store ingest failed file=$filePath: $e');
    }
  }

  /// Replaces [filePath]'s entry with a copy of itself, so that whatever
  /// watches the entry looks again. The book was marked ready before its
  /// hash was known and its text stored; what is read from the store by
  /// hash (a library row's word count) can only be found from here on.
  void _touch(String filePath) {
    if (!mounted) return;
    final entry = state[filePath];
    if (entry != null) _update(filePath, entry.copyWith());
  }

  /// Test-only: writes [doc] through to the content store as a finished
  /// extraction of [filePath] does.
  @visibleForTesting
  Future<void> debugIngest(String filePath, ExtractedDocument doc) =>
      _ingestToStore(filePath, doc);

  /// Returns the resolved content hash for [filePath], if known.
  String? contentHashOf(String filePath) =>
      _hashByPath[canonicalPathKey(filePath)];

  void _registerHash(String filePath, String hash) {
    final key = canonicalPathKey(filePath);
    final existingPath = _pathByHash[hash];
    if (existingPath != null && existingPath != key) {
      // Same content under two paths — keep the first, drop this one.
      // Surface the collapse explicitly (observability over silence).
      appLog(
        'preprocessing',
        'duplicate content collapsed file=$filePath '
            'hash=${hash.substring(0, 12)} keptPath=$existingPath',
      );
      _previewQueue.remove(filePath);
      _completionQueue.remove(filePath);
      _enqueuedKeys.remove(key);
      _hashByPath.remove(key);
      if (!mounted) return;
      final next = {...state}..remove(filePath);
      state = next;
      return;
    }
    _hashByPath[key] = hash;
    _pathByHash[hash] = key;
  }

  /// Test-only: injects an entry directly into queue state.
  @visibleForTesting
  void debugSetEntry(PdfEntry entry) {
    _enqueuedKeys.add(canonicalPathKey(entry.filePath));
    state = {...state, entry.filePath: entry};
  }

  /// Releases the in-memory document for [filePath] after a reading session
  /// ends. The extracted text stays in [PdfCache]; the next [prioritize]
  /// rehydrates it from disk. Keeps queue memory O(metadata), not O(words).
  void releaseDocument(String filePath) {
    if (!mounted) return;
    final entry = state[filePath];
    if (entry == null || entry.document == null) return;
    state = {...state, filePath: entry.copyWith(clearDocument: true)};
    appLog('preprocessing', 'released document file=${entry.fileName}');
  }

  /// Pause all background processing.
  void pauseBackground() {
    _isPaused = true;
  }

  /// Resume background processing.
  void resumeBackground() {
    _isPaused = false;
    _fillWorkers();
  }

  /// Prioritize a single file — if preview, extract remaining pages immediately.
  ///
  /// If the file is not yet in the queue (e.g. the reader was opened before
  /// the background scan finished), it is enqueued on-demand so extraction
  /// can proceed.
  Future<void> prioritize(String filePath) async {
    var existing = state[filePath];
    if (existing == null) {
      // Not yet scanned — enqueue on demand so extraction can proceed.
      final fileName = filePath.split(RegExp(r'[/\\]')).last;
      _enqueueIfNew(PdfEntry(filePath: filePath, fileName: fileName));
      existing = state[filePath];
      if (existing == null) return; // dedup removed it; already processing
    }
    if (existing.status == PdfStatus.ready) {
      if (existing.document != null) return;
      // Document was released after a previous session — rehydrate from
      // cache without re-extracting.
      final cached = await PdfCache.load(filePath);
      if (cached != null) {
        if (!mounted) return;
        final current = state[filePath];
        if (current == null) return;
        _update(filePath, current.copyWith(document: cached));
        unawaited(_ingestToStore(filePath, cached));
        return;
      }
      // Legacy cache miss — try the Ring 2 content store before paying for
      // a re-extraction.
      final hash =
          contentHashOf(filePath) ?? await _identity.knownHashFor(filePath);
      if (hash != null) {
        final fromStore = await _ref
            .read(contentStoreProvider)
            .getDocument(hash);
        if (fromStore != null) {
          if (!mounted) return;
          final current = state[filePath];
          if (current == null) return;
          _update(filePath, current.copyWith(document: fromStore));
          return;
        }
      }
      if (!mounted) return;
      // Cache evicted — fall through to a full re-extraction.
      if (!mounted) return;
      _update(
        filePath,
        existing.copyWith(
          status: PdfStatus.queued,
          clearDocument: true,
          retryCount: 0,
          progress: const PdfProgress(),
        ),
      );
      existing = state[filePath];
      if (existing == null) return;
    }

    _priorityFile = filePath;

    // Remove from queues to avoid double-processing.
    _previewQueue.remove(filePath);
    _completionQueue.remove(filePath);

    // Temporarily reduce background worker count by 1.
    _currentMaxWorkers = (_maxWorkers - 1).clamp(1, _maxWorkers);

    if (existing.status == PdfStatus.preview) {
      // Already have preview — just extract remaining pages.
      await _processBackgroundCompletion(filePath, isPriority: true);
    } else {
      // Not even previewed — do full extraction.
      await _processPreview(filePath, isPriority: true);
      final afterPreview = state[filePath];
      if (afterPreview?.status == PdfStatus.preview) {
        await _processBackgroundCompletion(filePath, isPriority: true);
      }
    }

    // Restore worker count and resume.
    _priorityFile = null;
    _currentMaxWorkers = _maxWorkers;
    _fillWorkers();
  }

  /// Fill worker slots from preview queue first, then completion queue.
  void _fillWorkers() {
    if (!mounted) return;
    if (_isPaused) return;

    while (_activeWorkers.length < _currentMaxWorkers) {
      if (_previewQueue.isNotEmpty) {
        final filePath = _previewQueue.removeFirst();
        final entry = state[filePath];
        if (entry == null || entry.status == PdfStatus.permanentlyFailed) {
          continue;
        }
        _activeWorkers.add(filePath);
        _processPreview(filePath).whenComplete(() {
          if (!mounted) return;
          _activeWorkers.remove(filePath);
          // After preview, enqueue for background completion if needed.
          final current = state[filePath];
          if (current?.status == PdfStatus.preview) {
            _completionQueue.add(filePath);
          }
          _fillWorkers();
        });
      } else if (_completionQueue.isNotEmpty) {
        final filePath = _completionQueue.removeFirst();
        final entry = state[filePath];
        if (entry == null ||
            entry.status == PdfStatus.ready ||
            entry.status == PdfStatus.permanentlyFailed) {
          continue;
        }
        _activeWorkers.add(filePath);
        _processBackgroundCompletion(filePath).whenComplete(() {
          if (!mounted) return;
          _activeWorkers.remove(filePath);
          _fillWorkers();
        });
      } else {
        break;
      }
    }

    // Check if all processing is done.
    if (_activeWorkers.isEmpty &&
        _previewQueue.isEmpty &&
        _completionQueue.isEmpty) {
      _stopNotificationUpdates();
    }
  }

  /// Phase 1: Extract preview pages (1–3).
  Future<void> _processPreview(
    String filePath, {
    bool isPriority = false,
  }) async {
    final entry = state[filePath];
    if (entry == null) return;

    // Check full cache first — skip both phases.
    try {
      final kind = await DocumentClassifier.classifyPath(filePath);
      if (kind == DocumentKind.unsupported) {
        _update(
          filePath,
          entry.copyWith(
            status: PdfStatus.unsupported,
            errorMessage: 'This file type is not supported.',
          ),
        );
        return;
      }

      final cachedFull = await PdfCache.load(filePath);
      if (cachedFull != null) {
        // Memory rule: only the prioritized (actively read) file keeps its
        // document in queue state. Background books carry metadata only —
        // the text stays on disk until a reading session asks for it.
        _update(
          filePath,
          entry.copyWith(
            status: PdfStatus.ready,
            document: isPriority ? cachedFull : null,
            clearDocument: !isPriority,
            progress: PdfProgress(
              lastCompletedPage: cachedFull.totalPages,
              totalPages: cachedFull.totalPages,
              phase: ExtractionPhase.done,
            ),
          ),
        );
        unawaited(_ingestToStore(filePath, cachedFull));
        return;
      }
    } on Object catch (e) {
      dev.log('Cache check failed: $e', name: 'preprocessing');
    }

    // Check preview cache.
    try {
      final cachedPreview = await PdfCache.loadPreview(filePath);
      if (cachedPreview != null) {
        // Page counts come from the durable manifest — a cold start with a
        // 200-book library must not open 200 PDFs (BK-3). Unknown books are
        // counted once and written back.
        final manifestEntry = await _manifest.entryFor(filePath);
        final int totalPages;
        if (manifestEntry != null && manifestEntry.pageCount > 0) {
          totalPages = manifestEntry.pageCount;
        } else {
          final kind = await DocumentClassifier.classifyPath(filePath);
          totalPages = kind == DocumentKind.epub
              ? await epubChapterCountInIsolate(filePath)
              : await pdfPageCountInIsolate(filePath);
          await _manifest.setPageCount(filePath, totalPages);
        }
        // Resume from committed chunk progress when it goes beyond the
        // bare preview (the preview cache holds everything committed).
        final resumePage = (manifestEntry?.lastCompletedPage ?? 0).clamp(
          previewPageCount.clamp(0, totalPages),
          totalPages,
        );
        _update(
          filePath,
          entry.copyWith(
            status: PdfStatus.preview,
            document: isPriority ? cachedPreview : null,
            clearDocument: !isPriority,
            progress: PdfProgress(
              lastCompletedPage: resumePage,
              totalPages: totalPages,
              phase: ExtractionPhase.preview,
            ),
          ),
        );
        return;
      }
    } on Object catch (e) {
      dev.log('Preview cache check failed: $e', name: 'preprocessing');
    }

    // Mark processing.
    _update(filePath, entry.copyWith(status: PdfStatus.processing));

    try {
      final kind = await DocumentClassifier.classifyPath(filePath);
      if (kind == DocumentKind.unsupported) {
        throw const UnsupportedPdfError('This file type is not supported.');
      }
      final result = kind == DocumentKind.epub
          ? await extractEpubPagesInIsolate(filePath, 0, previewPageCount - 1)
          : await extractPdfPagesInIsolate(filePath, 0, previewPageCount - 1);

      final totalPages = result.totalPages;
      final previewDoc = result.document;
      // Actual pages extracted (may exceed previewPageCount if front
      // matter was blank and the extractor probed deeper).
      final pagesExtracted = result.extractedEndPage + 1;

      // A fresh preview supersedes any stale committed chunk progress (the
      // preview cache was lost, so older progress is no longer recoverable).
      await _manifest.setProgress(
        filePath,
        lastCompletedPage: pagesExtracted,
        pageCount: totalPages,
      );

      // Save preview to cache (don't block).
      PdfCache.savePreview(filePath, previewDoc).catchError((Object e) {
        dev.log('Preview cache save failed: $e', name: 'preprocessing');
      });

      if (pagesExtracted >= totalPages) {
        // Small PDF or probe covered everything.
        PdfCache.save(filePath, previewDoc).catchError((Object e) {
          dev.log('Cache save failed: $e', name: 'preprocessing');
        });
        _update(
          filePath,
          entry.copyWith(
            status: PdfStatus.ready,
            document: isPriority ? previewDoc : null,
            clearDocument: !isPriority,
            retryCount: 0,
            progress: PdfProgress(
              lastCompletedPage: totalPages,
              totalPages: totalPages,
              phase: ExtractionPhase.done,
            ),
          ),
        );
      } else {
        _update(
          filePath,
          entry.copyWith(
            status: PdfStatus.preview,
            document: isPriority ? previewDoc : null,
            clearDocument: !isPriority,
            retryCount: 0,
            progress: PdfProgress(
              lastCompletedPage: pagesExtracted,
              totalPages: totalPages,
              phase: ExtractionPhase.preview,
            ),
          ),
        );
      }
      // The file's bytes were just read — settle its content identity now.
      // Complete books also flow into the Ring 2 store; previews stay in
      // PdfCache only (the store holds fully ingested books).
      if (pagesExtracted >= totalPages) {
        unawaited(_ingestToStore(filePath, previewDoc));
      } else {
        unawaited(_upgradeIdentity(filePath));
      }
    } on UnsupportedPdfError catch (e) {
      appLog('preprocessing', 'unsupported file=$filePath error=${e.message}');
      _update(
        filePath,
        entry.copyWith(status: PdfStatus.unsupported, errorMessage: e.message),
      );
    } on PdfTimeoutError catch (e) {
      appLog('preprocessing', 'timeout file=$filePath');
      _handleRetry(filePath, entry, e.toString(), isPreviewPhase: true);
    } on Object catch (e, st) {
      appLog(
        'preprocessing',
        'preview extraction FAILED file=$filePath error=$e',
      );
      dev.log(
        'Preview extraction failed: $e',
        name: 'preprocessing',
        error: e,
        stackTrace: st,
      );
      _handleRetry(filePath, entry, e.toString(), isPreviewPhase: true);
    }
  }

  /// Phase 2: Extract remaining pages after preview.
  Future<void> _processBackgroundCompletion(
    String filePath, {
    bool isPriority = false,
  }) async {
    final entry = state[filePath];
    if (entry == null) return;
    if (entry.status == PdfStatus.ready) return;

    // Background books carry no document in state — rehydrate the preview
    // from cache so phase 2 can merge onto it.
    final baseDoc = entry.document ?? await PdfCache.loadPreview(filePath);
    if (baseDoc == null) {
      // Preview neither in state nor on disk — restart from phase 1.
      if (!mounted) return;
      _update(
        filePath,
        entry.copyWith(
          status: PdfStatus.queued,
          clearDocument: true,
          progress: const PdfProgress(),
        ),
      );
      _previewQueue.add(filePath);
      _fillWorkers();
      return;
    }
    if (!mounted) return;

    final progress = entry.progress;
    final startPage = progress.lastCompletedPage;
    final totalPages = progress.totalPages;

    if (startPage >= totalPages) {
      // Already complete.
      _update(
        filePath,
        entry.copyWith(
          status: PdfStatus.ready,
          progress: progress.copyWith(phase: ExtractionPhase.done),
        ),
      );
      return;
    }

    _update(
      filePath,
      entry.copyWith(
        status: PdfStatus.processing,
        progress: progress.copyWith(
          phase: ExtractionPhase.backgroundCompletion,
        ),
      ),
    );

    try {
      final kind = await DocumentClassifier.classifyPath(filePath);
      if (kind == DocumentKind.unsupported) {
        throw const UnsupportedPdfError('This file type is not supported.');
      }

      // Chunked extraction (BK-7): fixed-size page chunks, each committed
      // durably (partial doc → preview cache, progress → manifest) so a
      // timeout or crash resumes from the last finished chunk — across
      // launches if needed — instead of restarting from the preview.
      var workingDoc = baseDoc;
      var cursor = startPage;
      while (cursor < totalPages) {
        if (!mounted) return;
        final chunkEnd = (cursor + completionChunkPages - 1).clamp(
          cursor,
          totalPages - 1,
        );
        final result = kind == DocumentKind.epub
            ? await extractEpubPagesInIsolate(filePath, cursor, chunkEnd)
            : await extractPdfPagesInIsolate(filePath, cursor, chunkEnd);
        workingDoc = workingDoc.merge(result.document);
        cursor = result.extractedEndPage + 1;

        if (!mounted) return;
        final current = state[filePath];
        if (current == null) return;
        if (cursor >= totalPages) break;

        // Commit the chunk before moving on (cache first, then manifest, so
        // recorded progress never exceeds what is recoverable from disk).
        await PdfCache.savePreview(filePath, workingDoc);
        await _manifest.setProgress(
          filePath,
          lastCompletedPage: cursor,
          pageCount: totalPages,
        );
        _update(
          filePath,
          current.copyWith(
            status: PdfStatus.processing,
            document: isPriority ? workingDoc : null,
            clearDocument: !isPriority,
            progress: PdfProgress(
              lastCompletedPage: cursor,
              totalPages: totalPages,
              phase: ExtractionPhase.backgroundCompletion,
            ),
          ),
        );

        // Scheduler yield: reading sessions pause background work between
        // chunks; the committed progress resumes when reading stops.
        if (_isPaused && !isPriority) {
          _completionQueue.add(filePath);
          appLog(
            'preprocessing',
            'completion yielded at page $cursor file=$filePath',
          );
          return;
        }
      }

      final fullDoc = workingDoc;

      // Save full document to cache (don't block).
      PdfCache.save(filePath, fullDoc).catchError((Object e) {
        dev.log('Cache save failed: $e', name: 'preprocessing');
      });
      await _manifest.setProgress(
        filePath,
        lastCompletedPage: totalPages,
        pageCount: totalPages,
      );

      _update(
        filePath,
        entry.copyWith(
          status: PdfStatus.ready,
          document: isPriority ? fullDoc : null,
          clearDocument: !isPriority,
          retryCount: 0,
          progress: PdfProgress(
            lastCompletedPage: totalPages,
            totalPages: totalPages,
            phase: ExtractionPhase.done,
          ),
        ),
      );
      unawaited(_ingestToStore(filePath, fullDoc));
    } on UnsupportedPdfError catch (e) {
      appLog('preprocessing', 'unsupported completion file=$filePath');
      _update(
        filePath,
        entry.copyWith(status: PdfStatus.unsupported, errorMessage: e.message),
      );
    } on PdfTimeoutError catch (e) {
      appLog('preprocessing', 'timeout (completion) file=$filePath');
      // Use the live entry — chunk commits may have advanced progress past
      // the snapshot taken when this method started.
      _handleRetry(
        filePath,
        state[filePath] ?? entry,
        e.toString(),
        isPreviewPhase: false,
      );
    } on Object catch (e, st) {
      appLog('preprocessing', 'completion FAILED file=$filePath error=$e');
      dev.log(
        'Background completion failed: $e',
        name: 'preprocessing',
        error: e,
        stackTrace: st,
      );
      _handleRetry(
        filePath,
        state[filePath] ?? entry,
        e.toString(),
        isPreviewPhase: false,
      );
    }
  }

  void _handleRetry(
    String filePath,
    PdfEntry entry,
    String errorMessage, {
    required bool isPreviewPhase,
  }) {
    final retries = entry.retryCount + 1;

    if (retries >= PdfEntry.maxRetries) {
      if (isPreviewPhase) {
        // Phase 1 failure — mark as permanently failed.
        _update(
          filePath,
          entry.copyWith(
            status: PdfStatus.permanentlyFailed,
            errorMessage:
                'Failed after ${PdfEntry.maxRetries} attempts: '
                '$errorMessage',
            retryCount: retries,
          ),
        );
        dev.log(
          'Permanently failed (preview): $filePath',
          name: 'preprocessing',
        );
        appLog(
          'preprocessing',
          'PERMANENTLY FAILED file=$filePath error=$errorMessage',
        );
      } else {
        // Phase 2 failure — keep all committed chunks, mark as partial.
        // Chunk progress is durable, so the next launch retries from the
        // last finished chunk instead of being capped forever (BK-7).
        final committed = entry.progress.lastCompletedPage.clamp(
          previewPageCount,
          entry.progress.totalPages > 0
              ? entry.progress.totalPages
              : previewPageCount,
        );
        _update(
          filePath,
          entry.copyWith(
            status: PdfStatus.preview,
            errorMessage:
                'Partial — pages 1–$committed extracted so far. '
                'Extraction will resume on next launch. ($errorMessage)',
            retryCount: retries,
          ),
        );
        dev.log(
          'Background completion permanently failed: $filePath',
          name: 'preprocessing',
        );
        appLog(
          'preprocessing',
          'completion permanently failed file=$filePath error=$errorMessage',
        );
      }
    } else {
      // Exponential backoff: 1s, 4s, 16s.
      final delaySeconds = 1 << (2 * (retries - 1)); // 1, 4, 16
      final updated = entry.copyWith(
        status: PdfStatus.error,
        errorMessage: errorMessage,
        retryCount: retries,
      );
      _update(filePath, updated);

      // Schedule retry after backoff.
      Future.delayed(Duration(seconds: delaySeconds), () {
        if (!mounted) return;
        if (isPreviewPhase) {
          _previewQueue.add(filePath);
        } else {
          _completionQueue.add(filePath);
        }
        _fillWorkers();
      });
    }
  }

  void _update(String filePath, PdfEntry entry) {
    if (!mounted) return;
    state = {...state, filePath: entry};
    _progressController.add(entry);
  }

  /// Retry all failed (non-permanent) entries.
  void retryErrors() {
    final errorPaths = state.entries
        .where((e) => e.value.status == PdfStatus.error)
        .map((e) => e.key)
        .toList();

    for (final path in errorPaths) {
      final entry = state[path];
      if (entry == null) continue;
      // Decide which queue based on extraction phase — the document itself
      // may have been released from memory (it lives in PdfCache).
      if (entry.progress.phase == ExtractionPhase.backgroundCompletion) {
        _completionQueue.add(path);
      } else {
        _previewQueue.add(path);
      }
    }
    _fillWorkers();
  }

  void _startNotificationUpdates() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _updateNotification(),
    );
    _updateNotification();
  }

  void _stopNotificationUpdates() {
    _notificationTimer?.cancel();
    _notificationTimer = null;
    NotificationService.dismiss();
  }

  void _updateNotification() {
    final op = overallProgress;
    if (op.total == 0) return;
    if (op.completed >= op.total) {
      _stopNotificationUpdates();
      return;
    }
    NotificationService.showProgress(
      title: 'Processing ${op.completed} of ${op.total} PDFs',
      progress: op.percent,
    );
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _progressController.close();
    super.dispose();
  }
}

final preprocessingQueueProvider =
    StateNotifierProvider<PreprocessingQueue, Map<String, PdfEntry>>(
      PreprocessingQueue.new,
    );

// ── Selector providers for the UI ──

/// Status of a single PDF by file path.
final pdfStatusProvider = Provider.family<PdfStatus, String>((ref, filePath) {
  final entries = ref.watch(preprocessingQueueProvider);
  return entries[filePath]?.status ?? PdfStatus.pending;
});

/// Page completion progress (0.0–1.0) of a single PDF.
final pdfProgressProvider = Provider.family<double, String>((ref, filePath) {
  final entries = ref.watch(preprocessingQueueProvider);
  return entries[filePath]?.progress.fraction ?? 0.0;
});

/// Count of permanently failed files (header badge) — selector-scoped so
/// the library doesn't watch the whole queue map.
final pdfFailedCountProvider = Provider<int>((ref) {
  return ref.watch(
    preprocessingQueueProvider.select(
      (m) =>
          m.values.where((e) => e.status == PdfStatus.permanentlyFailed).length,
    ),
  );
});

/// Overall progress across all PDFs.
final overallProgressProvider = Provider<OverallProgress>((ref) {
  final queue = ref.watch(preprocessingQueueProvider.notifier);
  // Re-read state to trigger reactivity.
  ref.watch(preprocessingQueueProvider);
  return queue.overallProgress;
});

/// Whether a priority preemption is currently in progress.
final isPriorityProcessingProvider = Provider<bool>((ref) {
  final queue = ref.watch(preprocessingQueueProvider.notifier);
  ref.watch(preprocessingQueueProvider);
  return queue.isPriorityProcessing;
});
