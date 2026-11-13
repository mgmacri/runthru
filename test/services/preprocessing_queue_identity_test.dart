import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/providers/document_title_provider.dart';
import 'package:runthru/services/content_identity.dart';
import 'package:runthru/services/content_store/content_store.dart';
import 'package:runthru/services/device_capability.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/library_source.dart';

LibrarySource sourceFor(String path, {required bool owns}) => LibrarySource(
  id: path,
  kind: LibrarySourceKind.folder,
  locator: path,
  displayName: path,
  addedAt: DateTime(2026),
  ownsFiles: owns,
);

/// Phase 2 of the scale overhaul (BK-4/BK-12): identity-correct, O(1) dedup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ContentIdentityService identity;

  setUp(() {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    tempDir = Directory.systemTemp.createTempSync('runthru_queue_identity');
    identity = ContentIdentityService(rootResolver: () async => tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        deviceCapabilityProvider.overrideWithValue(
          const DeviceCapability(
            processorCount: 4,
            maxWorkers: 2,
            isMobile: false,
          ),
        ),
        configProvider.overrideWith(
          () => throw UnimplementedError('config not needed'),
        ),
        pdfListProvider.overrideWith((ref) async => const <PdfEntry>[]),
        contentIdentityProvider.overrideWithValue(identity),
        contentStoreProvider.overrideWithValue(
          ContentStore(rootResolver: () async => '${tempDir.path}/store'),
        ),
      ],
    );
  }

  group('a library row\'s word count', () {
    test('is there once the book\'s text has been stored', () async {
      // The row asks for the count when the queue marks the book ready.
      // The text is written to the store, by content hash, only after
      // that, and nothing told the row to ask again: a book extracted
      // while the app was open showed no word count or reading time until
      // the next launch.
      final container = createContainer();
      addTearDown(container.dispose);
      final queue = container.read(preprocessingQueueProvider.notifier);
      queue.pauseBackground();
      final file = File('${tempDir.path}/book.pdf')
        ..writeAsStringSync('the bytes of a book');
      queue.debugSetEntry(
        PdfEntry(
          filePath: file.path,
          fileName: 'book.pdf',
          status: PdfStatus.ready,
        ),
      );
      final count = documentWordCountProvider(file.path);
      final sub = container.listen(count, (_, __) {});
      addTearDown(sub.close);
      expect(await container.read(count.future), isNull);

      await queue.debugIngest(
        file.path,
        const ExtractedDocument(
          sentences: [
            Sentence(words: ['one', 'two', 'three']),
            Sentence(words: ['four', 'five']),
          ],
        ),
      );
      await pumpEventQueue();

      expect(await container.read(count.future), 5);
    });
  });

  group('queue identity', () {
    test('two different books both named book.pdf coexist', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final queue = container.read(preprocessingQueueProvider.notifier);
      queue.pauseBackground();

      final dirA = Directory('${tempDir.path}/x')..createSync();
      final dirB = Directory('${tempDir.path}/y')..createSync();
      final a = File('${dirA.path}/book.pdf')..writeAsStringSync('book one');
      final b = File('${dirB.path}/book.pdf')..writeAsStringSync('book two');
      await identity.ensureHash(a.path);
      await identity.ensureHash(b.path);

      queue.enqueueEntry(PdfEntry(filePath: a.path, fileName: 'book.pdf'));
      queue.enqueueEntry(PdfEntry(filePath: b.path, fileName: 'book.pdf'));
      await pumpEventQueue();

      final state = container.read(preprocessingQueueProvider);
      expect(
        state.length,
        2,
        reason: 'distinct content must never collapse on filename',
      );
    });

    test('same content under two paths collapses to one entry', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final queue = container.read(preprocessingQueueProvider.notifier);
      queue.pauseBackground();

      final a = File('${tempDir.path}/original.pdf')
        ..writeAsStringSync('exact same bytes');
      final b = File('${tempDir.path}/reimported copy.pdf')
        ..writeAsStringSync('exact same bytes');
      await identity.ensureHash(a.path);
      await identity.ensureHash(b.path);

      queue.enqueueEntry(PdfEntry(filePath: a.path, fileName: 'original.pdf'));
      await pumpEventQueue();
      queue.enqueueEntry(
        PdfEntry(filePath: b.path, fileName: 'reimported copy.pdf'),
      );
      await pumpEventQueue();

      final state = container.read(preprocessingQueueProvider);
      expect(state.length, 1, reason: 'identical content dedupes by hash');
      expect(state.containsKey(a.path), isTrue, reason: 'first one wins');
      expect(queue.contentHashOf(a.path), isNotNull);
    });

    test('exact path re-enqueue stays O(1)-deduped', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final queue = container.read(preprocessingQueueProvider.notifier);
      queue.pauseBackground();

      queue.enqueueEntry(
        const PdfEntry(filePath: '/dup.pdf', fileName: 'dup.pdf'),
      );
      queue.enqueueEntry(
        const PdfEntry(filePath: '/dup.pdf', fileName: 'dup.pdf'),
      );
      await pumpEventQueue();

      expect(container.read(preprocessingQueueProvider).length, 1);
    });
  });

  group('scanSources content dedupe', () {
    test('owned copy with same name but different content is kept', () async {
      final referenced = Directory('${tempDir.path}/ref')..createSync();
      final owned = Directory('${tempDir.path}/owned')..createSync();
      File('${referenced.path}/book.pdf').writeAsStringSync('ref content');
      File('${owned.path}/book.pdf').writeAsStringSync('different content');

      final entries = await FolderScannerService.scanSources([
        sourceFor(referenced.path, owns: false),
        sourceFor(owned.path, owns: true),
      ], identity: identity);

      expect(
        entries.length,
        2,
        reason: 'same name, different bytes → both books are real',
      );
    });

    test('owned copy with identical content is skipped', () async {
      final referenced = Directory('${tempDir.path}/ref2')..createSync();
      final owned = Directory('${tempDir.path}/owned2')..createSync();
      File('${referenced.path}/book.pdf').writeAsStringSync('same content');
      File('${owned.path}/book.pdf').writeAsStringSync('same content');

      final entries = await FolderScannerService.scanSources([
        sourceFor(referenced.path, owns: false),
        sourceFor(owned.path, owns: true),
      ], identity: identity);

      expect(entries.length, 1, reason: 'true duplicate content collapses');
    });
  });
}
