import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/core/word_timer.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/widgets/chapter_title_card.dart';
import 'package:runthru/features/reading/widgets/section_complete_overlay.dart';
import 'package:runthru/screens/parallax_reading_screen.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

/// A small book: a copyright page, then two chapters and an epilogue of
/// [chapterWords] words each, then an index.
///
/// Word layout with the default 160 words per chapter:
/// * 0..12   Copyright (heading 1 word + 12 words)
/// * 13      "Chapter" "One" heading, text from 15
/// * then Chapter Two, Epilogue, Index.
ExtractedDocument _book({int chapterWords = 160}) {
  final sentences = <Sentence>[];
  void heading(String text) => sentences.add(
    Sentence(words: text.split(' '), startsParagraph: true, heading: 2),
  );
  void text(int words, String tag) {
    var left = words;
    var first = true;
    while (left > 0) {
      final n = left < 10 ? left : 10;
      sentences.add(
        Sentence(
          words: [for (var i = 0; i < n; i++) '$tag$i'],
          startsParagraph: first,
        ),
      );
      first = false;
      left -= n;
    }
  }

  heading('Copyright');
  text(12, 'c');
  heading('Chapter One');
  text(chapterWords, 'a');
  heading('Chapter Two');
  text(chapterWords, 'b');
  heading('Epilogue');
  text(chapterWords, 'e');
  heading('Index');
  text(30, 'i');
  return ExtractedDocument(sentences: sentences);
}

class _Config extends AsyncNotifier<AppConfig> implements ConfigNotifier {
  _Config(this._initial);

  final AppConfig _initial;

  @override
  Future<AppConfig> build() async => _initial;

  @override
  Future<void> applyReadingGoalPreset(ReadingGoalConfig goal) async {}

  @override
  Future<void> setLastReadingMode(String mode) async {}

  @override
  bool hasHintBeenShown(String id) => true;

  @override
  Future<void> markHintShown(String id) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<ProviderContainer> _open(
  WidgetTester tester, {
  ExtractedDocument? document,
  bool chapterMoments = true,
  bool reduced = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        configProvider.overrideWith(
          () => _Config(
            AppConfig(
              hasSeenReadingGoalOnboarding: true,
              defaultWpm: 600,
              chapterMoments: chapterMoments,
              // Every onboarding hint already seen.
              shownHints: const {
                'hint_tap',
                'hint_swipe_up',
                'hint_swipe_lr',
                'hint_double_tap',
              },
            ),
          ),
        ),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(420, 900),
            disableAnimations: reduced,
          ),
          child: ParallaxReadingScreen(
            filePath: 'clipboard://chapters',
            contentSource: 'clipboard',
            clipboardDocument: ClipboardDocument(
              title: 'A Small Book',
              fullText: '',
              document: document ?? _book(),
              pastedAt: DateTime(2026, 11, 10),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  // The scope owns the container, so its timers end with the widget tree.
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

WordTimerState _timer(ProviderContainer c) => c.read(wordTimerProvider);

/// Lets the reader run for [seconds], a frame at a time so every timer
/// tick and animation step is processed in order.
Future<void> _run(WidgetTester tester, double seconds) async {
  final steps = (seconds * 20).round();
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Runs until [done] or [seconds] have passed.
Future<void> _runUntil(
  WidgetTester tester,
  bool Function() done, {
  double seconds = 60,
}) async {
  final steps = (seconds * 20).round();
  for (var i = 0; i < steps && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('opening a book', () {
    testWidgets('starts at the first chapter and announces it', (tester) async {
      final c = await _open(tester);

      // Not at the copyright page, and not flashing words yet.
      expect(find.byType(ChapterTitleCard), findsOneWidget);
      expect(_timer(c).isPlaying, isFalse);
      expect(_timer(c).currentIndex, 13);
      expect(find.text('Skipped the front matter · < 1 min'), findsOneWidget);
      // The card is not a pause: no paused controls.
      expect(find.bySemanticsLabel('Pause reading'), findsOneWidget);
      expect(find.bySemanticsLabel('Resume reading'), findsNothing);

      // The card leaves by itself and reading starts after the heading.
      await _runUntil(
        tester,
        () => find.byType(ChapterTitleCard).evaluate().isEmpty,
      );
      expect(find.byType(ChapterTitleCard), findsNothing);
      expect(_timer(c).isPlaying, isTrue);
      expect(_timer(c).currentIndex, greaterThanOrEqualTo(15));
      expect(tester.takeException(), isNull);
      c.read(wordTimerProvider.notifier).pause();
      await _run(tester, 1);
    });

    testWidgets('the skipped front matter is one tap away', (tester) async {
      final c = await _open(tester);
      await _run(tester, 1.2);
      await tester.tap(find.byKey(ChapterTitleCard.readFromStartKey));
      await _run(tester, 0.2);

      // Back at the first word; the copyright page is front matter, so its
      // heading is shown whole rather than as a chapter card.
      expect(find.byType(ChapterTitleCard), findsNothing);
      expect(find.byType(SubHeadingCard), findsOneWidget);
      expect(_timer(c).currentIndex, 0);
      await _runUntil(
        tester,
        () => find.byType(SubHeadingCard).evaluate().isEmpty,
      );
      expect(_timer(c).isPlaying, isTrue);
      expect(_timer(c).currentIndex, inInclusiveRange(1, 6));
      c.read(wordTimerProvider.notifier).pause();
      await _run(tester, 1);
    });

    testWidgets('pressing pause on the card leaves the reader paused there', (
      tester,
    ) async {
      final c = await _open(tester);
      await _run(tester, 0.5);
      await tester.tap(find.bySemanticsLabel('Pause reading'));
      await _run(tester, 6);

      expect(find.byType(ChapterTitleCard), findsNothing);
      expect(_timer(c).isPlaying, isFalse);
      expect(_timer(c).currentIndex, 13);
      expect(find.bySemanticsLabel('Resume reading'), findsOneWidget);

      // Resume announces the chapter again, then reads.
      await tester.tap(find.bySemanticsLabel('Resume reading'));
      await _run(tester, 0.2);
      expect(find.byType(ChapterTitleCard), findsOneWidget);
      await tester.tapAt(const Offset(210, 450));
      await _run(tester, 0.6);
      expect(_timer(c).isPlaying, isTrue);
      c.read(wordTimerProvider.notifier).pause();
      await _run(tester, 1);
    });
  });

  group('finishing a chapter', () {
    testWidgets('is marked, then the next chapter is announced', (
      tester,
    ) async {
      final c = await _open(tester);
      // Start reading chapter one.
      await tester.tapAt(const Offset(210, 450));
      await _runUntil(
        tester,
        () => find.byType(SectionCompleteOverlay).evaluate().isNotEmpty,
      );

      expect(find.byType(SectionCompleteOverlay), findsOneWidget);
      expect(find.text('Chapter One complete'), findsOneWidget);
      expect(_timer(c).isPlaying, isFalse);
      // The position waits at chapter two's first word; none of its
      // heading words was flashed.
      const chapterTwo = 13 + 2 + 160;
      expect(_timer(c).currentIndex, chapterTwo);
      expect(find.text('Chapter'), findsNothing);

      await _run(tester, 2.5);
      expect(find.text('160'), findsOneWidget); // words read
      // Next up (and already named under the title in the header).
      expect(find.text('Chapter Two'), findsWidgets);
      await tester.tap(find.byKey(SectionCompleteOverlay.continueKey));
      await _run(tester, 0.3);

      expect(find.byType(SectionCompleteOverlay), findsNothing);
      expect(find.byType(ChapterTitleCard), findsOneWidget);
      await tester.tapAt(const Offset(210, 450));
      await _run(tester, 0.6);
      expect(_timer(c).isPlaying, isTrue);
      expect(_timer(c).currentIndex, greaterThanOrEqualTo(chapterTwo + 2));
      expect(tester.takeException(), isNull);
      c.read(wordTimerProvider.notifier).pause();
      await _run(tester, 1);
    });

    testWidgets('Take a break stays paused at the next chapter', (
      tester,
    ) async {
      final c = await _open(tester);
      await tester.tapAt(const Offset(210, 450));
      await _runUntil(
        tester,
        () => find.byType(SectionCompleteOverlay).evaluate().isNotEmpty,
      );
      await _run(tester, 1.5);
      await tester.tap(find.byKey(SectionCompleteOverlay.breakKey));
      await _run(tester, 8);

      expect(find.byType(SectionCompleteOverlay), findsNothing);
      expect(find.byType(ChapterTitleCard), findsNothing);
      expect(_timer(c).isPlaying, isFalse);
      expect(_timer(c).currentIndex, 13 + 2 + 160);
      expect(find.bySemanticsLabel('Resume reading'), findsOneWidget);
    });

    testWidgets('a short chapter is not celebrated, only announced', (
      tester,
    ) async {
      final c = await _open(tester, document: _book(chapterWords: 40));
      await tester.tapAt(const Offset(210, 450));
      // Read through chapter one (40 words) to the next card.
      await _run(tester, 1);
      await _runUntil(
        tester,
        () => find.byType(ChapterTitleCard).evaluate().isNotEmpty,
      );
      expect(find.byType(SectionCompleteOverlay), findsNothing);
      expect(find.text('Two'), findsOneWidget);
      c.read(wordTimerProvider.notifier).pause();
      await _run(tester, 6);
    });

    testWidgets('with reduced motion nothing continues by itself', (
      tester,
    ) async {
      final c = await _open(tester, reduced: true);
      // The card holds, then reading starts (no animation involved).
      await _runUntil(
        tester,
        () => find.byType(SectionCompleteOverlay).evaluate().isNotEmpty,
      );
      expect(find.byType(SectionCompleteOverlay), findsOneWidget);
      await _run(tester, 15);
      expect(find.byType(SectionCompleteOverlay), findsOneWidget);
      expect(_timer(c).isPlaying, isFalse);
    });
  });

  group('finishing the book', () {
    testWidgets('the finish screen comes before the back matter', (
      tester,
    ) async {
      final c = await _open(tester, document: _book(chapterWords: 40));
      final notifier = c.read(wordTimerProvider.notifier);
      // Jump to a few words before the end of the epilogue and read on.
      const epilogueEnd = 13 + 3 * (2 + 40) - 1;
      await tester.tapAt(const Offset(210, 450));
      await _run(tester, 0.6);
      notifier.seekTo(epilogueEnd - 4);
      await _runUntil(
        tester,
        () => find.byType(BookCompleteOverlay).evaluate().isNotEmpty,
      );

      expect(find.byType(BookCompleteOverlay), findsOneWidget);
      expect(find.text('You finished it'), findsOneWidget);
      expect(find.text('A Small Book'), findsWidgets);
      expect(_timer(c).isPlaying, isFalse);
      // The index is still to come, and is offered.
      expect(find.byKey(BookCompleteOverlay.keepReadingKey), findsOneWidget);

      await _run(tester, 2);
      await tester.tap(find.byKey(BookCompleteOverlay.keepReadingKey));
      await _run(tester, 0.3);
      expect(find.byType(BookCompleteOverlay), findsNothing);
      // The index heading is shown whole, then read on.
      expect(find.byType(SubHeadingCard), findsOneWidget);

      // At the very end the finish screen returns, with nothing more to
      // read.
      await _runUntil(
        tester,
        () => find.byType(BookCompleteOverlay).evaluate().isNotEmpty,
      );
      expect(find.byKey(BookCompleteOverlay.keepReadingKey), findsNothing);
      await _run(tester, 2);

      // Read it again goes back to chapter one, not the copyright page.
      await tester.tap(find.byKey(BookCompleteOverlay.readAgainKey));
      await _run(tester, 0.3);
      expect(find.byType(BookCompleteOverlay), findsNothing);
      expect(find.byType(ChapterTitleCard), findsOneWidget);
      expect(_timer(c).currentIndex, 13);
      expect(tester.takeException(), isNull);
      notifier.pause();
      await _run(tester, 6);
    });

    testWidgets('a short pasted note gets no finish screen', (tester) async {
      final c = await _open(
        tester,
        document: ExtractedDocument(
          sentences: [
            Sentence(words: [for (var i = 0; i < 30; i++) 'w$i']),
          ],
        ),
      );
      await _runUntil(tester, () => _timer(c).isFinished, seconds: 20);
      await _run(tester, 3);
      expect(_timer(c).isFinished, isTrue);
      expect(find.byType(BookCompleteOverlay), findsNothing);
    });
  });

  group('chapters in the reader chrome', () {
    testWidgets('the header names the chapter and opens the contents', (
      tester,
    ) async {
      final c = await _open(tester);
      await tester.tapAt(const Offset(210, 450));
      await _run(tester, 0.8);
      c.read(wordTimerProvider.notifier).pause();
      await _run(tester, 0.3);

      // Chapter under the title; time left in it on the rail.
      expect(find.text('Chapter One'), findsOneWidget);
      expect(find.textContaining('left in chapter'), findsOneWidget);

      await tester.tap(
        find.bySemanticsLabel('Contents: A Small Book, Chapter One'),
      );
      await _run(tester, 0.8);
      expect(find.text('Contents'), findsOneWidget);
      expect(find.text('0 of 3 chapters read'), findsOneWidget);

      // Pick the epilogue: the reader jumps there and announces it.
      await tester.tap(find.text('Epilogue'));
      await _run(tester, 0.8);
      expect(find.text('Contents'), findsNothing);
      expect(find.byType(ChapterTitleCard), findsOneWidget);
      expect(_timer(c).currentIndex, 13 + 2 * (2 + 160));
      await tester.tapAt(const Offset(210, 450));
      await _run(tester, 0.6);
      expect(_timer(c).isPlaying, isTrue);
      c.read(wordTimerProvider.notifier).pause();
      await _run(tester, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening the contents pauses reading; closing stays paused', (
      tester,
    ) async {
      final c = await _open(tester);
      await tester.tapAt(const Offset(210, 450));
      await _run(tester, 0.8);
      expect(_timer(c).isPlaying, isTrue);
      final before = _timer(c).currentIndex;

      await tester.tap(
        find.bySemanticsLabel('Contents: A Small Book, Chapter One'),
      );
      await _run(tester, 0.8);
      expect(_timer(c).isPlaying, isFalse);
      await tester.tap(find.bySemanticsLabel('Close contents'));
      await _run(tester, 0.8);
      await _run(tester, 2);

      expect(_timer(c).isPlaying, isFalse);
      expect(_timer(c).currentIndex, inInclusiveRange(before, before + 3));
    });

    testWidgets('a text without chapters has no contents button', (
      tester,
    ) async {
      final c = await _open(
        tester,
        document: ExtractedDocument(
          sentences: [
            for (var s = 0; s < 30; s++)
              Sentence(words: [for (var i = 0; i < 10; i++) 'w$i']),
          ],
        ),
      );
      await _run(tester, 0.5);
      expect(find.bySemanticsLabel(RegExp('^Contents:')), findsNothing);
      expect(find.textContaining('left in chapter'), findsNothing);
      c.read(wordTimerProvider.notifier).pause();
      await _run(tester, 1);
    });
  });

  group('leaving the app', () {
    testWidgets('pauses reading; coming back stays paused', (tester) async {
      final c = await _open(tester);
      await tester.tapAt(const Offset(210, 450));
      await _run(tester, 0.8);
      expect(_timer(c).isPlaying, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final leftAt = _timer(c).currentIndex;
      expect(_timer(c).isPlaying, isFalse);

      // However long the reader is away, not a word goes by.
      await _run(tester, 5);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _run(tester, 2);
      expect(_timer(c).isPlaying, isFalse);
      expect(_timer(c).currentIndex, leftAt);
      expect(find.bySemanticsLabel('Resume reading'), findsOneWidget);
    });

    testWidgets('a title card does not start reading in the background', (
      tester,
    ) async {
      final c = await _open(tester);
      expect(find.byType(ChapterTitleCard), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _run(tester, 8);
      expect(find.byType(ChapterTitleCard), findsNothing);
      expect(_timer(c).isPlaying, isFalse);
      expect(_timer(c).currentIndex, 13);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _run(tester, 1);
    });
  });

  group('with chapter moments off', () {
    testWidgets('headings read as words and nothing interrupts', (
      tester,
    ) async {
      final c = await _open(tester, chapterMoments: false);
      expect(find.byType(ChapterTitleCard), findsNothing);
      expect(_timer(c).isPlaying, isTrue);
      await _runUntil(tester, () => _timer(c).currentIndex > 13 + 2 + 160 + 5);
      expect(find.byType(SectionCompleteOverlay), findsNothing);
      expect(find.byType(ChapterTitleCard), findsNothing);
      expect(_timer(c).isPlaying, isTrue);
      c.read(wordTimerProvider.notifier).pause();
      await _run(tester, 1);
    });
  });

  test('a chapter counts as read from 150 words', () {
    // The fixtures above rely on it: 160 words celebrates, 40 does not.
    expect(RunThruTiming.celebrationMinWords, 150);
  });
}
