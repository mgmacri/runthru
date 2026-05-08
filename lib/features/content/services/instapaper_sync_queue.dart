/// Offline-first sync queue for Instapaper write operations.
///
/// Reading progress updates and archive operations are durable: they are
/// persisted to [SharedPreferences] on enqueue and drained against the
/// Instapaper API when a client is available. Failed sends remain in the
/// queue and are retried on the next drain (next enqueue, auth change, or
/// app resume).
///
/// Progress updates for the same bookmark coalesce: only the most recent
/// progress value is kept. An archive op for a bookmark supersedes any
/// pending progress op for that bookmark.
library;

import 'dart:async';
import 'dart:convert';

import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage key for the persisted queue.
const String _kQueueKey = 'instapaper_sync_queue_v1';

/// A single pending sync operation.
sealed class InstapaperSyncOp {
  /// Base constructor.
  const InstapaperSyncOp({required this.bookmarkId});

  /// The bookmark this op targets.
  final int bookmarkId;

  /// Serialise to a JSON-safe map.
  Map<String, Object?> toJson();

  /// Parse from a JSON map.
  static InstapaperSyncOp? fromJson(Map<String, Object?> json) {
    final type = json['type'] as String?;
    final id = (json['bookmark_id'] as num?)?.toInt();
    if (id == null) return null;
    switch (type) {
      case 'progress':
        final p = (json['progress'] as num?)?.toDouble();
        final ts = (json['timestamp'] as num?)?.toInt();
        if (p == null || ts == null) return null;
        return ProgressOp(bookmarkId: id, progress: p, timestamp: ts);
      case 'archive':
        return ArchiveOp(bookmarkId: id);
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
  };
}

/// Pending archive (mark-as-read) op.
class ArchiveOp extends InstapaperSyncOp {
  /// Creates an archive sync op.
  const ArchiveOp({required super.bookmarkId});

  @override
  Map<String, Object?> toJson() => {
    'type': 'archive',
    'bookmark_id': bookmarkId,
  };
}

/// Resolves the active Instapaper client, or null when unauthenticated.
typedef InstapaperClientResolver = InstapaperClient? Function();

/// Persistent, coalescing sync queue for Instapaper write ops.
///
/// Thread-safety: all public mutators are serialised through a single
/// [Future] chain to avoid concurrent SharedPreferences writes or duplicate
/// in-flight drains.
class InstapaperSyncQueue {
  /// Creates a queue with the given client resolver.
  InstapaperSyncQueue({required InstapaperClientResolver clientResolver})
    : _clientResolver = clientResolver;

  final InstapaperClientResolver _clientResolver;
  Future<void> _chain = Future<void>.value();
  bool _draining = false;

  /// Snapshot of pending ops (read-only view used by callers to overlay
  /// optimistic state on freshly fetched bookmark lists).
  Future<List<InstapaperSyncOp>> pendingOps() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_kQueueKey));
  }

  /// Enqueue a progress update and try to drain immediately.
  Future<void> enqueueProgress({
    required int bookmarkId,
    required double progress,
    int? timestampSeconds,
  }) {
    final ts =
        timestampSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    return _serialise(() async {
      await _mutate((ops) {
        // Drop any existing progress op for this bookmark — keep latest only.
        ops.removeWhere((o) => o is ProgressOp && o.bookmarkId == bookmarkId);
        // If an archive is already queued, the progress is moot.
        final archived = ops.any(
          (o) => o is ArchiveOp && o.bookmarkId == bookmarkId,
        );
        if (!archived) {
          ops.add(
            ProgressOp(
              bookmarkId: bookmarkId,
              progress: progress.clamp(0.0, 1.0),
              timestamp: ts,
            ),
          );
        }
      });
      await _drainLocked();
    });
  }

  /// Enqueue an archive op and try to drain immediately.
  Future<void> enqueueArchive({required int bookmarkId}) {
    return _serialise(() async {
      await _mutate((ops) {
        // An archive supersedes any pending progress for this bookmark.
        ops.removeWhere((o) => o.bookmarkId == bookmarkId);
        ops.add(ArchiveOp(bookmarkId: bookmarkId));
      });
      await _drainLocked();
    });
  }

  /// Drain the queue. Safe to call on auth change or app resume.
  Future<void> drain() => _serialise(_drainLocked);

  Future<void> _drainLocked() async {
    if (_draining) return;
    final client = _clientResolver();
    if (client == null) {
      appLog('instapaper-queue', 'drain skipped — no client');
      return;
    }
    _draining = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var ops = _decode(prefs.getString(_kQueueKey));
      if (ops.isEmpty) return;
      appLog('instapaper-queue', 'draining ${ops.length} op(s)');

      final remaining = <InstapaperSyncOp>[];
      for (final op in ops) {
        try {
          switch (op) {
            case ProgressOp():
              await client.updateReadProgress(
                bookmarkId: op.bookmarkId,
                progress: op.progress,
              );
            case ArchiveOp():
              await client.archiveBookmark(bookmarkId: op.bookmarkId);
          }
          appLog(
            'instapaper-queue',
            'sent ${op.runtimeType} bookmark=${op.bookmarkId}',
          );
        } on InstapaperApiException catch (e) {
          // 4xx (except auth/transient) are unrecoverable — drop.
          // For safety, retain on auth errors so re-login can flush.
          if (e.errorCode == 401 || e.errorCode == 403) {
            remaining.add(op);
            appLog(
              'instapaper-queue',
              'auth error (${e.errorCode}) — keeping op',
            );
          } else {
            appLog(
              'instapaper-queue',
              'dropping op (api ${e.errorCode}): ${e.message}',
            );
          }
        } on Object catch (e) {
          // Network / IO error — keep op for retry.
          remaining.add(op);
          appLog('instapaper-queue', 'transient error — keeping op: $e');
        }
      }

      // Persist whatever remains.
      ops = remaining;
      await prefs.setString(_kQueueKey, _encode(ops));
    } finally {
      _draining = false;
    }
  }

  Future<void> _mutate(void Function(List<InstapaperSyncOp> ops) update) async {
    final prefs = await SharedPreferences.getInstance();
    final ops = _decode(prefs.getString(_kQueueKey));
    update(ops);
    await prefs.setString(_kQueueKey, _encode(ops));
  }

  Future<void> _serialise(Future<void> Function() action) {
    final next = _chain.then((_) => action());
    _chain = next.catchError((Object _) {});
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
