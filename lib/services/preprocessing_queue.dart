import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/services/folder_scanner.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/services/pdf_cache.dart';
import 'package:speedy_boy/services/pdf_extractor.dart';

/// Maximum number of concurrent isolate workers.
const int _maxWorkers = 3;

/// FIFO queue with parallel workers, priority preemption, and dead-letter queue.
class PreprocessingQueue extends StateNotifier<Map<String, PdfEntry>> {
  PreprocessingQueue(this._ref) : super({}) {
    _init();
  }

  final Ref _ref;
  final _queue = <String>[];

  /// Tracks actively running workers by filePath.
  final _activeWorkers = <String>{};

  bool _isPaused = false;

  final _progressController = StreamController<PdfEntry>.broadcast();

  Stream<PdfEntry> get progress => _progressController.stream;

  /// Number of files that failed permanently.
  int get failedCount =>
      state.values.where((e) => e.status == PdfStatus.permanentlyFailed).length;

  /// Number of files with transient errors.
  int get errorCount =>
      state.values.where((e) => e.status == PdfStatus.error).length;

  void _init() {
    _ref.listen(pdfListProvider, (previous, next) {
      next.when(
        data: _enqueueAll,
        loading: () {},
        error: (_, __) {},
      );
    });
    // Initial enqueue
    final entries = _ref.read(pdfListProvider);
    entries.when(
      data: _enqueueAll,
      loading: () {},
      error: (_, __) {},
    );
  }

  void _enqueueAll(List<PdfEntry> entries) {
    for (final entry in entries) {
      if (!state.containsKey(entry.filePath)) {
        state = {
          ...state,
          entry.filePath: entry.copyWith(
            status: PdfStatus.queued,
          ),
        };
        _queue.add(entry.filePath);
      }
    }
    _fillWorkers();
  }

  /// Pause all background processing (called when user opens a PDF).
  void pauseBackground() {
    _isPaused = true;
  }

  /// Resume background processing.
  void resumeBackground() {
    _isPaused = false;
    _fillWorkers();
  }

  /// Prioritize a single file — pauses background and processes it first.
  Future<void> prioritize(String filePath) async {
    // Already ready?
    final existing = state[filePath];
    if (existing?.status == PdfStatus.ready) return;

    pauseBackground();

    // Remove from queue if present so we won't double-process
    _queue.remove(filePath);

    // Process immediately (outside the worker pool)
    await _processFile(filePath, isPriority: true);

    resumeBackground();
  }

  /// Fill worker slots up to [_maxWorkers].
  void _fillWorkers() {
    if (_isPaused) return;

    while (_activeWorkers.length < _maxWorkers && _queue.isNotEmpty) {
      final filePath = _queue.removeAt(0);
      final entry = state[filePath];
      if (entry == null) continue;

      // Skip permanently failed
      if (entry.status == PdfStatus.permanentlyFailed) continue;

      _activeWorkers.add(filePath);
      _processFile(filePath).whenComplete(() {
        _activeWorkers.remove(filePath);
        _fillWorkers();
      });
    }
  }

  Future<void> _processFile(
    String filePath, {
    bool isPriority = false,
  }) async {
    final entry = state[filePath];
    if (entry == null) return;

    // Check cache first
    try {
      final cached = await PdfCache.load(filePath);
      if (cached != null) {
        final updated = entry.copyWith(
          status: PdfStatus.ready,
          document: cached,
        );
        _update(filePath, updated);
        return;
      }
    } on Object catch (e) {
      dev.log('Cache check failed: $e', name: 'preprocessing');
    }

    // Mark processing
    final processing = entry.copyWith(status: PdfStatus.processing);
    _update(filePath, processing);

    try {
      final doc = await extractPdfInIsolate(filePath);

      // Don't block on cache save
      PdfCache.save(filePath, doc).catchError((Object e) {
        dev.log('Cache save failed: $e', name: 'preprocessing');
      });

      final ready = entry.copyWith(
        status: PdfStatus.ready,
        document: doc,
        retryCount: 0,
      );
      _update(filePath, ready);
    } on UnsupportedPdfError catch (e) {
      final unsupported = entry.copyWith(
        status: PdfStatus.unsupported,
        errorMessage: e.message,
      );
      _update(filePath, unsupported);
    } on PdfTimeoutError catch (e) {
      _handleRetry(filePath, entry, e.toString());
    } on Object catch (e, st) {
      dev.log(
        'PDF processing failed: $e',
        name: 'preprocessing',
        error: e,
        stackTrace: st,
      );
      _handleRetry(filePath, entry, e.toString());
    }
  }

  void _handleRetry(String filePath, PdfEntry entry, String errorMessage) {
    final retries = entry.retryCount + 1;
    if (retries >= PdfEntry.maxRetries) {
      final failed = entry.copyWith(
        status: PdfStatus.permanentlyFailed,
        errorMessage: 'Failed after ${PdfEntry.maxRetries} attempts: '
            '$errorMessage',
        retryCount: retries,
      );
      _update(filePath, failed);
      dev.log(
        'Permanently failed: $filePath ($errorMessage)',
        name: 'preprocessing',
      );
    } else {
      final errored = entry.copyWith(
        status: PdfStatus.error,
        errorMessage: errorMessage,
        retryCount: retries,
      );
      _update(filePath, errored);
      // Re-queue for retry
      _queue.add(filePath);
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
      _queue.add(path);
    }
    _fillWorkers();
  }

  @override
  void dispose() {
    _progressController.close();
    super.dispose();
  }
}

final preprocessingQueueProvider =
    StateNotifierProvider<PreprocessingQueue, Map<String, PdfEntry>>(
  PreprocessingQueue.new,
);
