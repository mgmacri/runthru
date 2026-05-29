import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/services/reading_progress_sync.dart';

void main() {
  ReadingProgressSnapshot snapshot({
    String contentId = 'instapaper://42',
    int wordIndex = 0,
    int totalWordCount = 100,
    double progress = 0.0,
  }) {
    return ReadingProgressSnapshot(
      contentId: contentId,
      wordIndex: wordIndex,
      totalWordCount: totalWordCount,
      progress: progress,
    );
  }

  test('local-only mode writes progress without a remote writer', () {
    fakeAsync((async) {
      final localWrites = <({String contentId, int wordIndex})>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add((contentId: contentId, wordIndex: wordIndex));
        },
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
      );

      sync.record(
        snapshot(contentId: 'drive://file-123', wordIndex: 18, progress: 0.18),
      );
      async.flushMicrotasks();

      expect(localWrites, [(contentId: 'drive://file-123', wordIndex: 18)]);
    });
  });

  test('Instapaper remote writer preserves bookmark progress writes', () {
    fakeAsync((async) {
      final localWrites = <int>[];
      final remoteWrites = <({int bookmarkId, double progress})>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add(wordIndex);
        },
        remoteWriter: InstapaperReadingProgressRemoteWriter(
          bookmarkId: 42,
          writeProgress: ({required bookmarkId, required progress}) async {
            remoteWrites.add((bookmarkId: bookmarkId, progress: progress));
          },
        ),
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
      );

      sync.record(snapshot(wordIndex: 10, progress: 0.10));
      async.flushMicrotasks();

      expect(localWrites, equals([10]));
      expect(remoteWrites, [(bookmarkId: 42, progress: 0.10)]);
    });
  });

  test(
    'fake Drive remote writer can be injected without Drive implementation',
    () {
      fakeAsync((async) {
        final remoteSnapshots = <ReadingProgressSnapshot>[];
        final sync = ReadingProgressSync(
          writeLocalProgress:
              ({required contentId, required wordIndex}) async {},
          remoteWriter: CallbackReadingProgressRemoteWriter((snapshot) async {
            if (snapshot.contentId.startsWith('drive://')) {
              remoteSnapshots.add(snapshot);
            }
          }),
          now: () => DateTime(2026, 1, 1).add(async.elapsed),
        );

        sync.record(
          snapshot(
            contentId: 'drive://drive-doc',
            wordIndex: 44,
            totalWordCount: 200,
            progress: 0.22,
          ),
        );
        async.flushMicrotasks();

        expect(remoteSnapshots, hasLength(1));
        expect(remoteSnapshots.single.contentId, 'drive://drive-doc');
        expect(remoteSnapshots.single.wordIndex, 44);
        expect(remoteSnapshots.single.totalWordCount, 200);
        expect(remoteSnapshots.single.progress, 0.22);
      });
    },
  );

  test('throttles frequent word changes and keeps the latest progress', () {
    fakeAsync((async) {
      final localWrites = <int>[];
      final remoteWrites = <double>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add(wordIndex);
        },
        remoteWriter: CallbackReadingProgressRemoteWriter((snapshot) async {
          remoteWrites.add(snapshot.progress);
        }),
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
        remoteWriter: CallbackReadingProgressRemoteWriter((snapshot) async {
          remoteWrites.add(snapshot.progress);
        }),
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

  test('dispose flushes pending progress and cancels scheduled timers', () {
    fakeAsync((async) {
      final localWrites = <int>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add(wordIndex);
        },
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
      );

      sync.record(snapshot(wordIndex: 10, progress: 0.10));
      async.flushMicrotasks();
      sync.record(snapshot(wordIndex: 12, progress: 0.12));
      async.flushMicrotasks();

      sync.dispose();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();

      expect(localWrites, equals([10, 12]));
    });
  });

  test('dispose does not throw when no progress is pending', () {
    fakeAsync((async) {
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {},
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
      );

      expect(() {
        sync.dispose();
        async.flushMicrotasks();
      }, returnsNormally);
    });
  });

  test(
    'cancelTimers cancels scheduled writes without flushing pending progress',
    () {
      fakeAsync((async) {
        final localWrites = <int>[];
        final sync = ReadingProgressSync(
          writeLocalProgress: ({required contentId, required wordIndex}) async {
            localWrites.add(wordIndex);
          },
          now: () => DateTime(2026, 1, 1).add(async.elapsed),
        );

        sync.record(snapshot(wordIndex: 10, progress: 0.10));
        async.flushMicrotasks();
        sync.record(snapshot(wordIndex: 12, progress: 0.12));
        async.flushMicrotasks();

        sync.cancelTimers();
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();

        expect(localWrites, equals([10]));

        sync.flush();
        async.flushMicrotasks();

        expect(localWrites, equals([10, 12]));
      });
    },
  );

  test('skips exact duplicate progress values', () {
    fakeAsync((async) {
      final localWrites = <int>[];
      final remoteWrites = <double>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add(wordIndex);
        },
        remoteWriter: CallbackReadingProgressRemoteWriter((snapshot) async {
          remoteWrites.add(snapshot.progress);
        }),
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
        remoteWriter: CallbackReadingProgressRemoteWriter((snapshot) {
          throw StateError('network down');
        }),
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
        onError: (error, stackTrace) => errors.add(error),
      );

      sync.record(snapshot(wordIndex: 25, progress: 0.25));
      async.flushMicrotasks();
      sync.record(snapshot(wordIndex: 50, progress: 0.50));
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();

      expect(localWrites, equals([25, 50]));
      expect(errors, hasLength(2));
      expect(errors, everyElement(isA<StateError>()));
    });
  });

  test('normalises word index and progress before persistence', () {
    fakeAsync((async) {
      final localWrites = <int>[];
      final remoteWrites = <double>[];
      final sync = ReadingProgressSync(
        writeLocalProgress: ({required contentId, required wordIndex}) async {
          localWrites.add(wordIndex);
        },
        remoteWriter: CallbackReadingProgressRemoteWriter((snapshot) async {
          remoteWrites.add(snapshot.progress);
        }),
        now: () => DateTime(2026, 1, 1).add(async.elapsed),
      );

      sync.record(snapshot(wordIndex: 120, totalWordCount: 100, progress: 1.4));
      async.flushMicrotasks();

      expect(localWrites, equals([99]));
      expect(remoteWrites, equals([1.0]));
    });
  });
}
