import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/reading_range_resolver.dart';
import 'package:runthru/services/models.dart';

void main() {
  group('resolveAndValidateRange', () {
    final boundaries = [
      const PageBoundary(
        pageNumber: 0,
        startSentenceIndex: 0,
        startWordIndex: 0,
        firstWords: 'Hello world foo bar baz',
      ),
      const PageBoundary(
        pageNumber: 1,
        startSentenceIndex: 2,
        startWordIndex: 10,
        firstWords: 'Page two starts here with',
      ),
      const PageBoundary(
        pageNumber: 2,
        startSentenceIndex: 4,
        startWordIndex: 25,
        firstWords: 'Final page content begins now',
      ),
    ];

    final allWords = List.generate(40, (i) => 'word$i');

    test('resolves with matching anchors', () {
      const range = ReadingRange(
        startPage: 0,
        startWordIndexOnPage: 3,
        startWordAnchor: 'word3',
        endPage: 1,
        endWordIndexOnPage: 5,
        endWordAnchor: 'word15',
      );

      final result = resolveAndValidateRange(range, boundaries, allWords);
      expect(result, isNotNull);
      expect(result!.resolvedStartWordIndex, 3);
      expect(result.resolvedEndWordIndex, 15);
    });

    test('resolves with mismatched anchors (best effort)', () {
      const range = ReadingRange(
        startPage: 0,
        startWordIndexOnPage: 3,
        startWordAnchor: 'wrong_word',
        endPage: 1,
        endWordIndexOnPage: 5,
        endWordAnchor: 'also_wrong',
      );

      final result = resolveAndValidateRange(range, boundaries, allWords);
      expect(result, isNotNull);
      // Still resolves to the positional index despite mismatch.
      expect(result!.resolvedStartWordIndex, 3);
      expect(result.resolvedEndWordIndex, 15);
    });

    test('clamps to valid range', () {
      const range = ReadingRange(
        startPage: 2,
        startWordIndexOnPage: 100,
        endPage: 2,
        endWordIndexOnPage: 200,
      );

      final result = resolveAndValidateRange(range, boundaries, allWords);
      expect(result, isNotNull);
      expect(result!.resolvedStartWordIndex, 39); // clamped to last
      expect(result.resolvedEndWordIndex, 39);
    });

    test('swaps start and end if start > end', () {
      const range = ReadingRange(
        startPage: 2,
        startWordIndexOnPage: 5,
        endPage: 0,
        endWordIndexOnPage: 2,
      );

      final result = resolveAndValidateRange(range, boundaries, allWords);
      expect(result, isNotNull);
      expect(
        result!.resolvedStartWordIndex <= result.resolvedEndWordIndex,
        isTrue,
      );
    });

    test('returns null for empty boundaries', () {
      const range = ReadingRange(
        startPage: 0,
        startWordIndexOnPage: 0,
        endPage: 1,
        endWordIndexOnPage: 5,
      );

      final result = resolveAndValidateRange(range, [], allWords);
      expect(result, isNull);
    });

    test('returns null for empty word list', () {
      const range = ReadingRange(
        startPage: 0,
        startWordIndexOnPage: 0,
        endPage: 1,
        endWordIndexOnPage: 5,
      );

      final result = resolveAndValidateRange(range, boundaries, []);
      expect(result, isNull);
    });
  });

  group('pageForWordIndex', () {
    final boundaries = [
      const PageBoundary(
          pageNumber: 0, startSentenceIndex: 0, startWordIndex: 0),
      const PageBoundary(
          pageNumber: 1, startSentenceIndex: 2, startWordIndex: 10),
      const PageBoundary(
          pageNumber: 2, startSentenceIndex: 4, startWordIndex: 25),
    ];

    test('returns correct page for word in first page', () {
      expect(pageForWordIndex(5, boundaries), 0);
    });

    test('returns correct page for word in middle page', () {
      expect(pageForWordIndex(15, boundaries), 1);
    });

    test('returns correct page for word at page boundary', () {
      expect(pageForWordIndex(10, boundaries), 1);
      expect(pageForWordIndex(25, boundaries), 2);
    });

    test('returns last page for word past all boundaries', () {
      expect(pageForWordIndex(100, boundaries), 2);
    });

    test('returns 0 for empty boundaries', () {
      expect(pageForWordIndex(5, []), 0);
    });
  });

  group('wordIndexOnPage', () {
    final boundaries = [
      const PageBoundary(
          pageNumber: 0, startSentenceIndex: 0, startWordIndex: 0),
      const PageBoundary(
          pageNumber: 1, startSentenceIndex: 2, startWordIndex: 10),
    ];

    test('returns correct offset within page', () {
      expect(wordIndexOnPage(13, boundaries), 3);
    });

    test('returns 0 for word at page start', () {
      expect(wordIndexOnPage(10, boundaries), 0);
    });

    test('returns raw index for empty boundaries', () {
      expect(wordIndexOnPage(5, []), 5);
    });
  });
}
