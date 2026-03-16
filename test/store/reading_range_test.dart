import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/sentence_resolver.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/store/models.dart';

void main() {
  group('BookmarkData with ReadingRange', () {
    test('JSON round-trip with range', () {
      final bookmark = BookmarkData(
        wordIndex: 150,
        timestamp: DateTime(2025, 6, 15),
        readingRange: const ReadingRange(
          startPage: 2,
          startWordIndexOnPage: 5,
          endPage: 10,
          endWordIndexOnPage: 20,
          resolvedStartWordIndex: 100,
          resolvedEndWordIndex: 500,
        ),
        readingProgress: 0.35,
      );

      final json = bookmark.toJson();
      final restored = BookmarkData.fromJson(json);

      expect(restored.wordIndex, 150);
      expect(restored.readingRange, isNotNull);
      expect(restored.readingRange!.startPage, 2);
      expect(restored.readingRange!.endPage, 10);
      expect(restored.readingRange!.resolvedStartWordIndex, 100);
      expect(restored.readingRange!.resolvedEndWordIndex, 500);
      expect(restored.readingProgress, 0.35);
    });

    test('JSON round-trip without range', () {
      const bookmark = BookmarkData(wordIndex: 50);
      final json = bookmark.toJson();
      final restored = BookmarkData.fromJson(json);

      expect(restored.wordIndex, 50);
      expect(restored.readingRange, isNull);
      expect(restored.readingProgress, 0.0);
    });

    test('copyWith clears range', () {
      const bookmark = BookmarkData(
        wordIndex: 50,
        readingRange: ReadingRange(startPage: 0, endPage: 5),
      );
      final updated = bookmark.copyWith(clearReadingRange: true);
      expect(updated.readingRange, isNull);
      expect(updated.wordIndex, 50);
    });
  });

  group('resolveRange', () {
    final boundaries = [
      const PageBoundary(
        pageNumber: 0,
        startSentenceIndex: 0,
        startWordIndex: 0,
        firstWords: 'Chapter One The',
      ),
      const PageBoundary(
        pageNumber: 1,
        startSentenceIndex: 8,
        startWordIndex: 80,
        firstWords: 'continued from page',
      ),
      const PageBoundary(
        pageNumber: 2,
        startSentenceIndex: 16,
        startWordIndex: 160,
        firstWords: 'new section begins',
      ),
      const PageBoundary(
        pageNumber: 3,
        startSentenceIndex: 24,
        startWordIndex: 240,
        firstWords: 'nearly the end',
      ),
    ];

    test('resolves start and end within different pages', () {
      const range = ReadingRange(
        startPage: 1,
        startWordIndexOnPage: 10,
        endPage: 3,
        endWordIndexOnPage: 5,
      );
      final result = resolveRange(range, boundaries);
      expect(result.globalStart, 90); // 80 + 10
      expect(result.globalEnd, 245); // 240 + 5
    });

    test('resolves range on same page', () {
      const range = ReadingRange(
        startPage: 2,
        startWordIndexOnPage: 0,
        endPage: 2,
        endWordIndexOnPage: 50,
      );
      final result = resolveRange(range, boundaries);
      expect(result.globalStart, 160);
      expect(result.globalEnd, 210);
    });

    test('resolves first page', () {
      const range = ReadingRange(
        startPage: 0,
        startWordIndexOnPage: 0,
        endPage: 0,
        endWordIndexOnPage: 30,
      );
      final result = resolveRange(range, boundaries);
      expect(result.globalStart, 0);
      expect(result.globalEnd, 30);
    });
  });

  group('resumeIndex with ReadingRange', () {
    test('snaps to range start if bookmark is before range', () {
      const doc = ExtractedDocument(sentences: [
        Sentence(words: ['a', 'b', 'c', 'd', 'e']),
        Sentence(words: ['f', 'g', 'h', 'i', 'j']),
        Sentence(words: ['k', 'l', 'm']),
      ]);

      const bookmark = BookmarkData(
        wordIndex: 2, // in first sentence
        readingRange: ReadingRange(
          startPage: 0,
          endPage: 0,
          resolvedStartWordIndex: 5, // second sentence start
          resolvedEndWordIndex: 12,
        ),
      );

      final result = resumeIndex(bookmark, doc);
      expect(result, 5); // Snapped to range start
    });

    test('returns normal sentence start when within range', () {
      const doc = ExtractedDocument(sentences: [
        Sentence(words: ['a', 'b', 'c', 'd', 'e']),
        Sentence(words: ['f', 'g', 'h', 'i', 'j']),
        Sentence(words: ['k', 'l', 'm']),
      ]);

      const bookmark = BookmarkData(
        wordIndex: 7, // in second sentence
        readingRange: ReadingRange(
          startPage: 0,
          endPage: 0,
          resolvedStartWordIndex: 0,
          resolvedEndWordIndex: 12,
        ),
      );

      final result = resumeIndex(bookmark, doc);
      expect(result, 5); // Second sentence start
    });

    test('works without reading range (backward compat)', () {
      const doc = ExtractedDocument(sentences: [
        Sentence(words: ['a', 'b', 'c']),
        Sentence(words: ['d', 'e', 'f']),
      ]);

      const bookmark = BookmarkData(wordIndex: 4);
      final result = resumeIndex(bookmark, doc);
      expect(result, 3); // Second sentence start
    });
  });
}
