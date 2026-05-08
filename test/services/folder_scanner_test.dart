import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/folder_scanner.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('folder_scanner_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('FolderScannerService', () {
    test('returns empty list for null path', () async {
      final results = await FolderScannerService.scanAsync(null);
      expect(results, isEmpty);
    });

    test('returns empty list for nonexistent directory', () async {
      final results = await FolderScannerService.scanAsync(
        '${tempDir.path}/does_not_exist',
      );
      expect(results, isEmpty);
    });

    test('finds .pdf files recursively (non-iOS)', () async {
      // Create nested structure with PDFs.
      File('${tempDir.path}/root.pdf').createSync();
      Directory('${tempDir.path}/sub').createSync();
      File('${tempDir.path}/sub/nested.pdf').createSync();

      final results = await FolderScannerService.scanAsync(tempDir.path);

      expect(results.length, 2);
      final names = results.map((e) => e.fileName).toSet();
      expect(names, containsAll(['root.pdf', 'nested.pdf']));
    });

    test('ignores non-pdf files', () async {
      File('${tempDir.path}/book.pdf').createSync();
      File('${tempDir.path}/notes.txt').createSync();
      File('${tempDir.path}/image.png').createSync();
      File('${tempDir.path}/doc.epub').createSync();

      final results = await FolderScannerService.scanAsync(tempDir.path);

      final names = results.map((e) => e.fileName).toList();
      expect(names, containsAll(['book.pdf', 'doc.epub']));
      expect(names, isNot(contains('notes.txt')));
      expect(names, isNot(contains('image.png')));
    });

    test('results are sorted alphabetically by fileName', () async {
      File('${tempDir.path}/zebra.pdf').createSync();
      File('${tempDir.path}/alpha.pdf').createSync();
      File('${tempDir.path}/middle.pdf').createSync();

      final results = await FolderScannerService.scanAsync(tempDir.path);

      final names = results.map((e) => e.fileName).toList();
      expect(names, ['alpha.pdf', 'middle.pdf', 'zebra.pdf']);
    });
  });
}
