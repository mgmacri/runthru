import 'dart:async';

/// Persists the local word index for a reading progress update.
typedef ReadingProgressLocalWrite =
    Future<void> Function({required String contentId, required int wordIndex});

/// Persists an Instapaper reading progress update.
typedef ReadingProgressRemoteWrite =
    Future<void> Function({required int bookmarkId, required double progress});

/// Current reading position for a content item.
class ReadingProgressSnapshot {
  /// Creates a reading progress snapshot.
  const ReadingProgressSnapshot({
    required this.contentId,
    required this.wordIndex,
    required this.totalWordCount,
    required this.progress,
    this.instapaperBookmarkId,
  });

  /// Stable app-local identity for this article or document.
  final String contentId;

  /// Current zero-based word index in the full document.
  final int wordIndex;

  /// Total number of words in the full document.
  final int totalWordCount;

  /// Current reading progress in the range 0.0 to 1.0.
  final double progress;

  /// Instapaper bookmark ID when this content came from Instapaper.
  final int? instapaperBookmarkId;

  /// Whether this snapshot should be synced to Instapaper.
  bool get isInstapaper => instapaperBookmarkId != null;

  ReadingProgressSnapshot get _normalised {
    final maxIndex = totalWordCount <= 0 ? 0 : totalWordCount - 1;
    return ReadingProgressSnapshot(
      contentId: contentId,
      wordIndex: wordIndex.clamp(0, maxIndex),
      totalWordCount: totalWordCount,
      progress: progress.clamp(0.0, 1.0),
      instapaperBookmarkId: instapaperBookmarkId,
    );
  }
}

/// Coalesces reading progress writes for Instapaper-backed reading sessions.
///
/// The reading timer can advance many times per second. This class keeps only
/// the latest pending progress per article, writes local bookmark state before
/// remote sync, and exposes [flush] for exit and lifecycle events.
class ReadingProgressSync {
  /// Creates a progress sync helper.
  ReadingProgressSync({
    required ReadingProgressLocalWrite writeLocalProgress,
    required ReadingProgressRemoteWrite writeRemoteProgress,
    Duration minWriteInterval = const Duration(seconds: 4),
    double minProgressDelta = 0.01,
    DateTime Function()? now,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _writeLocalProgress = writeLocalProgress,
       _writeRemoteProgress = writeRemoteProgress,
       _minWriteInterval = minWriteInterval,
       _minProgressDelta = minProgressDelta,
       _now = now ?? DateTime.now,
       _onError = onError;

  final ReadingProgressLocalWrite _writeLocalProgress;
  final ReadingProgressRemoteWrite _writeRemoteProgress;
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
  ///
  /// Non-Instapaper content is ignored; existing local bookmark persistence
  /// continues to own normal document progress.
  void record(ReadingProgressSnapshot snapshot) {
    if (!snapshot.isInstapaper) return;

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

  /// Flush pending progress for one article, or all pending articles.
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
        previous.progress == next.progress &&
        previous.instapaperBookmarkId == next.instapaperBookmarkId;
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
      _lastPersisted[contentId] = snapshot;
      _lastWriteAt[contentId] = _now();

      final bookmarkId = snapshot.instapaperBookmarkId;
      if (bookmarkId != null) {
        await _writeRemoteProgress(
          bookmarkId: bookmarkId,
          progress: snapshot.progress,
        );
      }
    } on Object catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    }
  }
}
