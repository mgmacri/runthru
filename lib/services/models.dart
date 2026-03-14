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

  Map<String, Object?> toJson() => {
        'sentences': sentences.map((s) => s.toJson()).toList(),
      };
}

enum PdfStatus { pending, processing, ready, error, unsupported }

class PdfEntry {
  const PdfEntry({
    required this.filePath,
    required this.fileName,
    this.status = PdfStatus.pending,
    this.document,
    this.errorMessage,
  });

  final String filePath;
  final String fileName;
  final PdfStatus status;
  final ExtractedDocument? document;
  final String? errorMessage;

  PdfEntry copyWith({
    PdfStatus? status,
    ExtractedDocument? document,
    String? errorMessage,
  }) {
    return PdfEntry(
      filePath: filePath,
      fileName: fileName,
      status: status ?? this.status,
      document: document ?? this.document,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class UnsupportedPdfError implements Exception {
  const UnsupportedPdfError(this.message);
  final String message;
  @override
  String toString() => 'UnsupportedPdfError: $message';
}
