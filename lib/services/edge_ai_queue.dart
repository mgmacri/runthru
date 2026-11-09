/// Durable background queue for on-device model work (Phase 7 plumbing).
///
/// Same shape as `InstapaperSyncQueue` — the proven integration pattern:
/// requests are persisted on enqueue, coalesced per (book, section, task),
/// and drained against a [ModelProcessor]. Transient failures keep the
/// request for retry; permanent ones drop it with a log line.
///
/// **No models ship yet.** The wired processor is [NoopModelProcessor].
/// Adding on-device summarization later means:
///  1. implement [ModelProcessor],
///  2. swap it into [edgeAiQueueProvider],
///  3. results land in `SectionMetadata.modelAnnotations` via
///     [ContentStore.annotateSection].
/// Nothing in the reading engine changes — Ring 1 only ever *reads*
/// annotations if they exist.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/services/content_store/content_store.dart';
import 'package:runthru/services/content_store/section_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kQueueKey = 'edge_ai_queue_v1';

/// A unit of model work: one task over one section.
class SectionProcessingRequest {
  /// Creates a request.
  const SectionProcessingRequest({
    required this.bookId,
    required this.sectionIndex,
    required this.task,
  });

  /// Parses from JSON; null when malformed.
  static SectionProcessingRequest? fromJson(Map<String, Object?> json) {
    final bookId = json['bookId'] as String?;
    final sectionIndex = json['sectionIndex'] as int?;
    final task = json['task'] as String?;
    if (bookId == null || sectionIndex == null || task == null) return null;
    return SectionProcessingRequest(
      bookId: bookId,
      sectionIndex: sectionIndex,
      task: task,
    );
  }

  /// Content hash of the target book.
  final String bookId;

  /// Target section.
  final int sectionIndex;

  /// Task identifier, e.g. `summarize`, `difficulty`.
  final String task;

  /// Coalescing key — one pending request per (book, section, task).
  String get key => '$bookId#$sectionIndex#$task';

  /// Serialises to JSON.
  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'sectionIndex': sectionIndex,
    'task': task,
  };
}

/// Thrown by a [ModelProcessor] for failures worth retrying (model still
/// downloading, device busy). Anything else thrown is treated as permanent
/// and the request is dropped.
class RetryableModelException implements Exception {
  /// Creates a retryable failure.
  const RetryableModelException(this.message);

  /// Diagnostic message.
  final String message;

  @override
  String toString() => 'RetryableModelException: $message';
}

/// The on-device model boundary. Inputs and outputs are plain serialisable
/// data — a [Section] in, an annotations map out — so implementations can
/// run in isolates or against platform ML APIs without the full document
/// in scope.
abstract interface class ModelProcessor {
  /// Processes [section] for [request.task]. Returns annotations to merge
  /// into the section's `modelAnnotations`, or null for "nothing to write".
  Future<Map<String, Object?>?> process(
    SectionProcessingRequest request,
    Section section,
  );
}

/// Placeholder processor — does nothing, successfully.
class NoopModelProcessor implements ModelProcessor {
  /// Creates the no-op processor.
  const NoopModelProcessor();

  @override
  Future<Map<String, Object?>?> process(
    SectionProcessingRequest request,
    Section section,
  ) async => null;
}

/// Persistent, coalescing queue feeding sections to a [ModelProcessor].
class EdgeAiQueue {
  /// Creates the queue.
  EdgeAiQueue({
    required ContentStore store,
    ModelProcessor processor = const NoopModelProcessor(),
  }) : _store = store,
       _processor = processor;

  final ContentStore _store;
  final ModelProcessor _processor;
  Future<void> _chain = Future<void>.value();
  bool _draining = false;

  static const String _tag = 'edge_ai_queue';

  /// Snapshot of pending requests.
  Future<List<SectionProcessingRequest>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_kQueueKey));
  }

  /// Enqueues [request] (coalescing duplicates) and drains.
  Future<void> enqueue(SectionProcessingRequest request) {
    return _serialise(() async {
      final prefs = await SharedPreferences.getInstance();
      final ops = _decode(prefs.getString(_kQueueKey));
      ops.removeWhere((op) => op.key == request.key);
      ops.add(request);
      await prefs.setString(_kQueueKey, _encode(ops));
      await _drainLocked();
    });
  }

  /// Drains the queue. Safe to call on app resume.
  Future<void> drain() => _serialise(_drainLocked);

  Future<void> _drainLocked() async {
    if (_draining) return;
    _draining = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ops = _decode(prefs.getString(_kQueueKey));
      if (ops.isEmpty) return;

      final remaining = <SectionProcessingRequest>[];
      for (final op in ops) {
        try {
          final section = await _store.getSection(op.bookId, op.sectionIndex);
          if (section == null) {
            // Section evicted or book gone — droppable, not retryable.
            appLog(_tag, 'dropping ${op.key}: section unavailable');
            continue;
          }
          final annotations = await _processor.process(op, section);
          if (annotations != null && annotations.isNotEmpty) {
            await _store.annotateSection(
              op.bookId,
              op.sectionIndex,
              annotations,
            );
          }
        } on RetryableModelException catch (e) {
          remaining.add(op);
          appLog(_tag, 'retaining ${op.key}: $e');
        } on Object catch (e) {
          appLog(_tag, 'dropping ${op.key}: permanent failure $e');
        }
      }
      await prefs.setString(_kQueueKey, _encode(remaining));
    } on Object catch (e) {
      appLog(_tag, 'drain failed: $e');
    } finally {
      _draining = false;
    }
  }

  Future<void> _serialise(Future<void> Function() action) {
    final next = _chain.then((_) => action());
    _chain = next.catchError((Object _) {});
    return next;
  }

  static List<SectionProcessingRequest> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, Object?>>()
          .map(SectionProcessingRequest.fromJson)
          .whereType<SectionProcessingRequest>()
          .toList();
    } on FormatException {
      return [];
    }
  }

  static String _encode(List<SectionProcessingRequest> ops) =>
      jsonEncode(ops.map((o) => o.toJson()).toList());
}

/// App-wide edge AI queue. Swap [NoopModelProcessor] for a real
/// implementation to ship a model — nothing else changes.
final edgeAiQueueProvider = Provider<EdgeAiQueue>((ref) {
  return EdgeAiQueue(store: ref.watch(contentStoreProvider));
});
