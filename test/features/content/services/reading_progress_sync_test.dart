import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/services/reading_progress_sync.dart';

void main() {
  ReadingProgressSnapshot snapshot({
    int wordIndex = 0,
    double progress = 0.0,
    int? bookmarkId = 42,
  }) {
    return ReadingProgressSnapshot(
      contentId: 'instapaper://42',
      wordIndex: wordIndex,
      totalWordCount: 100,
      progress: progress,
      instapaperBookmarkId: bookmarkId,
    );
  }

  test('throttles frequent word changes and keeps the latest progress', () {
    fakeAsync((async) {
      final localWrites = <int>[];
      final remoteWrites = <double>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add(wordIndex);
        },
        writeRemoteProgress: ({required bookmarkId, required progress}) async {
          remoteWrites.add(progress);
        },
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
      );

      sync.record(snapshot(wordIndex: 10, progress: 0.10));
      async.flushMicrotasks();

      sync.record(snapshot(wordIndex: 11, progress: 0.11));
      sync.record(snapshot(wordIndex: 12, progress: 0.12));
      sync.record(snapshot(wordIndex: 13, progress: 0.13));
      async.flushMicrotasks();

      expect(localWrites, equals([10]));
      expect(remoteWrites, equals([0.10]));

      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();

      expect(localWrites, equals([10, 13]));
      expect(remoteWrites, equals([0.10, 0.13]));
    });
  });

  test('flush persists pending progress before session exit', () {
    fakeAsync((async) {
      final localWrites = <int>[];
      final remoteWrites = <double>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add(wordIndex);
        },
        writeRemoteProgress: ({required bookmarkId, required progress}) async {
          remoteWrites.add(progress);
        },
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
      );

      sync.record(snapshot(wordIndex: 10, progress: 0.10));
      async.flushMicrotasks();
      sync.record(snapshot(wordIndex: 11, progress: 0.11));
      async.flushMicrotasks();

      expect(localWrites, equals([10]));

      sync.flush();
      async.flushMicrotasks();

      expect(localWrites, equals([10, 11]));
      expect(remoteWrites, equals([0.10, 0.11]));
    });
  });

  test('skips exact duplicate progress values', () {
    fakeAsync((async) {
      final localWrites = <int>[];
      final remoteWrites = <double>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add(wordIndex);
        },
        writeRemoteProgress: ({required bookmarkId, required progress}) async {
          remoteWrites.add(progress);
        },
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
      );

      sync.record(snapshot(wordIndex: 10, progress: 0.10));
      sync.record(snapshot(wordIndex: 10, progress: 0.10));
      async.flushMicrotasks();
      sync.flush();
      async.flushMicrotasks();

      expect(localWrites, equals([10]));
      expect(remoteWrites, equals([0.10]));
    });
  });

  test('does not erase local progress when remote sync fails', () {
    fakeAsync((async) {
      final localWrites = <int>[];
      final errors = <Object>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add(wordIndex);
        },
        writeRemoteProgress: ({required bookmarkId, required progress}) {
          throw StateError('network down');
        },
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
        onError: (error, stackTrace) => errors.add(error),
      );

      sync.record(snapshot(wordIndex: 25, progress: 0.25));
      async.flushMicrotasks();

      expect(localWrites, equals([25]));
      expect(errors.single, isA<StateError>());
    });
  });

  test('ignores non-Instapaper snapshots', () {
    fakeAsync((async) {
      final localWrites = <int>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add(wordIndex);
        },
        writeRemoteProgress:
            ({required bookmarkId, required progress}) async {},
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
      );

      sync.record(snapshot(wordIndex: 10, progress: 0.10, bookmarkId: null));
      async.flushMicrotasks();
      sync.flush();
      async.flushMicrotasks();

      expect(localWrites, isEmpty);
    });
  });
}
