import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/reading/providers/reading_progress_provider.dart';
import 'package:runthru/store/bookmark_store.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 5 of the scale overhaul (BK-5/BK-14): bookmarks and progress out of
/// the config blob — incremental writes, content-hash identity, bounded.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer createContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('BookmarkStore', () {
    test('save writes one per-bookmark entry, not a blob', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final store = container.read(bookmarkStoreProvider.notifier);
      await container.read(bookmarkStoreProvider.future);

      await store.save('/a.pdf', const BookmarkData(wordIndex: 10));
      await store.save('/b.pdf', const BookmarkData(wordIndex: 20));
      await store.save('/a.pdf', const BookmarkData(wordIndex: 30));

      final prefs = await SharedPreferences.getInstance();
      // Incremental granularity: each bookmark has its own key; updating one
      // touches one entry. The legacy config blob is never written.
      expect(prefs.getString('runthru_bm_/a.pdf'), isNotNull);
      expect(prefs.getString('runthru_bm_/b.pdf'), isNotNull);
      expect(prefs.getString('runthru_config'), isNull);
      final a = BookmarkData.fromJson(
        jsonDecode(prefs.getString('runthru_bm_/a.pdf')!)
            as Map<String, Object?>,
      );
      expect(a.wordIndex, 30);
    });

    test('bookmark survives re-import: same content hash, new path', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final store = container.read(bookmarkStoreProvider.notifier);
      await container.read(bookmarkStoreProvider.future);

      // Book read under its original path, hash already resolved.
      await store.save(
        '/old/import/book.pdf',
        const BookmarkData(wordIndex: 512, contentHash: 'hash-of-book'),
      );

      // Re-import copies it to a fresh microsecond-stamped directory. The
      // path lookup misses, but the content hash matches. (The hash for the
      // new path resolves to the same value; we exercise resolve's hash
      // fallback by injecting the data directly.)
      final resolvedByHash = store.resolveByContentHash(
        'hash-of-book',
        adoptPath: '/new/import/book.pdf',
      );
      expect(resolvedByHash, isNotNull);
      expect(resolvedByHash!.wordIndex, 512);

      // After adoption, the new path resolves directly.
      await null;
      expect(store.resolve('/new/import/book.pdf')?.wordIndex, 512);
    });

    test('legacy config bookmarks migrate once, originals retained', () async {
      final legacyConfig = {
        'bookmarks': {
          '/legacy.pdf': {'wordIndex': 99},
        },
      };
      SharedPreferences.setMockInitialValues({
        'runthru_config': jsonEncode(legacyConfig),
      });
      final container = createContainer();
      await container.read(configProvider.future);
      await container.read(bookmarkStoreProvider.future);

      final store = container.read(bookmarkStoreProvider.notifier);
      expect(store.resolve('/legacy.pdf')?.wordIndex, 99);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('runthru_bookmarks_migrated_v1'), isTrue);
      // Rollback path: the original blob is untouched.
      expect(prefs.getString('runthru_config'), jsonEncode(legacyConfig));
    });

    test(
      'prune removes orphaned local entries, keeps remote + active',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = createContainer();
        final store = container.read(bookmarkStoreProvider.notifier);
        await container.read(bookmarkStoreProvider.future);

        await store.save('/active.pdf', const BookmarkData(wordIndex: 1));
        await store.save('/gone.pdf', const BookmarkData(wordIndex: 2));
        await store.save(
          '/moved.pdf',
          const BookmarkData(wordIndex: 3, contentHash: 'still-here'),
        );
        await store.save('instapaper://123', const BookmarkData(wordIndex: 4));

        final pruned = await store.pruneMissingLocal(
          activePaths: {'/active.pdf'},
          activeHashes: {'still-here'},
        );

        expect(pruned, 1);
        expect(store.resolve('/active.pdf'), isNotNull);
        expect(store.resolve('/gone.pdf'), isNull);
        expect(store.resolve('/moved.pdf'), isNotNull, reason: 'hash active');
        expect(store.resolve('instapaper://123'), isNotNull, reason: 'remote');
      },
    );
  });

  group('ReadingProgress hardening', () {
    test('records are capped at maxRecords (oldest evicted)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final progress = container.read(readingProgressProvider.notifier);
      await container.read(readingProgressProvider.future);

      for (var i = 0; i < ReadingProgress.maxRecords + 25; i++) {
        await progress.record(
          contentId: '/book$i.pdf',
          source: 'local',
          title: 'Book $i',
          wordIndex: 1,
          totalWords: 100,
          lastReadAt: DateTime(2026).add(Duration(minutes: i)),
        );
      }

      final records = container.read(readingProgressProvider).valueOrNull!;
      expect(records.length, ReadingProgress.maxRecords);
      // The oldest records fell off; the newest survive.
      expect(progress.getRecord('/book0.pdf'), isNull);
      expect(
        progress.getRecord('/book${ReadingProgress.maxRecords + 24}.pdf'),
        isNotNull,
      );
    });

    test('re-import collapses records by content hash', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final progress = container.read(readingProgressProvider.notifier);
      await container.read(readingProgressProvider.future);

      await progress.record(
        contentId: '/old/book.pdf',
        source: 'local',
        title: 'Book',
        wordIndex: 100,
        totalWords: 1000,
        contentHash: 'same-book',
      );
      await progress.record(
        contentId: '/new/book.pdf',
        source: 'local',
        title: 'Book',
        wordIndex: 150,
        totalWords: 1000,
        contentHash: 'same-book',
      );

      final records = container.read(readingProgressProvider).valueOrNull!;
      expect(records.where((r) => r.contentHash == 'same-book').length, 1);
      expect(progress.getRecord('/new/book.pdf')?.wordIndex, 150);
      expect(progress.getRecord('/old/book.pdf'), isNull);
    });

    test('prune removes orphaned local records after source removal', () async {
      SharedPreferences.setMockInitialValues({});
      final container = createContainer();
      final progress = container.read(readingProgressProvider.notifier);
      await container.read(readingProgressProvider.future);

      await progress.record(
        contentId: '/kept.pdf',
        source: 'local',
        title: 'Kept',
        wordIndex: 1,
        totalWords: 10,
      );
      await progress.record(
        contentId: '/orphan.pdf',
        source: 'local',
        title: 'Orphan',
        wordIndex: 2,
        totalWords: 10,
      );
      await progress.record(
        contentId: 'instapaper://9',
        source: 'instapaper',
        title: 'Article',
        wordIndex: 3,
        totalWords: 10,
      );

      final pruned = await progress.pruneMissingLocal(
        activePaths: {'/kept.pdf'},
        activeHashes: const {},
      );

      expect(pruned, 1);
      expect(progress.getRecord('/kept.pdf'), isNotNull);
      expect(progress.getRecord('/orphan.pdf'), isNull);
      expect(progress.getRecord('instapaper://9'), isNotNull);
    });
  });
}
