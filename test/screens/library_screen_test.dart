import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/device_capability.dart';
import 'package:runthru/features/content/providers/document_title_provider.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/features/reading/providers/reading_progress_provider.dart';
import 'package:runthru/screens/library_screen.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/paged_tile_well.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Config extends AsyncNotifier<AppConfig> implements ConfigNotifier {
  @override
  Future<AppConfig> build() async =>
      const AppConfig(hasSeenReadingGoalOnboarding: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoInstapaper extends Notifier<InstapaperAuthState>
    implements InstapaperAuth {
  @override
  InstapaperAuthState build() => const InstapaperAuthUnauthenticated();

  @override
  InstapaperClient? get client => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// File path → the title its row shows (as an EPUB's metadata would give).
const Map<String, String> _titles = {
  '/storage/Download/books/pg11.epub': "Alice's Adventures in Wonderland",
  '/storage/Download/books/pg2701.epub': 'Moby Dick; Or, The Whale',
  '/storage/Download/books/frank.epub': 'Frankenstein',
};

const Map<String, String> _authors = {
  '/storage/Download/books/pg11.epub': 'Lewis Carroll',
  '/storage/Download/books/pg2701.epub': 'Herman Melville',
};

/// Known once a book's text has been extracted.
const Map<String, int> _wordCounts = {
  '/storage/Download/books/pg11.epub': 27000,
};

List<PdfEntry> _entries([Iterable<String>? paths]) => [
  for (final path in paths ?? _titles.keys)
    PdfEntry(
      filePath: path,
      fileName: path.split('/').last,
      status: PdfStatus.ready,
    ),
];

Future<ProviderContainer> _open(
  WidgetTester tester, {
  List<PdfEntry>? entries,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final books = entries ?? _entries();
  final container = ProviderContainer(
    overrides: [
      configProvider.overrideWith(_Config.new),
      deviceCapabilityProvider.overrideWithValue(
        const DeviceCapability(
          processorCount: 4,
          maxWorkers: 2,
          isMobile: false,
        ),
      ),
      pdfListProvider.overrideWith((ref) async => books),
      googleDriveAvailableProvider.overrideWithValue(false),
      instapaperAuthProvider.overrideWith(_NoInstapaper.new),
      documentInfoProvider.overrideWith(
        (ref, path) async => DocumentInfo(
          title: _titles[path] ?? path.split('/').last,
          author: _authors[path],
        ),
      ),
      documentWordCountProvider.overrideWith(
        (ref, path) async => _wordCounts[path],
      ),
    ],
  );
  // The queue keeps a periodic timer: the tree and the container go before
  // the test ends, or the framework reports the timer as leaked.
  _opened = container;
  // Nothing is extracted in these tests.
  final queue = container.read(preprocessingQueueProvider.notifier);
  queue.pauseBackground();
  // Every book is extracted and ready to read.
  books.forEach(queue.debugSetEntry);
  await container.read(readingProgressProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LibraryScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

ProviderContainer? _opened;

/// Runs [body] against an opened Library, then takes the screen down.
void _libraryTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      _opened?.dispose();
      _opened = null;
      await tester.pump(const Duration(seconds: 1));
    }
  });
}

Future<void> _search(WidgetTester tester, String query) async {
  if (find.byType(TextFormField).evaluate().isEmpty) {
    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pump();
  }
  await tester.enterText(find.byType(TextFormField), query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  _libraryTest('lists the books under the titles their files carry', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text("Alice's Adventures in Wonderland"), findsOneWidget);
    expect(find.text('Moby Dick; Or, The Whale'), findsOneWidget);
    expect(find.text('Frankenstein'), findsOneWidget);
    expect(find.text('3 books'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _libraryTest('rows say who wrote the book and how long it takes', (
    tester,
  ) async {
    await _open(tester);
    // 27,000 words at the default 300 words a minute. The time is its own
    // piece of text, so a long name gives way to it.
    expect(find.text('Lewis Carroll'), findsOneWidget);
    expect(find.text(' · 1 h 30 min'), findsOneWidget);
    // Not extracted yet: the author alone.
    expect(find.text('Herman Melville'), findsOneWidget);
    // Nothing known about it: as before.
    expect(find.text('Local file'), findsOneWidget);
  });

  _libraryTest('there is no empty Docs section or filter', (tester) async {
    await _open(tester);
    // Nothing the app reads is a "doc": the section could never fill.
    expect(find.text('Docs'), findsNothing);
    expect(find.text('No docs yet.'), findsNothing);
    expect(find.text('Books'), findsWidgets);
    expect(find.text('Articles'), findsWidgets);
  });

  group('search', () {
    _libraryTest('finds a book by a word from its title', (tester) async {
      await _open(tester);
      // The file is pg11.epub: only the title says "Wonderland".
      await _search(tester, 'wonderland');

      expect(find.text("Alice's Adventures in Wonderland"), findsOneWidget);
      expect(find.text('Moby Dick; Or, The Whale'), findsNothing);
      expect(find.text('1 book'), findsOneWidget);
      expect(find.text('No books match this search.'), findsNothing);
    });

    _libraryTest('still finds a book by its file name', (tester) async {
      await _open(tester);
      await _search(tester, 'pg2701');
      expect(find.text('Moby Dick; Or, The Whale'), findsOneWidget);
      expect(find.text('1 book'), findsOneWidget);
    });

    _libraryTest('does not match the folder the files sit in', (tester) async {
      await _open(tester);
      // Every path contains "Download/books".
      await _search(tester, 'download');
      expect(find.text('0 books'), findsOneWidget);
      expect(find.text('No books match this search.'), findsOneWidget);
      expect(find.text('Frankenstein'), findsNothing);
    });

    _libraryTest('narrows Continue Reading as well', (tester) async {
      final container = await _open(tester);
      final progress = container.read(readingProgressProvider.notifier);
      await progress.record(
        contentId: '/storage/Download/books/pg11.epub',
        source: 'local',
        title: "Alice's Adventures in Wonderland",
        wordIndex: 500,
        totalWords: 26000,
      );
      await progress.record(
        contentId: '/storage/Download/books/pg2701.epub',
        source: 'local',
        title: 'Moby Dick; Or, The Whale',
        wordIndex: 9000,
        totalWords: 210000,
      );
      await tester.pump();
      expect(find.text('Continue reading'), findsOneWidget);
      // In the shelf and in Books.
      expect(find.text('Moby Dick; Or, The Whale'), findsNWidgets(2));

      await _search(tester, 'whale');
      expect(find.text('Moby Dick; Or, The Whale'), findsNWidgets(2));
      expect(find.text("Alice's Adventures in Wonderland"), findsNothing);

      // Nothing in progress matches: no shelf, and no "add a source" card.
      await _search(tester, 'frankenstein');
      expect(find.text('Continue reading'), findsNothing);
      expect(find.text('Nothing in progress yet'), findsNothing);
      expect(find.text('Frankenstein'), findsOneWidget);
    });

    _libraryTest('says no articles match, not "connect Instapaper"', (
      tester,
    ) async {
      await _open(tester);
      await _search(tester, 'whale');
      expect(find.text('No articles match this search.'), findsOneWidget);
    });
  });

  group('nothing in progress', () {
    _libraryTest('with books: points at them, not at Sources', (tester) async {
      await _open(tester);
      expect(find.text('Nothing in progress yet'), findsOneWidget);
      expect(
        find.text('Pick something below to start reading.'),
        findsOneWidget,
      );
      expect(find.text('Add a source'), findsNothing);
    });

    _libraryTest('with an empty library: offers to add a source', (
      tester,
    ) async {
      await _open(tester, entries: const []);
      expect(find.text('Nothing in progress yet'), findsOneWidget);
      expect(find.text('Add a source'), findsOneWidget);
    });
  });

  group('finished books', () {
    _libraryTest('leave Continue Reading and show a check on their row', (
      tester,
    ) async {
      final container = await _open(tester);
      final progress = container.read(readingProgressProvider.notifier);
      const path = '/storage/Download/books/frank.epub';
      await progress.record(
        contentId: path,
        source: 'local',
        title: 'Frankenstein',
        wordIndex: 70000,
        totalWords: 78000,
        finished: true,
      );
      await tester.pump();

      expect(find.text('Continue reading'), findsOneWidget);
      expect(find.text('Nothing in progress yet'), findsOneWidget);
      // One row for it, in Books, with the check.
      expect(find.text('Frankenstein'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });

  _libraryTest('a long shelf pages four books at a time', (tester) async {
    final paths = [for (var i = 0; i < 9; i++) '/books/book$i.epub'];
    await _open(tester, entries: _entries(paths));
    expect(find.byType(PagedTileWell), findsOneWidget);
    expect(find.text('book3.epub'), findsOneWidget);
    expect(find.text('book4.epub'), findsNothing);
    expect(find.byKey(PagedTileWell.indicatorKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
