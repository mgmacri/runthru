import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/text_segmentation.dart';
import 'package:runthru/services/models.dart';

List<String> _texts(List<Sentence> s) =>
    s.map((x) => x.words.join(' ')).toList();
List<bool> _starts(List<Sentence> s) =>
    s.map((x) => x.startsParagraph).toList();

void main() {
  group('textToSentences', () {
    test('splits sentences and marks the first of each paragraph', () {
      final s = textToSentences('One two. Three four!\n\nFive six? Seven.');
      expect(_texts(s), ['One two.', 'Three four!', 'Five six?', 'Seven.']);
      expect(_starts(s), [true, false, true, false]);
    });

    test('a heading stays its own sentence without an added full stop', () {
      final s = textToSentences('Chapter One: Arrival\n\nThe ferry was late.');
      expect(_texts(s), ['Chapter One: Arrival', 'The ferry was late.']);
      expect(_starts(s), [true, true]);
    });

    test('a single newline is whitespace, not a paragraph', () {
      final s = textToSentences(
        'The ferry reached the island at 6:42\nin the morning.',
      );
      expect(_texts(s), [
        'The ferry reached the island at 6:42 in the morning.',
      ]);
    });

    test('splits after closing quotes and brackets', () {
      final s = textToSentences(
        '“Keep it current.” She laughed. (It worked.) Done… Then',
      );
      expect(_texts(s), [
        '“Keep it current.”',
        'She laughed.',
        '(It worked.)',
        'Done…',
        'Then',
      ]);
    });

    test('numbers with internal stops are not split', () {
      final s = textToSentences('Barometer 1,004.6 hPa and falling.');
      expect(s.length, 1);
    });

    test('drops punctuation-only fragments and blank paragraphs', () {
      final s = textToSentences('\n\n.\n\nReal text.\n\n\n\n');
      expect(_texts(s), ['Real text.']);
      expect(_starts(s), [true]);
    });
  });

  group('Sentence JSON', () {
    test('startsParagraph round-trips and is omitted when false', () {
      const start = Sentence(words: ['A'], startsParagraph: true);
      const plain = Sentence(words: ['B']);
      expect(start.toJson()['p'], isTrue);
      expect(plain.toJson().containsKey('p'), isFalse);
      expect(Sentence.fromJson(start.toJson()).startsParagraph, isTrue);
      expect(
        Sentence.fromJson({
          'words': ['C'],
        }).startsParagraph,
        isFalse,
      );
    });
  });

  group('paragraphStartWordIndices', () {
    test('maps paragraph starts to global word indices', () {
      final doc = ExtractedDocument(
        sentences: textToSentences('a b. c d.\n\ne f.'),
      );
      expect(paragraphStartWordIndices(doc), {0, 4});
    });

    test('documents without paragraph data return an empty set', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['x']),
        ],
      );
      expect(paragraphStartWordIndices(doc), isEmpty);
    });
  });
}
