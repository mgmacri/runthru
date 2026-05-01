import 'dart:async';
import 'dart:collection';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/services/device_capability.dart';
import 'package:runthru/services/epub_extractor.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/notification_service.dart';
import 'package:runthru/services/pdf_cache.dart';
import 'package:runthru/services/pdf_extractor.dart';

/// Hyper-parallel PDF preprocessing queue with adaptive worker pool,
/// progressive extraction (preview → full), and priority preemption.
class PreprocessingQueue extends StateNotifier<Map<String, PdfEntry>> {
  PreprocessingQueue(this._ref) : super({}) {
    _maxWorkers = _ref.read(deviceCapabilityProvider).maxWorkers;
    _currentMaxWorkers = _maxWorkers;
    _init();
  }

  final Ref _ref;

  /// Whether a file is EPUB based on extension.
  static bool _isEpub(String path) => path.toLowerCase().endsWith('.epub');

  /// Phase 1 queue — preview extraction (pages 1–3).
  final _previewQueue = Queue<String>();

  /// Phase 2 queue — background completion (remaining pages).
  final _completionQueue = Queue<String>();

  /// Tracks actively running workers by filePath.
  final _activeWorkers = <String>{};

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
        .where((e) =>
            e.status == PdfStatus.ready ||
            e.status == PdfStatus.permanentlyFailed ||
            e.status == PdfStatus.unsupported)
        .length;
    return OverallProgress(completed: completed, total: total);
  }

  Timer? _notificationTimer;

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
    appLog('preprocessing', 'enqueueAll — ${entries.length} files');
    for (final entry in entries) {
      if (!state.containsKey(entry.filePath)) {
        appLog('preprocessing', 'enqueue file=${entry.fileName}');
        state = {
          ...state,
          entry.filePath: entry.copyWith(status: PdfStatus.queued),
        };
        _previewQueue.add(entry.filePath);
      }
    }
    _startNotificationUpdates();
    _fillWorkers();
  }

  /// Enqueue entries from a streaming multi-directory scan.
  void enqueueEntry(PdfEntry entry) {
    if (state.containsKey(entry.filePath)) return;
    state = {
      ...state,
      entry.filePath: entry.copyWith(status: PdfStatus.queued),
    };
    _previewQueue.add(entry.filePath);
    _fillWorkers();
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
  Future<void> prioritize(String filePath) async {
    final existing = state[filePath];
    if (existing == null) return;
    if (existing.status == PdfStatus.ready) return;

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
      final cachedFull = await PdfCache.load(filePath);
      if (cachedFull != null) {
        _update(
            filePath,
            entry.copyWith(
              status: PdfStatus.ready,
              document: cachedFull,
              progress: entry.progress.copyWith(phase: ExtractionPhase.done),
            ));
        return;
      }
    } on Object catch (e) {
      dev.log('Cache check failed: $e', name: 'preprocessing');
    }

    // Check preview cache.
    try {
      final cachedPreview = await PdfCache.loadPreview(filePath);
      if (cachedPreview != null) {
        final totalPages = _isEpub(filePath)
            ? await epubChapterCountInIsolate(filePath)
            : await pdfPageCountInIsolate(filePath);
        _update(
            filePath,
            entry.copyWith(
              status: PdfStatus.preview,
              document: cachedPreview,
              progress: PdfProgress(
                lastCompletedPage: previewPageCount.clamp(0, totalPages),
                totalPages: totalPages,
                phase: ExtractionPhase.preview,
              ),
            ));
        return;
      }
    } on Object catch (e) {
      dev.log('Preview cache check failed: $e', name: 'preprocessing');
    }

    // Mark processing.
    _update(filePath, entry.copyWith(status: PdfStatus.processing));

    try {
      final result = _isEpub(filePath)
          ? await extractEpubPagesInIsolate(filePath, 0, previewPageCount - 1)
          : await extractPdfPagesInIsolate(filePath, 0, previewPageCount - 1);

      final totalPages = result.totalPages;
      final previewDoc = result.document;
      // Actual pages extracted (may exceed previewPageCount if front
      // matter was blank and the extractor probed deeper).
      final pagesExtracted = result.extractedEndPage + 1;

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
              document: previewDoc,
              retryCount: 0,
              progress: PdfProgress(
                lastCompletedPage: totalPages,
                totalPages: totalPages,
                phase: ExtractionPhase.done,
              ),
            ));
      } else {
        _update(
            filePath,
            entry.copyWith(
              status: PdfStatus.preview,
              document: previewDoc,
              retryCount: 0,
              progress: PdfProgress(
                lastCompletedPage: pagesExtracted,
                totalPages: totalPages,
                phase: ExtractionPhase.preview,
              ),
            ));
      }
    } on UnsupportedPdfError catch (e) {
      appLog('preprocessing', 'unsupported file=$filePath error=${e.message}');
      _update(
          filePath,
          entry.copyWith(
            status: PdfStatus.unsupported,
            errorMessage: e.message,
          ));
    } on PdfTimeoutError catch (e) {
      appLog('preprocessing', 'timeout file=$filePath');
      _handleRetry(filePath, entry, e.toString(), isPreviewPhase: true);
    } on Object catch (e, st) {
      appLog(
          'preprocessing', 'preview extraction FAILED file=$filePath error=$e');
      dev.log('Preview extraction failed: $e',
          name: 'preprocessing', error: e, stackTrace: st);
      _handleRetry(filePath, entry, e.toString(), isPreviewPhase: true);
    }
  }

  /// Phase 2: Extract remaining pages after preview.
  Future<void> _processBackgroundCompletion(
    String filePath, {
    bool isPriority = false,
  }) async {
    final entry = state[filePath];
    if (entry == null || entry.document == null) return;
    if (entry.status == PdfStatus.ready) return;

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
          ));
      return;
    }

    _update(
        filePath,
        entry.copyWith(
          status: PdfStatus.processing,
          progress: progress.copyWith(
            phase: ExtractionPhase.backgroundCompletion,
          ),
        ));

    try {
      final result = _isEpub(filePath)
          ? await extractEpubPagesInIsolate(filePath, startPage, totalPages - 1)
          : await extractPdfPagesInIsolate(filePath, startPage, totalPages - 1);

      final fullDoc = entry.document!.merge(result.document);

      // Save full document to cache (don't block).
      PdfCache.save(filePath, fullDoc).catchError((Object e) {
        dev.log('Cache save failed: $e', name: 'preprocessing');
      });

      _update(
          filePath,
          entry.copyWith(
            status: PdfStatus.ready,
            document: fullDoc,
            retryCount: 0,
            progress: PdfProgress(
              lastCompletedPage: totalPages,
              totalPages: totalPages,
              phase: ExtractionPhase.done,
            ),
          ));
    } on PdfTimeoutError catch (e) {
      appLog('preprocessing', 'timeout (completion) file=$filePath');
      _handleRetry(filePath, entry, e.toString(), isPreviewPhase: false);
    } on Object catch (e, st) {
      appLog('preprocessing', 'completion FAILED file=$filePath error=$e');
      dev.log('Background completion failed: $e',
          name: 'preprocessing', error: e, stackTrace: st);
      _handleRetry(filePath, entry, e.toString(), isPreviewPhase: false);
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
              errorMessage: 'Failed after ${PdfEntry.maxRetries} attempts: '
                  '$errorMessage',
              retryCount: retries,
            ));
        dev.log('Permanently failed (preview): $filePath',
            name: 'preprocessing');
        appLog('preprocessing',
            'PERMANENTLY FAILED file=$filePath error=$errorMessage');
      } else {
        // Phase 2 failure — keep preview data, mark as preview (partial).
        _update(
            filePath,
            entry.copyWith(
              status: PdfStatus.preview,
              errorMessage: 'Partial — pages 1–$previewPageCount only. '
                  'Background completion failed: $errorMessage',
              retryCount: retries,
            ));
        dev.log('Background completion permanently failed: $filePath',
            name: 'preprocessing');
        appLog('preprocessing',
            'completion permanently failed file=$filePath error=$errorMessage');
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
      // Decide which queue based on whether it has preview data.
      if (entry.document != null &&
          entry.progress.phase == ExtractionPhase.backgroundCompletion) {
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
