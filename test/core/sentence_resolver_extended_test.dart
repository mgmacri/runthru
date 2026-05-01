import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/sentence_resolver.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/store/models.dart';

void main() {
  group('resumeIndex', () {
    const doc = ExtractedDocument(sentences: [
      Sentence(words: ['Hello', 'world', 'foo']), // 0..2
      Sentence(words: ['bar', 'baz']), // 3..4
      Sentence(words: ['qux']), // 5
    ]);

    test('returns 0 for empty document', () {
      const emptyDoc = ExtractedDocument(sentences: []);
      const bookmark = BookmarkData(wordIndex: 5);
      expect(resumeIndex(bookmark, emptyDoc), 0);
    });

    test('returns 0 when bookmark is in first sentence', () {
      const bookmark = BookmarkData(wordIndex: 1);
      expect(resumeIndex(bookmark, doc), 0);
    });

    test('returns start of second sentence', () {
      const bookmark = BookmarkData(wordIndex: 3);
      expect(resumeIndex(bookmark, doc), 3);
    });

    test('returns start of second sentence for middle word', () {
      const bookmark = BookmarkData(wordIndex: 4);
      expect(resumeIndex(bookmark, doc), 3);
    });

    test('returns start of third sentence', () {
      const bookmark = BookmarkData(wordIndex: 5);
      expect(resumeIndex(bookmark, doc), 5);
    });

    test('handles bookmark past end by returning last sentence start', () {
      const bookmark = BookmarkData(wordIndex: 100);
      expect(resumeIndex(bookmark, doc), 5);
    });
  });
}
