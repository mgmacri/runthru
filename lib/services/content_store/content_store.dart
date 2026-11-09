/// Ring 2 — the content store.
///
/// The only sanctioned way for anything (reader, range picker, future
/// on-device models) to obtain book text. Callers hand in a `bookId`
/// (content hash) and get back bounded [Section] windows; they never see
/// file paths, cache keys, gzip, or extraction.
///
/// Layout:
///   <appSupport>/content_store/index.json                 (LRU index)
///   <appSupport>/content_store/<bookId>/manifest.json     (BookMetadata)
///   <appSupport>/content_store/<bookId>/section_0000.json.gz
///
/// Writing order is sections first, manifest last — manifest presence marks
/// a fully ingested book, so a crash mid-write never yields a half-readable
/// book and re-running ingestion is idempotent.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/services/book_identity.dart';
import 'package:runthru/services/content_store/section_models.dart';
import 'package:runthru/services/models.dart';

/// Sectioned, lazy, content-hash-keyed store for extracted book text.
class ContentStore {
  /// Creates a store. [rootResolver] is injectable for tests; production
  /// resolves to `<appSupport>/content_store`.
  ContentStore({
    Future<String?> Function()? rootResolver,
    int memorySectionCap = 6,
  }) : _rootResolver = rootResolver ?? _defaultRoot,
       _memorySectionCap = memorySectionCap;

  final Future<String?> Function() _rootResolver;

  /// Max sections held in memory across all books (LRU).
  final int _memorySectionCap;

  /// In-memory section LRU. Insertion order = recency (oldest first).
  final _memory = <String, Section>{};

  /// Serialises index writes.
  Future<void> _chain = Future<void>.value();

  static const String _tag = 'content_store';

  static Future<String?> _defaultRoot() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      return '${appDir.path}/content_store';
    } on Object {
      return null;
    }
  }

  Future<String?> _root() async {
    final root = await _rootResolver();
    if (root == null) return null;
    try {
      final dir = Directory(root);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return root;
    } on FileSystemException {
      return null;
    }
  }

  Future<String?> _bookDir(String bookId) async {
    final root = await _root();
    if (root == null || bookId.isEmpty) return null;
    return '$root/$bookId';
  }

  static String _sectionFileName(int index) =>
      'section_${index.toString().padLeft(4, '0')}.json.gz';

  // ── Reads ──────────────────────────────────────────────────────────

  /// Lightweight metadata — never loads text.
  Future<BookMetadata?> getMetadata(String bookId) async {
    final dir = await _bookDir(bookId);
    if (dir == null) return null;
    try {
      final file = File('$dir/manifest.json');
      if (!file.existsSync()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return BookMetadata.fromJson(json);
    } on Object catch (e) {
      appLog(_tag, 'manifest read failed book=$bookId: $e');
      return null;
    }
  }

  /// Number of sections — never loads text.
  Future<int> getSectionCount(String bookId) async {
    return (await getMetadata(bookId))?.totalSections ?? 0;
  }

  /// Whether [bookId] is fully ingested (manifest present).
  Future<bool> hasBook(String bookId) async {
    final dir = await _bookDir(bookId);
    if (dir == null) return false;
    return File('$dir/manifest.json').existsSync();
  }

  /// One bounded word window, from memory LRU, then disk. Null when the
  /// book is unknown or the section file was evicted (callers fall back to
  /// re-extraction through Ring 3).
  Future<Section?> getSection(String bookId, int sectionIndex) async {
    final memKey = '$bookId#$sectionIndex';
    final hit = _memory.remove(memKey);
    if (hit != null) {
      _memory[memKey] = hit; // re-insert = touch
      return hit;
    }

    final dir = await _bookDir(bookId);
    if (dir == null) return null;
    final file = File('$dir/${_sectionFileName(sectionIndex)}');
    if (!file.existsSync()) return null;

    try {
      final bytes = await file.readAsBytes();
      final section = await Isolate.run(() {
        final json =
            jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, Object?>;
        return Section.fromJson(json);
      });
      _memory[memKey] = section;
      while (_memory.length > _memorySectionCap) {
        _memory.remove(_memory.keys.first);
      }
      unawaited(touchLastRead(bookId));
      return section;
    } on Object catch (e) {
      appLog(_tag, 'section read failed book=$bookId idx=$sectionIndex: $e');
      return null;
    }
  }

  /// Fire-and-forget background load of an upcoming section into the
  /// memory LRU so the reader never waits at a section boundary.
  void prefetchSection(String bookId, int sectionIndex) {
    if (_memory.containsKey('$bookId#$sectionIndex')) return;
    unawaited(
      getSection(bookId, sectionIndex).catchError((Object e) {
        appLog(_tag, 'prefetch failed book=$bookId idx=$sectionIndex: $e');
        return null;
      }),
    );
  }

  /// Assembles the full document from sections. Session-scoped use only —
  /// this is O(book), not O(section); background code must use [getSection].
  Future<ExtractedDocument?> getDocument(String bookId) async {
    final meta = await getMetadata(bookId);
    if (meta == null) return null;
    final sentences = <Sentence>[];
    for (var i = 0; i < meta.totalSections; i++) {
      final section = await getSection(bookId, i);
      if (section == null) {
        appLog(_tag, 'getDocument missing section book=$bookId idx=$i');
        return null; // partially evicted — caller re-extracts
      }
      sentences.addAll(section.sentences);
    }
    return ExtractedDocument(
      sentences: sentences,
      pageBoundaries: meta.pageBoundaries,
      totalPages: meta.totalPages,
    );
  }

  /// Opens a forward iterator at [sectionIndex] — the shape a future
  /// SummarizationService walks a book with.
  Future<SectionCursor?> openCursor(String bookId, int sectionIndex) async {
    final section = await getSection(bookId, sectionIndex);
    if (section == null) return null;
    prefetchSection(bookId, sectionIndex + 1);
    return SectionCursor(store: this, bookId: bookId, section: section);
  }

  /// Merges [annotations] into the stored section's `modelAnnotations`
  /// (edge AI output path). The section file is rewritten; readers see the
  /// annotations on their next load.
  Future<bool> annotateSection(
    String bookId,
    int sectionIndex,
    Map<String, Object?> annotations,
  ) async {
    final dir = await _bookDir(bookId);
    if (dir == null) return false;
    final section = await getSection(bookId, sectionIndex);
    if (section == null) return false;
    final updated = Section(
      sentences: section.sentences,
      meta: section.meta.withAnnotations(annotations),
    );
    try {
      final bytes = await Isolate.run(
        () => gzip.encode(utf8.encode(jsonEncode(updated.toJson()))),
      );
      await File('$dir/${_sectionFileName(sectionIndex)}').writeAsBytes(bytes);
      _memory['$bookId#$sectionIndex'] = updated;
      return true;
    } on Object catch (e) {
      appLog(_tag, 'annotate failed book=$bookId idx=$sectionIndex: $e');
      return false;
    }
  }

  // ── Ingestion (Ring 3 → Ring 2) ───────────────────────────────────

  /// Persists an extracted document under its identity. Idempotent: a book
  /// whose manifest already exists at the current schema version is skipped.
  Future<void> putDocument(BookIdentity identity, ExtractedDocument doc) async {
    if (identity.isProvisional) {
      appLog(_tag, 'refusing provisional identity ${identity.contentHash}');
      return;
    }
    final dir = await _bookDir(identity.contentHash);
    if (dir == null) return;

    final existing = await getMetadata(identity.contentHash);
    if (existing != null &&
        existing.schemaVersion == kContentStoreSchemaVersion &&
        existing.totalSentences == doc.sentences.length) {
      return; // already ingested
    }

    try {
      final sizeBytes = await Isolate.run(
        () => writeBookSync(dir, identity, doc),
      );
      await _updateIndex(
        identity.contentHash,
        (e) => _IndexEntry(lastReadAt: DateTime.now(), sizeBytes: sizeBytes),
      );
      // Drop stale in-memory sections for this book.
      _memory.removeWhere((k, _) => k.startsWith('${identity.contentHash}#'));
      appLog(_tag, 'ingested book=${identity.displayName} bytes=$sizeBytes');
    } on Object catch (e) {
      appLog(_tag, 'ingest failed book=${identity.displayName}: $e');
    }
  }

  /// Splits [doc] into sentence-aligned sections of ~[kSectionTargetWords]
  /// words. Pure — safe to call anywhere.
  static List<Section> splitIntoSections(ExtractedDocument doc) {
    final sections = <Section>[];
    var sentenceCursor = 0;
    var wordCursor = 0;
    while (sentenceCursor < doc.sentences.length) {
      final startSentence = sentenceCursor;
      final startWord = wordCursor;
      var words = 0;
      while (sentenceCursor < doc.sentences.length &&
          words < kSectionTargetWords) {
        words += doc.sentences[sentenceCursor].words.length;
        sentenceCursor++;
      }
      wordCursor += words;
      sections.add(
        Section(
          sentences: doc.sentences.sublist(startSentence, sentenceCursor),
          meta: SectionMetadata(
            sectionIndex: sections.length,
            startWordIndex: startWord,
            startSentenceIndex: startSentence,
            wordCount: words,
            startPage: _pageAtSentence(doc.pageBoundaries, startSentence),
            endPage: _pageAtSentence(doc.pageBoundaries, sentenceCursor - 1),
          ),
        ),
      );
    }
    return sections;
  }

  static int _pageAtSentence(List<PageBoundary> boundaries, int sentenceIdx) {
    var page = -1;
    for (final b in boundaries) {
      if (b.startSentenceIndex <= sentenceIdx) {
        page = b.pageNumber;
      } else {
        break;
      }
    }
    return page;
  }

  /// Synchronous full-book write — call inside an isolate. Sections are
  /// written before the manifest so a crash never leaves a "complete" book
  /// with missing text. Returns bytes written.
  static int writeBookSync(
    String dirPath,
    BookIdentity identity,
    ExtractedDocument doc,
  ) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final sections = splitIntoSections(doc);
    var total = 0;
    for (final section in sections) {
      final bytes = gzip.encode(utf8.encode(jsonEncode(section.toJson())));
      File(
        '$dirPath/${_sectionFileName(section.meta.sectionIndex)}',
      ).writeAsBytesSync(bytes);
      total += bytes.length;
    }

    final manifest = BookMetadata(
      bookId: identity.contentHash,
      displayName: identity.displayName,
      sourceId: identity.sourceId,
      totalWords: doc.totalWords,
      totalSentences: doc.sentences.length,
      totalSections: sections.length,
      totalPages: doc.totalPages,
      pageBoundaries: doc.pageBoundaries,
    );
    final manifestBytes = utf8.encode(jsonEncode(manifest.toJson()));
    File('$dirPath/manifest.json').writeAsBytesSync(manifestBytes);
    return total + manifestBytes.length;
  }

  // ── Budget / index ─────────────────────────────────────────────────

  /// Marks [bookId] as read now (drives LRU eviction order).
  Future<void> touchLastRead(String bookId) {
    return _updateIndex(
      bookId,
      (e) =>
          _IndexEntry(lastReadAt: DateTime.now(), sizeBytes: e?.sizeBytes ?? 0),
    );
  }

  /// Total bytes used by the store.
  Future<int> totalUsageBytes() async {
    final root = await _root();
    if (root == null) return 0;
    try {
      return await Isolate.run(() {
        var total = 0;
        final dir = Directory(root);
        if (!dir.existsSync()) return 0;
        for (final f in dir.listSync(recursive: true)) {
          if (f is File) {
            try {
              total += f.lengthSync();
            } on FileSystemException {
              // skip
            }
          }
        }
        return total;
      });
    } on Object {
      return 0;
    }
  }

  /// Evicts section files of the least-recently-read books until usage is
  /// at most [budgetBytes] minus [reservedBytes] (bytes other caches under
  /// the same policy already use). Manifests survive eviction so metadata
  /// keeps working; evicted text re-extracts on demand.
  Future<void> enforceBudget(int budgetBytes, {int reservedBytes = 0}) async {
    final root = await _root();
    if (root == null) return;
    final effective = (budgetBytes - reservedBytes).clamp(0, budgetBytes);
    final index = await _loadIndex();
    final order = index.entries.toList()
      ..sort((a, b) => a.value.lastReadAt.compareTo(b.value.lastReadAt));
    final lruBookIds = [for (final e in order) e.key];
    try {
      final evicted = await Isolate.run(
        () => _evictSync(root, effective, lruBookIds),
      );
      if (evicted.isNotEmpty) {
        appLog(_tag, 'evicted sections of ${evicted.length} book(s)');
        _memory.removeWhere(
          (k, _) => evicted.any((id) => k.startsWith('$id#')),
        );
      }
    } on Object catch (e) {
      appLog(_tag, 'eviction failed: $e');
    }
  }

  /// Synchronous eviction — runs inside an isolate.
  static List<String> _evictSync(
    String root,
    int budgetBytes,
    List<String> lruBookIds,
  ) {
    final dir = Directory(root);
    if (!dir.existsSync()) return const [];
    var total = 0;
    for (final f in dir.listSync(recursive: true)) {
      if (f is File) {
        try {
          total += f.lengthSync();
        } on FileSystemException {
          // skip
        }
      }
    }
    if (total <= budgetBytes) return const [];

    final evicted = <String>[];
    for (final bookId in lruBookIds) {
      if (total <= budgetBytes) break;
      final bookDir = Directory('$root/$bookId');
      if (!bookDir.existsSync()) continue;
      var removed = false;
      for (final f in bookDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json.gz')) continue; // keep manifest
        try {
          final size = f.lengthSync();
          f.deleteSync();
          total -= size;
          removed = true;
        } on FileSystemException {
          // skip
        }
      }
      if (removed) evicted.add(bookId);
    }
    return evicted;
  }

  // index.json: bookId → {lastReadAt, sizeBytes}

  Future<Map<String, _IndexEntry>> _loadIndex() async {
    final root = await _root();
    if (root == null) return {};
    try {
      final file = File('$root/index.json');
      if (!file.existsSync()) return {};
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return json.map(
        (k, v) => MapEntry(k, _IndexEntry.fromJson(v as Map<String, Object?>)),
      );
    } on Object {
      return {};
    }
  }

  Future<void> _updateIndex(
    String bookId,
    _IndexEntry Function(_IndexEntry? existing) update,
  ) {
    final next = _chain.then((_) async {
      final root = await _root();
      if (root == null) return;
      try {
        final index = await _loadIndex();
        index[bookId] = update(index[bookId]);
        await File('$root/index.json').writeAsString(
          jsonEncode(index.map((k, v) => MapEntry(k, v.toJson()))),
        );
      } on Object catch (e) {
        appLog(_tag, 'index update failed: $e');
      }
    });
    _chain = next.catchError((Object _) {});
    return next;
  }
}

class _IndexEntry {
  const _IndexEntry({required this.lastReadAt, required this.sizeBytes});

  factory _IndexEntry.fromJson(Map<String, Object?> json) {
    return _IndexEntry(
      lastReadAt:
          DateTime.tryParse(json['lastReadAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sizeBytes: json['sizeBytes'] as int? ?? 0,
    );
  }

  final DateTime lastReadAt;
  final int sizeBytes;

  Map<String, Object?> toJson() => {
    'lastReadAt': lastReadAt.toIso8601String(),
    'sizeBytes': sizeBytes,
  };
}

/// Forward iterator over a book's sections with one-ahead prefetch.
/// The stable contract a future on-device summariser consumes.
class SectionCursor {
  /// Creates a cursor positioned on [section].
  SectionCursor({
    required ContentStore store,
    required this.bookId,
    required this.section,
  }) : _store = store;

  final ContentStore _store;

  /// Book being iterated.
  final String bookId;

  /// Current section payload.
  final Section section;

  /// Loads the next section (already prefetching one further ahead), or
  /// null at the end of the book / on eviction.
  Future<SectionCursor?> next() {
    return _store.openCursor(bookId, section.meta.sectionIndex + 1);
  }
}

/// App-wide content store.
final contentStoreProvider = Provider<ContentStore>((ref) => ContentStore());
