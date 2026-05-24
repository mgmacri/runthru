import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/document_classifier.dart';

void main() {
  group('DocumentClassifier', () {
    test('classifies supported extensions case-insensitively', () {
      expect(
        DocumentClassifier.kindFromExtension('/books/a.PDF'),
        DocumentKind.pdf,
      );
      expect(
        DocumentClassifier.kindFromExtension('/books/a.EPUB'),
        DocumentKind.epub,
      );
      expect(
        DocumentClassifier.kindFromExtension('/books/a.txt'),
        DocumentKind.unsupported,
      );
    });

    test('classifies PDF signature', () {
      expect(
        DocumentClassifier.kindFromBytes('%PDF-1.7'.codeUnits),
        DocumentKind.pdf,
      );
    });

    test('classifies EPUB signature', () {
      expect(
        DocumentClassifier.kindFromBytes([
          0x50,
          0x4b,
          0x03,
          0x04,
          ...'mimetypeapplication/epub+zip'.codeUnits,
        ]),
        DocumentKind.epub,
      );
    });

    test('uses signature over misleading extension when available', () async {
      final tempDir = Directory.systemTemp.createTempSync('doc_kind_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final file = File('${tempDir.path}/book.epub')
        ..writeAsStringSync('%PDF-1.7 corrupt but identifiable');

      expect(
        await DocumentClassifier.classifyPath(file.path),
        DocumentKind.pdf,
      );
    });

    test('keeps extension classification for missing files', () async {
      expect(
        await DocumentClassifier.classifyPath('/missing/book.epub'),
        DocumentKind.epub,
      );
    });
  });
}
