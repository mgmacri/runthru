import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_extractor.dart';

void main() {
  group('pdfExtract', () {
    test('throws FileSystemException for non-existent file', () async {
      expect(
        () => pdfExtract('/non/existent/file.pdf'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws FileSystemException for empty path', () async {
      expect(() => pdfExtract(''), throwsA(isA<FileSystemException>()));
    });

    test('throwOnEmpty parameter is accepted by pdfExtract', () {
      // Validate the parameter exists on the function signature.
      // Actual PDF extraction requires pdfrx FFI (getCacheDirectory),
      // which isn't available in unit tests.
      expect(
        () => pdfExtract('/non/existent/file.pdf', throwOnEmpty: false),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('pdfExtractWithProgress', () {
    test('reports error for non-existent file', () async {
      Object? reportedError;
      ExtractedDocument? reportedDoc;

      final stream = pdfExtractWithProgress(
        '/non/existent/file.pdf',
        onComplete: (doc) => reportedDoc = doc,
        onError: (e) => reportedError = e,
      );

      // Drain the stream.
      await stream.toList();

      expect(reportedError, isNotNull);
      expect(reportedError, isA<FileSystemException>());
      expect(reportedDoc, isNull);
    });

    test('stream closes after error', () async {
      final stream = pdfExtractWithProgress(
        '/non/existent/file.pdf',
        onComplete: (_) {},
        onError: (_) {},
      );

      final values = await stream.toList();
      // Stream should terminate (toList completes).
      expect(values, isA<List<double>>());
    });
  });

  group('extractPdfInIsolate', () {
    test('throws FileSystemException for non-existent file', () async {
      expect(
        () => extractPdfInIsolate('/non/existent/file.pdf'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('pdfPageCountInIsolate', () {
    test('throws for non-existent file', () async {
      expect(
        () => pdfPageCountInIsolate('/non/existent/file.pdf'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('Sentence model', () {
    test('has correct word list', () {
      const sentence = Sentence(words: ['Hello', 'world']);
      expect(sentence.words, ['Hello', 'world']);
    });

    test('serializes to JSON and back', () {
      const original = Sentence(words: ['The', 'quick', 'brown', 'fox']);
      final json = original.toJson();
      final restored = Sentence.fromJson(json);
      expect(restored.words, original.words);
    });

    test('empty sentence has empty word list', () {
      const sentence = Sentence(words: []);
      expect(sentence.words, isEmpty);
    });
  });

  group('ExtractedDocument model', () {
    test('tracks total words', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['Hello', 'world']),
          Sentence(words: ['This', 'is', 'a', 'test']),
        ],
      );
      expect(doc.totalWords, 6);
      expect(doc.allWords, ['Hello', 'world', 'This', 'is', 'a', 'test']);
    });

    test('empty ExtractedDocument has zero words', () {
      const doc = ExtractedDocument(sentences: []);
      expect(doc.totalWords, 0);
      expect(doc.allWords, isEmpty);
    });

    test('hasPageBoundaries is false when empty', () {
      const doc = ExtractedDocument(sentences: []);
      expect(doc.hasPageBoundaries, isFalse);
    });

    test('hasPageBoundaries is true when present', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['word']),
        ],
        pageBoundaries: [
          PageBoundary(
            pageNumber: 0,
            startSentenceIndex: 0,
            startWordIndex: 0,
            firstWords: 'word',
          ),
        ],
        totalPages: 1,
      );
      expect(doc.hasPageBoundaries, isTrue);
    });

    test('merge combines two documents', () {
      const doc1 = ExtractedDocument(
        sentences: [
          Sentence(words: ['Hello']),
        ],
        pageBoundaries: [
          PageBoundary(
            pageNumber: 0,
            startSentenceIndex: 0,
            startWordIndex: 0,
            firstWords: 'Hello',
          ),
        ],
        totalPages: 1,
      );
      const doc2 = ExtractedDocument(
        sentences: [
          Sentence(words: ['World']),
        ],
        pageBoundaries: [
          PageBoundary(
            pageNumber: 1,
            startSentenceIndex: 1,
            startWordIndex: 1,
            firstWords: 'World',
          ),
        ],
        totalPages: 2,
      );
      final merged = doc1.merge(doc2);
      expect(merged.sentences.length, 2);
      expect(merged.pageBoundaries.length, 2);
      expect(merged.totalPages, 2);
      expect(merged.totalWords, 2);
    });

    test('JSON round-trip preserves all fields', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['Hello', 'world']),
          Sentence(words: ['Test']),
        ],
        pageBoundaries: [
          PageBoundary(
            pageNumber: 0,
            startSentenceIndex: 0,
            startWordIndex: 0,
            firstWords: 'Hello world',
          ),
        ],
        totalPages: 5,
      );

      final json = doc.toJson();
      final restored = ExtractedDocument.fromJson(json);

      expect(restored.sentences.length, doc.sentences.length);
      expect(restored.totalPages, doc.totalPages);
      expect(restored.pageBoundaries.length, doc.pageBoundaries.length);
      expect(restored.pageBoundaries[0].pageNumber, 0);
      expect(restored.pageBoundaries[0].firstWords, 'Hello world');
      expect(restored.totalWords, doc.totalWords);
    });
  });

  group('PageRangeResult', () {
    test('has correct structure', () {
      const result = PageRangeResult(
        document: ExtractedDocument(sentences: []),
        totalPages: 5,
        extractedStartPage: 0,
        extractedEndPage: 2,
        pageBoundaries: [],
      );
      expect(result.totalPages, 5);
      expect(result.extractedStartPage, 0);
      expect(result.extractedEndPage, 2);
    });
  });

  group('PdfProgress', () {
    test('fraction is 0.0 when totalPages is 0', () {
      const progress = PdfProgress();
      expect(progress.fraction, 0.0);
    });

    test('fraction computes correctly', () {
      const progress = PdfProgress(lastCompletedPage: 3, totalPages: 10);
      expect(progress.fraction, 0.3);
    });

    test('fraction is 1.0 when all pages complete', () {
      const progress = PdfProgress(lastCompletedPage: 5, totalPages: 5);
      expect(progress.fraction, 1.0);
    });

    test('copyWith creates modified copy', () {
      const progress = PdfProgress(
        lastCompletedPage: 2,
        totalPages: 10,
        phase: ExtractionPhase.preview,
      );
      final updated = progress.copyWith(
        lastCompletedPage: 5,
        phase: ExtractionPhase.done,
      );
      expect(updated.lastCompletedPage, 5);
      expect(updated.totalPages, 10);
      expect(updated.phase, ExtractionPhase.done);
    });
  });

  group('Error types', () {
    test('UnsupportedPdfError carries message', () {
      const error = UnsupportedPdfError('Image-only PDF');
      expect(error.message, 'Image-only PDF');
      expect(error.toString(), contains('Image-only PDF'));
    });

    test('PdfTimeoutError carries file path', () {
      const error = PdfTimeoutError('/path/to/large.pdf');
      expect(error.filePath, '/path/to/large.pdf');
      expect(error.toString(), contains('/path/to/large.pdf'));
    });
  });
}
