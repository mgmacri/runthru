/// Data models for persistent configuration.
library;

import 'package:runthru/features/reading/pacing/pacing_config.dart';
import 'package:runthru/services/models.dart';

// P10 Grade B — parallax intensity controls room distortion level
enum ParallaxIntensity { none, off, subtle, full }

// P16 Grade C — reading goal presets for onboarding
enum ReadingGoalPreset { deepRead, comfortable, quickScan }

// P18 Grade B — ORP display condition for anchor character
enum OrpCondition { orpBoldColor, orpColorOnly, centerAligned }

/// User-selected Google Drive access mode.
enum GoogleDriveAccessMode {
  /// Use only files the user explicitly chooses.
  selectedFilesOnly,

  /// Allow a Drive-wide browser after explicit opt-in.
  fullDriveBrowser,
}

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
      readingRange: clearReadingRange
          ? null
          : (readingRange ?? this.readingRange),
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
    this.parallaxIntensity = ParallaxIntensity.none,
    this.readingGoalPreset,
    this.orpCondition = OrpCondition.orpBoldColor,
    this.shownHints = const {},
    this.hasSeenReadingGoalOnboarding = false,
    this.pacingConfig = defaultPacingConfig,
    this.letterSpacing = 0.0,
    this.wordSpacing = 0.0,
    this.readingRulerEnabled = false,
    this.googleDriveAccessMode = GoogleDriveAccessMode.selectedFilesOnly,
  });

  factory AppConfig.fromJson(Map<String, Object?> json) {
    final bookmarksRaw = json['bookmarks'] as Map<String, Object?>? ?? {};
    final bookmarks = bookmarksRaw.map(
      (key, value) =>
          MapEntry(key, BookmarkData.fromJson(value as Map<String, Object?>)),
    );

    // Parse v3 enums with safe fallbacks for backward compatibility.
    final parallaxIntensityStr = json['parallaxIntensity'] as String?;
    final parallaxIntensity =
        ParallaxIntensity.values.asNameMap()[parallaxIntensityStr] ??
        ParallaxIntensity.none;

    final readingGoalPresetStr = json['readingGoalPreset'] as String?;
    final readingGoalPreset = readingGoalPresetStr != null
        ? ReadingGoalPreset.values.asNameMap()[readingGoalPresetStr]
        : null;

    final orpConditionStr = json['orpCondition'] as String?;
    final orpCondition =
        OrpCondition.values.asNameMap()[orpConditionStr] ??
        OrpCondition.orpBoldColor;

    final googleDriveAccessModeStr = json['googleDriveAccessMode'] as String?;
    final googleDriveAccessMode =
        GoogleDriveAccessMode.values.asNameMap()[googleDriveAccessModeStr] ??
        GoogleDriveAccessMode.selectedFilesOnly;

    return AppConfig(
      defaultWpm: json['defaultWpm'] as int? ?? 300,
      pdfFolderPath: json['pdfFolderPath'] as String?,
      bookmarks: bookmarks,
      anchorColorIndex: json['anchorColorIndex'] as int? ?? 0,
      fontFamily: json['fontFamily'] as String? ?? 'BricolageGrotesque',
      fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
      hasPremium: json['hasPremium'] as bool? ?? false,
      parallaxIntensity: parallaxIntensity,
      readingGoalPreset: readingGoalPreset,
      orpCondition: orpCondition,
      shownHints:
          (json['shownHints'] as List<dynamic>?)?.cast<String>().toSet() ??
          const {},
      hasSeenReadingGoalOnboarding:
          json['hasSeenReadingGoalOnboarding'] as bool? ?? false,
      pacingConfig: json.containsKey('pacingConfig')
          ? PacingConfig.fromJson(json['pacingConfig'] as Map<String, Object?>)
          : defaultPacingConfig,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
      wordSpacing: (json['wordSpacing'] as num?)?.toDouble() ?? 0.0,
      readingRulerEnabled: json['readingRulerEnabled'] as bool? ?? false,
      googleDriveAccessMode: googleDriveAccessMode,
    );
  }

  final int defaultWpm;
  final String? pdfFolderPath;
  final Map<String, BookmarkData> bookmarks;
  final int anchorColorIndex;
  final String fontFamily;
  final double fontScale;
  final bool hasPremium;
  final ParallaxIntensity parallaxIntensity;
  final ReadingGoalPreset? readingGoalPreset;
  final OrpCondition orpCondition;
  // P27 — hint IDs tracked per installation (Rule 27)
  final Set<String> shownHints;
  final bool hasSeenReadingGoalOnboarding;

  /// Per-word adaptive pacing configuration.
  final PacingConfig pacingConfig;

  /// Letter spacing in logical pixels (0.0–5.0).
  final double letterSpacing;

  /// Word spacing in logical pixels (0.0–20.0).
  final double wordSpacing;

  /// Whether the reading ruler overlay is enabled.
  final bool readingRulerEnabled;

  /// Google Drive access mode selected by the user.
  final GoogleDriveAccessMode googleDriveAccessMode;

  AppConfig copyWith({
    int? defaultWpm,
    String? pdfFolderPath,
    bool clearPdfFolderPath = false,
    Map<String, BookmarkData>? bookmarks,
    int? anchorColorIndex,
    String? fontFamily,
    double? fontScale,
    bool? hasPremium,
    ParallaxIntensity? parallaxIntensity,
    ReadingGoalPreset? readingGoalPreset,
    bool clearReadingGoalPreset = false,
    OrpCondition? orpCondition,
    Set<String>? shownHints,
    bool? hasSeenReadingGoalOnboarding,
    PacingConfig? pacingConfig,
    double? letterSpacing,
    double? wordSpacing,
    bool? readingRulerEnabled,
    GoogleDriveAccessMode? googleDriveAccessMode,
  }) {
    return AppConfig(
      defaultWpm: defaultWpm ?? this.defaultWpm,
      pdfFolderPath: clearPdfFolderPath
          ? null
          : (pdfFolderPath ?? this.pdfFolderPath),
      bookmarks: bookmarks ?? this.bookmarks,
      anchorColorIndex: anchorColorIndex ?? this.anchorColorIndex,
      fontFamily: fontFamily ?? this.fontFamily,
      fontScale: fontScale ?? this.fontScale,
      hasPremium: hasPremium ?? this.hasPremium,
      parallaxIntensity: parallaxIntensity ?? this.parallaxIntensity,
      readingGoalPreset: clearReadingGoalPreset
          ? null
          : (readingGoalPreset ?? this.readingGoalPreset),
      orpCondition: orpCondition ?? this.orpCondition,
      shownHints: shownHints ?? this.shownHints,
      hasSeenReadingGoalOnboarding:
          hasSeenReadingGoalOnboarding ?? this.hasSeenReadingGoalOnboarding,
      pacingConfig: pacingConfig ?? this.pacingConfig,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      readingRulerEnabled: readingRulerEnabled ?? this.readingRulerEnabled,
      googleDriveAccessMode:
          googleDriveAccessMode ?? this.googleDriveAccessMode,
    );
  }

  Map<String, Object?> toJson() => {
    'defaultWpm': defaultWpm,
    'pdfFolderPath': pdfFolderPath,
    'bookmarks': bookmarks.map((key, value) => MapEntry(key, value.toJson())),
    'anchorColorIndex': anchorColorIndex,
    'fontFamily': fontFamily,
    'fontScale': fontScale,
    'hasPremium': hasPremium,
    'parallaxIntensity': parallaxIntensity.name,
    'readingGoalPreset': readingGoalPreset?.name,
    'orpCondition': orpCondition.name,
    'shownHints': shownHints.toList(),
    'hasSeenReadingGoalOnboarding': hasSeenReadingGoalOnboarding,
    'pacingConfig': pacingConfig.toJson(),
    'letterSpacing': letterSpacing,
    'wordSpacing': wordSpacing,
    'readingRulerEnabled': readingRulerEnabled,
    'googleDriveAccessMode': googleDriveAccessMode.name,
  };
}
