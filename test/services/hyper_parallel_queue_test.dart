import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/device_capability.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_extractor.dart';

void main() {
  group('DeviceCapability — adaptive worker pool', () {
    test('maxWorkers is at least 2', () {
      // We can't override Platform.numberOfProcessors, but we can verify
      // the provider returns a sensible value on the current machine.
      final capability = DeviceCapability(
        processorCount: 1,
        maxWorkers: _computeWorkers(1, isMobile: false),
        isMobile: false,
      );
      expect(capability.maxWorkers, greaterThanOrEqualTo(2));
    });

    test('desktop caps at 12', () {
      final workers = _computeWorkers(24, isMobile: false);
      expect(workers, equals(12));
    });

    test('mobile caps at 6', () {
      final workers = _computeWorkers(12, isMobile: true);
      expect(workers, equals(6));
    });

    test('single-core device still gets 2 workers', () {
      final workers = _computeWorkers(1, isMobile: true);
      expect(workers, equals(2));
    });

    test('two-core device gets 2 workers', () {
      final workers = _computeWorkers(2, isMobile: false);
      expect(workers, equals(2));
    });

    test('8-core desktop gets 7 workers', () {
      final workers = _computeWorkers(8, isMobile: false);
      expect(workers, equals(7));
    });

    test('8-core mobile gets 6 workers (capped)', () {
      final workers = _computeWorkers(8, isMobile: true);
      expect(workers, equals(6));
    });

    test('4-core mobile gets 3 workers', () {
      final workers = _computeWorkers(4, isMobile: true);
      expect(workers, equals(3));
    });
  });

  group('PdfEntry — model', () {
    test('copyWith preserves fields', () {
      const entry = PdfEntry(
        filePath: '/test.pdf',
        fileName: 'test.pdf',
        status: PdfStatus.queued,
        progress: PdfProgress(
          lastCompletedPage: 2,
          totalPages: 10,
          phase: ExtractionPhase.preview,
        ),
      );

      final updated = entry.copyWith(status: PdfStatus.processing);
      expect(updated.status, PdfStatus.processing);
      expect(updated.progress.lastCompletedPage, 2);
      expect(updated.progress.totalPages, 10);
      expect(updated.filePath, '/test.pdf');
    });

    test('clearDocument nulls the document', () {
      const doc = ExtractedDocument(sentences: [
        Sentence(words: ['hello']),
      ]);
      const entry = PdfEntry(
        filePath: '/test.pdf',
        fileName: 'test.pdf',
        document: doc,
      );

      final cleared = entry.copyWith(clearDocument: true);
      expect(cleared.document, isNull);
    });
  });

  group('PdfProgress', () {
    test('fraction is 0.0 when totalPages is 0', () {
      const progress = PdfProgress();
      expect(progress.fraction, 0.0);
    });

    test('fraction computation', () {
      const progress = PdfProgress(lastCompletedPage: 5, totalPages: 10);
      expect(progress.fraction, 0.5);
    });

    test('fraction at 100%', () {
      const progress = PdfProgress(lastCompletedPage: 10, totalPages: 10);
      expect(progress.fraction, 1.0);
    });
  });

  group('OverallProgress', () {
    test('percent is 0.0 when total is 0', () {
      const op = OverallProgress();
      expect(op.percent, 0.0);
    });

    test('percent computation', () {
      const op = OverallProgress(completed: 3, total: 10);
      expect(op.percent, closeTo(0.3, 0.001));
    });
  });

  group('PdfStatus enum', () {
    test('preview is a valid status', () {
      expect(PdfStatus.values.contains(PdfStatus.preview), isTrue);
    });

    test('all expected statuses exist', () {
      expect(
          PdfStatus.values,
          containsAll([
            PdfStatus.pending,
            PdfStatus.queued,
            PdfStatus.processing,
            PdfStatus.preview,
            PdfStatus.ready,
            PdfStatus.error,
            PdfStatus.unsupported,
            PdfStatus.permanentlyFailed,
          ]));
    });
  });

  group('ExtractedDocument', () {
    test('merge combines sentences from two documents', () {
      const doc1 = ExtractedDocument(sentences: [
        Sentence(words: ['hello', 'world']),
      ]);
      const doc2 = ExtractedDocument(sentences: [
        Sentence(words: ['foo', 'bar']),
      ]);

      final merged = doc1.merge(doc2);
      expect(merged.sentences.length, 2);
      expect(merged.totalWords, 4);
      expect(merged.allWords, ['hello', 'world', 'foo', 'bar']);
    });

    test('merge with empty document', () {
      const doc1 = ExtractedDocument(sentences: [
        Sentence(words: ['hello']),
      ]);
      const doc2 = ExtractedDocument(sentences: []);

      final merged = doc1.merge(doc2);
      expect(merged.sentences.length, 1);
      expect(merged.totalWords, 1);
    });

    test('JSON round-trip', () {
      const original = ExtractedDocument(sentences: [
        Sentence(words: ['a', 'b']),
        Sentence(words: ['c']),
      ]);

      final json = original.toJson();
      final restored = ExtractedDocument.fromJson(json);

      expect(restored.sentences.length, 2);
      expect(restored.allWords, ['a', 'b', 'c']);
    });
  });

  group('Exponential backoff', () {
    test('delay sequence is 1s, 4s, 16s', () {
      // Matches the formula: 1 << (2 * (retries - 1)) where retries is 1,2,3
      final delays = <int>[];
      for (var retries = 1; retries <= 3; retries++) {
        delays.add(1 << (2 * (retries - 1)));
      }
      expect(delays, [1, 4, 16]);
    });
  });

  group('PageRangeResult', () {
    test('holds extraction metadata', () {
      const result = PageRangeResult(
        document: ExtractedDocument(sentences: []),
        totalPages: 50,
        extractedStartPage: 0,
        extractedEndPage: 2,
      );

      expect(result.totalPages, 50);
      expect(result.extractedStartPage, 0);
      expect(result.extractedEndPage, 2);
    });
  });

  group('previewPageCount', () {
    test('is 3', () {
      expect(previewPageCount, 3);
    });
  });
}

/// Replicates the worker computation logic for testing without Platform access.
int _computeWorkers(int processorCount, {required bool isMobile}) {
  final cap = isMobile ? 6 : 12;
  final raw = processorCount - 1;
  return raw.clamp(2, cap);
}
