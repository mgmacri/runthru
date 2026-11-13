import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/services/web_page_decoder.dart';

void main() {
  // "café – “fine”" as Windows-1252 writes it: é is E9, the dash 96, the
  // curly quotes 93 and 94. None of that is valid UTF-8.
  const cp1252 = [
    0x63, 0x61, 0x66, 0xE9, 0x20, 0x96, 0x20, 0x93, //
    0x66, 0x69, 0x6E, 0x65, 0x94,
  ];
  const text = 'café – “fine”';

  group('decodeWebPage', () {
    test('reads UTF-8, named or not', () {
      final bytes = utf8.encode('<p>$text</p>');
      expect(decodeWebPage(bytes), '<p>$text</p>');
      expect(decodeWebPage(bytes, charset: 'UTF-8'), '<p>$text</p>');
      expect(decodeWebPage(bytes, charset: 'utf8'), '<p>$text</p>');
    });

    test('an old page that names no encoding is read as Windows-1252', () {
      // Read as strict UTF-8, such a page could not be opened at all.
      expect(decodeWebPage(cp1252), text);
    });

    test('goes by the header, then by the page\'s own meta tag', () {
      expect(decodeWebPage(cp1252, charset: 'ISO-8859-1'), text);
      expect(decodeWebPage(cp1252, charset: 'windows-1252'), text);
      expect(
        decodeWebPage([
          ...latin1.encode('<html><head><meta charset="windows-1252">'),
          ...cp1252,
        ]),
        '<html><head><meta charset="windows-1252">$text',
      );
      expect(
        decodeWebPage([
          ...latin1.encode(
            '<meta http-equiv="Content-Type" '
            'content="text/html; charset=iso-8859-1">',
          ),
          ...cp1252,
        ]),
        endsWith(text),
      );
    });

    test('says when it cannot read the encoding, and does not guess', () {
      expect(decodeWebPage(cp1252, charset: 'Shift_JIS'), isNull);
      expect(
        decodeWebPage(latin1.encode('<meta charset="gb2312"><p>x</p>')),
        isNull,
      );
      // UTF-16, by its byte order mark.
      expect(decodeWebPage(const [0xFF, 0xFE, 0x68, 0x00]), isNull);
    });

    test('a page that says UTF-8 and is not quite is still read', () {
      final bytes = [...utf8.encode('good '), 0xE9, ...utf8.encode(' end')];
      final decoded = decodeWebPage(bytes, charset: 'utf-8')!;
      expect(decoded, startsWith('good '));
      expect(decoded, endsWith(' end'));
    });

    test('drops a UTF-8 byte order mark', () {
      expect(decodeWebPage([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]), text);
    });
  });

  group('readWebPage', () {
    test('collects a body that fits', () async {
      final bytes = await readWebPage(
        Stream.fromIterable([
          [1, 2],
          [3],
        ]),
        maxBytes: 3,
      );
      expect(bytes, [1, 2, 3]);
    });

    test('gives up on a body that is too large, without reading on', () async {
      var chunksAsked = 0;
      Stream<List<int>> endless() async* {
        while (true) {
          chunksAsked++;
          yield List.filled(1024, 0);
        }
      }

      await expectLater(
        readWebPage(endless(), maxBytes: 4096),
        throwsA(isA<WebPageTooLarge>()),
      );
      // Five kilobytes were enough to know; the rest was never asked for.
      expect(chunksAsked, 5);
    });
  });
}
