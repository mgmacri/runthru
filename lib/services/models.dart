/// Data models for the PDF pipeline.
library;

class Sentence {
  const Sentence({required this.words});

  factory Sentence.fromJson(Map<String, Object?> json) {
    final words =
        (json['words'] as List<Object?>?)?.cast<String>() ?? <String>[];
    return Sentence(words: words);
  }

  final List<String> words;

  Map<String, Object?> toJson() => {'words': words};
}

class ExtractedDocument {
  const ExtractedDocument({required this.sentences});

  factory ExtractedDocument.fromJson(Map<String, Object?> json) {
    final sentences = (json['sentences'] as List<Object?>?)
            ?.map((e) => Sentence.fromJson(e as Map<String, Object?>))
            .toList() ??
        <Sentence>[];
    return ExtractedDocument(sentences: sentences);
  }

  final List<Sentence> sentences;

  /// Total word count across all sentences.
  int get totalWords => sentences.fold(0, (sum, s) => sum + s.words.length);

  /// Flat list of all words in reading order.
  List<String> get allWords => sentences.expand((s) => s.words).toList();

  /// Append sentences from another document (used for progressive extraction).
  ExtractedDocument merge(ExtractedDocument other) {
    return ExtractedDocument(
      sentences: [...sentences, ...other.sentences],
    );
  }

  Map<String, Object?> toJson() => {
        'sentences': sentences.map((s) => s.toJson()).toList(),
      };
}

enum PdfStatus {
  pending,
  queued,
  processing,

  /// Phase 1 complete — pages 1–3 extracted, remaining pages pending.
  preview,
  ready,
  error,
  unsupported,
  permanentlyFailed,
}

/// Per-file progress tracking for chunked extraction.
class PdfProgress {
  const PdfProgress({
    this.lastCompletedPage = 0,
    this.totalPages = 0,
    this.phase = ExtractionPhase.pending,
  });

  final int lastCompletedPage;
  final int totalPages;
  final ExtractionPhase phase;

  /// 0.0–1.0 page completion ratio.
  double get fraction => totalPages > 0 ? lastCompletedPage / totalPages : 0.0;

  PdfProgress copyWith({
    int? lastCompletedPage,
    int? totalPages,
    ExtractionPhase? phase,
  }) {
    return PdfProgress(
      lastCompletedPage: lastCompletedPage ?? this.lastCompletedPage,
      totalPages: totalPages ?? this.totalPages,
      phase: phase ?? this.phase,
    );
  }
}

enum ExtractionPhase { pending, preview, backgroundCompletion, done }

class PdfEntry {
  const PdfEntry({
    required this.filePath,
    required this.fileName,
    this.status = PdfStatus.pending,
    this.document,
    this.errorMessage,
    this.retryCount = 0,
    this.progress = const PdfProgress(),
  });

  final String filePath;
  final String fileName;
  final PdfStatus status;
  final ExtractedDocument? document;
  final String? errorMessage;
  final int retryCount;
  final PdfProgress progress;

  /// Max retries before marking as permanently failed.
  static const int maxRetries = 3;

  PdfEntry copyWith({
    PdfStatus? status,
    ExtractedDocument? document,
    bool clearDocument = false,
    String? errorMessage,
    int? retryCount,
    PdfProgress? progress,
  }) {
    return PdfEntry(
      filePath: filePath,
      fileName: fileName,
      status: status ?? this.status,
      document: clearDocument ? null : (document ?? this.document),
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      progress: progress ?? this.progress,
    );
  }
}

/// Overall processing progress across all PDFs.
class OverallProgress {
  const OverallProgress({
    this.completed = 0,
    this.total = 0,
  });

  final int completed;
  final int total;

  double get percent => total > 0 ? completed / total : 0.0;
}

class UnsupportedPdfError implements Exception {
  const UnsupportedPdfError(this.message);
  final String message;
  @override
  String toString() => 'UnsupportedPdfError: $message';
}

class PdfTimeoutError implements Exception {
  const PdfTimeoutError(this.filePath);
  final String filePath;
  @override
  String toString() =>
      'PdfTimeoutError: extraction exceeded timeout for $filePath';
}

// ── Section-based persistence models (Prompt 2) ──────────────────────

/// A fixed-size chunk of sentences for lazy loading.
class SectionData {
  const SectionData({
    required this.sectionIndex,
    required this.startSentenceIndex,
    required this.sentences,
  });

  factory SectionData.fromJson(Map<String, Object?> json) {
    return SectionData(
      sectionIndex: json['sectionIndex'] as int? ?? 0,
      startSentenceIndex: json['startSentenceIndex'] as int? ?? 0,
      sentences: (json['sentences'] as List<Object?>?)
              ?.map((e) => Sentence.fromJson(e as Map<String, Object?>))
              .toList() ??
          <Sentence>[],
    );
  }

  final int sectionIndex;
  final int startSentenceIndex;
  final List<Sentence> sentences;

  int get totalWords => sentences.fold(0, (sum, s) => sum + s.words.length);

  Map<String, Object?> toJson() => {
        'sectionIndex': sectionIndex,
        'startSentenceIndex': startSentenceIndex,
        'sentences': sentences.map((s) => s.toJson()).toList(),
      };
}

/// Metadata manifest for a sectioned PDF document.
class DocumentManifest {
  const DocumentManifest({
    required this.filePath,
    required this.fileHash,
    required this.totalSentences,
    required this.totalWords,
    required this.totalSections,
    required this.sectionSize,
    this.pageMap = const {},
    required this.lastModified,
    required this.createdAt,
  });

  factory DocumentManifest.fromJson(Map<String, Object?> json) {
    final pageMapRaw = json['pageMap'] as Map<String, Object?>? ?? {};
    final pageMap = pageMapRaw.map(
      (k, v) => MapEntry(int.parse(k), v as int),
    );
    return DocumentManifest(
      filePath: json['filePath'] as String? ?? '',
      fileHash: json['fileHash'] as String? ?? '',
      totalSentences: json['totalSentences'] as int? ?? 0,
      totalWords: json['totalWords'] as int? ?? 0,
      totalSections: json['totalSections'] as int? ?? 1,
      sectionSize: json['sectionSize'] as int? ?? 200,
      pageMap: pageMap,
      lastModified: json['lastModified'] != null
          ? DateTime.parse(json['lastModified'] as String)
          : DateTime.now(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  final String filePath;
  final String fileHash;
  final int totalSentences;
  final int totalWords;
  final int totalSections;
  final int sectionSize;

  /// pageNumber → startSentenceIndex
  final Map<int, int> pageMap;
  final DateTime lastModified;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'filePath': filePath,
        'fileHash': fileHash,
        'totalSentences': totalSentences,
        'totalWords': totalWords,
        'totalSections': totalSections,
        'sectionSize': sectionSize,
        'pageMap': pageMap.map((k, v) => MapEntry(k.toString(), v)),
        'lastModified': lastModified.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Global store index tracking last-opened timestamps per file hash.
class StoreIndex {
  const StoreIndex({required this.entries});

  factory StoreIndex.fromJson(Map<String, Object?> json) {
    final raw = json['entries'] as Map<String, Object?>? ?? {};
    final entries = raw.map(
      (k, v) => MapEntry(k, DateTime.parse(v as String)),
    );
    return StoreIndex(entries: entries);
  }

  /// fileHash → lastOpened timestamp
  final Map<String, DateTime> entries;

  StoreIndex touch(String hash) {
    final updated = Map<String, DateTime>.from(entries);
    updated[hash] = DateTime.now();
    return StoreIndex(entries: updated);
  }

  StoreIndex remove(String hash) {
    final updated = Map<String, DateTime>.from(entries);
    updated.remove(hash);
    return StoreIndex(entries: updated);
  }

  Map<String, Object?> toJson() => {
        'entries': entries.map((k, v) => MapEntry(k, v.toIso8601String())),
      };
}

// ── Page boundary tracking (Prompt 3) ────────────────────────────────

/// Marks where a PDF page begins in the global word/sentence stream.
class PageBoundary {
  const PageBoundary({
    required this.pageNumber,
    required this.startSentenceIndex,
    required this.startWordIndex,
    this.firstWords = '',
  });

  factory PageBoundary.fromJson(Map<String, Object?> json) {
    return PageBoundary(
      pageNumber: json['pageNumber'] as int? ?? 0,
      startSentenceIndex: json['startSentenceIndex'] as int? ?? 0,
      startWordIndex: json['startWordIndex'] as int? ?? 0,
      firstWords: json['firstWords'] as String? ?? '',
    );
  }

  final int pageNumber;
  final int startSentenceIndex;
  final int startWordIndex;

  /// First ~5 words as a preview label.
  final String firstWords;

  Map<String, Object?> toJson() => {
        'pageNumber': pageNumber,
        'startSentenceIndex': startSentenceIndex,
        'startWordIndex': startWordIndex,
        'firstWords': firstWords,
      };
}

/// User-defined reading range (start page/word → end page/word).
class ReadingRange {
  const ReadingRange({
    required this.startPage,
    this.startWordIndexOnPage = 0,
    this.startWordAnchor,
    required this.endPage,
    this.endWordIndexOnPage = 0,
    this.endWordAnchor,
    this.resolvedStartWordIndex = 0,
    this.resolvedEndWordIndex = 0,
  });

  factory ReadingRange.fromJson(Map<String, Object?> json) {
    return ReadingRange(
      startPage: json['startPage'] as int? ?? 0,
      startWordIndexOnPage: json['startWordIndexOnPage'] as int? ?? 0,
      startWordAnchor: json['startWordAnchor'] as String?,
      endPage: json['endPage'] as int? ?? 0,
      endWordIndexOnPage: json['endWordIndexOnPage'] as int? ?? 0,
      endWordAnchor: json['endWordAnchor'] as String?,
      resolvedStartWordIndex: json['resolvedStartWordIndex'] as int? ?? 0,
      resolvedEndWordIndex: json['resolvedEndWordIndex'] as int? ?? 0,
    );
  }

  final int startPage;
  final int startWordIndexOnPage;
  final String? startWordAnchor;
  final int endPage;
  final int endWordIndexOnPage;
  final String? endWordAnchor;
  final int resolvedStartWordIndex;
  final int resolvedEndWordIndex;

  ReadingRange copyWith({
    int? startPage,
    int? startWordIndexOnPage,
    String? startWordAnchor,
    int? endPage,
    int? endWordIndexOnPage,
    String? endWordAnchor,
    int? resolvedStartWordIndex,
    int? resolvedEndWordIndex,
  }) {
    return ReadingRange(
      startPage: startPage ?? this.startPage,
      startWordIndexOnPage: startWordIndexOnPage ?? this.startWordIndexOnPage,
      startWordAnchor: startWordAnchor ?? this.startWordAnchor,
      endPage: endPage ?? this.endPage,
      endWordIndexOnPage: endWordIndexOnPage ?? this.endWordIndexOnPage,
      endWordAnchor: endWordAnchor ?? this.endWordAnchor,
      resolvedStartWordIndex:
          resolvedStartWordIndex ?? this.resolvedStartWordIndex,
      resolvedEndWordIndex: resolvedEndWordIndex ?? this.resolvedEndWordIndex,
    );
  }

  Map<String, Object?> toJson() => {
        'startPage': startPage,
        'startWordIndexOnPage': startWordIndexOnPage,
        'startWordAnchor': startWordAnchor,
        'endPage': endPage,
        'endWordIndexOnPage': endWordIndexOnPage,
        'endWordAnchor': endWordAnchor,
        'resolvedStartWordIndex': resolvedStartWordIndex,
        'resolvedEndWordIndex': resolvedEndWordIndex,
      };
}

/// Resolves a ReadingRange to global word indices using page boundaries.
({int globalStart, int globalEnd}) resolveRange(
  ReadingRange range,
  List<PageBoundary> boundaries,
) {
  int resolvePageWord(int page, int wordOnPage, String? anchor) {
    // Find the boundary for the target page
    PageBoundary? boundary;
    for (final b in boundaries) {
      if (b.pageNumber == page) {
        boundary = b;
        break;
      }
    }
    if (boundary == null) {
      // Fall back: use the last boundary before this page
      for (final b in boundaries.reversed) {
        if (b.pageNumber <= page) {
          boundary = b;
          break;
        }
      }
    }
    return (boundary?.startWordIndex ?? 0) + wordOnPage;
  }

  final globalStart = resolvePageWord(
    range.startPage,
    range.startWordIndexOnPage,
    range.startWordAnchor,
  );
  final globalEnd = resolvePageWord(
    range.endPage,
    range.endWordIndexOnPage,
    range.endWordAnchor,
  );
  return (globalStart: globalStart, globalEnd: globalEnd);
}
