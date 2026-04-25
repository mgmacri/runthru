import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/clipboard_document.dart';
import 'package:speedy_boy/core/clipboard_service.dart';
import 'package:speedy_boy/core/context_reveal_notifier.dart';
import 'package:speedy_boy/core/context_reveal_state.dart';
import 'package:speedy_boy/core/word_timer.dart';

/// TASK-131 — Integration test: clipboard reading flow.
///
/// Tests the full clipboard-to-reading pipeline:
/// 1. Create ClipboardDocument from pasted text
/// 2. Verify preview properties (title, words, sentences)
/// 3. Load into word timer and verify reading works
/// 4. Exercise all gestures on clipboard content
/// 5. Verify ephemeral nature (Rule 28)
void main() {
  const sampleText =
      'Speed reading is a valuable skill for modern life. '
      'It helps you process information faster and retain key ideas. '
      'Practice makes perfect when learning to read quickly.';

  late ProviderContainer container;
  late ContextRevealNotifier crNotifier;
  late WordTimerNotifier wordTimer;

  setUp(() {
    container = ProviderContainer();
    crNotifier = container.read(contextRevealProvider.notifier);
    wordTimer = container.read(wordTimerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  group('Clipboard reading flow integration', () {
    test('1. ClipboardDocument creation from pasted text', () {
      final doc = ClipboardDocument.fromClipboardText(sampleText);

      expect(doc.words, isNotEmpty);
      expect(doc.words.first, 'Speed');
      expect(doc.document.sentences.length, 3);
      expect(doc.title, isNotEmpty);
      expect(doc.title, isNot(equals('Clipboard')));
    });

    test('2. Preview dialog data — title and word count', () {
      final doc = ClipboardDocument.fromClipboardText(sampleText);

      // Title extracted from first line/40 chars.
      expect(doc.title.length, lessThanOrEqualTo(41));
      // Words match document.allWords.
      expect(doc.words, equals(doc.document.allWords));
      expect(doc.document.totalWords, doc.words.length);
      // No page boundaries for clipboard documents.
      expect(doc.document.hasPageBoundaries, isFalse);
    });

    test('3. Load clipboard document into word timer → reading starts', () {
      final doc = ClipboardDocument.fromClipboardText(sampleText);

      // Simulate what ParallaxReadingScreen._loadClipboardDocument does.
      wordTimer.loadDocument(doc.words.length, startIndex: 0);
      wordTimer.play();

      expect(container.read(wordTimerProvider).isPlaying, isTrue);
      expect(container.read(wordTimerProvider).currentIndex, 0);
      expect(container.read(wordTimerProvider).totalWords, doc.words.length);
    });

    test('4. All gestures work on clipboard content', () {
      final doc = ClipboardDocument.fromClipboardText(sampleText);
      wordTimer.loadDocument(doc.words.length, startIndex: 0);
      wordTimer.play();
      wordTimer.seekTo(5);

      // Tap — pause.
      wordTimer.pause();
      expect(container.read(wordTimerProvider).isPlaying, isFalse);

      // Tap — resume with auto-rewind.
      wordTimer.play();
      expect(container.read(wordTimerProvider).currentIndex, 2); // 5 - 3

      // Swipe up — enter ContextReveal.
      wordTimer.pause();
      crNotifier.enterSentence(2);
      expect(container.read(contextRevealProvider).isActive, isTrue);
      expect(
        container.read(contextRevealProvider).tier,
        ContextRevealTier.sentence,
      );

      // Swipe up again — jiggle (ceiling).
      crNotifier.triggerJiggle();
      expect(container.read(contextRevealProvider).isJiggling, isTrue);
      crNotifier.clearJiggle();

      // Shift window forward.
      crNotifier.shiftWindowForward();
      expect(container.read(contextRevealProvider).windowOffset, 1);

      // Swipe down — dismiss and resume.
      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 3); // 2 + 1
      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 3);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);

      // Double-tap — restart current sentence.
      wordTimer.restartCurrentSentence(0);
      expect(container.read(wordTimerProvider).currentIndex, 0);
    });

    test('5. Clipboard document is ephemeral (Rule 28)', () {
      final before = DateTime.now();
      final doc = ClipboardDocument.fromClipboardText(sampleText);
      final after = DateTime.now();

      // pastedAt timestamp is set.
      expect(
        doc.pastedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        doc.pastedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );

      // No bookmark mechanism — word timer has no file identity.
      wordTimer.loadDocument(doc.words.length, startIndex: 0);
      wordTimer.play();
      wordTimer.seekTo(10);
      // Reading position is session-only — no persistence API called.
      expect(container.read(wordTimerProvider).currentIndex, 10);
    });

    test('empty clipboard text produces empty document', () {
      final doc = ClipboardDocument.fromClipboardText('   ');
      expect(doc.title, 'Clipboard');
      expect(doc.words, isEmpty);
    });

    test('paragraph breaks create sentence boundaries', () {
      final doc = ClipboardDocument.fromClipboardText(
        'First paragraph with words.\n\nSecond paragraph with more words.',
      );
      expect(doc.document.sentences.length, greaterThanOrEqualTo(2));
    });

    test('minTextLength threshold is 10 characters', () {
      expect(ClipboardService.minTextLength, 10);
    });
  });
}
