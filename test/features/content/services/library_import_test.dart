import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/services/library_import.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/store/library_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryImport', () {
    test(
      'supported book detection accepts PDF and EPUB case-insensitively',
      () {
        expect(LibraryImport.isSupportedBookPath('/books/a.pdf'), isTrue);
        expect(LibraryImport.isSupportedBookPath('/books/a.PDF'), isTrue);
        expect(LibraryImport.isSupportedBookPath('/books/a.epub'), isTrue);
        expect(LibraryImport.isSupportedBookPath('/books/a.EPUB'), isTrue);
        expect(LibraryImport.isSupportedBookPath('/books/a.txt'), isFalse);
        expect(
          LibraryImport.isSupportedBookPath('/books/pdf_notes.txt'),
          isFalse,
        );
      },
    );

    test('collision-safe naming increments without overwriting', () {
      final dir = Directory.systemTemp.createTempSync('library_import_names_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      expect(
        LibraryImport.uniqueDestinationFile(dir, 'book.pdf').path,
        '${dir.path}/book.pdf',
      );

      File('${dir.path}/book.pdf').writeAsStringSync('first');
      expect(
        LibraryImport.uniqueDestinationFile(dir, 'book.pdf').path,
        '${dir.path}/book (2).pdf',
      );

      File('${dir.path}/book (2).pdf').writeAsStringSync('second');
      expect(
        LibraryImport.uniqueDestinationFile(dir, 'book.pdf').path,
        '${dir.path}/book (3).pdf',
      );
    });

    test(
      'duplicate mobile-selected basenames stay discoverable after copy',
      () async {
        final temp = Directory.systemTemp.createTempSync(
          'library_import_copy_',
        );
        addTearDown(() {
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });

        final sourceA = Directory('${temp.path}/a')..createSync();
        final sourceB = Directory('${temp.path}/b')..createSync();
        final dest = Directory('${temp.path}/owned')..createSync();
        final first = File('${sourceA.path}/book.pdf')
          ..writeAsStringSync('one');
        final second = File('${sourceB.path}/book.pdf')
          ..writeAsStringSync('two');

        first.copySync(
          LibraryImport.uniqueDestinationFile(dest, 'book.pdf').path,
        );
        second.copySync(
          LibraryImport.uniqueDestinationFile(dest, 'book.pdf').path,
        );

        final entries = await FolderScannerService.scanSources([
          LibrarySource(
            id: 'owned',
            kind: LibrarySourceKind.folder,
            locator: dest.path,
            displayName: 'Imported files',
            ownsFiles: true,
            addedAt: DateTime(2026),
          ),
        ]);

        expect(entries.map((entry) => entry.fileName), [
          'book (2).pdf',
          'book.pdf',
        ]);
      },
    );
  });
}
