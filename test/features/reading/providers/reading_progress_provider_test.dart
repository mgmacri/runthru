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

  group('ReadingProgress.shelf', () {
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
    test('shelf collapses legacy duplicate records sharing a contentId', () async {
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
      expect(shelf.length, 1, reason: 'duplicates must collapse to one entry');
      // The most recently read instance wins.
      expect(shelf.first.wordIndex, 25);
    });

    test('record heals pre-existing duplicates and persists a single entry', () async {
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
    });
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
