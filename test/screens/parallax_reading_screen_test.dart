import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/features/reading/providers/reading_progress_provider.dart';
import 'package:runthru/screens/parallax_reading_screen.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/store/models.dart';

void main() {
  group('ParallaxReadingScreen Drive source contract', () {
    test('uses drive source with the canonical drive:// file identity', () {
      final screen = ParallaxReadingScreen(
        filePath: 'drive://file-123',
        contentSource: 'drive',
        clipboardDocument: ClipboardDocument(
          title: 'Drive Doc',
          fullText: '',
          document: const ExtractedDocument(
            sentences: [
              Sentence(words: ['Drive', 'resume', 'works']),
            ],
          ),
          pastedAt: _openedAt,
        ),
      );

      expect(screen.filePath, 'drive://file-123');
      expect(screen.contentSource, 'drive');
      expect(screen.clipboardDocument!.title, 'Drive Doc');
      expect(screen.instapaperBookmarkId, isNull);
    });

    test('keeps clipboard sessions explicitly ephemeral', () {
      final screen = ParallaxReadingScreen(
        filePath: 'clipboard://clip',
        contentSource: 'clipboard',
        clipboardDocument: ClipboardDocument(
          title: 'Clip',
          fullText: '',
          document: const ExtractedDocument(
            sentences: [
              Sentence(words: ['Temporary']),
            ],
          ),
          pastedAt: _openedAt,
        ),
      );

      expect(screen.filePath, 'clipboard://clip');
      expect(screen.contentSource, 'clipboard');
      expect(screen.clipboardDocument, isNotNull);
    });

    test('resumes Drive documents from saved ReadingProgress when newer', () {
      final index = bestImportedResumeIndex(
        bookmark: BookmarkData(wordIndex: 12, timestamp: DateTime(2026, 5, 23)),
        driveProgress: ProgressRecord(
          contentId: 'drive://file-123',
          source: 'drive',
          title: 'Drive Doc',
          wordIndex: 48,
          totalWords: 100,
          lastReadAt: DateTime(2026, 5, 24),
        ),
      );

      expect(index, 48);
    });

    test('ignores finished Drive progress when choosing resume index', () {
      final index = bestImportedResumeIndex(
        bookmark: BookmarkData(wordIndex: 12, timestamp: DateTime(2026, 5, 24)),
        driveProgress: ProgressRecord(
          contentId: 'drive://file-123',
          source: 'drive',
          title: 'Drive Doc',
          wordIndex: 99,
          totalWords: 100,
          lastReadAt: DateTime(2026, 5, 25),
          finished: true,
        ),
      );

      expect(index, 12);
    });

    test('production dispose uses ReadingProgressSync.dispose', () {
      final source = File(
        'lib/screens/parallax_reading_screen.dart',
      ).readAsStringSync();
      final disposeBody = RegExp(
        r'void dispose\(\) \{(?<body>[\s\S]*?)\n  \}',
      ).firstMatch(source)!.namedGroup('body')!;

      expect(disposeBody, contains('_progressSync.dispose()'));
      expect(disposeBody, isNot(contains('_progressSync.cancelTimers()')));
    });
  });
}

final _openedAt = DateTime(2026, 5, 24);
