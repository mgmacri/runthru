import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/services/folder_scanner.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/services/pdf_cache.dart';
import 'package:speedy_boy/services/pdf_extractor.dart';

/// FIFO queue processing PDFs in background Isolates.
class PreprocessingQueue extends StateNotifier<Map<String, PdfEntry>> {
  PreprocessingQueue(this._ref) : super({}) {
    _init();
  }

  final Ref _ref;
  final _queue = <String>[];
  bool _isProcessing = false;
  final _progressController = StreamController<PdfEntry>.broadcast();

  Stream<PdfEntry> get progress => _progressController.stream;

  void _init() {
    _ref.listen(pdfListProvider, (previous, next) {
      _enqueueAll(next);
    });
    // Initial enqueue
    final entries = _ref.read(pdfListProvider);
    _enqueueAll(entries);
  }

  void _enqueueAll(List<PdfEntry> entries) {
    for (final entry in entries) {
      if (!state.containsKey(entry.filePath)) {
        state = {
          ...state,
          entry.filePath: entry.copyWith(
            status: PdfStatus.pending,
          ),
        };
        _queue.add(entry.filePath);
      }
    }
    _processNext();
  }

  Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final filePath = _queue.removeAt(0);
      final entry = state[filePath];
      if (entry == null) continue;

      // Check cache first
      final cached = await PdfCache.load(filePath);
      if (cached != null) {
        final updated = entry.copyWith(
          status: PdfStatus.ready,
          document: cached,
        );
        state = {...state, filePath: updated};
        _progressController.add(updated);
        continue;
      }

      // Mark processing
      final processing = entry.copyWith(
        status: PdfStatus.processing,
      );
      state = {...state, filePath: processing};
      _progressController.add(processing);

      try {
        final doc = await extractPdfInIsolate(filePath);
        await PdfCache.save(filePath, doc);

        final ready = entry.copyWith(
          status: PdfStatus.ready,
          document: doc,
        );
        state = {...state, filePath: ready};
        _progressController.add(ready);
      } on UnsupportedPdfError catch (e) {
        final unsupported = entry.copyWith(
          status: PdfStatus.unsupported,
          errorMessage: e.message,
        );
        state = {...state, filePath: unsupported};
        _progressController.add(unsupported);
      } on Object catch (e) {
        final errored = entry.copyWith(
          status: PdfStatus.error,
          errorMessage: e.toString(),
        );
        state = {...state, filePath: errored};
        _progressController.add(errored);
      }
    }

    _isProcessing = false;
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
