import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/store/models.dart';

void main() {
  group('AppConfig', () {
    test('defaults', () {
      const config = AppConfig();
      expect(config.defaultWpm, 300);
      expect(config.pdfFolderPath, isNull);
      expect(config.bookmarks, isEmpty);
      expect(
        config.googleDriveAccessMode,
        GoogleDriveAccessMode.selectedFilesOnly,
      );
    });

    test('roundtrip JSON serialization', () {
      final config = AppConfig(
        defaultWpm: 500,
        pdfFolderPath: '/docs',
        bookmarks: {
          '/test.pdf': BookmarkData(wordIndex: 42, timestamp: DateTime(2026)),
        },
        googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
      );

      final json = config.toJson();
      final restored = AppConfig.fromJson(json);

      expect(restored.defaultWpm, 500);
      expect(restored.pdfFolderPath, '/docs');
      expect(restored.bookmarks['/test.pdf']?.wordIndex, 42);
      expect(
        restored.googleDriveAccessMode,
        GoogleDriveAccessMode.fullDriveBrowser,
      );
    });

    test('fromJson handles missing fields gracefully', () {
      final config = AppConfig.fromJson({});
      expect(config.defaultWpm, 300);
      expect(config.pdfFolderPath, isNull);
      expect(
        config.googleDriveAccessMode,
        GoogleDriveAccessMode.selectedFilesOnly,
      );
    });

    test('corrupt Google Drive access mode defaults to selected files', () {
      final config = AppConfig.fromJson({
        'googleDriveAccessMode': 'workspaceReadOnly',
      });

      expect(
        config.googleDriveAccessMode,
        GoogleDriveAccessMode.selectedFilesOnly,
      );
    });

    test('v3 fields default safely when JSON keys missing', () {
      final config = AppConfig.fromJson({});
      expect(config.parallaxIntensity, ParallaxIntensity.none);
      expect(config.readingGoalPreset, isNull);
      expect(config.orpCondition, OrpCondition.orpBoldColor);
      expect(config.shownHints, isEmpty);
    });

    test('parallaxIntensity serializes and deserializes', () {
      for (final intensity in ParallaxIntensity.values) {
        final config = AppConfig(parallaxIntensity: intensity);
        final json = config.toJson();
        final restored = AppConfig.fromJson(json);
        expect(restored.parallaxIntensity, intensity);
      }
    });

    test('orpCondition serializes and deserializes', () {
      for (final condition in OrpCondition.values) {
        final config = AppConfig(orpCondition: condition);
        final json = config.toJson();
        final restored = AppConfig.fromJson(json);
        expect(restored.orpCondition, condition);
      }
    });

    test('readingGoalPreset null by default', () {
      const config = AppConfig();
      expect(config.readingGoalPreset, isNull);

      // Round-trip with a non-null preset
      final withPreset = config.copyWith(
        readingGoalPreset: ReadingGoalPreset.deepRead,
      );
      final json = withPreset.toJson();
      final restored = AppConfig.fromJson(json);
      expect(restored.readingGoalPreset, ReadingGoalPreset.deepRead);

      // Round-trip with null preset
      final cleared = withPreset.copyWith(clearReadingGoalPreset: true);
      final json2 = cleared.toJson();
      final restored2 = AppConfig.fromJson(json2);
      expect(restored2.readingGoalPreset, isNull);
    });

    test('shownHints defaults to empty set', () {
      const config = AppConfig();
      expect(config.shownHints, isEmpty);

      final updated = config.copyWith(
        shownHints: {'hint_tap', 'hint_swipe_up'},
      );
      final json = updated.toJson();
      final restored = AppConfig.fromJson(json);
      expect(restored.shownHints, {'hint_tap', 'hint_swipe_up'});
    });

    test('shownHints missing key in JSON returns empty set', () {
      final config = AppConfig.fromJson({});
      expect(config.shownHints, isEmpty);
    });
  });

  group('BookmarkData', () {
    test('roundtrip JSON', () {
      final bookmark = BookmarkData(
        wordIndex: 100,
        timestamp: DateTime(2026, 3, 14),
      );
      final json = bookmark.toJson();
      final restored = BookmarkData.fromJson(json);
      expect(restored.wordIndex, 100);
      expect(restored.timestamp, isNotNull);
    });
  });
}
