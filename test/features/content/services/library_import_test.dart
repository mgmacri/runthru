import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/services/library_import.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/store/library_source.dart';
import 'package:runthru/store/library_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A picker that cannot open, as when the system refuses it.
class _FailingPicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => throw PlatformException(
    code: 'read_external_storage_denied',
    message: 'User did not allow reading external storage',
  );
}

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

  group('files handed over by the picker', () {
    late Directory temp;
    late Directory elsewhere;
    late Directory library;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('picker_temp_');
      elsewhere = Directory.systemTemp.createTempSync('reader_files_');
      library = Directory.systemTemp.createTempSync('library_dest_');
    });

    tearDown(() {
      for (final dir in [temp, elsewhere, library]) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    PlatformFile picked(Directory dir, String name) {
      final file = File('${dir.path}/$name')..writeAsStringSync('book');
      return PlatformFile(name: name, path: file.path, size: 4);
    }

    test(
      'are copied into the library, and the picker\'s copies removed',
      () async {
        // On a phone the picker gives the app copies in its temporary folder.
        // They were left there: every imported book was stored twice.
        final novel = picked(temp, 'novel.epub');
        final paper = picked(temp, 'paper.pdf');
        final notes = picked(temp, 'notes.txt');

        final copied = await LibraryImport.copyPickedFiles(
          [novel, paper, notes],
          library,
          temp: temp,
        );

        expect(copied, 2);
        expect(File('${library.path}/novel.epub').existsSync(), isTrue);
        expect(File('${library.path}/paper.pdf').existsSync(), isTrue);
        expect(File('${library.path}/notes.txt').existsSync(), isFalse);
        // Nothing of the picker's is left behind, used or not.
        expect(temp.listSync(), isEmpty);
      },
    );

    test('the reader\'s own files are never removed', () async {
      // Where the picker hands over the real file (not a copy in the
      // temporary folder), it stays where the reader keeps it.
      final own = picked(elsewhere, 'mine.pdf');

      final copied = await LibraryImport.copyPickedFiles(
        [own],
        library,
        temp: temp,
      );

      expect(copied, 1);
      expect(File(own.path!).existsSync(), isTrue);
      expect(File('${library.path}/mine.pdf').existsSync(), isTrue);
    });
  });

  group('when the picker fails', () {
    testWidgets('the reader is told in a sentence, not in the error\'s words', (
      tester,
    ) async {
      // No picker is registered under test, so there is none to put back.
      FilePicker.platform = _FailingPicker();
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      late BuildContext context;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      await LibraryImport.pickFiles(
        context,
        container.read(librarySourcesProvider.notifier),
      );
      await tester.pump();

      expect(
        find.text('RunThru could not add those files. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('external storage'), findsNothing);
      // Let the snack bar run its course.
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  test('the confirmation counts books in plain words', () {
    expect(LibraryImport.booksAddedMessage(1), '1 book added');
    expect(LibraryImport.booksAddedMessage(7), '7 books added');
    expect(LibraryImport.booksAddedMessage(1), isNot(contains('(s)')));
  });
}
