import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/store/models.dart';

void main() {
  group('ReadingRange serialization', () {
    test('round-trips through JSON', () {
      const range = ReadingRange(
        startPage: 5,
        startWordIndexOnPage: 12,
        startWordAnchor: 'quantum',
        endPage: 42,
        endWordIndexOnPage: 7,
        endWordAnchor: 'conclusion',
        resolvedStartWordIndex: 100,
        resolvedEndWordIndex: 500,
      );

      final json = range.toJson();
      final restored = ReadingRange.fromJson(json);

      expect(restored.startPage, 5);
      expect(restored.startWordIndexOnPage, 12);
      expect(restored.startWordAnchor, 'quantum');
      expect(restored.endPage, 42);
      expect(restored.endWordIndexOnPage, 7);
      expect(restored.endWordAnchor, 'conclusion');
      expect(restored.resolvedStartWordIndex, 100);
      expect(restored.resolvedEndWordIndex, 500);
    });

    test('handles missing optional fields', () {
      final json = <String, Object?>{
        'startPage': 0,
        'endPage': 10,
      };
      final range = ReadingRange.fromJson(json);

      expect(range.startPage, 0);
      expect(range.startWordIndexOnPage, 0);
      expect(range.startWordAnchor, isNull);
      expect(range.endPage, 10);
      expect(range.endWordIndexOnPage, 0);
      expect(range.endWordAnchor, isNull);
      expect(range.resolvedStartWordIndex, 0);
      expect(range.resolvedEndWordIndex, 0);
    });
  });

  group('BookmarkData with ReadingRange serialization', () {
    test('round-trips with readingRange', () {
      final bookmark = BookmarkData(
        wordIndex: 150,
        timestamp: DateTime(2025, 6, 15, 10, 30),
        readingRange: const ReadingRange(
          startPage: 3,
          startWordIndexOnPage: 5,
          startWordAnchor: 'hello',
          endPage: 20,
          endWordIndexOnPage: 10,
          endWordAnchor: 'world',
          resolvedStartWordIndex: 50,
          resolvedEndWordIndex: 300,
        ),
        readingProgress: 0.42,
      );

      final json = bookmark.toJson();
      final restored = BookmarkData.fromJson(json);

      expect(restored.wordIndex, 150);
      expect(restored.readingProgress, 0.42);
      expect(restored.readingRange, isNotNull);
      expect(restored.readingRange!.startPage, 3);
      expect(restored.readingRange!.startWordAnchor, 'hello');
      expect(restored.readingRange!.endPage, 20);
      expect(restored.readingRange!.endWordAnchor, 'world');
      expect(restored.readingRange!.resolvedStartWordIndex, 50);
      expect(restored.readingRange!.resolvedEndWordIndex, 300);
    });

    test('round-trips without readingRange', () {
      final bookmark = BookmarkData(
        wordIndex: 75,
        timestamp: DateTime(2025, 1, 1),
      );

      final json = bookmark.toJson();
      final restored = BookmarkData.fromJson(json);

      expect(restored.wordIndex, 75);
      expect(restored.readingRange, isNull);
    });

    test('copyWith clearReadingRange clears the range', () {
      const bookmark = BookmarkData(
        wordIndex: 100,
        readingRange: ReadingRange(startPage: 1, endPage: 5),
      );

      final cleared = bookmark.copyWith(clearReadingRange: true);
      expect(cleared.readingRange, isNull);
      expect(cleared.wordIndex, 100);
    });
  });

  group('AppConfig with BookmarkData+ReadingRange', () {
    test('full JSON round-trip preserves nested readingRange', () {
      final config = AppConfig(
        defaultWpm: 450,
        bookmarks: {
          '/path/to/book.pdf': BookmarkData(
            wordIndex: 200,
            timestamp: DateTime(2025, 3, 1),
            readingRange: const ReadingRange(
              startPage: 10,
              startWordIndexOnPage: 3,
              startWordAnchor: 'chapter',
              endPage: 50,
              endWordIndexOnPage: 7,
              endWordAnchor: 'end',
              resolvedStartWordIndex: 120,
              resolvedEndWordIndex: 980,
            ),
          ),
        },
      );

      final json = config.toJson();
      final restored = AppConfig.fromJson(json);

      expect(restored.defaultWpm, 450);
      expect(restored.bookmarks.length, 1);

      final bookmark = restored.bookmarks['/path/to/book.pdf'];
      expect(bookmark, isNotNull);
      expect(bookmark!.wordIndex, 200);
      expect(bookmark.readingRange, isNotNull);
      expect(bookmark.readingRange!.startPage, 10);
      expect(bookmark.readingRange!.startWordAnchor, 'chapter');
      expect(bookmark.readingRange!.endPage, 50);
      expect(bookmark.readingRange!.endWordAnchor, 'end');
      expect(bookmark.readingRange!.resolvedStartWordIndex, 120);
      expect(bookmark.readingRange!.resolvedEndWordIndex, 980);
    });

    test('round-trip with no bookmarks', () {
      const config = AppConfig();
      final json = config.toJson();
      final restored = AppConfig.fromJson(json);

      expect(restored.bookmarks, isEmpty);
    });
  });

  group('ExtractedDocument with pageBoundaries', () {
    test('round-trips pageBoundaries and totalPages', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['hello', 'world']),
          Sentence(words: ['foo', 'bar']),
        ],
        pageBoundaries: [
          PageBoundary(
            pageNumber: 0,
            startSentenceIndex: 0,
            startWordIndex: 0,
            firstWords: 'hello world',
          ),
          PageBoundary(
            pageNumber: 1,
            startSentenceIndex: 1,
            startWordIndex: 2,
            firstWords: 'foo bar',
          ),
        ],
        totalPages: 2,
      );

      final json = doc.toJson();
      final restored = ExtractedDocument.fromJson(json);

      expect(restored.totalPages, 2);
      expect(restored.pageBoundaries.length, 2);
      expect(restored.pageBoundaries[0].pageNumber, 0);
      expect(restored.pageBoundaries[0].startWordIndex, 0);
      expect(restored.pageBoundaries[1].pageNumber, 1);
      expect(restored.pageBoundaries[1].startWordIndex, 2);
      expect(restored.hasPageBoundaries, isTrue);
    });

    test('fromJson handles missing pageBoundaries (old format)', () {
      final json = <String, Object?>{
        'sentences': [
          {
            'words': ['a', 'b'],
          },
        ],
      };
      final doc = ExtractedDocument.fromJson(json);

      expect(doc.pageBoundaries, isEmpty);
      expect(doc.totalPages, 0);
      expect(doc.hasPageBoundaries, isFalse);
    });

    test('merge combines pageBoundaries', () {
      const doc1 = ExtractedDocument(
        sentences: [
          Sentence(words: ['a'])
        ],
        pageBoundaries: [
          PageBoundary(pageNumber: 0, startSentenceIndex: 0, startWordIndex: 0),
        ],
        totalPages: 2,
      );
      const doc2 = ExtractedDocument(
        sentences: [
          Sentence(words: ['b'])
        ],
        pageBoundaries: [
          PageBoundary(pageNumber: 1, startSentenceIndex: 0, startWordIndex: 1),
        ],
        totalPages: 2,
      );

      final merged = doc1.merge(doc2);
      expect(merged.sentences.length, 2);
      expect(merged.pageBoundaries.length, 2);
      expect(merged.totalPages, 2);
    });
  });
}
