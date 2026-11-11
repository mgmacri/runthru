import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/features/content/services/instapaper_sync_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _queueKey = 'instapaper_sync_queue_v1';

const _network = InstapaperApiException(
  kind: InstapaperFailureKind.network,
  errorCode: 0,
  message: 'Network request failed',
);
const _rateLimited = InstapaperApiException(
  kind: InstapaperFailureKind.rateLimited,
  errorCode: 1040,
  message: 'Instapaper API error 1040',
);
const _serverError = InstapaperApiException(
  kind: InstapaperFailureKind.serviceUnavailable,
  errorCode: 503,
  message: 'HTTP 503',
);
const _unauthorized = InstapaperApiException(
  kind: InstapaperFailureKind.unauthorized,
  errorCode: 403,
  message: 'HTTP 403',
);
const _bookmarkGone = InstapaperApiException(
  kind: InstapaperFailureKind.bookmarkNotFound,
  errorCode: 1241,
  message: 'Instapaper API error 1241',
);
const _unknown = InstapaperApiException(
  kind: InstapaperFailureKind.unknown,
  errorCode: 400,
  message: 'HTTP 400',
);

/// A client whose write calls follow a script: each call takes the next
/// step, which is null (succeed), an object (throw it) or a [Completer]
/// (wait for it, then succeed). An empty script succeeds.
class _ScriptedClient extends InstapaperClient {
  _ScriptedClient()
    : super(
        config: const InstapaperClientConfig(
          consumerKey: 'k',
          consumerSecret: 's',
        ),
      );

  final List<String> calls = [];
  final Queue<Object?> script = Queue<Object?>();

  Future<void> _next(String call) async {
    calls.add(call);
    if (script.isEmpty) return;
    final step = script.removeFirst();
    if (step is Completer<void>) {
      await step.future;
      return;
    }
    if (step != null) throw step;
  }

  @override
  Future<void> updateReadProgress({
    required int bookmarkId,
    required double progress,
    int? timestampSeconds,
  }) => _next(
    'progress:$bookmarkId:${progress.toStringAsFixed(2)}:$timestampSeconds',
  );

  @override
  Future<void> archiveBookmark({required int bookmarkId}) =>
      _next('archive:$bookmarkId');
}

void main() {
  late _ScriptedClient client;
  InstapaperClient? resolved;
  final authFailures = <InstapaperFailureKind>[];

  InstapaperSyncQueue newQueue({
    List<Duration> retryDelays = const [],
    int maxAttempts = 5,
  }) {
    final queue = InstapaperSyncQueue(
      clientResolver: () => resolved,
      onAuthFailure: (error) => authFailures.add(error.kind),
      retryDelays: retryDelays,
      maxAttempts: maxAttempts,
    );
    addTearDown(queue.dispose);
    return queue;
  }

  Future<List<String>> pending(InstapaperSyncQueue queue) async => [
    for (final op in await queue.pendingOps())
      switch (op) {
        ProgressOp() =>
          'progress:${op.bookmarkId}:${op.progress.toStringAsFixed(2)}:${op.timestamp}',
        ArchiveOp() => 'archive:${op.bookmarkId}',
      },
  ];

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    client = _ScriptedClient();
    resolved = client;
    authFailures.clear();
  });

  group('sending', () {
    test('progress goes out with the time it was recorded', () async {
      final queue = newQueue();

      await queue.enqueueProgress(
        bookmarkId: 7,
        progress: 0.5,
        timestampSeconds: 1700000123,
      );
      await queue.drain();

      expect(client.calls, ['progress:7:0.50:1700000123']);
      expect(await pending(queue), isEmpty);
    });

    test('ops are sent in the order they were queued', () async {
      resolved = null;
      final queue = newQueue();
      await queue.enqueueProgress(
        bookmarkId: 1,
        progress: 0.1,
        timestampSeconds: 10,
      );
      await queue.enqueueArchive(bookmarkId: 2);
      await queue.enqueueProgress(
        bookmarkId: 3,
        progress: 0.3,
        timestampSeconds: 30,
      );

      resolved = client;
      await queue.drain();

      expect(client.calls, [
        'progress:1:0.10:10',
        'archive:2',
        'progress:3:0.30:30',
      ]);
      expect(await pending(queue), isEmpty);
    });

    test('nothing is sent, and nothing is lost, while signed out', () async {
      resolved = null;
      final queue = newQueue();

      await queue.enqueueArchive(bookmarkId: 9);
      await queue.drain();

      expect(client.calls, isEmpty);
      expect(await pending(queue), ['archive:9']);
    });
  });

  group('failures', () {
    test(
      'an op that could not be sent offline is kept and sent later',
      () async {
        // The client reports "no connection" as an InstapaperApiException; the
        // queue used to treat every such exception as permanent and drop the op.
        final queue = newQueue();
        client.script.add(_network);

        await queue.enqueueArchive(bookmarkId: 9);
        await queue.drain();

        expect(await pending(queue), ['archive:9']);

        await queue.drain();

        expect(client.calls, ['archive:9', 'archive:9']);
        expect(await pending(queue), isEmpty);
      },
    );

    test('rate limits, server errors and timeouts keep the op', () async {
      for (final failure in <Object>[
        _rateLimited,
        _serverError,
        TimeoutException('slow'),
        Exception('anything else'),
      ]) {
        SharedPreferences.setMockInitialValues({});
        client = _ScriptedClient()..script.add(failure);
        resolved = client;
        final queue = newQueue();

        await queue.enqueueProgress(
          bookmarkId: 1,
          progress: 0.2,
          timestampSeconds: 5,
        );
        await queue.drain();

        expect(await pending(queue), ['progress:1:0.20:5'], reason: '$failure');
      }
    });

    test(
      'a failure that will repeat stops the drain instead of hammering',
      () async {
        resolved = null;
        final queue = newQueue();
        await queue.enqueueArchive(bookmarkId: 1);
        await queue.enqueueArchive(bookmarkId: 2);
        await queue.enqueueArchive(bookmarkId: 3);

        resolved = client;
        client.script.add(_network);
        await queue.drain();

        expect(client.calls, ['archive:1']);
        expect(await pending(queue), ['archive:1', 'archive:2', 'archive:3']);
      },
    );

    test('a revoked connection keeps every op and reports it once', () async {
      resolved = null;
      final queue = newQueue();
      await queue.enqueueArchive(bookmarkId: 1);
      await queue.enqueueArchive(bookmarkId: 2);

      resolved = client;
      client.script.add(_unauthorized);
      await queue.drain();

      expect(client.calls, ['archive:1']);
      expect(await pending(queue), ['archive:1', 'archive:2']);
      expect(authFailures, [InstapaperFailureKind.unauthorized]);
    });

    test(
      'an op for a bookmark that is gone is dropped; the rest go out',
      () async {
        resolved = null;
        final queue = newQueue();
        await queue.enqueueArchive(bookmarkId: 1);
        await queue.enqueueArchive(bookmarkId: 2);

        resolved = client;
        client.script.add(_bookmarkGone);
        await queue.drain();

        expect(client.calls, ['archive:1', 'archive:2']);
        expect(await pending(queue), isEmpty);
      },
    );

    test(
      'an op that keeps failing for no known reason is given up on',
      () async {
        final queue = newQueue(maxAttempts: 3);
        client.script.addAll([_unknown, _unknown, _unknown]);

        await queue.enqueueArchive(bookmarkId: 1);
        await queue.drain();
        expect(await pending(queue), ['archive:1'], reason: 'after 1 failure');
        await queue.drain();
        expect(await pending(queue), ['archive:1'], reason: 'after 2 failures');
        await queue.drain();

        expect(await pending(queue), isEmpty, reason: 'after 3 failures');
        expect(client.calls, hasLength(3));
      },
    );

    test(
      'an op with an unknown failure does not hold up the ones behind it',
      () async {
        resolved = null;
        final queue = newQueue();
        await queue.enqueueArchive(bookmarkId: 1);
        await queue.enqueueArchive(bookmarkId: 2);

        resolved = client;
        client.script.add(_unknown);
        await queue.drain();

        expect(client.calls, ['archive:1', 'archive:2']);
        expect(await pending(queue), ['archive:1']);
      },
    );

    test('offline failures do not count towards giving up', () async {
      final queue = newQueue(maxAttempts: 2);
      client.script.addAll([_network, _network, _network, _network]);

      await queue.enqueueArchive(bookmarkId: 1);
      for (var i = 0; i < 4; i++) {
        await queue.drain();
      }

      expect(await pending(queue), ['archive:1']);
    });
  });

  group('coalescing', () {
    setUp(() => resolved = null);

    test('only the latest progress for a bookmark is kept', () async {
      final queue = newQueue();
      await queue.enqueueProgress(
        bookmarkId: 1,
        progress: 0.1,
        timestampSeconds: 10,
      );
      await queue.enqueueProgress(
        bookmarkId: 2,
        progress: 0.5,
        timestampSeconds: 11,
      );
      await queue.enqueueProgress(
        bookmarkId: 1,
        progress: 0.3,
        timestampSeconds: 12,
      );

      expect(await pending(queue), [
        'progress:2:0.50:11',
        'progress:1:0.30:12',
      ]);
    });

    test('an archive replaces the pending progress for its bookmark', () async {
      final queue = newQueue();
      await queue.enqueueProgress(
        bookmarkId: 1,
        progress: 0.9,
        timestampSeconds: 10,
      );
      await queue.enqueueArchive(bookmarkId: 1);
      await queue.enqueueArchive(bookmarkId: 1);

      expect(await pending(queue), ['archive:1']);
    });

    test(
      'progress for a bookmark already queued for archive is ignored',
      () async {
        final queue = newQueue();
        await queue.enqueueArchive(bookmarkId: 1);
        await queue.enqueueProgress(
          bookmarkId: 1,
          progress: 1,
          timestampSeconds: 10,
        );

        expect(await pending(queue), ['archive:1']);
      },
    );

    test(
      'a finished article sends its final position, then the archive',
      () async {
        final queue = newQueue();
        await queue.enqueueProgress(
          bookmarkId: 1,
          progress: 0.6,
          timestampSeconds: 10,
        );
        await queue.enqueueArchive(
          bookmarkId: 1,
          finalProgress: 1,
          timestampSeconds: 50,
        );
        // A position recorded a word before the end arrives late: moot.
        await queue.enqueueProgress(
          bookmarkId: 1,
          progress: 0.99,
          timestampSeconds: 51,
        );

        expect(await pending(queue), ['progress:1:1.00:50', 'archive:1']);

        resolved = client;
        await queue.drain();
        expect(client.calls, ['progress:1:1.00:50', 'archive:1']);
        expect(await pending(queue), isEmpty);
      },
    );

    test('progress is kept inside 0 to 1', () async {
      final queue = newQueue();
      await queue.enqueueProgress(
        bookmarkId: 1,
        progress: 3,
        timestampSeconds: 10,
      );

      expect(await pending(queue), ['progress:1:1.00:10']);
    });
  });

  group('durability', () {
    test('enqueue returns once the op is saved, not once it is sent', () async {
      final queue = newQueue();
      final gate = Completer<void>();
      client.script.add(gate);

      await queue
          .enqueueArchive(bookmarkId: 1)
          .timeout(const Duration(seconds: 2));

      expect(await pending(queue), ['archive:1']);
      gate.complete();
      await queue.drain();
      expect(await pending(queue), isEmpty);
    });

    test(
      'an op queued during a send is saved at once and sent in turn',
      () async {
        final queue = newQueue();
        final gate = Completer<void>();
        client.script.add(gate);
        await queue.enqueueArchive(bookmarkId: 1);
        // Let the first send start.
        await Future<void>.delayed(Duration.zero);
        expect(client.calls, ['archive:1']);

        await queue
            .enqueueArchive(bookmarkId: 2)
            .timeout(const Duration(seconds: 2));
        expect(await pending(queue), ['archive:1', 'archive:2']);

        gate.complete();
        await queue.drain();

        expect(client.calls, ['archive:1', 'archive:2']);
        expect(await pending(queue), isEmpty);
      },
    );

    test(
      'newer progress queued during a send is not lost with the old',
      () async {
        final queue = newQueue();
        final gate = Completer<void>();
        client.script.add(gate);
        await queue.enqueueProgress(
          bookmarkId: 1,
          progress: 0.2,
          timestampSeconds: 10,
        );
        await Future<void>.delayed(Duration.zero);
        expect(client.calls, ['progress:1:0.20:10']);

        await queue.enqueueProgress(
          bookmarkId: 1,
          progress: 0.6,
          timestampSeconds: 20,
        );
        gate.complete();
        await queue.drain();

        expect(client.calls, ['progress:1:0.20:10', 'progress:1:0.60:20']);
        expect(await pending(queue), isEmpty);
      },
    );

    test('clearing during a send stops the rest from going out', () async {
      resolved = null;
      final queue = newQueue();
      await queue.enqueueArchive(bookmarkId: 1);
      await queue.enqueueArchive(bookmarkId: 2);

      final gate = Completer<void>();
      client.script.add(gate);
      resolved = client;
      final draining = queue.drain();
      await Future<void>.delayed(Duration.zero);
      expect(client.calls, ['archive:1']);

      await queue.clear();
      gate.complete();
      await draining;

      expect(client.calls, ['archive:1']);
      expect(await pending(queue), isEmpty);
    });

    test('ops saved by an earlier version still load', () async {
      SharedPreferences.setMockInitialValues({
        _queueKey: jsonEncode([
          {
            'type': 'progress',
            'bookmark_id': 4,
            'progress': 0.25,
            'timestamp': 99,
          },
          {'type': 'archive', 'bookmark_id': 5},
          {'type': 'mystery', 'bookmark_id': 6},
          {'type': 'archive'},
        ]),
      });
      final queue = newQueue();

      expect(await pending(queue), ['progress:4:0.25:99', 'archive:5']);
      await queue.drain();
      expect(client.calls, ['progress:4:0.25:99', 'archive:5']);
    });

    test('a corrupt store reads as empty', () async {
      SharedPreferences.setMockInitialValues({_queueKey: '{not json'});
      final queue = newQueue();

      expect(await pending(queue), isEmpty);
      await queue.enqueueArchive(bookmarkId: 1);
      await queue.drain();
      expect(client.calls, ['archive:1']);
    });
  });

  group('retry', () {
    test('a send that failed offline is tried again on its own', () async {
      final queue = newQueue(retryDelays: const [Duration(milliseconds: 20)]);
      client.script.add(_network);

      await queue.enqueueArchive(bookmarkId: 1);
      await queue.drain();
      expect(await pending(queue), ['archive:1']);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      await queue.drain();

      expect(client.calls, ['archive:1', 'archive:1']);
      expect(await pending(queue), isEmpty);
    });

    test('no retry is scheduled after the queue is disposed', () async {
      final queue = newQueue(retryDelays: const [Duration(milliseconds: 20)]);
      client.script.add(_network);
      await queue.enqueueArchive(bookmarkId: 1);
      await queue.drain();

      queue.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(client.calls, ['archive:1']);
    });
  });
}
