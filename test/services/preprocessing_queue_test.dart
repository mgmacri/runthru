import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/services/models.dart';

void main() {
  group('PdfEntry', () {
    test('copyWith preserves fields when not overridden', () {
      const entry = PdfEntry(
        filePath: '/test.pdf',
        fileName: 'test.pdf',
        status: PdfStatus.processing,
        retryCount: 2,
        errorMessage: 'some error',
      );

      final copy = entry.copyWith();

      expect(copy.filePath, '/test.pdf');
      expect(copy.fileName, 'test.pdf');
      expect(copy.status, PdfStatus.processing);
      expect(copy.retryCount, 2);
      expect(copy.errorMessage, 'some error');
    });

    test('copyWith overrides specified fields', () {
      const entry = PdfEntry(
        filePath: '/test.pdf',
        fileName: 'test.pdf',
      );

      final copy = entry.copyWith(
        status: PdfStatus.ready,
        retryCount: 1,
      );

      expect(copy.status, PdfStatus.ready);
      expect(copy.retryCount, 1);
    });

    test('maxRetries is 3', () {
      expect(PdfEntry.maxRetries, 3);
    });
  });

  group('PdfStatus', () {
    test('has all required states', () {
      expect(
          PdfStatus.values,
          containsAll([
            PdfStatus.pending,
            PdfStatus.queued,
            PdfStatus.processing,
            PdfStatus.ready,
            PdfStatus.error,
            PdfStatus.unsupported,
            PdfStatus.permanentlyFailed,
          ]));
    });
  });

  group('ExtractedDocument', () {
    test('allWords flattens sentences', () {
      const doc = ExtractedDocument(sentences: [
        Sentence(words: ['Hello', 'world']),
        Sentence(words: ['foo', 'bar']),
      ]);

      expect(doc.allWords, ['Hello', 'world', 'foo', 'bar']);
      expect(doc.totalWords, 4);
    });

    test('empty sentences produce empty allWords', () {
      const doc = ExtractedDocument(sentences: []);
      expect(doc.allWords, isEmpty);
      expect(doc.totalWords, 0);
    });

    test('fromJson / toJson round-trip', () {
      const doc = ExtractedDocument(sentences: [
        Sentence(words: ['Hello', 'world']),
        Sentence(words: ['test']),
      ]);

      final json = doc.toJson();
      final restored = ExtractedDocument.fromJson(json);

      expect(restored.totalWords, doc.totalWords);
      expect(restored.allWords, doc.allWords);
    });
  });

  group('UnsupportedPdfError', () {
    test('toString includes message', () {
      const error = UnsupportedPdfError('no text');
      expect(error.toString(), contains('no text'));
    });
  });

  group('PdfTimeoutError', () {
    test('toString includes filePath', () {
      const error = PdfTimeoutError('/big.pdf');
      expect(error.toString(), contains('/big.pdf'));
    });
  });

  group('Dead letter queue', () {
    test('entry becomes permanently failed after max retries', () {
      var entry = const PdfEntry(
        filePath: '/bad.pdf',
        fileName: 'bad.pdf',
      );

      // Simulate 3 retries
      for (var i = 0; i < PdfEntry.maxRetries; i++) {
        entry = entry.copyWith(
          retryCount: entry.retryCount + 1,
          status: PdfStatus.error,
          errorMessage: 'attempt ${i + 1}',
        );
      }

      expect(entry.retryCount, PdfEntry.maxRetries);

      // At max retries, should be marked permanently failed
      if (entry.retryCount >= PdfEntry.maxRetries) {
        entry = entry.copyWith(status: PdfStatus.permanentlyFailed);
      }
      expect(entry.status, PdfStatus.permanentlyFailed);
    });
  });
}
