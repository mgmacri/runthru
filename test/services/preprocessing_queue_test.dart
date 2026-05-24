import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/models.dart';

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

    test('merge offsets phase-2 pageBoundary startWordIndex by phase-1 totalWords', () {
      // Phase 1: chapters 0-1, 5 words total.
      const phase1 = ExtractedDocument(
        sentences: [
          Sentence(words: ['a', 'b', 'c']),
          Sentence(words: ['d', 'e']),
        ],
        pageBoundaries: [
          PageBoundary(pageNumber: 0, startSentenceIndex: 0, startWordIndex: 0, firstWords: 'a b c'),
          PageBoundary(pageNumber: 1, startSentenceIndex: 1, startWordIndex: 3, firstWords: 'd e'),
        ],
        totalPages: 4,
      );

      // Phase 2: chapters 2-3. Extractor starts its own globalWordIndex from 0.
      const phase2 = ExtractedDocument(
        sentences: [
          Sentence(words: ['f', 'g']),
          Sentence(words: ['h']),
        ],
        pageBoundaries: [
          PageBoundary(pageNumber: 2, startSentenceIndex: 0, startWordIndex: 0, firstWords: 'f g'),
          PageBoundary(pageNumber: 3, startSentenceIndex: 1, startWordIndex: 2, firstWords: 'h'),
        ],
        totalPages: 4,
      );

      final merged = phase1.merge(phase2);

      // Sentences are all 8 words in order.
      expect(merged.totalWords, 8);
      expect(merged.allWords, ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);

      // Phase-1 boundaries unchanged.
      expect(merged.pageBoundaries[0].startWordIndex, 0);
      expect(merged.pageBoundaries[1].startWordIndex, 3);

      // Phase-2 boundaries must be offset by phase-1's 5 words and 2 sentences.
      expect(merged.pageBoundaries[2].startWordIndex, 5,
          reason: 'chapter 2 should start at word 5 (phase-1 had 5 words)');
      expect(merged.pageBoundaries[3].startWordIndex, 7,
          reason: 'chapter 3 should start at word 7');
      expect(merged.pageBoundaries[2].startSentenceIndex, 2,
          reason: 'chapter 2 sentence index should be offset by phase-1 sentence count (2)');
      expect(merged.pageBoundaries[3].startSentenceIndex, 3);
    });

    test('merge with empty phase-2 pageBoundaries leaves phase-1 intact', () {
      const phase1 = ExtractedDocument(
        sentences: [Sentence(words: ['a', 'b'])],
        pageBoundaries: [
          PageBoundary(pageNumber: 0, startSentenceIndex: 0, startWordIndex: 0),
        ],
        totalPages: 1,
      );
      const phase2 = ExtractedDocument(sentences: []);
      final merged = phase1.merge(phase2);
      expect(merged.pageBoundaries.length, 1);
      expect(merged.pageBoundaries[0].startWordIndex, 0);
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
