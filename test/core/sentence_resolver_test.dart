import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/sentence_resolver.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/store/models.dart';

void main() {
  const doc = ExtractedDocument(
    sentences: [
      Sentence(words: ['The', 'quick', 'brown']), // 0..2
      Sentence(words: ['fox', 'jumps']), // 3..4
      Sentence(words: ['over', 'the', 'lazy', 'dog']), // 5..8
    ],
  );

  group('resumeIndex', () {
    test('word at sentence start → returns same index', () {
      expect(
        resumeIndex(const BookmarkData(wordIndex: 0), doc),
        0,
      );
      expect(
        resumeIndex(const BookmarkData(wordIndex: 3), doc),
        3,
      );
      expect(
        resumeIndex(const BookmarkData(wordIndex: 5), doc),
        5,
      );
    });

    test('word mid-sentence → returns sentence start', () {
      expect(
        resumeIndex(const BookmarkData(wordIndex: 1), doc),
        0,
      );
      expect(
        resumeIndex(const BookmarkData(wordIndex: 2), doc),
        0,
      );
      expect(
        resumeIndex(const BookmarkData(wordIndex: 4), doc),
        3,
      );
      expect(
        resumeIndex(const BookmarkData(wordIndex: 7), doc),
        5,
      );
    });

    test('word at last position → returns last sentence start', () {
      expect(
        resumeIndex(const BookmarkData(wordIndex: 8), doc),
        5,
      );
    });

    test('word past end → returns last sentence start', () {
      expect(
        resumeIndex(const BookmarkData(wordIndex: 100), doc),
        5,
      );
    });

    test('empty document → returns 0', () {
      const emptyDoc = ExtractedDocument(sentences: []);
      expect(
        resumeIndex(
          const BookmarkData(wordIndex: 5),
          emptyDoc,
        ),
        0,
      );
    });
  });
}
