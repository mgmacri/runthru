/// Riverpod provider managing per-item reading progress across all sources.
///
/// This is the single source of truth for the Continue Reading shelf and
/// for resume-on-open in the reader. Progress is keyed by a stable [contentId]
/// (e.g. a file path or `instapaper://<bookmarkId>`) so it survives re-syncs.
library;

import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'reading_progress_provider.g.dart';

const _progressKey = 'runthru_reading_progress';

/// A single item's reading progress record.
class ProgressRecord {
  /// Creates a progress record.
  const ProgressRecord({
    required this.contentId,
    required this.source,
    required this.title,
    required this.wordIndex,
    required this.totalWords,
    required this.lastReadAt,
    this.finished = false,
    this.contentHash,
  });

  /// Reconstructs a record from JSON (SharedPreferences).
  factory ProgressRecord.fromJson(Map<String, Object?> json) {
    return ProgressRecord(
      contentId: json['contentId'] as String? ?? '',
      source: json['source'] as String? ?? 'local',
      title: json['title'] as String? ?? '',
      wordIndex: json['wordIndex'] as int? ?? 0,
      totalWords: json['totalWords'] as int? ?? 0,
      lastReadAt: json['lastReadAt'] != null
          ? DateTime.parse(json['lastReadAt'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
      finished: json['finished'] as bool? ?? false,
      contentHash: json['contentHash'] as String?,
    );
  }

  /// Stable content identifier (file path, `instapaper://<id>`, etc.).
  final String contentId;

  /// Source label: `'local'`, `'instapaper'`, `'drive'`, etc.
  final String source;

  /// Human-readable title shown on the Continue Reading shelf.
  final String title;

  /// Current word offset into the normalised word list.
  final int wordIndex;

  /// Total word count (denominator for percent).
  final int totalWords;

  /// When progress was last updated (drives shelf ordering).
  final DateTime lastReadAt;

  /// True when the item has been read to completion.
  final bool finished;

  /// Content hash of the underlying book — survives re-imports that change
  /// the path-based [contentId].
  final String? contentHash;

  /// Reading progress 0.0–1.0.
  double get percent =>
      totalWords > 0 ? (wordIndex / totalWords).clamp(0.0, 1.0) : 0.0;

  /// Whole percent for display. An item that has been started never shows
  /// 0 and one that is not finished never shows 100: "0" beside a book in
  /// Continue Reading and "100" beside one still on the shelf both read as
  /// mistakes.
  int get displayPercent {
    if (finished) return 100;
    if (totalWords <= 0 || wordIndex <= 0) return 0;
    return (percent * 100).round().clamp(1, 99);
  }

  /// Approximate minutes remaining at 238 wpm average.
  int get minutesLeft => minutesLeftAt(238);

  /// Approximate minutes remaining at [wpm] words a minute: the reader's
  /// own speed, so the Library agrees with the figure in the reader.
  int minutesLeftAt(int wpm) {
    final wordsLeft = (totalWords - wordIndex).clamp(0, totalWords);
    return (wordsLeft / wpm.clamp(30, 1500)).ceil();
  }

  /// Returns a copy with the given fields replaced.
  ProgressRecord copyWith({
    String? contentId,
    String? source,
    String? title,
    int? wordIndex,
    int? totalWords,
    DateTime? lastReadAt,
    bool? finished,
    String? contentHash,
  }) {
    return ProgressRecord(
      contentId: contentId ?? this.contentId,
      source: source ?? this.source,
      title: title ?? this.title,
      wordIndex: wordIndex ?? this.wordIndex,
      totalWords: totalWords ?? this.totalWords,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      finished: finished ?? this.finished,
      contentHash: contentHash ?? this.contentHash,
    );
  }

  /// Serialises to JSON for SharedPreferences.
  Map<String, Object?> toJson() => {
    'contentId': contentId,
    'source': source,
    'title': title,
    'wordIndex': wordIndex,
    'totalWords': totalWords,
    'lastReadAt': lastReadAt.toIso8601String(),
    'finished': finished,
    'contentHash': contentHash,
  };
}

/// Notifier managing the per-item progress store.
///
/// Persists to SharedPreferences as a JSON list. All mutations are
/// synchronised to prevent concurrent read-modify-write data loss.
///
/// TODO(background-sync): Reconcile Instapaper items against the server-side
/// `progress` / `progress_timestamp` fields when background sync lands.
/// Local store is authoritative for now; last-write-wins with the server
/// timestamp as the tiebreaker once reconciliation is implemented.
@riverpod
class ReadingProgress extends _$ReadingProgress {
  @override
  Future<List<ProgressRecord>> build() => _load();

  /// Records (or updates) progress for [contentId].
  ///
  /// If [totalWords] changed since the last record, [wordIndex] is clamped to
  /// the new total to prevent an out-of-range position.
  ///
  /// [finished] marks the item as read to the end at [wordIndex]. A later
  /// write keeps that mark for as long as the reader has only gone on from
  /// there (the notes after the story); going back into the text makes it
  /// an item in progress again.
  ///
  /// [lastReadAt] is exposed for testing; in production it defaults to now.
  /// Maximum retained records — oldest (by [ProgressRecord.lastReadAt])
  /// are evicted beyond this, so the store never grows without bound.
  static const int maxRecords = 500;

  Future<void> record({
    required String contentId,
    required String source,
    required String title,
    required int wordIndex,
    required int totalWords,
    DateTime? lastReadAt,
    String? contentHash,
    bool finished = false,
  }) async {
    // Collapse any pre-existing duplicates (legacy persisted data or a
    // concurrent write that landed before this call) into a single entry per
    // contentId, then upsert this one. This is the single point that keeps the
    // store free of duplicate shelf items.
    final byId = _indexByContentId(state.valueOrNull ?? const []);
    // Identity rule: the same content re-imported under a new path keeps a
    // single record — drop entries that match by content hash.
    if (contentHash != null) {
      byId.removeWhere(
        (key, value) => key != contentId && value.contentHash == contentHash,
      );
    }
    final clampedWord = wordIndex.clamp(0, totalWords);
    final existing = byId[contentId];
    final stillFinished =
        existing != null &&
        existing.finished &&
        clampedWord >= existing.wordIndex;
    byId[contentId] = ProgressRecord(
      contentId: contentId,
      source: source,
      title: title,
      wordIndex: clampedWord,
      totalWords: totalWords,
      lastReadAt: lastReadAt ?? DateTime.now(),
      finished: finished || stillFinished,
      contentHash: contentHash ?? existing?.contentHash,
    );

    var records = byId.values.toList();
    if (records.length > maxRecords) {
      records.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
      records = records.take(maxRecords).toList();
    }
    state = AsyncData(records);
    await _persist(records);
  }

  /// Removes local-source records whose path is gone from every source and
  /// whose content hash is no longer active (source-removal cleanup).
  /// Remote sources are untouched. Returns the number pruned.
  Future<int> pruneMissingLocal({
    required Set<String> activePaths,
    required Set<String> activeHashes,
  }) async {
    final records = state.valueOrNull ?? const <ProgressRecord>[];
    final kept = records.where((r) {
      if (r.source != 'local') return true;
      if (activePaths.contains(r.contentId)) return true;
      final hash = r.contentHash;
      return hash != null && activeHashes.contains(hash);
    }).toList();
    final pruned = records.length - kept.length;
    if (pruned > 0) {
      state = AsyncData(kept);
      await _persist(kept);
    }
    return pruned;
  }

  /// Marks the item as finished; removes it from the Continue Reading shelf.
  Future<void> markFinished(String contentId) async {
    final byId = _indexByContentId(state.valueOrNull ?? const []);
    final existing = byId[contentId];
    if (existing == null) return;
    byId[contentId] = existing.copyWith(finished: true);
    final records = byId.values.toList();
    state = AsyncData(records);
    await _persist(records);
  }

  /// Returns the progress record for [contentId], or null if not found.
  ProgressRecord? getRecord(String contentId) {
    return state.valueOrNull
        ?.where((r) => r.contentId == contentId)
        .firstOrNull;
  }

  /// Items in progress (not finished, wordIndex > 0), most-recent first,
  /// capped at 10 — drives the Continue Reading shelf.
  List<ProgressRecord> get shelf {
    // First dedupe by contentId (handles stale duplicate writes).
    final unique = _indexByContentId(state.valueOrNull ?? const []).values;
    final filtered =
        unique.where((r) => !r.finished && r.wordIndex > 0).toList()
          ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    // Second-pass dedupe local files by normalised title — prevents the same
    // book appearing twice when it was imported from two different paths.
    // Remote sources keep their stable contentId because identical titles can
    // represent distinct Drive files, Instapaper items, or local books.
    final seenLocalTitles = <String>{};
    final deduped = filtered.where((r) {
      if (r.source != 'local') return true;
      return seenLocalTitles.add(r.title.trim().toLowerCase());
    }).toList();
    return deduped.take(10).toList();
  }

  /// Indexes records by [ProgressRecord.contentId], keeping the most recently
  /// read instance when duplicates are present. Insertion order follows the
  /// kept record's first appearance, which is irrelevant to callers that sort.
  static Map<String, ProgressRecord> _indexByContentId(
    List<ProgressRecord> records,
  ) {
    final byId = <String, ProgressRecord>{};
    for (final record in records) {
      final existing = byId[record.contentId];
      if (existing == null ||
          !record.lastReadAt.isBefore(existing.lastReadAt)) {
        byId[record.contentId] = record;
      }
    }
    return byId;
  }

  Future<List<ProgressRecord>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<Object?>;
      final parsed = list
          .whereType<Map<String, Object?>>()
          .map(ProgressRecord.fromJson)
          .toList();
      // Heal any duplicates written by older builds before they reach the UI.
      return _indexByContentId(parsed).values.toList();
    } on Object {
      return [];
    }
  }

  Future<void> _persist(List<ProgressRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _progressKey,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }
}
