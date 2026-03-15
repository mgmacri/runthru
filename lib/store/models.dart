/// Data models for persistent configuration.
library;

class BookmarkData {
  const BookmarkData({
    required this.wordIndex,
    this.timestamp,
  });

  factory BookmarkData.fromJson(Map<String, Object?> json) {
    return BookmarkData(
      wordIndex: json['wordIndex'] as int? ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }

  final int wordIndex;
  final DateTime? timestamp;

  Map<String, Object?> toJson() => {
        'wordIndex': wordIndex,
        'timestamp': timestamp?.toIso8601String(),
      };
}

class AppConfig {
  const AppConfig({
    this.defaultWpm = 300,
    this.pdfFolderPath,
    this.bookmarks = const {},
    this.anchorColorIndex = 0,
    this.fontFamily = 'BricolageGrotesque',
  });

  factory AppConfig.fromJson(Map<String, Object?> json) {
    final bookmarksRaw = json['bookmarks'] as Map<String, Object?>? ?? {};
    final bookmarks = bookmarksRaw.map(
      (key, value) => MapEntry(
        key,
        BookmarkData.fromJson(value as Map<String, Object?>),
      ),
    );

    return AppConfig(
      defaultWpm: json['defaultWpm'] as int? ?? 300,
      pdfFolderPath: json['pdfFolderPath'] as String?,
      bookmarks: bookmarks,
      anchorColorIndex: json['anchorColorIndex'] as int? ?? 0,
      fontFamily: json['fontFamily'] as String? ?? 'BricolageGrotesque',
    );
  }

  final int defaultWpm;
  final String? pdfFolderPath;
  final Map<String, BookmarkData> bookmarks;
  final int anchorColorIndex;
  final String fontFamily;

  AppConfig copyWith({
    int? defaultWpm,
    String? pdfFolderPath,
    bool clearPdfFolderPath = false,
    Map<String, BookmarkData>? bookmarks,
    int? anchorColorIndex,
    String? fontFamily,
  }) {
    return AppConfig(
      defaultWpm: defaultWpm ?? this.defaultWpm,
      pdfFolderPath:
          clearPdfFolderPath ? null : (pdfFolderPath ?? this.pdfFolderPath),
      bookmarks: bookmarks ?? this.bookmarks,
      anchorColorIndex: anchorColorIndex ?? this.anchorColorIndex,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  Map<String, Object?> toJson() => {
        'defaultWpm': defaultWpm,
        'pdfFolderPath': pdfFolderPath,
        'bookmarks': bookmarks.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'anchorColorIndex': anchorColorIndex,
        'fontFamily': fontFamily,
      };
}
