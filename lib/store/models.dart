/// Data models for persistent configuration.
library;

import 'package:speedy_boy/services/models.dart';

class BookmarkData {
  const BookmarkData({
    required this.wordIndex,
    this.timestamp,
    this.readingRange,
    this.readingProgress = 0.0,
  });

  factory BookmarkData.fromJson(Map<String, Object?> json) {
    return BookmarkData(
      wordIndex: json['wordIndex'] as int? ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
      readingRange: json['readingRange'] != null
          ? ReadingRange.fromJson(json['readingRange'] as Map<String, Object?>)
          : null,
      readingProgress: (json['readingProgress'] as num?)?.toDouble() ?? 0.0,
    );
  }

  final int wordIndex;
  final DateTime? timestamp;
  final ReadingRange? readingRange;
  final double readingProgress;

  BookmarkData copyWith({
    int? wordIndex,
    DateTime? timestamp,
    ReadingRange? readingRange,
    bool clearReadingRange = false,
    double? readingProgress,
  }) {
    return BookmarkData(
      wordIndex: wordIndex ?? this.wordIndex,
      timestamp: timestamp ?? this.timestamp,
      readingRange:
          clearReadingRange ? null : (readingRange ?? this.readingRange),
      readingProgress: readingProgress ?? this.readingProgress,
    );
  }

  Map<String, Object?> toJson() => {
        'wordIndex': wordIndex,
        'timestamp': timestamp?.toIso8601String(),
        'readingRange': readingRange?.toJson(),
        'readingProgress': readingProgress,
      };
}

class AppConfig {
  const AppConfig({
    this.defaultWpm = 300,
    this.pdfFolderPath,
    this.bookmarks = const {},
    this.anchorColorIndex = 0,
    this.fontFamily = 'BricolageGrotesque',
    this.fontScale = 1.0,
    this.hasPremium = false,
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
      fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
      hasPremium: json['hasPremium'] as bool? ?? false,
    );
  }

  final int defaultWpm;
  final String? pdfFolderPath;
  final Map<String, BookmarkData> bookmarks;
  final int anchorColorIndex;
  final String fontFamily;
  final double fontScale;
  final bool hasPremium;

  AppConfig copyWith({
    int? defaultWpm,
    String? pdfFolderPath,
    bool clearPdfFolderPath = false,
    Map<String, BookmarkData>? bookmarks,
    int? anchorColorIndex,
    String? fontFamily,
    double? fontScale,
    bool? hasPremium,
  }) {
    return AppConfig(
      defaultWpm: defaultWpm ?? this.defaultWpm,
      pdfFolderPath:
          clearPdfFolderPath ? null : (pdfFolderPath ?? this.pdfFolderPath),
      bookmarks: bookmarks ?? this.bookmarks,
      anchorColorIndex: anchorColorIndex ?? this.anchorColorIndex,
      fontFamily: fontFamily ?? this.fontFamily,
      fontScale: fontScale ?? this.fontScale,
      hasPremium: hasPremium ?? this.hasPremium,
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
        'fontScale': fontScale,
        'hasPremium': hasPremium,
      };
}
