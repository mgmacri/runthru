import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/book_identity.dart';
import 'package:runthru/services/content_identity.dart';
import 'package:runthru/services/content_store/content_store.dart';
import 'package:runthru/services/content_store/content_store_migration.dart';
import 'package:runthru/services/content_store/section_models.dart';
import 'package:runthru/services/models.dart';

/// Phase 3 of the scale overhaul: Ring 2 content store — sectioned, lazy,
/// content-hash keyed, evictable.
void main() {
  late Directory tempDir;
  late ContentStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('runthru_store_test');
    store = ContentStore(
      rootResolver: () async => '${tempDir.path}/content_store',
      memorySectionCap: 2,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  const identity = BookIdentity(
    contentHash: 'abc123def456',
    sourceId: 'local',
    displayName: 'Test Book',
  );

  /// A document large enough to span multiple sections (~5x target words).
  ExtractedDocument bigDoc() {
    final sentences = <Sentence>[
      for (var i = 0; i < kSectionTargetWords; i++)
        Sentence(words: ['sentence$i', 'word', 'alpha', 'beta', 'gamma']),
    ];
    return ExtractedDocument(
      sentences: sentences,
      pageBoundaries: const [
        PageBoundary(pageNumber: 0, startSentenceIndex: 0, startWordIndex: 0),
        PageBoundary(
          pageNumber: 1,
          startSentenceIndex: 800,
          startWordIndex: 4000,
        ),
      ],
      totalPages: 2,
    );
  }

  group('ingestion and lazy reads', () {
    test('putDocument → metadata, section count, no text loaded', () async {
      final doc = bigDoc();
      await store.putDocument(identity, doc);

      final meta = await store.getMetadata(identity.contentHash);
      expect(meta, isNotNull);
      expect(meta!.totalWords, doc.totalWords);
      expect(meta.totalSentences, doc.sentences.length);
      expect(meta.totalPages, 2);
      expect(meta.pageBoundaries, hasLength(2));
      expect(meta.totalSections, greaterThan(1));
      expect(
        await store.getSectionCount(identity.contentHash),
        meta.totalSections,
      );
    });

    test('getSection returns bounded sentence-aligned windows', () async {
      final doc = bigDoc();
      await store.putDocument(identity, doc);
      final count = await store.getSectionCount(identity.contentHash);

      var wordsSeen = 0;
      for (var i = 0; i < count; i++) {
        final section = await store.getSection(identity.contentHash, i);
        expect(section, isNotNull);
        expect(section!.meta.sectionIndex, i);
        expect(section.meta.startWordIndex, wordsSeen);
        expect(
          section.words.length,
          lessThanOrEqualTo(kSectionTargetWords + 10),
        );
        wordsSeen += section.words.length;
      }
      expect(wordsSeen, doc.totalWords);
    });

    test('getDocument reassembles the exact original text', () async {
      final doc = bigDoc();
      await store.putDocument(identity, doc);

      final loaded = await store.getDocument(identity.contentHash);
      expect(loaded, isNotNull);
      expect(loaded!.totalWords, doc.totalWords);
      expect(loaded.allWords, doc.allWords);
      expect(loaded.totalPages, doc.totalPages);
      expect(loaded.pageBoundaries, hasLength(2));
    });

    test('rawText and words on Section are model-input ready', () async {
      await store.putDocument(identity, bigDoc());
      final section = await store.getSection(identity.contentHash, 0);
      expect(section!.rawText, startsWith('sentence0 word alpha'));
      expect(section.meta.modelAnnotations, isEmpty);
      expect(section.meta.startPage, 0);
    });

    test('unknown book → null metadata, null section, zero count', () async {
      expect(await store.getMetadata('nope'), isNull);
      expect(await store.getSection('nope', 0), isNull);
      expect(await store.getSectionCount('nope'), 0);
      expect(await store.hasBook('nope'), isFalse);
    });

    test('provisional identities are refused', () async {
      final prov = BookIdentity(
        contentHash: BookIdentity.provisionalHash('drive:x', '/tmp/dl'),
        sourceId: 'drive:x',
        displayName: 'incomplete',
      );
      await store.putDocument(prov, bigDoc());
      expect(await store.hasBook(prov.contentHash), isFalse);
    });
  });

  group('migration safety', () {
    test('re-ingesting the same book is idempotent', () async {
      final doc = bigDoc();
      await store.putDocument(identity, doc);
      final firstMeta = await store.getMetadata(identity.contentHash);

      await store.putDocument(identity, doc); // second pass — no-op
      final secondMeta = await store.getMetadata(identity.contentHash);

      expect(secondMeta!.totalSections, firstMeta!.totalSections);
      expect(secondMeta.totalWords, firstMeta.totalWords);
      final loaded = await store.getDocument(identity.contentHash);
      expect(loaded!.allWords, doc.allWords);
    });

    test(
      'crash mid-ingest (no manifest) → book absent, re-run heals',
      () async {
        final doc = bigDoc();
        await store.putDocument(identity, doc);

        // Simulate a crash that lost the manifest after sections were written.
        File(
          '${tempDir.path}/content_store/${identity.contentHash}/manifest.json',
        ).deleteSync();

        expect(await store.hasBook(identity.contentHash), isFalse);
        expect(await store.getDocument(identity.contentHash), isNull);

        // Re-running the (idempotent) ingestion restores the book fully.
        await store.putDocument(identity, doc);
        final loaded = await store.getDocument(identity.contentHash);
        expect(loaded!.allWords, doc.allWords);
      },
    );

    test('dry run reports books pending migration without migrating', () async {
      final contentDir = Directory('${tempDir.path}/files')..createSync();
      final file = File('${contentDir.path}/legacy.pdf')
        ..writeAsStringSync('legacy book bytes');
      final identitySvc = ContentIdentityService(
        rootResolver: () async => tempDir.path,
      );
      final hash = await identitySvc.ensureHash(file.path);

      var pending = await ContentStoreMigration.dryRunReport(
        filePaths: [file.path],
        store: store,
        identity: identitySvc,
      );
      expect(pending, [file.path]);
      expect(await store.hasBook(hash!), isFalse, reason: 'dry run only');

      await store.putDocument(
        BookIdentity(contentHash: hash, sourceId: 'local', displayName: 'l'),
        bigDoc(),
      );
      pending = await ContentStoreMigration.dryRunReport(
        filePaths: [file.path],
        store: store,
        identity: identitySvc,
      );
      expect(pending, isEmpty);
    });
  });

  group('eviction', () {
    test(
      'budget pressure evicts LRU book sections but keeps manifests',
      () async {
        const old = BookIdentity(
          contentHash: 'older0000',
          sourceId: 'local',
          displayName: 'Old Book',
        );
        await store.putDocument(old, bigDoc());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await store.putDocument(identity, bigDoc());
        await store.touchLastRead(identity.contentHash);

        // Budget that fits roughly one book.
        final oneBook = await store.totalUsageBytes() ~/ 2;
        await store.enforceBudget(oneBook + 1024);

        // Old book: sections gone, metadata still served.
        expect(await store.getMetadata(old.contentHash), isNotNull);
        expect(await store.getSection(old.contentHash, 0), isNull);

        // Recently read book intact.
        expect(await store.getSection(identity.contentHash, 0), isNotNull);
      },
    );

    test('no eviction under budget', () async {
      await store.putDocument(identity, bigDoc());
      await store.enforceBudget(1 << 30);
      expect(await store.getSection(identity.contentHash, 0), isNotNull);
    });
  });
}
