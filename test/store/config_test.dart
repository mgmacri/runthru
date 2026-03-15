import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/store/models.dart';

void main() {
  group('AppConfig', () {
    test('defaults', () {
      const config = AppConfig();
      expect(config.defaultWpm, 300);
      expect(config.pdfFolderPath, isNull);
      expect(config.bookmarks, isEmpty);
    });

    test('roundtrip JSON serialization', () {
      final config = AppConfig(
        defaultWpm: 500,
        pdfFolderPath: '/docs',
        bookmarks: {
          '/test.pdf': BookmarkData(
            wordIndex: 42,
            timestamp: DateTime(2026),
          ),
        },
      );

      final json = config.toJson();
      final restored = AppConfig.fromJson(json);

      expect(restored.defaultWpm, 500);
      expect(restored.pdfFolderPath, '/docs');
      expect(restored.bookmarks['/test.pdf']?.wordIndex, 42);
    });

    test('fromJson handles missing fields gracefully', () {
      final config = AppConfig.fromJson({});
      expect(config.defaultWpm, 300);
      expect(config.pdfFolderPath, isNull);
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
