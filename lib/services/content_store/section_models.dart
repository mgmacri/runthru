/// Ring 2 data contracts: the section is the unit of loading, caching,
/// eviction, and (future) on-device model processing.
library;

import 'package:runthru/services/models.dart';

/// Current on-disk schema version for the content store.
const int kContentStoreSchemaVersion = 1;

/// Target words per section. Sections are sentence-aligned, so real sizes
/// vary around this; it keeps any single load bounded (~1500 words ≈ a few
/// hundred KB of Dart strings) regardless of book size.
const int kSectionTargetWords = 1500;

/// Metadata describing one section without its text.
class SectionMetadata {
  /// Creates section metadata.
  const SectionMetadata({
    required this.sectionIndex,
    required this.startWordIndex,
    required this.startSentenceIndex,
    required this.wordCount,
    this.startPage = -1,
    this.endPage = -1,
    this.languageHint,
    this.modelAnnotations = const {},
  });

  /// Rebuilds metadata from JSON.
  factory SectionMetadata.fromJson(Map<String, Object?> json) {
    return SectionMetadata(
      sectionIndex: json['sectionIndex'] as int? ?? 0,
      startWordIndex: json['startWordIndex'] as int? ?? 0,
      startSentenceIndex: json['startSentenceIndex'] as int? ?? 0,
      wordCount: json['wordCount'] as int? ?? 0,
      startPage: json['startPage'] as int? ?? -1,
      endPage: json['endPage'] as int? ?? -1,
      languageHint: json['languageHint'] as String?,
      modelAnnotations:
          (json['modelAnnotations'] as Map<String, Object?>?) ?? const {},
    );
  }

  /// Zero-based section index within the book.
  final int sectionIndex;

  /// Global word offset of the section's first word.
  final int startWordIndex;

  /// Global sentence offset of the section's first sentence.
  final int startSentenceIndex;

  /// Words in this section.
  final int wordCount;

  /// First source page covered, or -1 when unknown.
  final int startPage;

  /// Last source page covered, or -1 when unknown.
  final int endPage;

  /// Optional BCP-47 language hint for model input.
  final String? languageHint;

  /// Output slot for on-device models (e.g. `difficultyPerWord`).
  /// Ring 1 never calls a model — it only reads annotations if present.
  final Map<String, Object?> modelAnnotations;

  /// Returns a copy with [modelAnnotations] merged with [annotations].
  SectionMetadata withAnnotations(Map<String, Object?> annotations) {
    return SectionMetadata(
      sectionIndex: sectionIndex,
      startWordIndex: startWordIndex,
      startSentenceIndex: startSentenceIndex,
      wordCount: wordCount,
      startPage: startPage,
      endPage: endPage,
      languageHint: languageHint,
      modelAnnotations: {...modelAnnotations, ...annotations},
    );
  }

  /// Per-word difficulty multipliers written by an on-device model, or null
  /// when no model has annotated this section. Read by the pacing path.
  List<double>? get difficultyPerWord {
    final raw = modelAnnotations['difficultyPerWord'];
    if (raw is! List) return null;
    return [for (final v in raw) (v as num).toDouble()];
  }

  /// Serialises to JSON.
  Map<String, Object?> toJson() => {
    'sectionIndex': sectionIndex,
    'startWordIndex': startWordIndex,
    'startSentenceIndex': startSentenceIndex,
    'wordCount': wordCount,
    'startPage': startPage,
    'endPage': endPage,
    'languageHint': languageHint,
    'modelAnnotations': modelAnnotations,
  };
}

/// One bounded window of a book: the payload Ring 1 reads from and a future
/// summariser/difficulty model receives. Never larger than roughly
/// [kSectionTargetWords] words plus one sentence.
class Section {
  /// Creates a section.
  Section({required this.sentences, required this.meta});

  /// Rebuilds a section from JSON.
  factory Section.fromJson(Map<String, Object?> json) {
    return Section(
      sentences:
          (json['sentences'] as List<Object?>?)
              ?.map((e) => Sentence.fromJson(e as Map<String, Object?>))
              .toList() ??
          const [],
      meta: SectionMetadata.fromJson(
        json['meta'] as Map<String, Object?>? ?? const {},
      ),
    );
  }

  /// Sentence-structured text.
  final List<Sentence> sentences;

  /// Metadata (word counts, page range, model annotations).
  final SectionMetadata meta;

  List<String>? _words;
  String? _rawText;

  /// Flat word list in reading order (computed once, cached).
  List<String> get words =>
      _words ??= [for (final s in sentences) ...s.words];

  /// Joined text of the section — model input shape.
  String get rawText => _rawText ??= words.join(' ');

  /// Serialises to JSON.
  Map<String, Object?> toJson() => {
    'sentences': sentences.map((s) => s.toJson()).toList(),
    'meta': meta.toJson(),
  };
}

/// Book-level metadata served without loading any text.
class BookMetadata {
  /// Creates book metadata.
  const BookMetadata({
    required this.bookId,
    required this.displayName,
    required this.sourceId,
    required this.totalWords,
    required this.totalSentences,
    required this.totalSections,
    required this.totalPages,
    this.pageBoundaries = const [],
    this.schemaVersion = kContentStoreSchemaVersion,
  });

  /// Rebuilds metadata from JSON.
  factory BookMetadata.fromJson(Map<String, Object?> json) {
    return BookMetadata(
      bookId: json['bookId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? 'local',
      totalWords: json['totalWords'] as int? ?? 0,
      totalSentences: json['totalSentences'] as int? ?? 0,
      totalSections: json['totalSections'] as int? ?? 0,
      totalPages: json['totalPages'] as int? ?? 0,
      pageBoundaries:
          (json['pageBoundaries'] as List<Object?>?)
              ?.map((e) => PageBoundary.fromJson(e as Map<String, Object?>))
              .toList() ??
          const [],
      schemaVersion: json['schemaVersion'] as int? ?? 0,
    );
  }

  /// Content hash — canonical identity.
  final String bookId;

  /// User-visible name.
  final String displayName;

  /// Originating integration (`local`, `drive:<id>`, …).
  final String sourceId;

  /// Total words across all sections.
  final int totalWords;

  /// Total sentences across all sections.
  final int totalSentences;

  /// Number of sections on disk when fully ingested.
  final int totalSections;

  /// Source page count (0 when unknown).
  final int totalPages;

  /// Page → word/sentence offsets (small; metadata-grade).
  final List<PageBoundary> pageBoundaries;

  /// On-disk schema version (idempotent migrations check this).
  final int schemaVersion;

  /// Serialises to JSON.
  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'displayName': displayName,
    'sourceId': sourceId,
    'totalWords': totalWords,
    'totalSentences': totalSentences,
    'totalSections': totalSections,
    'totalPages': totalPages,
    'pageBoundaries': pageBoundaries.map((b) => b.toJson()).toList(),
    'schemaVersion': schemaVersion,
  };
}
