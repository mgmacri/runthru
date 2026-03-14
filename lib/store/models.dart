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
    this.stereoscopicEnabled = false,
    this.parallaxFactor = 1.0,
    this.anchorColorIndex = 0,
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
      stereoscopicEnabled: json['stereoscopicEnabled'] as bool? ?? false,
      parallaxFactor: (json['parallaxFactor'] as num?)?.toDouble() ?? 1.0,
      anchorColorIndex: json['anchorColorIndex'] as int? ?? 0,
    );
  }

  final int defaultWpm;
  final String? pdfFolderPath;
  final Map<String, BookmarkData> bookmarks;
  final bool stereoscopicEnabled;
  final double parallaxFactor;
  final int anchorColorIndex;

  AppConfig copyWith({
    int? defaultWpm,
    String? pdfFolderPath,
    bool clearPdfFolderPath = false,
    Map<String, BookmarkData>? bookmarks,
    bool? stereoscopicEnabled,
    double? parallaxFactor,
    int? anchorColorIndex,
  }) {
    return AppConfig(
      defaultWpm: defaultWpm ?? this.defaultWpm,
      pdfFolderPath:
          clearPdfFolderPath ? null : (pdfFolderPath ?? this.pdfFolderPath),
      bookmarks: bookmarks ?? this.bookmarks,
      stereoscopicEnabled: stereoscopicEnabled ?? this.stereoscopicEnabled,
      parallaxFactor: parallaxFactor ?? this.parallaxFactor,
      anchorColorIndex: anchorColorIndex ?? this.anchorColorIndex,
    );
  }

  Map<String, Object?> toJson() => {
        'defaultWpm': defaultWpm,
        'pdfFolderPath': pdfFolderPath,
        'bookmarks': bookmarks.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'stereoscopicEnabled': stereoscopicEnabled,
        'parallaxFactor': parallaxFactor,
        'anchorColorIndex': anchorColorIndex,
      };
}
