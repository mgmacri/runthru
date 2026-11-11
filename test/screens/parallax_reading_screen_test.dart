import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/core/word_timer.dart';
import 'package:runthru/features/content/models/instapaper_bookmark.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/providers/instapaper_bookmarks_provider.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/features/reading/pacing/pacing_config.dart';
import 'package:runthru/features/reading/providers/reading_mode_provider.dart';
import 'package:runthru/features/reading/providers/reading_progress_provider.dart';
import 'package:runthru/screens/parallax_reading_screen.dart';
import 'package:runthru/services/device_capability.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('where an Instapaper article opens (B-49)', () {
    DateTime at(int seconds) =>
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

    test('never read: the start', () {
      expect(instapaperResumeIndex(totalWords: 1000), 0);
    });

    test('read only elsewhere: where Instapaper says', () {
      expect(
        instapaperResumeIndex(
          totalWords: 1000,
          remoteProgress: 0.5,
          remoteTimestampSeconds: 5000,
        ),
        500,
      );
    });

    test('read only here: the saved word', () {
      expect(
        instapaperResumeIndex(
          totalWords: 1000,
          bookmark: BookmarkData(wordIndex: 312, timestamp: at(5000)),
        ),
        312,
      );
    });

    test('read further on another device since: that position', () {
      expect(
        instapaperResumeIndex(
          totalWords: 1000,
          bookmark: BookmarkData(wordIndex: 300, timestamp: at(5000)),
          remoteProgress: 0.8,
          remoteTimestampSeconds: 9000,
        ),
        800,
      );
    });

    test('a newer position that is behind does not move the reader back', () {
      // A moment's look on another device while this one had not synced.
      expect(
        instapaperResumeIndex(
          totalWords: 1000,
          bookmark: BookmarkData(wordIndex: 800, timestamp: at(5000)),
          remoteProgress: 0.3,
          remoteTimestampSeconds: 9000,
        ),
        800,
      );
    });

    test('an older position that is ahead is left alone', () {
      // The reader went back on this device after reading ahead elsewhere.
      expect(
        instapaperResumeIndex(
          totalWords: 1000,
          bookmark: BookmarkData(wordIndex: 300, timestamp: at(9000)),
          remoteProgress: 0.8,
          remoteTimestampSeconds: 5000,
        ),
        300,
      );
    });

    test('this device\'s own position coming back does not nudge it', () {
      // Sent as 0.3123 of 100000 words, stamped a little later.
      expect(
        instapaperResumeIndex(
          totalWords: 100000,
          bookmark: BookmarkData(wordIndex: 31226, timestamp: at(5000)),
          remoteProgress: 0.3123,
          remoteTimestampSeconds: 5400,
        ),
        31226,
      );
    });

    test('a bookmark without a time gives way to a further position', () {
      expect(
        instapaperResumeIndex(
          totalWords: 1000,
          bookmark: const BookmarkData(wordIndex: 100),
          remoteProgress: 0.4,
          remoteTimestampSeconds: 5000,
        ),
        400,
      );
    });

    test('the saved word is scaled when the text changed length', () {
      expect(
        instapaperResumeIndex(
          totalWords: 2000,
          bookmark: BookmarkData(wordIndex: 500, timestamp: at(5000)),
          savedTotalWords: 1000,
        ),
        1000,
      );
    });

    test('positions past the end land on the last word', () {
      expect(
        instapaperResumeIndex(
          totalWords: 40,
          remoteProgress: 1,
          remoteTimestampSeconds: 5000,
        ),
        39,
      );
      expect(
        instapaperResumeIndex(
          totalWords: 40,
          bookmark: BookmarkData(wordIndex: 400, timestamp: at(5000)),
        ),
        39,
      );
      expect(instapaperResumeIndex(totalWords: 0, remoteProgress: 0.5), 0);
    });
  });

  group('reading an Instapaper article (B-49)', () {
    late _RecordingInstapaperClient client;
    ProviderContainer? opened;

    /// A 40-word article at 600 words a minute: 100 ms a word.
    Future<ProviderContainer> openArticle(
      WidgetTester tester, {
      double remoteProgress = 0,
      int remoteTimestamp = 0,
      ReadingMode mode = ReadingMode.singleWord,
      int words = 40,
    }) async {
      SharedPreferences.setMockInitialValues({});
      client = _RecordingInstapaperClient();
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWith(
            () => _FakeConfigNotifier(
              const AppConfig(
                hasSeenReadingGoalOnboarding: true,
                defaultWpm: 600,
                // No title cards or finish screens: the plain end of text.
                chapterMoments: false,
              ),
            ),
          ),
          instapaperAuthProvider.overrideWith(
            () => _ConnectedInstapaper(client),
          ),
        ],
      );
      opened = container;
      // As in the app, where the Library keeps the progress store alive.
      container.listen(readingProgressProvider, (_, __) {});
      await container.read(readingProgressProvider.future);
      container.read(readingModeNotifierProvider.notifier).setMode(mode);
      // The article is in the list, as it is when opened from the Library.
      await container.read(instapaperBookmarksProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ParallaxReadingScreen(
              filePath: 'instapaper://42',
              contentSource: 'instapaper',
              instapaperBookmarkId: 42,
              instapaperInitialProgress: remoteProgress,
              instapaperProgressTimestamp: remoteTimestamp,
              clipboardDocument: ClipboardDocument(
                title: 'An Article',
                fullText: '',
                document: ExtractedDocument(
                  sentences: [
                    for (var s = 0; s < words ~/ 10; s++)
                      Sentence(
                        words: [for (var i = 0; i < 10; i++) 'w${s * 10 + i}'],
                      ),
                  ],
                ),
                pastedAt: _openedAt,
              ),
            ),
          ),
        ),
      );
      // The article loads a few async steps after the first frame; no word
      // has flashed by then (the first is 100 ms away).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      return container;
    }

    Future<void> leave(WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );
      expect(tester.takeException(), isNull);
      // Let the title lookup's timeout and the sync throttles finish.
      await tester.pump(const Duration(seconds: 10));
    }

    /// Runs [body], then disposes the container the article was opened in
    /// before the test ends (its notifiers keep periodic timers).
    void articleTest(
      String description,
      Future<void> Function(WidgetTester tester) body,
    ) {
      testWidgets(description, (tester) async {
        try {
          await body(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          opened?.dispose();
          opened = null;
        }
      });
    }

    articleTest('opened and left without reading: nothing is sent', (
      tester,
    ) async {
      final container = await openArticle(
        tester,
        remoteProgress: 0.5,
        remoteTimestamp: 1700000000,
      );
      // Opens where Instapaper has it.
      expect(container.read(wordTimerProvider).currentIndex, 20);

      await leave(tester, container);

      expect(client.calls, isEmpty);
      expect(
        await container.read(instapaperSyncQueueProvider).pendingOps(),
        isEmpty,
      );
    });

    articleTest('read for a while and left: the position is sent', (
      tester,
    ) async {
      final container = await openArticle(tester);
      await tester.pump(const Duration(seconds: 2));
      final index = container.read(wordTimerProvider).currentIndex;
      expect(index, inInclusiveRange(10, 30));

      await leave(tester, container);

      final last = client.calls.last;
      expect(last, startsWith('progress:42:'));
      expect(double.parse(last.split(':')[2]), closeTo(index / 40, 0.11));
      expect(client.calls.where((c) => c.startsWith('archive')), isEmpty);
      // Still in the list, with its progress.
      final listed = container.read(instapaperBookmarksProvider).value!.single;
      expect(listed.progress, greaterThan(0.2));
    });

    articleTest('read to the last word: 100%, then archived, once', (
      tester,
    ) async {
      final container = await openArticle(tester);
      // 40 words at 100 ms each, plus the pauses at sentence ends.
      await tester.pump(const Duration(seconds: 15));
      expect(container.read(wordTimerProvider).isFinished, isTrue);

      await leave(tester, container);

      final finish = client.calls.indexOf('progress:42:1.0000');
      expect(finish, isNot(-1), reason: '${client.calls}');
      // The archive follows the final position, and nothing follows it.
      expect(client.calls.sublist(finish), [
        'progress:42:1.0000',
        'archive:42',
      ]);
      expect(container.read(instapaperBookmarksProvider).value, isEmpty);
      final record = container
          .read(readingProgressProvider.notifier)
          .getRecord('instapaper://42');
      expect(record?.finished, isTrue);
    });

    articleTest('an article that opens on its last word is not archived', (
      tester,
    ) async {
      // Finished on another device and kept there, unarchived. Long enough
      // for the finish screen (a shorter text starts over instead).
      final container = await openArticle(
        tester,
        words: 200,
        remoteProgress: 1,
        remoteTimestamp: 1700000000,
      );
      expect(container.read(wordTimerProvider).currentIndex, 199);
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('You finished'), findsWidgets);

      await leave(tester, container);

      expect(client.calls, isEmpty);
      expect(container.read(instapaperBookmarksProvider).value, hasLength(1));
    });

    articleTest('Book mode: turning past the last page finishes the article', (
      tester,
    ) async {
      final container = await openArticle(tester, mode: ReadingMode.book);
      await tester.pump(const Duration(milliseconds: 500));

      // A tap on the right of the page turns it; on the last page that
      // turns past the end.
      for (var i = 0; i < 4; i++) {
        await tester.tapAt(const Offset(600, 300));
        await tester.pump(const Duration(milliseconds: 400));
      }

      await leave(tester, container);

      expect(
        client.calls,
        containsAllInOrder(['progress:42:1.0000', 'archive:42']),
      );
      expect(client.calls.where((c) => c == 'archive:42'), hasLength(1));
      expect(container.read(instapaperBookmarksProvider).value, isEmpty);
      final record = container
          .read(readingProgressProvider.notifier)
          .getRecord('instapaper://42');
      expect(record?.finished, isTrue);
    });
  });

  group('ParallaxReadingScreen first-run onboarding', () {
    testWidgets('fresh direct reader stays paused before gate completion', (
      tester,
    ) async {
      final config = _FakeConfigNotifier(const AppConfig());

      await tester.pumpWidget(_readingHarness(config));
      await tester.pump();
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);
      expect(find.text('Reading, brought to you.'), findsNothing);
      final context = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(context);
      expect(container.read(wordTimerProvider).isPlaying, isFalse);
    });

    testWidgets('completed onboarding flag skips onboarding', (tester) async {
      final config = _FakeConfigNotifier(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );

      await tester.pumpWidget(_readingHarness(config));
      await tester.pump();
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);
      expect(find.text('Reading, brought to you.'), findsNothing);
      expect(find.text('Tap to pause'), findsOneWidget);
      final context = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(context);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
    });

    testWidgets('startup waits for onboarding state before reading gate', (
      tester,
    ) async {
      final config = _FakeConfigNotifier.delayed();

      await tester.pumpWidget(_readingHarness(config));
      await tester.pump();
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);

      config.complete(const AppConfig());
      await tester.pump();
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);
      final context = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(context);
      expect(container.read(wordTimerProvider).isPlaying, isFalse);
    });

    testWidgets('pause focus mode toggle persists without retriggering hints', (
      tester,
    ) async {
      final config = _FakeConfigNotifier(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );

      await tester.pumpWidget(_readingHarness(config, disableAnimations: true));
      await tester.pump();
      await tester.pump();

      final context = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(context);
      container.read(wordTimerProvider.notifier).pause();
      await tester.pump();
      expect(find.text('Focus Mode'), findsOneWidget);

      tester
          .widget<Switch>(find.byKey(const ValueKey('pause-focus-mode-switch')))
          .onChanged
          ?.call(true);
      await tester.pump();
      await tester.pump();

      expect(config.state.requireValue.focusModeEnabled, isTrue);
      expect(find.text('Tap anywhere to pause or resume'), findsNothing);

      await tester.tapAt(const Offset(20, 260));
      // The paused tap routes through the main reader detector, which also
      // listens for double-taps — resume fires after the double-tap window.
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
    });

    testWidgets(
      'paused reader controls drive sentence seek and speed changes',
      (tester) async {
        final config = _FakeConfigNotifier(
          const AppConfig(hasSeenReadingGoalOnboarding: true),
        );

        await tester.pumpWidget(_readingHarness(config));
        await tester.pump();
        await tester.pump();

        final context = tester.element(find.byType(MaterialApp));
        final container = ProviderScope.containerOf(context);
        final timer = container.read(wordTimerProvider.notifier);

        timer.pause();
        await tester.pump();

        expect(find.bySemanticsLabel('Resume reading'), findsOneWidget);
        expect(find.byTooltip('Previous sentence'), findsOneWidget);
        expect(find.byTooltip('Next sentence'), findsOneWidget);
        expect(find.text('200'), findsOneWidget);
        expect(find.text('300'), findsOneWidget);
        expect(find.text('400'), findsOneWidget);
        expect(find.text('500'), findsOneWidget);
        // Sentence-below panel renders the sentence as RichText with the
        // live word inked.
        expect(find.text('First run works', findRichText: true), findsWidgets);

        await tester.tap(
          find.byIcon(Icons.keyboard_double_arrow_right_rounded),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(container.read(wordTimerProvider).currentIndex, 3);
        expect(
          find.text('Second sentence exists', findRichText: true),
          findsWidgets,
        );

        await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left_rounded));
        await tester.pump(const Duration(milliseconds: 50));
        expect(container.read(wordTimerProvider).currentIndex, 0);
        expect(find.text('First run works', findRichText: true), findsWidgets);

        await tester.tap(find.text('400'));
        await tester.pump(const Duration(milliseconds: 50));
        expect(container.read(wordTimerProvider).wpm, 400);
      },
    );

    testWidgets('persistent tray and speed selector visible while playing', (
      tester,
    ) async {
      final config = _FakeConfigNotifier(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );

      await tester.pumpWidget(_readingHarness(config, disableAnimations: true));
      await tester.pump();
      await tester.pump();

      final context = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(context);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);

      // Persistent tray always visible in non-focus mode.
      expect(find.byTooltip('Previous sentence'), findsOneWidget);
      expect(find.byTooltip('Next sentence'), findsOneWidget);
      expect(find.text('SPEED'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      // While playing the play/pause button has 'Pause reading' label.
      expect(find.bySemanticsLabel('Pause reading'), findsOneWidget);
      expect(find.bySemanticsLabel('Resume reading'), findsNothing);
    });

    testWidgets('leaving a local book after reading does not throw', (
      tester,
    ) async {
      // dispose() records Continue Reading progress, which reads the title;
      // the title must not touch `ref` there (it is invalid during dispose).
      final config = _FakeConfigNotifier(
        const AppConfig(hasSeenReadingGoalOnboarding: true, defaultWpm: 600),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(() => config)],
          child: MaterialApp(
            home: ParallaxReadingScreen(
              filePath: '/books/local-book.epub',
              contentSource: 'local',
              clipboardDocument: ClipboardDocument(
                title: '',
                fullText: '',
                document: ExtractedDocument(
                  sentences: [
                    Sentence(words: [for (var i = 0; i < 40; i++) 'w$i']),
                  ],
                ),
                pastedAt: _openedAt,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      // Let the title lookup's timeout and sync throttles finish.
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('leaving a library book releases its text without throwing', (
      tester,
    ) async {
      // dispose() used to change PreprocessingQueue state while the tree was
      // being torn down. Riverpod asserts on that, and the throw skipped the
      // rest of dispose: system bars stayed hidden after leaving a book.
      SharedPreferences.setMockInitialValues({});
      final config = _FakeConfigNotifier(
        const AppConfig(hasSeenReadingGoalOnboarding: true, defaultWpm: 600),
      );
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWith(() => config),
          deviceCapabilityProvider.overrideWithValue(
            const DeviceCapability(
              processorCount: 4,
              maxWorkers: 2,
              isMobile: false,
            ),
          ),
          pdfListProvider.overrideWith((ref) async => const <PdfEntry>[]),
        ],
      );
      const path = '/books/queued.pdf';
      final queue = container.read(preprocessingQueueProvider.notifier);
      queue.pauseBackground();
      queue.debugSetEntry(
        PdfEntry(
          filePath: path,
          fileName: 'queued.pdf',
          status: PdfStatus.ready,
          document: ExtractedDocument(
            sentences: [
              Sentence(words: [for (var i = 0; i < 40; i++) 'w$i']),
            ],
            pageBoundaries: const [
              PageBoundary(
                pageNumber: 0,
                startSentenceIndex: 0,
                startWordIndex: 0,
              ),
            ],
            totalPages: 1,
          ),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ParallaxReadingScreen(filePath: path)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(
        container.read(preprocessingQueueProvider)[path]!.document,
        isNotNull,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(
        container.read(preprocessingQueueProvider)[path]!.document,
        isNull,
      );

      await tester.pump(const Duration(seconds: 10));
      container.dispose();
    });

    testWidgets('speed chips highlight only an exact speed match', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      bool selected(String label) =>
          tester
              .getSemantics(find.bySemanticsLabel(RegExp('^$label')))
              .getSemanticsData()
              .flagsCollection
              .isSelected
              .toBoolOrNull() ??
          false;

      await tester.pumpWidget(
        _readingHarness(
          _FakeConfigNotifier(
            const AppConfig(
              hasSeenReadingGoalOnboarding: true,
              defaultWpm: 250,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // 250 sits between chips: none may claim to be the current speed.
      for (final label in ['200 WPM', '300 WPM', '400 WPM', '500 WPM']) {
        expect(selected(label), isFalse, reason: label);
      }
      handle.dispose();
    });

    testWidgets(
      'speed selector tour target covers visible label and speed buttons',
      (tester) async {
        final config = _FakeConfigNotifier(
          const AppConfig(hasSeenReadingGoalOnboarding: true),
        );

        await tester.pumpWidget(_readingHarness(config));
        await tester.pump();
        await tester.pump();

        final speedSelector = find.byKey(
          const ValueKey('reader-speed-selector-visible-group'),
        );
        expect(speedSelector, findsOneWidget);

        final targetRect = tester.getRect(speedSelector);
        expect(targetRect.isEmpty, isFalse);

        final speedLabelRect = tester.getRect(find.text('SPEED'));
        final buttonRects = [
          tester.getRect(find.text('200')),
          tester.getRect(find.text('300')),
          tester.getRect(find.text('400')),
          tester.getRect(find.text('500')),
        ];
        final visibleGroupRect = buttonRects.fold<Rect>(
          speedLabelRect,
          (rect, buttonRect) => rect.expandToInclude(buttonRect),
        );

        expect(targetRect.contains(speedLabelRect.topLeft), isTrue);
        expect(targetRect.contains(speedLabelRect.bottomRight), isTrue);
        for (final buttonRect in buttonRects) {
          expect(targetRect.contains(buttonRect.topLeft), isTrue);
          expect(targetRect.contains(buttonRect.bottomRight), isTrue);
        }

        expect(
          targetRect.width,
          lessThanOrEqualTo(visibleGroupRect.width + 40),
        );
        // Height slack accounts for the 48dp minimum tap target on the
        // speed chips (RunThruA11y.minTapTarget) plus the pill padding.
        expect(
          targetRect.height,
          lessThanOrEqualTo(visibleGroupRect.height + 48),
        );
      },
    );

    // WCAG 2.2 AA — the paused reading surface (full chrome visible) must
    // meet tap-target, text-contrast, and labeled-target guidelines.
    testWidgets('paused reading screen meets accessibility guidelines', (
      tester,
    ) async {
      // The VM test platform reports as desktop Linux, so the screen calls
      // window_manager for fullscreen. Stub the channel so its
      // MissingPluginException can't surface inside the expectLater awaits.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        ),
      );
      final handle = tester.ensureSemantics();
      final config = _FakeConfigNotifier(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );

      await tester.pumpWidget(_readingHarness(config, disableAnimations: true));
      await tester.pump();
      await tester.pump();

      final context = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(context);
      container.read(wordTimerProvider.notifier).pause();
      await tester.pump();
      await tester.pump();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('tapping play/pause button in tray toggles wordTimerProvider', (
      tester,
    ) async {
      final config = _FakeConfigNotifier(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );

      await tester.pumpWidget(_readingHarness(config, disableAnimations: true));
      await tester.pump();
      await tester.pump();

      final context = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(context);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);

      // Tap the tray's pause button to stop playback.
      await tester.tap(find.bySemanticsLabel('Pause reading'));
      await tester.pump();
      expect(container.read(wordTimerProvider).isPlaying, isFalse);

      // Tap the tray's play button to resume.
      await tester.tap(find.bySemanticsLabel('Resume reading'));
      await tester.pump();
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
    });

    testWidgets('progress rail shows pct and WPM label', (tester) async {
      final config = _FakeConfigNotifier(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );

      await tester.pumpWidget(_readingHarness(config, disableAnimations: true));
      await tester.pump();
      await tester.pump();

      // Progress rail renders a percentage and WPM label.
      expect(find.textContaining('%'), findsAtLeastNWidgets(1));
      expect(find.textContaining('WPM'), findsAtLeastNWidgets(1));
    });

    testWidgets('focus mode hides reader chrome and paused controls', (
      tester,
    ) async {
      final config = _FakeConfigNotifier(
        const AppConfig(
          hasSeenReadingGoalOnboarding: true,
          focusModeEnabled: true,
        ),
      );

      await tester.pumpWidget(_readingHarness(config, disableAnimations: true));
      await tester.pump();
      await tester.pump();

      expect(find.text('Tap to pause'), findsNothing);

      final context = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(context);
      container.read(wordTimerProvider.notifier).pause();
      await tester.pump();

      // The pause overlay keeps the Focus Mode toggle visible — it is the
      // only way back out of focus mode.
      expect(find.text('Focus Mode'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.bySemanticsLabel('Resume reading'), findsNothing);
      expect(find.byTooltip('Previous sentence'), findsNothing);
      expect(find.byTooltip('Next sentence'), findsNothing);
      expect(find.text('200'), findsNothing);
      expect(find.text('300'), findsNothing);
      expect(find.text('400'), findsNothing);
      expect(find.text('500'), findsNothing);
      expect(
        find.byKey(const ValueKey('pause-focus-mode-switch')),
        findsOneWidget,
      );
    });
  });

  // B-55: nothing handed the Word Pacing settings to the timer, so reading
  // always used the default pacing whatever the sliders said; and speed
  // changed in Settings opened over the reader ("Aa") was ignored until the
  // next book.
  group('speed and word pacing from Settings (B-55)', () {
    const pacing = PacingConfig(
      longWordScalePercent: 175,
      punctuationScalePercent: 50,
    );

    testWidgets('the reader paces with the saved Word Pacing', (tester) async {
      final config = _FakeConfigNotifier(
        const AppConfig(
          hasSeenReadingGoalOnboarding: true,
          pacingConfig: pacing,
        ),
      );
      await tester.pumpWidget(_readingHarness(config));
      await tester.pump();
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(container.read(wordTimerProvider).pacingConfig, pacing);
    });

    testWidgets('changes made in Settings over the reader apply on return', (
      tester,
    ) async {
      final config = _FakeConfigNotifier(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );
      await tester.pumpWidget(_readingHarness(config));
      await tester.pump();
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      container.read(wordTimerProvider.notifier).pause();
      await tester.pump();
      expect(container.read(wordTimerProvider).wpm, 300);
      expect(
        container.read(wordTimerProvider).pacingConfig,
        defaultPacingConfig,
      );

      // What the Reading Speed and Word Pacing controls write.
      await config.setDefaultWpm(420);
      await config.updatePacingConfig(pacing);
      await tester.pump();

      expect(container.read(wordTimerProvider).wpm, 420);
      expect(container.read(wordTimerProvider).pacingConfig, pacing);
    });
  });
}

final _openedAt = DateTime(2026, 5, 24);

Widget _readingHarness(
  _FakeConfigNotifier config, {
  bool disableAnimations = false,
}) {
  return ProviderScope(
    overrides: [configProvider.overrideWith(() => config)],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          accessibleNavigation: false,
          disableAnimations: disableAnimations,
        ),
        child: ParallaxReadingScreen(
          filePath: 'clipboard://first-run',
          contentSource: 'clipboard',
          clipboardDocument: ClipboardDocument(
            title: 'First Run',
            fullText: '',
            document: const ExtractedDocument(
              sentences: [
                Sentence(words: ['First', 'run', 'works']),
                Sentence(words: ['Second', 'sentence', 'exists']),
              ],
            ),
            pastedAt: _openedAt,
          ),
        ),
      ),
    ),
  );
}

/// A signed-in Instapaper account whose requests are recorded.
class _ConnectedInstapaper extends Notifier<InstapaperAuthState>
    implements InstapaperAuth {
  _ConnectedInstapaper(this._client);

  final InstapaperClient _client;

  @override
  InstapaperAuthState build() => const InstapaperAuthAuthenticated(
    user: InstapaperUser(userId: 1, username: 'reader'),
  );

  @override
  InstapaperClient? get client => _client;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingInstapaperClient extends InstapaperClient {
  _RecordingInstapaperClient()
    : super(
        config: const InstapaperClientConfig(
          consumerKey: 'k',
          consumerSecret: 's',
        ),
      );

  /// "progress:<id>:<0.0000>" and "archive:<id>", in the order sent.
  final calls = <String>[];

  @override
  Future<InstapaperBookmarkPage> fetchBookmarks({
    int limit = InstapaperClient.maxListLimit,
    String folderId = 'unread',
  }) async => const InstapaperBookmarkPage(
    bookmarks: [
      InstapaperBookmark(
        bookmarkId: 42,
        url: 'https://example.com/a',
        title: 'An Article',
      ),
    ],
  );

  @override
  Future<void> updateReadProgress({
    required int bookmarkId,
    required double progress,
    int? timestampSeconds,
  }) async => calls.add('progress:$bookmarkId:${progress.toStringAsFixed(4)}');

  @override
  Future<void> archiveBookmark({required int bookmarkId}) async =>
      calls.add('archive:$bookmarkId');
}

class _FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  _FakeConfigNotifier(this._initial);

  _FakeConfigNotifier.delayed() : _initial = null;

  final AppConfig? _initial;
  final Completer<AppConfig> _completer = Completer<AppConfig>();

  @override
  Future<AppConfig> build() async {
    final initial = _initial;
    if (initial != null) return initial;
    return _completer.future;
  }

  void complete(AppConfig config) {
    if (!_completer.isCompleted) {
      _completer.complete(config);
    }
  }

  @override
  Future<void> applyReadingGoalPreset(ReadingGoalConfig goal) async {
    state = AsyncData(
      state.requireValue.copyWith(
        defaultWpm: goal.wpm,
        parallaxIntensity: goal.parallaxIntensity,
        readingGoalPreset: goal.preset,
      ),
    );
  }

  @override
  Future<void> setHasSeenReadingGoalOnboarding(bool seen) async {
    state = AsyncData(
      state.requireValue.copyWith(hasSeenReadingGoalOnboarding: seen),
    );
  }

  @override
  Future<void> setFocusModeEnabled(bool enabled) async {
    state = AsyncData(state.requireValue.copyWith(focusModeEnabled: enabled));
  }

  @override
  Future<void> setDefaultWpm(int wpm) async {
    state = AsyncData(state.requireValue.copyWith(defaultWpm: wpm));
  }

  @override
  Future<void> updatePacingConfig(PacingConfig pacingConfig) async {
    state = AsyncData(state.requireValue.copyWith(pacingConfig: pacingConfig));
  }

  @override
  bool hasHintBeenShown(String id) {
    return state.valueOrNull?.shownHints.contains(id) ?? false;
  }

  @override
  Future<void> markHintShown(String id) async {
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(shownHints: {...current.shownHints, id}),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
