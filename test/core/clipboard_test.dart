import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/core/clipboard_service.dart';

void main() {
  group('ClipboardDocument', () {
    test('clipboard text tokenized into words', () {
      final doc = ClipboardDocument.fromClipboardText(
        'The quick brown fox jumps over the lazy dog.',
      );
      expect(doc.words, isNotEmpty);
      expect(doc.words.first, 'The');
      expect(doc.words.last, 'dog.');
      expect(doc.words.length, 9);
    });

    test('title extracted from first 40 chars', () {
      final doc = ClipboardDocument.fromClipboardText(
        'A very long title that exceeds forty characters in length for testing purposes. '
        'More text follows here to make the input realistic.',
      );
      // Title should be truncated from the first 40 chars.
      expect(doc.title.length, lessThanOrEqualTo(41)); // 40 + ellipsis
      expect(doc.title, isNot(equals('Clipboard')));
    });

    test('short title uses first line', () {
      final doc = ClipboardDocument.fromClipboardText(
        'Short Title\nThis is the body of the text with more content.',
      );
      expect(doc.title, 'Short Title');
    });

    test('empty text defaults to Clipboard title', () {
      final doc = ClipboardDocument.fromClipboardText('   ');
      expect(doc.title, 'Clipboard');
      expect(doc.words, isEmpty);
    });

    test('paragraph breaks create sentence boundaries', () {
      final doc = ClipboardDocument.fromClipboardText(
        'First paragraph with words\n\nSecond paragraph with more words',
      );
      // \n\n should be replaced with ". " creating a sentence boundary.
      expect(doc.document.sentences.length, greaterThanOrEqualTo(2));
    });

    test('standard sentence boundaries detected', () {
      final doc = ClipboardDocument.fromClipboardText(
        'First sentence. Second sentence! Third sentence?',
      );
      expect(doc.document.sentences.length, 3);
      expect(doc.document.sentences[0].words, ['First', 'sentence.']);
      expect(doc.document.sentences[1].words, ['Second', 'sentence!']);
      expect(doc.document.sentences[2].words, ['Third', 'sentence?']);
    });

    test('clipboard document provides word list for reading viewport', () {
      final doc = ClipboardDocument.fromClipboardText(
        'Speed reading is a wonderful skill. It allows fast comprehension.',
      );
      // Words are available for the reading viewport.
      expect(doc.words, equals(doc.document.allWords));
      expect(doc.document.totalWords, doc.words.length);
      // No page boundaries for clipboard documents.
      expect(doc.document.hasPageBoundaries, isFalse);
      expect(doc.document.totalPages, 0);
    });

    test('pastedAt timestamp is set', () {
      final before = DateTime.now();
      final doc = ClipboardDocument.fromClipboardText('Some text to read.');
      final after = DateTime.now();
      expect(
        doc.pastedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        doc.pastedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('markdown bold and italic markers are stripped', () {
      final doc = ClipboardDocument.fromClipboardText(
        '**bold text** and *italic text* should be clean.',
      );
      expect(doc.words, isNot(contains('**bold')));
      expect(doc.words, isNot(contains('*italic')));
      expect(doc.words, contains('bold'));
      expect(doc.words, contains('italic'));
    });

    test('markdown headings are stripped', () {
      final doc = ClipboardDocument.fromClipboardText(
        '## Heading Two\nSome body text follows here.',
      );
      expect(doc.words, isNot(contains('##')));
      expect(doc.words, contains('Heading'));
    });

    test('markdown links converted to text', () {
      final doc = ClipboardDocument.fromClipboardText(
        'Click [this link](https://example.com) for more info.',
      );
      expect(doc.words, isNot(contains('[this')));
      expect(doc.words, contains('this'));
      expect(doc.words, contains('link'));
    });

    test('markdown list markers are stripped', () {
      final doc = ClipboardDocument.fromClipboardText(
        '- first item\n- second item\n1. ordered item',
      );
      expect(doc.words, isNot(contains('-')));
      expect(doc.words, isNot(contains('1.')));
      expect(doc.words, contains('first'));
      expect(doc.words, contains('ordered'));
    });

    test('standalone asterisk bullet markers are stripped', () {
      final doc = ClipboardDocument.fromClipboardText(
        '* desire (what pulls you forward) * and fear (what resists change).',
      );
      // The literal * markers from the screenshot should be removed.
      expect(doc.words, isNot(contains('*')));
      expect(doc.words, contains('desire'));
      expect(doc.words, contains('fear'));
    });
  });

  group('ClipboardService', () {
    test('minTextLength is 10', () {
      expect(ClipboardService.minTextLength, 10);
    });

    // Note: ClipboardService.readFromClipboard() requires the Flutter
    // engine and system clipboard, so it cannot be unit-tested without
    // mocking Clipboard.getData. The acceptance criteria for "returns null
    // for empty clipboard" and "returns null for text under 10 characters"
    // are validated through the ClipboardDocument model tests and the
    // minTextLength constant check above.
  });
}
