import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/sentence_resolver.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/store/models.dart';

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
      expect(resumeIndex(const BookmarkData(wordIndex: 0), doc), 0);
      expect(resumeIndex(const BookmarkData(wordIndex: 3), doc), 3);
      expect(resumeIndex(const BookmarkData(wordIndex: 5), doc), 5);
    });

    test('word mid-sentence → returns sentence start', () {
      expect(resumeIndex(const BookmarkData(wordIndex: 1), doc), 0);
      expect(resumeIndex(const BookmarkData(wordIndex: 2), doc), 0);
      expect(resumeIndex(const BookmarkData(wordIndex: 4), doc), 3);
      expect(resumeIndex(const BookmarkData(wordIndex: 7), doc), 5);
    });

    test('word at last position → returns last sentence start', () {
      expect(resumeIndex(const BookmarkData(wordIndex: 8), doc), 5);
    });

    test('word past end → returns last sentence start', () {
      expect(resumeIndex(const BookmarkData(wordIndex: 100), doc), 5);
    });

    test('empty document → returns 0', () {
      const emptyDoc = ExtractedDocument(sentences: []);
      expect(resumeIndex(const BookmarkData(wordIndex: 5), emptyDoc), 0);
    });
  });

  group('sentenceBoundsForWord', () {
    test('returns bounds for the active sentence', () {
      final words = 'The quick brown. Fox jumps high!'.split(' ');
      expect(sentenceBoundsForWord(words, 1), (start: 0, end: 2));
      expect(sentenceBoundsForWord(words, 4), (start: 3, end: 5));
    });

    test('clamps out-of-range index', () {
      final words = 'The quick brown.'.split(' ');
      expect(sentenceBoundsForWord(words, 99), (start: 0, end: 2));
    });

    test('handles empty word lists', () {
      expect(sentenceBoundsForWord(const [], 4), (start: 0, end: -1));
    });
  });

  group('sentenceWindowAround', () {
    List<String> words(int n) => [for (var i = 0; i < n; i++) 'w$i'];

    test('short sentences are returned whole', () {
      final w = sentenceWindowAround(words(12), 7);
      expect(w.words.length, 12);
      expect(w.highlight, 7);
      expect(w.clippedStart, isFalse);
      expect(w.clippedEnd, isFalse);
    });

    test('long sentence keeps the current word visible near the end', () {
      final all = words(80);
      final w = sentenceWindowAround(all, 75);
      expect(w.words.length, 30);
      expect(w.words[w.highlight], 'w75');
      expect(w.clippedStart, isTrue);
      expect(w.clippedEnd, isFalse);
    });

    test('long sentence keeps context before a mid-sentence word', () {
      final w = sentenceWindowAround(words(80), 40);
      expect(w.words[w.highlight], 'w40');
      expect(w.highlight, 10);
      expect(w.clippedStart, isTrue);
      expect(w.clippedEnd, isTrue);
    });

    test('word near the start does not clip the start', () {
      final w = sentenceWindowAround(words(80), 2);
      expect(w.words.first, 'w0');
      expect(w.highlight, 2);
      expect(w.clippedStart, isFalse);
      expect(w.clippedEnd, isTrue);
    });
  });
}
