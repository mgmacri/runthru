import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_cache.dart';

void main() {
  group('Sentence', () {
    test('heading level round-trips and is omitted for body text', () {
      const heading = Sentence(
        words: ['1.', 'The', 'Arrival'],
        startsParagraph: true,
        heading: 2,
      );
      final json = heading.toJson();
      expect(json['h'], 2);
      final back = Sentence.fromJson(json);
      expect(back.heading, 2);
      expect(back.isHeading, isTrue);
      expect(back.startsParagraph, isTrue);

      const body = Sentence(words: ['Plain', 'text.']);
      expect(body.toJson().containsKey('h'), isFalse);
      expect(Sentence.fromJson(body.toJson()).isHeading, isFalse);
    });

    test('documents stored before headings existed load as body text', () {
      final legacy = Sentence.fromJson({
        'words': ['Old', 'cache'],
        'p': true,
      });
      expect(legacy.heading, 0);
    });
  });

  group('OutlineEntry', () {
    test('round-trips title, position, depth and type', () {
      const entry = OutlineEntry(
        title: 'Chapter 3',
        startWordIndex: 1200,
        startSentenceIndex: 80,
        depth: 1,
        type: 'chapter',
      );
      final back = OutlineEntry.fromJson(entry.toJson());
      expect(back.title, 'Chapter 3');
      expect(back.startWordIndex, 1200);
      expect(back.startSentenceIndex, 80);
      expect(back.depth, 1);
      expect(back.type, 'chapter');
    });

    test('top-level untyped entries stay compact', () {
      const entry = OutlineEntry(
        title: 'Preface',
        startWordIndex: 0,
        startSentenceIndex: 0,
      );
      final json = entry.toJson();
      expect(json.containsKey('d'), isFalse);
      expect(json.containsKey('k'), isFalse);
    });
  });

  group('ExtractedDocument', () {
    test('new documents carry the current extraction version', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['Hi.']),
        ],
      );
      expect(doc.version, kExtractionVersion);
      expect(
        ExtractedDocument.fromJson(doc.toJson()).version,
        kExtractionVersion,
      );
    });

    test('documents stored before the version field are version 1', () {
      final legacy = ExtractedDocument.fromJson({
        'sentences': [
          {
            'words': ['Hi.'],
          },
        ],
        'pageBoundaries': <Object?>[],
        'totalPages': 1,
      });
      expect(legacy.version, 1);
      expect(legacy.outline, isEmpty);
    });

    test('outline round-trips and is omitted when empty', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(
            words: ['Chapter', 'One'],
            startsParagraph: true,
            heading: 1,
          ),
          Sentence(words: ['It', 'began.']),
        ],
        outline: [
          OutlineEntry(
            title: 'Chapter One',
            startWordIndex: 0,
            startSentenceIndex: 0,
          ),
        ],
      );
      final back = ExtractedDocument.fromJson(doc.toJson());
      expect(back.outline.single.title, 'Chapter One');

      const bare = ExtractedDocument(
        sentences: [
          Sentence(words: ['Hi.']),
        ],
      );
      expect(bare.toJson().containsKey('outline'), isFalse);
    });

    test('merge offsets the incoming outline and page boundaries', () {
      const first = ExtractedDocument(
        sentences: [
          Sentence(words: ['One', 'two', 'three.']),
        ],
        pageBoundaries: [
          PageBoundary(pageNumber: 0, startSentenceIndex: 0, startWordIndex: 0),
        ],
        outline: [
          OutlineEntry(title: 'A', startWordIndex: 0, startSentenceIndex: 0),
        ],
        totalPages: 2,
      );
      const second = ExtractedDocument(
        sentences: [
          Sentence(words: ['Four', 'five.']),
        ],
        pageBoundaries: [
          PageBoundary(pageNumber: 1, startSentenceIndex: 0, startWordIndex: 0),
        ],
        outline: [
          OutlineEntry(title: 'B', startWordIndex: 0, startSentenceIndex: 0),
        ],
        totalPages: 2,
      );
      final merged = first.merge(second);
      expect(merged.outline.map((e) => e.title), ['A', 'B']);
      expect(merged.outline[1].startWordIndex, 3);
      expect(merged.outline[1].startSentenceIndex, 1);
      expect(merged.pageBoundaries[1].startWordIndex, 3);
      expect(merged.sentences.length, 2);
    });

    test('merge joins a sentence that continues across the boundary', () {
      const first = ExtractedDocument(
        sentences: [
          Sentence(words: ['Done.']),
          Sentence(words: ['He', 'walked', 'to'], startsParagraph: true),
        ],
      );
      const second = ExtractedDocument(
        sentences: [
          Sentence(words: ['the', 'door.']),
          Sentence(words: ['Next.']),
        ],
        pageBoundaries: [
          PageBoundary(pageNumber: 1, startSentenceIndex: 0, startWordIndex: 0),
        ],
        outline: [
          OutlineEntry(title: 'B', startWordIndex: 2, startSentenceIndex: 1),
        ],
        continuesPrevious: true,
      );
      final merged = first.merge(second);
      expect(merged.sentences.length, 3);
      expect(merged.sentences[1].words, ['He', 'walked', 'to', 'the', 'door.']);
      expect(merged.sentences[1].startsParagraph, isTrue);
      // The page starts at "the", mid-sentence, inside sentence 1.
      expect(merged.pageBoundaries.single.startWordIndex, 4);
      expect(merged.pageBoundaries.single.startSentenceIndex, 1);
      expect(merged.outline.single.startWordIndex, 6);
      expect(merged.outline.single.startSentenceIndex, 2);
      expect(merged.allWords.join(' '), 'Done. He walked to the door. Next.');
    });

    test('merge rejoins a word hyphenated across the boundary', () {
      const first = ExtractedDocument(
        sentences: [
          Sentence(words: ['as', 'my', 'fa$kSplitWordMarker']),
        ],
      );
      const second = ExtractedDocument(
        sentences: [
          Sentence(words: ['ther', 'said.']),
        ],
        pageBoundaries: [
          PageBoundary(pageNumber: 1, startSentenceIndex: 0, startWordIndex: 0),
        ],
        continuesPrevious: true,
      );
      final merged = first.merge(second);
      expect(merged.allWords, ['as', 'my', 'father', 'said.']);
      // The page now begins inside the rejoined word.
      expect(merged.pageBoundaries.single.startWordIndex, 2);
    });

    test('merge never joins into or out of a heading', () {
      const first = ExtractedDocument(
        sentences: [
          Sentence(
            words: ['Chapter', 'Two'],
            startsParagraph: true,
            heading: 1,
          ),
        ],
      );
      const second = ExtractedDocument(
        sentences: [
          Sentence(words: ['it', 'continued.']),
        ],
        continuesPrevious: true,
      );
      final merged = first.merge(second);
      expect(merged.sentences.length, 2);
      expect(merged.sentences.first.isHeading, isTrue);
    });

    test('continuesPrevious without earlier text is ignored', () {
      const first = ExtractedDocument(sentences: []);
      const second = ExtractedDocument(
        sentences: [
          Sentence(words: ['orphan', 'start.']),
        ],
        continuesPrevious: true,
      );
      expect(first.merge(second).allWords, ['orphan', 'start.']);
    });
  });

  group('PdfCache.isUsable', () {
    const boundary = PageBoundary(
      pageNumber: 0,
      startSentenceIndex: 0,
      startWordIndex: 0,
    );

    test('serves documents from the current extractor', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['Hi.']),
        ],
        pageBoundaries: [boundary],
      );
      expect(PdfCache.isUsable(doc), isTrue);
    });

    test('rejects text cached by an older extractor so it is redone', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['in\u0002clined']),
        ],
        pageBoundaries: [boundary],
        version: 1,
      );
      expect(PdfCache.isUsable(doc), isFalse);
    });

    test('rejects the oldest format without page boundaries', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['Hi.']),
        ],
      );
      expect(PdfCache.isUsable(doc), isFalse);
    });
  });

  group('joinSplitWord', () {
    test('drops the hyphen for an ordinary split word', () {
      expect(joinSplitWord('con-', 'fidences'), 'confidences');
      expect(joinSplitWord('fa$kSplitWordMarker', 'ther'), 'father');
      expect(joinSplitWord('quiver‐', 'ing'), 'quivering');
    });

    test('keeps the hyphen before a capital or a digit', () {
      expect(joinSplitWord('Anglo-', 'Saxon'), 'Anglo-Saxon');
      expect(joinSplitWord('mid-', '1990s'), 'mid-1990s');
    });

    test('keeps the hyphen after a prefix that takes one', () {
      expect(joinSplitWord('self-', 'aware'), 'self-aware');
      expect(joinSplitWord('“Well-', 'known'), '“Well-known');
      expect(joinSplitWord('twenty-', 'two'), 'twenty-two');
    });

    test('an empty right half returns the cleaned left half', () {
      expect(joinSplitWord('end-', ''), 'end');
    });
  });
}
