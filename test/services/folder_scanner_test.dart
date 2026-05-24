import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/store/library_source.dart';

LibrarySource _src(LibrarySourceKind kind, String locator) => LibrarySource(
  id: locator,
  kind: kind,
  locator: locator,
  displayName: locator,
  addedAt: DateTime(2026),
);

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

    test('finds EPUBs with long names and spaces', () async {
      File(
        '${tempDir.path}/The Coming Wave By Mustafa SuleymanMichael Bhaskar-pdfread.net.epub',
      ).createSync();

      final results = await FolderScannerService.scanAsync(tempDir.path);

      expect(
        results.map((e) => e.fileName),
        contains(
          'The Coming Wave By Mustafa SuleymanMichael Bhaskar-pdfread.net.epub',
        ),
      );
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

  group('FolderScannerService.scanSources', () {
    test('merges multiple folder sources and a file source', () async {
      Directory('${tempDir.path}/a').createSync();
      Directory('${tempDir.path}/b').createSync();
      File('${tempDir.path}/a/one.pdf').createSync();
      File('${tempDir.path}/b/two.epub').createSync();
      File('${tempDir.path}/loose.pdf').createSync();

      final results = await FolderScannerService.scanSources([
        _src(LibrarySourceKind.folder, '${tempDir.path}/a'),
        _src(LibrarySourceKind.folder, '${tempDir.path}/b'),
        _src(LibrarySourceKind.file, '${tempDir.path}/loose.pdf'),
      ]);

      final names = results.map((e) => e.fileName).toSet();
      expect(names, containsAll(['one.pdf', 'two.epub', 'loose.pdf']));
    });

    test('deduplicates a file already covered by a folder source', () async {
      File('${tempDir.path}/dup.pdf').createSync();

      final results = await FolderScannerService.scanSources([
        _src(LibrarySourceKind.folder, tempDir.path),
        _src(LibrarySourceKind.file, '${tempDir.path}/dup.pdf'),
      ]);

      expect(results.where((e) => e.fileName == 'dup.pdf').length, 1);
    });

    test(
      'deduplicates repeated app-managed folder copies by book name',
      () async {
        final firstCopy = Directory('${tempDir.path}/copy-a')..createSync();
        final secondCopy = Directory('${tempDir.path}/copy-b')..createSync();
        File('${firstCopy.path}/book.pdf').writeAsStringSync('first');
        File('${secondCopy.path}/book.pdf').writeAsStringSync('second');

        final results = await FolderScannerService.scanSources([
          _src(
            LibrarySourceKind.folder,
            firstCopy.path,
          ).copyWith(ownsFiles: true),
          _src(
            LibrarySourceKind.folder,
            secondCopy.path,
          ).copyWith(ownsFiles: true),
        ]);

        expect(results.where((e) => e.fileName == 'book.pdf'), hasLength(1));
      },
    );

    test(
      'deduplicates same book from referenced and imported folders',
      () async {
        final referenced = Directory('${tempDir.path}/pdfs')..createSync();
        final imported = Directory('${tempDir.path}/owned')..createSync();
        File('${referenced.path}/book.epub').writeAsStringSync('original');
        File('${imported.path}/book.epub').writeAsStringSync('copy');

        final results = await FolderScannerService.scanSources([
          _src(LibrarySourceKind.folder, referenced.path),
          _src(LibrarySourceKind.folder, imported.path).copyWith(
            ownsFiles: true,
            sourceKey: 'android-tree:content://tree/book',
          ),
        ]);

        expect(results.where((e) => e.fileName == 'book.epub'), hasLength(1));
        expect(results.single.filePath, '${referenced.path}/book.epub');
      },
    );

    test('skips missing or non-book file sources', () async {
      final results = await FolderScannerService.scanSources([
        _src(LibrarySourceKind.file, '${tempDir.path}/missing.pdf'),
        _src(LibrarySourceKind.file, '${tempDir.path}/notes.txt'),
      ]);
      expect(results, isEmpty);
    });
  });
}
