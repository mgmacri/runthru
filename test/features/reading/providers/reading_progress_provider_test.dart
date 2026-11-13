import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/reading/providers/reading_progress_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer makeContainer() {
    return ProviderContainer();
  }

  group('ReadingProgress.record', () {
    test('stores Drive progress under drive:// file identity', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      await notifier.record(
        contentId: 'drive://file-123',
        source: 'drive',
        title: 'Drive Doc',
        wordIndex: 42,
        totalWords: 300,
      );

      final record = notifier.getRecord('drive://file-123');
      expect(record, isNotNull);
      expect(record!.contentId, 'drive://file-123');
      expect(record.source, 'drive');
      expect(record.wordIndex, 42);
    });

    test('adds a new entry and makes it available via getRecord', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      await notifier.record(
        contentId: 'file:///test.pdf',
        source: 'local',
        title: 'Test Book',
        wordIndex: 50,
        totalWords: 200,
      );

      final record = notifier.getRecord('file:///test.pdf');
      expect(record, isNotNull);
      expect(record!.wordIndex, 50);
      expect(record.totalWords, 200);
      expect(record.source, 'local');
      expect(record.title, 'Test Book');
      expect(record.finished, isFalse);
    });

    test('updates an existing entry on second call', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      await notifier.record(
        contentId: 'file:///test.pdf',
        source: 'local',
        title: 'Test Book',
        wordIndex: 50,
        totalWords: 200,
      );
      await notifier.record(
        contentId: 'file:///test.pdf',
        source: 'local',
        title: 'Test Book',
        wordIndex: 120,
        totalWords: 200,
      );

      final record = notifier.getRecord('file:///test.pdf');
      expect(record!.wordIndex, 120);
      // Only one record for the same contentId.
      final all = container.read(readingProgressProvider).valueOrNull ?? [];
      expect(all.where((r) => r.contentId == 'file:///test.pdf').length, 1);
    });

    test('clamps wordIndex to totalWords on re-normalisation', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      await notifier.record(
        contentId: 'file:///test.pdf',
        source: 'local',
        title: 'Test',
        wordIndex: 180,
        totalWords: 200,
      );
      // Simulate re-normalisation that shrinks totalWords.
      await notifier.record(
        contentId: 'file:///test.pdf',
        source: 'local',
        title: 'Test',
        wordIndex: 180,
        totalWords: 100, // shorter after re-parse
      );

      final record = notifier.getRecord('file:///test.pdf');
      expect(record!.wordIndex, 100); // clamped to new total
    });
  });

  group('ReadingProgress.markFinished', () {
    test('marks a Drive item finished without creating duplicates', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      await notifier.record(
        contentId: 'drive://same-file',
        source: 'drive',
        title: 'Original Title',
        wordIndex: 60,
        totalWords: 100,
      );
      await notifier.record(
        contentId: 'drive://same-file',
        source: 'drive',
        title: 'Renamed Title',
        wordIndex: 100,
        totalWords: 100,
      );

      await notifier.markFinished('drive://same-file');

      final all = container.read(readingProgressProvider).valueOrNull ?? [];
      final matching = all
          .where((record) => record.contentId == 'drive://same-file')
          .toList();
      expect(matching.length, 1);
      expect(matching.single.finished, isTrue);
      expect(notifier.shelf, isEmpty);
    });

    test('marks item finished so it leaves the shelf', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      await notifier.record(
        contentId: 'file:///test.pdf',
        source: 'local',
        title: 'Test',
        wordIndex: 190,
        totalWords: 200,
      );
      expect(notifier.shelf.length, 1);

      await notifier.markFinished('file:///test.pdf');
      expect(notifier.shelf, isEmpty);
    });
  });

  group('finished items', () {
    Future<ReadingProgress> open(ProviderContainer container) async {
      await container.read(readingProgressProvider.future);
      return container.read(readingProgressProvider.notifier);
    }

    Future<void> write(
      ReadingProgress notifier,
      int wordIndex, {
      bool finished = false,
    }) => notifier.record(
      contentId: 'file:///novel.epub',
      source: 'local',
      title: 'A Novel',
      wordIndex: wordIndex,
      totalWords: 1000,
      finished: finished,
    );

    test('a book read in one sitting is recorded as finished', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = await open(container);

      // No earlier record: nothing was saved before the last page.
      await write(notifier, 960, finished: true);

      final record = notifier.getRecord('file:///novel.epub');
      expect(record, isNotNull);
      expect(record!.finished, isTrue);
      expect(record.wordIndex, 960);
      expect(notifier.shelf, isEmpty);
    });

    test('reading on into the notes keeps it finished', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = await open(container);

      await write(notifier, 400);
      // The story ends at 960; the index runs to 1000.
      await write(notifier, 960, finished: true);
      await write(notifier, 985);

      expect(notifier.getRecord('file:///novel.epub')!.finished, isTrue);
      expect(notifier.getRecord('file:///novel.epub')!.wordIndex, 985);
      expect(notifier.shelf, isEmpty);

      // Reopened later and closed without reading: still finished.
      await write(notifier, 985);
      expect(notifier.getRecord('file:///novel.epub')!.finished, isTrue);
      expect(notifier.shelf, isEmpty);
    });

    test('going back into the text puts it in progress again', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = await open(container);

      await write(notifier, 960, finished: true);
      // Read it again, from chapter two.
      await write(notifier, 120);

      expect(notifier.getRecord('file:///novel.epub')!.finished, isFalse);
      expect(notifier.shelf.single.contentId, 'file:///novel.epub');
    });

    test('the finished mark survives a restart', () async {
      final container = makeContainer();
      final notifier = await open(container);
      await write(notifier, 960, finished: true);
      container.dispose();

      final reopened = makeContainer();
      addTearDown(reopened.dispose);
      final again = await open(reopened);
      expect(again.getRecord('file:///novel.epub')!.finished, isTrue);
      expect(again.shelf, isEmpty);
    });
  });

  group('a length recorded from a partly extracted book', () {
    test('is marked as such, and the mark survives a restart', () async {
      final container = ProviderContainer();
      container.listen(readingProgressProvider, (_, __) {});
      await container.read(readingProgressProvider.future);
      await container
          .read(readingProgressProvider.notifier)
          .record(
            contentId: '/books/long.pdf',
            source: 'local',
            title: 'Long',
            wordIndex: 20,
            totalWords: 40,
            partialText: true,
          );
      container.dispose();

      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      reopened.listen(readingProgressProvider, (_, __) {});
      await reopened.read(readingProgressProvider.future);
      final record = reopened
          .read(readingProgressProvider.notifier)
          .getRecord('/books/long.pdf')!;
      expect(record.partialText, isTrue);

      // The next write, from the whole text, clears it.
      await reopened
          .read(readingProgressProvider.notifier)
          .record(
            contentId: '/books/long.pdf',
            source: 'local',
            title: 'Long',
            wordIndex: 20,
            totalWords: 400,
          );
      expect(
        reopened
            .read(readingProgressProvider.notifier)
            .getRecord('/books/long.pdf')!
            .partialText,
        isFalse,
      );
    });

    test('records written before the mark existed read as whole', () {
      final record = ProgressRecord.fromJson(const {
        'contentId': 'x',
        'wordIndex': 5,
        'totalWords': 10,
      });
      expect(record.partialText, isFalse);
      expect(record.toJson().containsKey('partialText'), isFalse);
    });
  });

  group('ProgressRecord.displayPercent', () {
    ProgressRecord at(int wordIndex, {bool finished = false}) => ProgressRecord(
      contentId: 'x',
      source: 'local',
      title: 'X',
      wordIndex: wordIndex,
      totalWords: 100000,
      lastReadAt: DateTime(2026, 11, 10),
      finished: finished,
    );

    test('a started book never shows 0', () {
      expect(at(0).displayPercent, 0);
      expect(at(12).displayPercent, 1);
      expect(at(499).displayPercent, 1);
      expect(at(42000).displayPercent, 42);
    });

    test('an unfinished book never shows 100', () {
      expect(at(99990).displayPercent, 99);
      expect(at(100000).displayPercent, 99);
    });

    test('a finished book shows 100 wherever the story ended', () {
      expect(at(96000, finished: true).displayPercent, 100);
    });
  });

  group('ReadingProgress.shelf', () {
    test('includes in-progress Drive records', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      await notifier.record(
        contentId: 'drive://doc-on-shelf',
        source: 'drive',
        title: 'Shelf Doc',
        wordIndex: 12,
        totalWords: 120,
      );

      final shelf = notifier.shelf;
      expect(shelf, hasLength(1));
      expect(shelf.single.contentId, 'drive://doc-on-shelf');
      expect(shelf.single.source, 'drive');
    });

    test(
      'does not collapse Drive and local records with the same title',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);

        await container.read(readingProgressProvider.future);
        final notifier = container.read(readingProgressProvider.notifier);

        await notifier.record(
          contentId: '/books/report.pdf',
          source: 'local',
          title: 'Report',
          wordIndex: 10,
          totalWords: 100,
        );
        await notifier.record(
          contentId: 'drive://report-file',
          source: 'drive',
          title: 'Report',
          wordIndex: 20,
          totalWords: 100,
        );

        final shelf = notifier.shelf;
        expect(shelf, hasLength(2));
        expect(shelf.map((record) => record.contentId), {
          '/books/report.pdf',
          'drive://report-file',
        });
      },
    );

    test('reopening the same Drive file updates one shelf record', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      await notifier.record(
        contentId: 'drive://same-file',
        source: 'drive',
        title: 'Original Title',
        wordIndex: 10,
        totalWords: 100,
      );
      await notifier.record(
        contentId: 'drive://same-file',
        source: 'drive',
        title: 'Renamed Title',
        wordIndex: 44,
        totalWords: 100,
      );

      final shelf = notifier.shelf;
      expect(shelf, hasLength(1));
      expect(shelf.single.contentId, 'drive://same-file');
      expect(shelf.single.title, 'Renamed Title');
      expect(shelf.single.wordIndex, 44);
    });

    test('excludes items with wordIndex == 0', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      await notifier.record(
        contentId: 'file:///unstarted.pdf',
        source: 'local',
        title: 'Unstarted',
        wordIndex: 0,
        totalWords: 200,
      );

      expect(notifier.shelf, isEmpty);
    });

    test('orders by lastReadAt descending', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      final earlier = DateTime(2025, 1, 1, 10, 0, 0);
      final later = DateTime(2025, 1, 1, 10, 0, 1);

      await notifier.record(
        contentId: 'a.pdf',
        source: 'local',
        title: 'A',
        wordIndex: 10,
        totalWords: 100,
        lastReadAt: earlier,
      );
      await notifier.record(
        contentId: 'b.pdf',
        source: 'local',
        title: 'B',
        wordIndex: 20,
        totalWords: 100,
        lastReadAt: later,
      );

      final shelf = notifier.shelf;
      expect(shelf.first.contentId, 'b.pdf');
    });

    test('excludes finished items', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      await notifier.record(
        contentId: 'file:///done.pdf',
        source: 'local',
        title: 'Done',
        wordIndex: 199,
        totalWords: 200,
      );
      await notifier.markFinished('file:///done.pdf');

      expect(notifier.shelf, isEmpty);
    });

    test('caps shelf at 10 items', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(readingProgressProvider.future);
      final notifier = container.read(readingProgressProvider.notifier);

      for (var i = 0; i < 15; i++) {
        await notifier.record(
          contentId: 'file:///$i.pdf',
          source: 'local',
          title: 'Book $i',
          wordIndex: 10,
          totalWords: 100,
        );
      }

      expect(notifier.shelf.length, 10);
    });
  });

  group('ReadingProgress duplicate handling', () {
    test(
      'shelf collapses legacy duplicate records sharing a contentId',
      () async {
        // Simulate a store written by an older build that persisted the same
        // item twice (the bug behind duplicate Continue Reading entries).
        ProgressRecord dup(DateTime at, int wordIndex) => ProgressRecord(
          contentId: 'file:///dupe.pdf',
          source: 'local',
          title: 'Dupe',
          wordIndex: wordIndex,
          totalWords: 100,
          lastReadAt: at,
        );
        SharedPreferences.setMockInitialValues({
          'runthru_reading_progress': jsonEncode([
            dup(DateTime(2025, 1, 1), 10).toJson(),
            dup(DateTime(2025, 1, 2), 25).toJson(),
          ]),
        });

        final container = makeContainer();
        addTearDown(container.dispose);

        await container.read(readingProgressProvider.future);
        final notifier = container.read(readingProgressProvider.notifier);

        final shelf = notifier.shelf;
        expect(
          shelf.length,
          1,
          reason: 'duplicates must collapse to one entry',
        );
        // The most recently read instance wins.
        expect(shelf.first.wordIndex, 25);
      },
    );

    test(
      'record heals pre-existing duplicates and persists a single entry',
      () async {
        // Start from a store that already holds a duplicate, then record new
        // progress for that item. The collapse must survive the round-trip to
        // SharedPreferences, not just the in-memory view.
        ProgressRecord dup(int wordIndex) => ProgressRecord(
          contentId: 'file:///heal.pdf',
          source: 'local',
          title: 'Heal',
          wordIndex: wordIndex,
          totalWords: 100,
          lastReadAt: DateTime(2025, 1, 1),
        );
        SharedPreferences.setMockInitialValues({
          'runthru_reading_progress': jsonEncode([
            dup(10).toJson(),
            dup(15).toJson(),
          ]),
        });

        final container = makeContainer();
        addTearDown(container.dispose);

        await container.read(readingProgressProvider.future);
        final notifier = container.read(readingProgressProvider.notifier);

        await notifier.record(
          contentId: 'file:///heal.pdf',
          source: 'local',
          title: 'Heal',
          wordIndex: 30,
          totalWords: 100,
        );

        // In-memory view is clean.
        expect(
          notifier.shelf.where((r) => r.contentId == 'file:///heal.pdf').length,
          1,
        );

        // And the persisted JSON now holds exactly one record for that item.
        final prefs = await SharedPreferences.getInstance();
        final persisted =
            jsonDecode(prefs.getString('runthru_reading_progress')!) as List;
        final persistedForId = persisted
            .whereType<Map<String, Object?>>()
            .where((m) => m['contentId'] == 'file:///heal.pdf')
            .toList();
        expect(persistedForId.length, 1);
        expect(persistedForId.single['wordIndex'], 30);
      },
    );
  });

  group('ProgressRecord', () {
    test('percent is computed from wordIndex / totalWords', () {
      final record = ProgressRecord(
        contentId: 'x',
        source: 'local',
        title: 'X',
        wordIndex: 50,
        totalWords: 200,
        lastReadAt: _epoch,
      );
      expect(record.percent, closeTo(0.25, 0.001));
    });

    test('percent clamps to 0 when totalWords is 0', () {
      final record = ProgressRecord(
        contentId: 'x',
        source: 'local',
        title: 'X',
        wordIndex: 0,
        totalWords: 0,
        lastReadAt: _epoch,
      );
      expect(record.percent, 0.0);
    });

    test('roundtrips through fromJson / toJson', () {
      final original = ProgressRecord(
        contentId: 'instapaper://42',
        source: 'instapaper',
        title: 'My Article',
        wordIndex: 100,
        totalWords: 500,
        lastReadAt: DateTime(2025, 6, 1),
        finished: false,
      );
      final roundtripped = ProgressRecord.fromJson(original.toJson());
      expect(roundtripped.contentId, original.contentId);
      expect(roundtripped.source, original.source);
      expect(roundtripped.title, original.title);
      expect(roundtripped.wordIndex, original.wordIndex);
      expect(roundtripped.totalWords, original.totalWords);
      expect(roundtripped.finished, original.finished);
    });
  });
}

final DateTime _epoch = DateTime(1970);
