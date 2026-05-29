import 'dart:async';

/// Persists the local word index for a reading progress update.
typedef ReadingProgressLocalWrite =
    Future<void> Function({required String contentId, required int wordIndex});

/// Persists a source-specific remote reading progress update.
typedef ReadingProgressRemoteWrite =
    Future<void> Function(ReadingProgressSnapshot snapshot);

/// Persists an Instapaper reading progress update.
typedef InstapaperReadingProgressWrite =
    Future<void> Function({required int bookmarkId, required double progress});

/// Current reading position for a content item.
class ReadingProgressSnapshot {
  /// Creates a reading progress snapshot.
  const ReadingProgressSnapshot({
    required this.contentId,
    required this.wordIndex,
    required this.totalWordCount,
    required this.progress,
  });

  /// Stable app-local identity for this article or document.
  final String contentId;

  /// Current zero-based word index in the full document.
  final int wordIndex;

  /// Total number of words in the full document.
  final int totalWordCount;

  /// Current reading progress in the range 0.0 to 1.0.
  final double progress;

  ReadingProgressSnapshot get _normalised {
    final maxIndex = totalWordCount <= 0 ? 0 : totalWordCount - 1;
    return ReadingProgressSnapshot(
      contentId: contentId,
      wordIndex: wordIndex.clamp(0, maxIndex),
      totalWordCount: totalWordCount,
      progress: progress.clamp(0.0, 1.0),
    );
  }
}

/// Strategy for source-specific remote progress writes.
abstract interface class ReadingProgressRemoteWriter {
  /// Writes the latest remote progress represented by [snapshot].
  Future<void> write(ReadingProgressSnapshot snapshot);
}

/// Adapts a callback to [ReadingProgressRemoteWriter].
final class CallbackReadingProgressRemoteWriter
    implements ReadingProgressRemoteWriter {
  /// Creates a remote writer backed by [write].
  const CallbackReadingProgressRemoteWriter(ReadingProgressRemoteWrite write)
    : _write = write;

  final ReadingProgressRemoteWrite _write;

  @override
  Future<void> write(ReadingProgressSnapshot snapshot) => _write(snapshot);
}

/// Remote writer preserving Instapaper reading-progress behavior.
final class InstapaperReadingProgressRemoteWriter
    implements ReadingProgressRemoteWriter {
  /// Creates an Instapaper progress writer for one bookmark.
  const InstapaperReadingProgressRemoteWriter({
    required this.bookmarkId,
    required this.writeProgress,
  });

  /// Stable Instapaper bookmark ID for the active reading session.
  final int bookmarkId;

  /// Instapaper progress callback.
  final InstapaperReadingProgressWrite writeProgress;

  @override
  Future<void> write(ReadingProgressSnapshot snapshot) {
    return writeProgress(bookmarkId: bookmarkId, progress: snapshot.progress);
  }
}

/// Coalesces source-agnostic reading progress writes.
///
/// The reading timer can advance many times per second. This class keeps only
/// the latest pending progress per content item, writes local progress before
/// optional remote sync, and exposes [flush] for exit and lifecycle events.
class ReadingProgressSync {
  /// Creates a progress sync helper.
  ReadingProgressSync({
    required ReadingProgressLocalWrite writeLocalProgress,
    ReadingProgressRemoteWriter? remoteWriter,
    Duration minWriteInterval = const Duration(seconds: 4),
    double minProgressDelta = 0.01,
    DateTime Function()? now,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _writeLocalProgress = writeLocalProgress,
       _remoteWriter = remoteWriter,
       _minWriteInterval = minWriteInterval,
       _minProgressDelta = minProgressDelta,
       _now = now ?? DateTime.now,
       _onError = onError;

  final ReadingProgressLocalWrite _writeLocalProgress;
  final ReadingProgressRemoteWriter? _remoteWriter;
  final Duration _minWriteInterval;
  final double _minProgressDelta;
  final DateTime Function() _now;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  final Map<String, ReadingProgressSnapshot> _pending = {};
  final Map<String, ReadingProgressSnapshot> _lastPersisted = {};
  final Map<String, DateTime> _lastWriteAt = {};
  final Map<String, Timer> _timers = {};
  final Map<String, Future<void>> _chains = {};

  /// Record the latest reading progress for a content item.
  void record(ReadingProgressSnapshot snapshot) {
    final normalised = snapshot._normalised;
    if (_isExactDuplicate(normalised, _pending[normalised.contentId]) ||
        _isExactDuplicate(normalised, _lastPersisted[normalised.contentId])) {
      return;
    }

    _pending[normalised.contentId] = normalised;

    if (_shouldWriteNow(normalised)) {
      _timers.remove(normalised.contentId)?.cancel();
      unawaited(_flushContent(normalised.contentId, force: false));
      return;
    }

    _schedule(normalised.contentId);
  }

  /// Flush pending progress for one content item, or all pending content items.
  Future<void> flush({String? contentId}) async {
    if (contentId != null) {
      _timers.remove(contentId)?.cancel();
      await _flushContent(contentId, force: true);
      return;
    }

    final ids = _pending.keys.toList(growable: false);
    for (final id in ids) {
      _timers.remove(id)?.cancel();
      await _flushContent(id, force: true);
    }
  }

  /// Cancel scheduled background writes.
  void cancelTimers() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  /// Flush pending writes and cancel scheduled timers.
  Future<void> dispose() async {
    cancelTimers();
    await flush();
  }

  bool _shouldWriteNow(ReadingProgressSnapshot snapshot) {
    final last = _lastPersisted[snapshot.contentId];
    if (last == null) return true;
    if (!_hasMeaningfulProgressChange(snapshot, last)) return false;

    final lastAt = _lastWriteAt[snapshot.contentId];
    return lastAt == null || _now().difference(lastAt) >= _minWriteInterval;
  }

  bool _shouldWrite(ReadingProgressSnapshot snapshot, {required bool force}) {
    final last = _lastPersisted[snapshot.contentId];
    if (last == null) return true;
    if (_isExactDuplicate(snapshot, last)) return false;
    return force || _hasMeaningfulProgressChange(snapshot, last);
  }

  bool _hasMeaningfulProgressChange(
    ReadingProgressSnapshot next,
    ReadingProgressSnapshot previous,
  ) {
    if (next.wordIndex == previous.wordIndex) return false;
    return (next.progress - previous.progress).abs() >= _minProgressDelta;
  }

  bool _isExactDuplicate(
    ReadingProgressSnapshot next,
    ReadingProgressSnapshot? previous,
  ) {
    return previous != null &&
        previous.wordIndex == next.wordIndex &&
        previous.progress == next.progress;
  }

  void _schedule(String contentId) {
    if (_timers.containsKey(contentId)) return;

    final lastAt = _lastWriteAt[contentId];
    final delay = lastAt == null
        ? _minWriteInterval
        : _minWriteInterval - _now().difference(lastAt);
    _timers[contentId] = Timer(delay.isNegative ? Duration.zero : delay, () {
      _timers.remove(contentId);
      unawaited(_flushContent(contentId, force: false));
    });
  }

  Future<void> _flushContent(String contentId, {required bool force}) {
    final previous = _chains[contentId] ?? Future<void>.value();
    final next = previous.then((_) => _runFlush(contentId, force: force));
    _chains[contentId] = next.catchError((Object _) {});
    return next;
  }

  Future<void> _runFlush(String contentId, {required bool force}) async {
    final snapshot = _pending[contentId];
    if (snapshot == null) return;
    if (!_shouldWrite(snapshot, force: force)) {
      _pending.remove(contentId);
      return;
    }

    _pending.remove(contentId);

    try {
      await _writeLocalProgress(
        contentId: snapshot.contentId,
        wordIndex: snapshot.wordIndex,
      );
    } on Object catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
      return;
    }

    _lastPersisted[contentId] = snapshot;
    _lastWriteAt[contentId] = _now();

    final remoteWriter = _remoteWriter;
    if (remoteWriter == null) return;

    try {
      await remoteWriter.write(snapshot);
    } on Object catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    }
  }
}
