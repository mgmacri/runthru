import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/store/library_source.dart';
import 'package:runthru/store/library_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  ProviderContainer makeContainerWithDelete(LibrarySourceDelete delete) {
    final container = ProviderContainer(
      overrides: [
        librarySourcesProvider.overrideWith(
          () => LibrarySourcesNotifier(deleteOwnedSource: delete),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('LibrarySourcesNotifier', () {
    test('starts empty with no prefs', () async {
      final container = makeContainer();
      final sources = await container.read(librarySourcesProvider.future);
      expect(sources, isEmpty);
    });

    test('migrates legacy pdfFolderPath into one referenced folder', () async {
      SharedPreferences.setMockInitialValues({
        'runthru_config': jsonEncode({'pdfFolderPath': '/books'}),
      });
      final container = makeContainer();

      final sources = await container.read(librarySourcesProvider.future);

      expect(sources, hasLength(1));
      expect(sources.first.kind, LibrarySourceKind.folder);
      expect(sources.first.locator, '/books');
      expect(sources.first.ownsFiles, isFalse);
    });

    test('adds folders/files and dedupes by locator', () async {
      final container = makeContainer();
      await container.read(librarySourcesProvider.future);
      final notifier = container.read(librarySourcesProvider.notifier);

      await notifier.addFolder('/a');
      await notifier.addFolder('/a/'); // canonical duplicate
      await notifier.addFile('/b.pdf');

      final list = container.read(librarySourcesProvider).requireValue;
      expect(list, hasLength(2));
    });

    test('dedupes copied folder sources by source key', () async {
      final container = makeContainer();
      await container.read(librarySourcesProvider.future);
      final notifier = container.read(librarySourcesProvider.notifier);

      await notifier.addFolder(
        '/app/library/1',
        ownsFiles: true,
        displayName: 'Book',
        sourceKey: 'android-tree:content://tree/book',
      );
      await notifier.addFolder(
        '/app/library/2',
        ownsFiles: true,
        displayName: 'Book',
        sourceKey: 'android-tree:content://tree/book/',
      );

      final list = container.read(librarySourcesProvider).requireValue;
      expect(list, hasLength(1));
      expect(list.single.locator, '/app/library/1');
    });

    test(
      'derives friendly Android tree URI fallback when display name is empty',
      () async {
        final container = makeContainer();
        await container.read(librarySourcesProvider.future);
        final notifier = container.read(librarySourcesProvider.notifier);

        await notifier.addFolder(
          '/app/library/1',
          ownsFiles: true,
          displayName: '',
          sourceKey:
              'android-tree:content://com.android.externalstorage.documents/tree/primary%3ABook',
        );

        final list = container.read(librarySourcesProvider).requireValue;
        expect(list.single.displayName, 'Book');
      },
    );

    test('preserves Android SAF display name across reload', () async {
      final container = makeContainer();
      await container.read(librarySourcesProvider.future);
      await container
          .read(librarySourcesProvider.notifier)
          .addFolder(
            '/app/library/1',
            ownsFiles: true,
            displayName: 'Book',
            sourceKey:
                'android-tree:content://com.android.externalstorage.documents/tree/primary%3ABook',
          );

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final reloaded = await container2.read(librarySourcesProvider.future);

      expect(reloaded.single.displayName, 'Book');
      expect(reloaded.single.sourceKey, contains('primary%3ABook'));
    });

    test('removing an owned source deletes its directory', () async {
      final dir = Directory.systemTemp.createTempSync('lib_owned_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      File('${dir.path}/x.pdf').writeAsStringSync('x');

      final container = makeContainer();
      await container.read(librarySourcesProvider.future);
      final notifier = container.read(librarySourcesProvider.notifier);

      await notifier.addFolder(dir.path, ownsFiles: true);
      final id = container.read(librarySourcesProvider).requireValue.first.id;
      await notifier.remove(id);

      expect(container.read(librarySourcesProvider).requireValue, isEmpty);
      expect(dir.existsSync(), isFalse);
    });

    test(
      'removing an owned source succeeds when directory is missing',
      () async {
        final dir = Directory.systemTemp.createTempSync('lib_missing_');
        dir.deleteSync();

        final container = makeContainer();
        await container.read(librarySourcesProvider.future);
        final notifier = container.read(librarySourcesProvider.notifier);

        await notifier.addFolder(dir.path, ownsFiles: true);
        final id = container.read(librarySourcesProvider).requireValue.first.id;
        await notifier.remove(id);

        expect(container.read(librarySourcesProvider).requireValue, isEmpty);
      },
    );

    test('delete failure keeps owned source in state and prefs', () async {
      final container = makeContainerWithDelete((source) async {
        throw const FileSystemException('denied');
      });
      await container.read(librarySourcesProvider.future);
      final notifier = container.read(librarySourcesProvider.notifier);

      await notifier.addFolder('/owned', ownsFiles: true);
      final source = container.read(librarySourcesProvider).requireValue.first;

      await expectLater(
        notifier.remove(source.id),
        throwsA(isA<LibrarySourceRemovalException>()),
      );

      final current = container.read(librarySourcesProvider).requireValue;
      expect(current.single.id, source.id);

      final prefs = await SharedPreferences.getInstance();
      final persisted =
          jsonDecode(prefs.getString('runthru_library_sources')!)
              as List<Object?>;
      expect(persisted, hasLength(1));
      expect(
        (persisted.single! as Map<String, Object?>)['locator'],
        source.locator,
      );
    });

    test('delete failure throws LibrarySourceRemovalException', () async {
      final container = makeContainerWithDelete((source) async {
        throw LibrarySourceRemovalException(
          source.locator,
          const FileSystemException('denied'),
        );
      });
      await container.read(librarySourcesProvider.future);
      final notifier = container.read(librarySourcesProvider.notifier);

      await notifier.addFolder('/owned', ownsFiles: true);
      final id = container.read(librarySourcesProvider).requireValue.first.id;

      await expectLater(
        notifier.remove(id),
        throwsA(isA<LibrarySourceRemovalException>()),
      );
    });

    test('removing a referenced source leaves real files untouched', () async {
      final dir = Directory.systemTemp.createTempSync('lib_ref_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final container = makeContainer();
      await container.read(librarySourcesProvider.future);
      final notifier = container.read(librarySourcesProvider.notifier);

      await notifier.addFolder(dir.path); // ownsFiles defaults false
      final id = container.read(librarySourcesProvider).requireValue.first.id;
      await notifier.remove(id);

      expect(container.read(librarySourcesProvider).requireValue, isEmpty);
      expect(dir.existsSync(), isTrue);
    });

    test('added sources persist across notifier rebuilds', () async {
      final container = makeContainer();
      await container.read(librarySourcesProvider.future);
      await container.read(librarySourcesProvider.notifier).addFolder('/keep');

      // A fresh container reads from the same mock SharedPreferences store.
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final reloaded = await container2.read(librarySourcesProvider.future);
      expect(reloaded.map((s) => s.locator), contains('/keep'));
    });
  });
}
