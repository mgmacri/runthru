/// Offline-first sync queue for Instapaper write operations.
///
/// Reading progress updates and archive operations are durable: an op is
/// written to [SharedPreferences] before [InstapaperSyncQueue.enqueueProgress]
/// or [InstapaperSyncQueue.enqueueArchive] returns, and sending happens
/// afterwards, on its own. Nothing a caller awaits ever waits on the network.
///
/// An op leaves the queue only when Instapaper accepted it, when it can
/// never succeed (the bookmark is gone), or when Instapaper has refused it
/// several times while taking other ops. A send that failed for any other
/// reason stays queued and is tried again: after a pause, on the next
/// enqueue, on the next list refresh, and on sign-in.
///
/// Progress updates for the same bookmark coalesce: only the most recent
/// progress value is kept. An archive op for a bookmark supersedes any
/// pending progress op for that bookmark.
library;

import 'dart:async';
import 'dart:convert';

import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/models/instapaper_bookmark.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage key for the persisted queue.
const String _kQueueKey = 'instapaper_sync_queue_v1';

/// A single pending sync operation.
sealed class InstapaperSyncOp {
  /// Base constructor.
  const InstapaperSyncOp({required this.bookmarkId, this.attempts = 0});

  /// The bookmark this op targets.
  final int bookmarkId;

  /// How many sends Instapaper has refused for the op itself: for a reason
  /// the queue does not know, or with trouble of its own in a pass where it
  /// accepted other ops. Sends that never reached Instapaper, and refusals
  /// while it accepted nothing, are not counted.
  final int attempts;

  /// Serialise to a JSON-safe map.
  Map<String, Object?> toJson();

  /// The same op with a different [attempts] count.
  InstapaperSyncOp withAttempts(int attempts);

  /// Whether [other] is this very op (ignoring [attempts]): the same kind,
  /// bookmark and, for progress, the same position and time.
  bool sameAs(InstapaperSyncOp other);

  /// Parse from a JSON map. Null for an entry that is not a known op.
  static InstapaperSyncOp? fromJson(Map<String, Object?> json) {
    final id = instapaperInt(json['bookmark_id']);
    if (id == null) return null;
    final attempts = instapaperInt(json['attempts']) ?? 0;
    switch (json['type']) {
      case 'progress':
        final p = instapaperDouble(json['progress']);
        final ts = instapaperInt(json['timestamp']);
        if (p == null || ts == null) return null;
        return ProgressOp(
          bookmarkId: id,
          progress: p.clamp(0.0, 1.0),
          timestamp: ts,
          attempts: attempts,
        );
      case 'archive':
        return ArchiveOp(bookmarkId: id, attempts: attempts);
      default:
        return null;
    }
  }
}

/// Pending reading-progress update.
class ProgressOp extends InstapaperSyncOp {
  /// Creates a progress sync op.
  const ProgressOp({
    required super.bookmarkId,
    required this.progress,
    required this.timestamp,
    super.attempts,
  });

  /// Reading progress in the range 0.0–1.0.
  final double progress;

  /// Unix seconds at which the progress was recorded.
  final int timestamp;

  @override
  Map<String, Object?> toJson() => {
    'type': 'progress',
    'bookmark_id': bookmarkId,
    'progress': progress,
    'timestamp': timestamp,
    if (attempts > 0) 'attempts': attempts,
  };

  @override
  ProgressOp withAttempts(int attempts) => ProgressOp(
    bookmarkId: bookmarkId,
    progress: progress,
    timestamp: timestamp,
    attempts: attempts,
  );

  @override
  bool sameAs(InstapaperSyncOp other) =>
      other is ProgressOp &&
      other.bookmarkId == bookmarkId &&
      other.progress == progress &&
      other.timestamp == timestamp;
}

/// Pending archive (mark-as-read) op.
class ArchiveOp extends InstapaperSyncOp {
  /// Creates an archive sync op.
  const ArchiveOp({required super.bookmarkId, super.attempts});

  @override
  Map<String, Object?> toJson() => {
    'type': 'archive',
    'bookmark_id': bookmarkId,
    if (attempts > 0) 'attempts': attempts,
  };

  @override
  ArchiveOp withAttempts(int attempts) =>
      ArchiveOp(bookmarkId: bookmarkId, attempts: attempts);

  @override
  bool sameAs(InstapaperSyncOp other) =>
      other is ArchiveOp && other.bookmarkId == bookmarkId;
}

/// Resolves the active Instapaper client, or null when unauthenticated.
typedef InstapaperClientResolver = InstapaperClient? Function();

/// What one send came to.
enum _Outcome {
  /// Instapaper accepted the op.
  sent,

  /// The op can never succeed; it leaves the queue.
  dropped,

  /// Refused for an unknown reason; counted, and the next op gets its turn.
  failed,

  /// Instapaper answered with trouble of its own (a server error, a reply
  /// that makes no sense). Either it is unwell, or it cannot take this op:
  /// the op is kept, and the rest of the pass shows which.
  troubled,

  /// Nothing will get through right now (no connection, a rate limit, a
  /// wrong clock): stop, keep everything, try again after a pause.
  retryLater,

  /// Nothing will get through until the reader signs in again: stop, keep
  /// everything.
  needsSignIn,
}

/// How one pass over the queue ended.
enum _Pass {
  /// Every queued op had its turn.
  workedThrough,

  /// Nobody is signed in. Worth another look if a drain was asked for
  /// meanwhile (sign-in may just have finished).
  noClient,

  /// Stopped early; another pass now would meet the same wall.
  blocked,
}

/// Persistent, coalescing sync queue for Instapaper write ops.
///
/// Storage updates are serialised among themselves and never wait on a
/// request. One drain runs at a time; a drain asked for while one is running
/// makes that one take another pass.
class InstapaperSyncQueue {
  /// Creates a queue with the given client resolver.
  ///
  /// [onAuthFailure] is told when Instapaper refuses the saved connection.
  /// [retryDelays] are the pauses before a failed drain is tried again (the
  /// last one repeats); an empty list means no timed retry. An op refused
  /// [maxAttempts] times for itself (see [InstapaperSyncOp.attempts]) is
  /// given up on.
  InstapaperSyncQueue({
    required InstapaperClientResolver clientResolver,
    void Function(InstapaperApiException error)? onAuthFailure,
    List<Duration> retryDelays = const [
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 15),
    ],
    int maxAttempts = 5,
  }) : _clientResolver = clientResolver,
       _onAuthFailure = onAuthFailure,
       _retryDelays = retryDelays,
       _maxAttempts = maxAttempts;

  final InstapaperClientResolver _clientResolver;
  final void Function(InstapaperApiException error)? _onAuthFailure;
  final List<Duration> _retryDelays;
  final int _maxAttempts;

  SharedPreferences? _prefs;
  Future<void> _storeChain = Future<void>.value();

  Future<void>? _drainFuture;
  bool _drainAgain = false;

  /// Bumped by [clear]: a drain that started before it stops touching ops.
  int _generation = 0;

  Timer? _retryTimer;
  int _retryStep = 0;
  bool _disposed = false;

  /// How many bookmarks Instapaper may answer with trouble, with nothing
  /// accepted, before a pass takes it that Instapaper itself is unwell.
  static const int _troubleLimit = 2;

  /// Bookmarks whose ops Instapaper answered with trouble and has not taken
  /// since. They go last in a pass, so that what is queued behind them is
  /// sent, and shows whether the trouble was theirs.
  final Set<int> _setAside = <int>{};

  /// Snapshot of pending ops (read-only view used by callers to overlay
  /// optimistic state on freshly fetched bookmark lists).
  Future<List<InstapaperSyncOp>> pendingOps() => _read();

  /// Save a progress update, then send it in the background.
  ///
  /// Completes when the op is saved.
  Future<void> enqueueProgress({
    required int bookmarkId,
    required double progress,
    int? timestampSeconds,
  }) async {
    final ts =
        timestampSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    await _mutate((ops) {
      // If an archive is already queued, the progress is moot. What is
      // queued for the bookmark stays as it is: with the archive may sit
      // the final position of an article read to its end.
      final archived = ops.any(
        (o) => o is ArchiveOp && o.bookmarkId == bookmarkId,
      );
      if (archived) return;
      // Drop any existing progress op for this bookmark — keep latest only.
      ops.removeWhere((o) => o is ProgressOp && o.bookmarkId == bookmarkId);
      ops.add(
        ProgressOp(
          bookmarkId: bookmarkId,
          progress: progress.clamp(0.0, 1.0),
          timestamp: ts,
        ),
      );
    });
    unawaited(drain());
  }

  /// Save an archive op, then send it in the background.
  ///
  /// With [finalProgress] (the article was read to the end) that position
  /// is sent first, so the archived article does not stay at whatever
  /// partial percentage was last synced.
  ///
  /// Completes when the op is saved.
  Future<void> enqueueArchive({
    required int bookmarkId,
    double? finalProgress,
    int? timestampSeconds,
  }) async {
    final ts =
        timestampSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    await _mutate((ops) {
      // An archive supersedes any pending progress for this bookmark.
      ops.removeWhere((o) => o.bookmarkId == bookmarkId);
      if (finalProgress != null) {
        ops.add(
          ProgressOp(
            bookmarkId: bookmarkId,
            progress: finalProgress.clamp(0.0, 1.0),
            timestamp: ts,
          ),
        );
      }
      ops.add(ArchiveOp(bookmarkId: bookmarkId));
    });
    unawaited(drain());
  }

  /// Send what is queued. Safe to call at any time (sign-in, list refresh,
  /// app resume); completes when this round of sending is over.
  Future<void> drain() {
    final running = _drainFuture;
    if (running != null) {
      _drainAgain = true;
      return running;
    }
    final future = _drainLoop();
    _drainFuture = future;
    return future;
  }

  /// Clear all pending Instapaper write operations.
  Future<void> clear() {
    _generation++;
    _cancelRetry();
    _retryStep = 0;
    return _locked((prefs) => prefs.remove(_kQueueKey));
  }

  /// Stop timed retries. Queued ops stay saved for the next launch.
  void dispose() {
    _disposed = true;
    _cancelRetry();
  }

  // ── Draining ──────────────────────────────────────────────────────────────

  Future<void> _drainLoop() async {
    // Ops refused during this drain: a further pass leaves them for the
    // next drain instead of sending them again straight away.
    final refused = <InstapaperSyncOp>[];
    try {
      do {
        _drainAgain = false;
        if (await _drainOnce(refused) == _Pass.blocked) break;
      } while (_drainAgain && !_disposed);
    } finally {
      // Cleared in the same step as the loop's last check, so a drain asked
      // for from now on starts a new one instead of joining a finished one.
      _drainFuture = null;
    }
  }

  /// One pass over the queue.
  Future<_Pass> _drainOnce(List<InstapaperSyncOp> refused) async {
    final generation = _generation;
    final client = _resolveClient();
    if (client == null) {
      appLog('instapaper-queue', 'drain skipped: no client');
      return _Pass.noClient;
    }

    final queued = await _read();
    if (queued.isEmpty) {
      _cancelRetry();
      _setAside.clear();
      return _Pass.workedThrough;
    }
    appLog('instapaper-queue', 'draining ${queued.length} op(s)');

    // Ops for one bookmark keep their order (a position before its archive).
    _setAside.retainAll({for (final op in queued) op.bookmarkId});
    final ops = [
      ...queued.where((op) => !_setAside.contains(op.bookmarkId)),
      ...queued.where((op) => _setAside.contains(op.bookmarkId)),
    ];

    // Ops Instapaper answered with trouble in this pass. Whether the
    // trouble is Instapaper's or theirs shows when another op is accepted.
    final troubled = <InstapaperSyncOp>[];
    var accepted = false;
    var pass = _Pass.workedThrough;
    var retry = false;

    sending:
    for (final op in ops) {
      if (_disposed || generation != _generation) return _Pass.workedThrough;
      if (refused.any(op.sameAs)) continue;
      // The archive behind a position Instapaper would not take waits with
      // it: one request per troubled bookmark in a pass.
      if (troubled.any((t) => t.bookmarkId == op.bookmarkId)) continue;
      // Replaced or cleared since the snapshot was taken.
      if (!await _contains(op)) continue;

      final outcome = await _send(client, op);
      // Cleared during the send: nothing queued belongs to this pass now.
      if (generation != _generation) return _Pass.workedThrough;

      switch (outcome) {
        case _Outcome.sent:
          _retryStep = 0;
          accepted = true;
          _setAside.remove(op.bookmarkId);
          await _remove(op);
        case _Outcome.dropped:
          await _remove(op);
        case _Outcome.failed:
          refused.add(op);
          await _countFailure(op);
        case _Outcome.troubled:
          troubled.add(op);
          if (!accepted && troubled.length >= _troubleLimit) {
            break sending;
          }
        case _Outcome.retryLater:
          retry = true;
          pass = _Pass.blocked;
          break sending;
        case _Outcome.needsSignIn:
          // Signing in starts the next drain; a timer would only knock on
          // a closed door.
          return _Pass.blocked;
      }
    }

    if (troubled.isNotEmpty) {
      _setAside.addAll(troubled.map((op) => op.bookmarkId));
      retry = true;
      if (accepted) {
        // Instapaper took other ops in this pass, so these were refused
        // for themselves. That counts towards giving up on them, and they
        // no longer hold up anything else.
        for (final op in troubled) {
          refused.add(op);
          await _countFailure(op);
        }
      } else {
        // Nothing got through: Instapaper is unwell. Everything is kept.
        pass = _Pass.blocked;
      }
    }
    if (retry) _scheduleRetry();
    return pass;
  }

  Future<_Outcome> _send(InstapaperClient client, InstapaperSyncOp op) async {
    final label = '${op.runtimeType} bookmark=${op.bookmarkId}';
    try {
      switch (op) {
        case ProgressOp():
          await client.updateReadProgress(
            bookmarkId: op.bookmarkId,
            progress: op.progress,
            timestampSeconds: op.timestamp,
          );
        case ArchiveOp():
          await client.archiveBookmark(bookmarkId: op.bookmarkId);
      }
      appLog('instapaper-queue', 'sent $label');
      return _Outcome.sent;
    } on InstapaperApiException catch (e) {
      final why = 'category=${e.kind.name} code=${e.errorCode}';
      if (e.isPermanent) {
        appLog('instapaper-queue', 'dropping $label: $why');
        return _Outcome.dropped;
      }
      if (e.kind == InstapaperFailureKind.unauthorized ||
          e.kind == InstapaperFailureKind.suspended) {
        appLog('instapaper-queue', 'keeping ops until sign-in: $why');
        if (e.kind == InstapaperFailureKind.unauthorized) {
          _onAuthFailure?.call(e);
        }
        return _Outcome.needsSignIn;
      }
      if (e.kind == InstapaperFailureKind.serviceUnavailable ||
          e.kind == InstapaperFailureKind.unexpectedResponse) {
        appLog('instapaper-queue', 'not taken for now, $label: $why');
        return _Outcome.troubled;
      }
      if (e.isTransient) {
        appLog('instapaper-queue', 'keeping ops, will retry: $why');
        return _Outcome.retryLater;
      }
      appLog('instapaper-queue', 'send refused for $label: $why');
      return _Outcome.failed;
    } on InstapaperAuthException catch (e) {
      // The build has no consumer key: nothing can be sent.
      appLog('instapaper-queue', 'keeping ops: category=${e.kind.name}');
      return _Outcome.needsSignIn;
    } on Object catch (e) {
      appLog(
        'instapaper-queue',
        'keeping ops, will retry: ${InstapaperRedactor.redact('$e')}',
      );
      return _Outcome.retryLater;
    }
  }

  InstapaperClient? _resolveClient() {
    try {
      return _clientResolver();
    } on Object {
      // The owner (a provider container) is gone.
      return null;
    }
  }

  void _scheduleRetry() {
    if (_disposed || _retryDelays.isEmpty) return;
    _retryTimer?.cancel();
    final step = _retryStep < _retryDelays.length
        ? _retryStep
        : _retryDelays.length - 1;
    _retryStep++;
    _retryTimer = Timer(_retryDelays[step], () {
      _retryTimer = null;
      if (!_disposed) unawaited(drain());
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // ── Storage ───────────────────────────────────────────────────────────────

  Future<SharedPreferences> _preferences() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<List<InstapaperSyncOp>> _read() async =>
      _decode((await _preferences()).getString(_kQueueKey));

  Future<bool> _contains(InstapaperSyncOp op) async =>
      (await _read()).any(op.sameAs);

  /// Removes [op] if it is still queued as it was sent. A newer op for the
  /// same bookmark, queued while this one was on its way, stays.
  Future<void> _remove(InstapaperSyncOp op) => _mutate((ops) {
    final index = ops.indexWhere(op.sameAs);
    if (index >= 0) ops.removeAt(index);
  });

  Future<void> _countFailure(InstapaperSyncOp op) => _mutate((ops) {
    final index = ops.indexWhere(op.sameAs);
    if (index < 0) return;
    final attempts = ops[index].attempts + 1;
    if (attempts >= _maxAttempts) {
      ops.removeAt(index);
      appLog(
        'instapaper-queue',
        'giving up on ${op.runtimeType} bookmark=${op.bookmarkId} '
            'after $attempts refusals',
      );
    } else {
      ops[index] = ops[index].withAttempts(attempts);
    }
  });

  Future<void> _mutate(void Function(List<InstapaperSyncOp> ops) update) =>
      _locked((prefs) {
        final ops = _decode(prefs.getString(_kQueueKey));
        update(ops);
        return prefs.setString(_kQueueKey, _encode(ops));
      });

  /// Runs [action] after every storage update asked for before it. No
  /// request is ever made inside, so this never waits on the network.
  Future<void> _locked(
    Future<Object?> Function(SharedPreferences prefs) action,
  ) {
    final next = _storeChain.then((_) async {
      await action(await _preferences());
    });
    _storeChain = next.catchError((Object _) {});
    return next;
  }

  static List<InstapaperSyncOp> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <InstapaperSyncOp>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <InstapaperSyncOp>[];
      return decoded
          .whereType<Map<String, Object?>>()
          .map(InstapaperSyncOp.fromJson)
          .whereType<InstapaperSyncOp>()
          .toList();
    } on FormatException {
      return <InstapaperSyncOp>[];
    }
  }

  static String _encode(List<InstapaperSyncOp> ops) =>
      jsonEncode(ops.map((o) => o.toJson()).toList());
}
