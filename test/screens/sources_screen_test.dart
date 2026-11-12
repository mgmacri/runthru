import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/features/content/models/instapaper_bookmark.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/drive_local_store.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/screens/home_shell.dart';
import 'package:runthru/screens/sources_screen.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/store/library_source.dart';
import 'package:runthru/store/library_sources.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInstapaperAuth extends Notifier<InstapaperAuthState>
    implements InstapaperAuth {
  _FakeInstapaperAuth(this.initialState, {this.fakeClient});

  final InstapaperAuthState initialState;

  /// Handed out while the state is "connected".
  final InstapaperClient? fakeClient;

  @override
  InstapaperAuthState build() => initialState;

  @override
  InstapaperClient? get client =>
      state is InstapaperAuthAuthenticated ? fakeClient : null;

  @override
  Future<void> login({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> logout() async {
    state = const InstapaperAuthUnauthenticated();
  }

  @override
  Future<void> connect() async {
    state = const InstapaperAuthLegacyFallbackRequired(
      message: 'Use legacy sign-in instead.',
    );
  }

  @override
  Future<void> sessionExpired() async {
    state = const InstapaperAuthError(
      kind: InstapaperFailureKind.unauthorized,
      message: 'Instapaper needs you to sign in again.',
    );
  }

  @override
  Future<void> checkSession() async {}

  @override
  void updateUser(InstapaperUser user) {}

  @override
  void dismissError() {
    if (state is InstapaperAuthError) {
      state = const InstapaperAuthUnauthenticated();
    }
  }
}

/// An Instapaper account with two unread articles, scriptable to fail.
class _FakeInstapaperClient extends InstapaperClient {
  _FakeInstapaperClient()
    : super(
        config: const InstapaperClientConfig(
          consumerKey: 'k',
          consumerSecret: 's',
        ),
      );

  List<InstapaperBookmark> bookmarks = [
    const InstapaperBookmark(
      bookmarkId: 1,
      url: 'https://www.example.com/first',
      title: 'First Article',
      description: 'A short description of the first article.',
    ),
    const InstapaperBookmark(
      bookmarkId: 2,
      url: 'https://news.example.org/second',
      title: 'Second Article',
    ),
  ];
  Object? listError;
  int listCalls = 0;

  String text = '<p>Enough words here to make an article worth reading.</p>';
  Object? textError;
  Completer<void>? textGate;
  final textCalls = <int>[];

  @override
  Future<InstapaperBookmarkPage> fetchBookmarks({
    int limit = InstapaperClient.maxListLimit,
    String folderId = 'unread',
  }) async {
    listCalls++;
    final error = listError;
    if (error != null) throw error;
    return InstapaperBookmarkPage(bookmarks: List.of(bookmarks));
  }

  @override
  Future<String> getBookmarkText({required int bookmarkId}) async {
    textCalls.add(bookmarkId);
    await textGate?.future;
    final error = textError;
    if (error != null) throw error;
    return text;
  }

  @override
  Future<void> updateReadProgress({
    required int bookmarkId,
    required double progress,
    int? timestampSeconds,
  }) async {}

  @override
  Future<void> archiveBookmark({required int bookmarkId}) async {}
}

class _FakeGoogleDriveAuth extends Notifier<GoogleDriveAuthState>
    implements GoogleDriveAuth {
  _FakeGoogleDriveAuth(this.initialState);

  final GoogleDriveAuthState initialState;
  var grantAccessCalls = 0;

  @override
  GoogleDriveAuthState build() => initialState;

  @override
  Future<Map<String, String>> authorizationHeaders({
    GoogleDriveAccessMode? accessMode,
    bool allowInteractivePrompt = false,
  }) async => {};

  @override
  Future<void> connect({GoogleDriveAccessMode? accessMode}) async {
    state = const GoogleDriveAuthAuthenticated(
      user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
    );
  }

  @override
  Future<bool> grantDriveAccess() async {
    grantAccessCalls++;
    return true;
  }

  @override
  Future<void> disconnect() async {
    state = const GoogleDriveAuthUnauthenticated();
  }
}

class _FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  _FakeConfigNotifier(this._config);

  final AppConfig _config;

  @override
  Future<AppConfig> build() async => _config;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGoogleDriveClient extends GoogleDriveClient {
  _FakeGoogleDriveClient({this.metadataError})
    : super(headersProvider: () async => {});

  final String exportedText = 'Drive document text.';
  final GoogleDriveException? listError = null;
  final GoogleDriveException? metadataError;
  final GoogleDriveFile metadataFile = const GoogleDriveFile(
    id: 'drive-doc',
    name: 'Drive Doc',
    mimeType: googleDocsMimeType,
  );

  @override
  Future<List<GoogleDriveFile>> listDriveFiles({
    String? query,
    int maxResults = GoogleDriveClient.defaultMaxListResults,
  }) async {
    final failure = listError;
    if (failure != null) throw failure;
    return [metadataFile];
  }

  @override
  Future<GoogleDriveFile> metadata(String fileId) async {
    final failure = metadataError;
    if (failure != null) throw failure;
    return GoogleDriveFile(
      id: fileId,
      name: metadataFile.name,
      mimeType: metadataFile.mimeType,
    );
  }

  @override
  Future<String> exportGoogleDoc(
    GoogleDriveFile file, {
    String exportMimeType = plainTextMimeType,
  }) async {
    return exportedText;
  }
}

Widget _harness(
  Widget child, {
  bool driveAvailable = true,
  bool instapaperAvailable = true,
}) {
  SharedPreferences.setMockInitialValues({});
  return ProviderScope(
    overrides: [
      // Tests run without OAuth dart-defines; opt in explicitly (R-04).
      googleDriveAvailableProvider.overrideWithValue(driveAvailable),
      instapaperAvailableProvider.overrideWithValue(instapaperAvailable),
      instapaperAuthProvider.overrideWith(
        () => _FakeInstapaperAuth(const InstapaperAuthUnauthenticated()),
      ),
      googleDriveAuthProvider.overrideWith(
        () => _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated()),
      ),
      googleDriveClientProvider.overrideWithValue(_FakeGoogleDriveClient()),
      // Widget tests run under FakeAsync — real file I/O in the Drive
      // local-copy lookup would never complete. A null root disables it.
      driveLocalStoreProvider.overrideWithValue(
        DriveLocalStore(rootResolver: () async => null),
      ),
      configProvider.overrideWith(
        () => _FakeConfigNotifier(
          const AppConfig(
            hasSeenReadingGoalOnboarding: true,
            googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
          ),
        ),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

Widget _harnessWithSources(List<LibrarySource> sources) {
  SharedPreferences.setMockInitialValues({});
  return ProviderScope(
    overrides: [
      librarySourcesProvider.overrideWith(() => _FakeLibrarySources(sources)),
      googleDriveAvailableProvider.overrideWithValue(true),
      instapaperAvailableProvider.overrideWithValue(true),
      instapaperAuthProvider.overrideWith(
        () => _FakeInstapaperAuth(const InstapaperAuthUnauthenticated()),
      ),
      googleDriveAuthProvider.overrideWith(
        () => _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated()),
      ),
      googleDriveClientProvider.overrideWithValue(_FakeGoogleDriveClient()),
      // Widget tests run under FakeAsync — real file I/O in the Drive
      // local-copy lookup would never complete. A null root disables it.
      driveLocalStoreProvider.overrideWithValue(
        DriveLocalStore(rootResolver: () async => null),
      ),
      configProvider.overrideWith(
        () => _FakeConfigNotifier(
          const AppConfig(
            hasSeenReadingGoalOnboarding: true,
            googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
          ),
        ),
      ),
    ],
    child: const MaterialApp(home: SourcesScreen()),
  );
}

Widget _homeShellRouterHarness({
  required GoogleDriveAuthState driveAuthState,
  required void Function(Map<String, Object?> extra) onReadDrive,
  _FakeGoogleDriveAuth? driveAuth,
  GoogleDriveClient? driveClient,
  Map<String, Object>? sharedPreferences = const {},
  InstapaperAuthState instapaperState = const InstapaperAuthUnauthenticated(),
  InstapaperClient? instapaperClient,
  void Function(Map<String, Object?> extra)? onReadInstapaper,
}) {
  SharedPreferences.setMockInitialValues(sharedPreferences ?? const {});
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => const MaterialPage(child: HomeShell()),
      ),
      GoRoute(
        path: '/read-drive',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, Object?>;
          return MaterialPage(
            child: _ReadDriveProbe(extra: extra, onShown: onReadDrive),
          );
        },
      ),
      GoRoute(
        path: '/read-instapaper',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, Object?>;
          return MaterialPage(
            child: _ReadDriveProbe(
              extra: extra,
              onShown: onReadInstapaper ?? (_) {},
              label: 'Instapaper Reader',
            ),
          );
        },
      ),
      GoRoute(
        path: '/elsewhere',
        builder: (context, state) => const Scaffold(body: Text('Elsewhere')),
      ),
      GoRoute(path: '/sources', redirect: (_, __) => '/?tab=1'),
    ],
  );
  return ProviderScope(
    overrides: [
      instapaperAuthProvider.overrideWith(
        () =>
            _FakeInstapaperAuth(instapaperState, fakeClient: instapaperClient),
      ),
      instapaperAvailableProvider.overrideWithValue(true),
      googleDriveAvailableProvider.overrideWithValue(true),
      googleDriveAuthProvider.overrideWith(
        () => driveAuth ?? _FakeGoogleDriveAuth(driveAuthState),
      ),
      googleDriveClientProvider.overrideWithValue(
        driveClient ?? _FakeGoogleDriveClient(),
      ),
      driveLocalStoreProvider.overrideWithValue(
        DriveLocalStore(rootResolver: () async => null),
      ),
      configProvider.overrideWith(
        () => _FakeConfigNotifier(
          const AppConfig(
            hasSeenReadingGoalOnboarding: true,
            googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
          ),
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

class _ReadDriveProbe extends StatefulWidget {
  const _ReadDriveProbe({
    required this.extra,
    required this.onShown,
    this.label = 'Drive Reader',
  });

  final Map<String, Object?> extra;
  final void Function(Map<String, Object?> extra) onShown;
  final String label;

  @override
  State<_ReadDriveProbe> createState() => _ReadDriveProbeState();
}

class _ReadDriveProbeState extends State<_ReadDriveProbe> {
  @override
  void initState() {
    super.initState();
    widget.onShown(widget.extra);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Text(widget.label));
  }
}

class _FakeLibrarySources extends LibrarySourcesNotifier {
  _FakeLibrarySources(this.sources);

  final List<LibrarySource> sources;

  @override
  Future<List<LibrarySource>> build() async => sources;
}

const _driveConnected = GoogleDriveAuthAuthenticated(
  user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
);

Map<String, Object> _progressPrefsWithDriveShelfItem() {
  return {
    'runthru_reading_progress': jsonEncode([
      {
        'contentId': 'drive://drive-doc',
        'source': 'drive',
        'title': 'Drive Doc',
        'wordIndex': 10,
        'totalWords': 100,
        'lastReadAt': DateTime(2026, 5, 25).toIso8601String(),
        'finished': false,
      },
    ]),
  };
}

void main() {
  group('SourcesScreen', () {
    testWidgets('renders dedicated source filters and the moved plus menu', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(const SourcesScreen()));
      await tester.pump();

      expect(find.text('Sources'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Folders'), findsWidgets);
      expect(find.text('Files'), findsWidgets);
      expect(find.text('Articles'), findsWidgets);
      expect(find.bySemanticsLabel('Open reading sources'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Folder'), findsOneWidget);
      expect(find.text('Instapaper'), findsWidgets);
      expect(find.text('Drive'), findsOneWidget);
    });

    testWidgets(
      'hides every Drive entry point when the build has no OAuth config',
      (tester) async {
        await tester.pumpWidget(
          _harness(const SourcesScreen(), driveAvailable: false),
        );
        await tester.pump();

        expect(find.text('Google Drive'), findsNothing);

        await tester.tap(find.bySemanticsLabel('Open reading sources'));
        await tester.pumpAndSettle();

        expect(find.text('Paste'), findsOneWidget);
        expect(find.text('Drive'), findsNothing);
        expect(find.bySemanticsLabel('Add from Google Drive'), findsNothing);
      },
    );

    testWidgets(
      'hides every Instapaper entry point when the build has no consumer key',
      (tester) async {
        // Seen on a release build made without the dart-defines: the reader
        // was told to "Rebuild with --dart-define=INSTAPAPER_CONSUMER_KEY".
        await tester.pumpWidget(
          _harness(const SourcesScreen(), instapaperAvailable: false),
        );
        await tester.pump();

        expect(find.text('Instapaper'), findsNothing);
        expect(find.bySemanticsLabel('Connect Instapaper'), findsNothing);

        await tester.tap(find.text('Articles').first);
        await tester.pumpAndSettle();
        expect(find.textContaining('Instapaper'), findsNothing);
        expect(
          find.text('Share a web link to RunThru to read it.'),
          findsOneWidget,
        );

        await tester.tap(find.bySemanticsLabel('Open reading sources'));
        await tester.pumpAndSettle();
        expect(find.text('Paste'), findsOneWidget);
        expect(find.text('Instapaper'), findsNothing);
        expect(find.bySemanticsLabel('Add from Instapaper'), findsNothing);
      },
    );

    testWidgets('filters folders, files, and article sources', (tester) async {
      await tester.pumpWidget(_harness(const SourcesScreen()));
      await tester.pump();

      await tester.tap(find.text('Folders').first);
      await tester.pumpAndSettle();
      expect(find.text('Add folder'), findsNothing);
      expect(find.text('Add files'), findsNothing);
      expect(find.text('Substack'), findsNothing);

      await tester.tap(find.text('Files').first);
      await tester.pumpAndSettle();
      expect(find.text('Add files'), findsNothing);
      expect(find.text('Clipboard'), findsOneWidget);
      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.text('Add folder'), findsNothing);

      await tester.tap(find.text('Articles').first);
      await tester.pumpAndSettle();
      expect(find.text('Instapaper'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      // Release rule: no "coming soon" placeholders in the UI.
      expect(find.text('Substack'), findsNothing);
      expect(find.textContaining('Coming soon'), findsNothing);
      expect(find.text('Add files'), findsNothing);
    });

    testWidgets('hides app-managed import storage from removable folders', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harnessWithSources([
          LibrarySource(
            id: 'watched',
            kind: LibrarySourceKind.folder,
            locator: '/home/matt/Downloads',
            displayName: 'Downloads',
            addedAt: DateTime(2026),
          ),
          LibrarySource(
            id: 'owned',
            kind: LibrarySourceKind.folder,
            locator: '/app/documents/library/123',
            displayName: 'Imported files',
            ownsFiles: true,
            addedAt: DateTime(2026),
          ),
          LibrarySource(
            id: 'book-folder',
            kind: LibrarySourceKind.folder,
            locator: '/data/user/0/com.runthru.app/app_flutter/library/456',
            displayName: 'Book',
            ownsFiles: true,
            sourceKey: 'android-tree:content://tree/book',
            addedAt: DateTime(2026),
          ),
          LibrarySource(
            id: 'legacy-app-data',
            kind: LibrarySourceKind.folder,
            locator: '/data/user/0/com.runthru.app/app_flutter/pdfs',
            displayName: 'pdfs',
            addedAt: DateTime(2026),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Folders').first);
      await tester.pumpAndSettle();

      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('/home/matt/Downloads'), findsOneWidget);
      expect(find.text('Book'), findsOneWidget);
      expect(find.text('Imported copy · stored in app'), findsOneWidget);
      expect(
        find.text('/data/user/0/com.runthru.app/app_flutter/library/456'),
        findsNothing,
      );
      expect(find.text('Imported files'), findsNothing);
      expect(find.text('/app/documents/library/123'), findsNothing);
      expect(find.bySemanticsLabel('Remove Imported files'), findsNothing);
      expect(find.text('pdfs'), findsNothing);
      expect(
        find.text('/data/user/0/com.runthru.app/app_flutter/pdfs'),
        findsNothing,
      );
    });

    testWidgets('home shell exposes Sources in the bottom navigation', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(const HomeShell()));
      await tester.pump();

      expect(find.bySemanticsLabel('Library'), findsWidgets);
      expect(find.bySemanticsLabel('Sources'), findsWidgets);
      expect(find.bySemanticsLabel('Analytics'), findsOneWidget);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Sources').last);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Open reading sources'), findsOneWidget);
    });

    testWidgets('home shell nav morphs active pill into circle while moving', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(const HomeShell()));
      await tester.pump();

      final librarySize = tester.getSize(
        find.byKey(const ValueKey('home-nav-indicator-Library')),
      );
      expect(librarySize.width, 46);
      expect(librarySize.height, 46);

      await tester.tap(find.bySemanticsLabel('Sources').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final movingSourcesSize = tester.getSize(
        find.byKey(const ValueKey('home-nav-indicator-Sources')),
      );
      expect(movingSourcesSize.width, closeTo(46, 0.5));
      expect(movingSourcesSize.height, closeTo(46, 0.5));

      await tester.pumpAndSettle();

      final settledSourcesSize = tester.getSize(
        find.byKey(const ValueKey('home-nav-indicator-Sources')),
      );
      expect(settledSourcesSize.width, 46);
      expect(settledSourcesSize.height, 46);
    });

    testWidgets(
      'Library Drive resume navigates to the Drive reader exactly once after Sources was built',
      (tester) async {
        final readDriveExtras = <Map<String, Object?>>[];
        await tester.pumpWidget(
          _homeShellRouterHarness(
            driveAuthState: _driveConnected,
            sharedPreferences: _progressPrefsWithDriveShelfItem(),
            onReadDrive: readDriveExtras.add,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.bySemanticsLabel('Sources').last);
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Library').last);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Drive Doc').first);
        await tester.pumpAndSettle();

        expect(find.text('Drive Reader'), findsOneWidget);
        expect(readDriveExtras, hasLength(1));
        expect(readDriveExtras.single['document'], isA<ExtractedDocument>());
        expect(readDriveExtras.single['identity'], isNotNull);
        expect(readDriveExtras.single['title'], 'Drive Doc');
        expect(readDriveExtras.single['fileId'], 'drive-doc');
        expect(readDriveExtras.single['sourceId'], 'drive://drive-doc');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeShell, skipOffstage: false)),
        );
        expect(
          container.read(googleDriveImportProvider),
          isA<GoogleDriveImportIdle>(),
        );
      },
    );

    testWidgets(
      'Sources Drive import navigates to the Drive reader exactly once after Library was built',
      (tester) async {
        final readDriveExtras = <Map<String, Object?>>[];
        await tester.pumpWidget(
          _homeShellRouterHarness(
            driveAuthState: _driveConnected,
            onReadDrive: readDriveExtras.add,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.bySemanticsLabel('Sources').last);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Drive Doc'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Drive Doc'));
        await tester.pumpAndSettle();

        expect(find.text('Drive Reader'), findsOneWidget);
        expect(readDriveExtras, hasLength(1));
        expect(readDriveExtras.single['fileId'], 'drive-doc');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeShell, skipOffstage: false)),
        );
        expect(
          container.read(googleDriveImportProvider),
          isA<GoogleDriveImportIdle>(),
        );
      },
    );

    testWidgets('non-initiating Drive import listener ignores completion', (
      tester,
    ) async {
      final readDriveExtras = <Map<String, Object?>>[];
      await tester.pumpWidget(
        _homeShellRouterHarness(
          driveAuthState: _driveConnected,
          sharedPreferences: _progressPrefsWithDriveShelfItem(),
          onReadDrive: readDriveExtras.add,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Sources').last);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Library').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Drive Doc').first,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drive Doc').first);
      await tester.pumpAndSettle();

      expect(readDriveExtras, hasLength(1));
      expect(readDriveExtras.single['fileId'], 'drive-doc');
    });

    testWidgets('Drive import errors show only for the initiating surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        _homeShellRouterHarness(
          driveAuthState: _driveConnected,
          onReadDrive: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Sources').last);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeShell)),
      );

      await container
          .read(googleDriveImportProvider.notifier)
          .importFile(
            const GoogleDriveFile(
              id: 'sheet',
              name: 'Sheet',
              mimeType: 'application/vnd.google-apps.spreadsheet',
            ),
            origin: DriveImportOrigin.sources,
          );
      await tester.pump();

      expect(
        find.text('That Drive file type is not supported.'),
        findsOneWidget,
      );
    });

    testWidgets('Drive permission import snackbar offers Grant access', (
      tester,
    ) async {
      final driveAuth = _FakeGoogleDriveAuth(_driveConnected);
      await tester.pumpWidget(
        _homeShellRouterHarness(
          driveAuthState: _driveConnected,
          driveAuth: driveAuth,
          driveClient: _FakeGoogleDriveClient(
            metadataError: const GoogleDriveException(
              kind: GoogleDriveFailureKind.permission,
              message: 'forbidden',
            ),
          ),
          onReadDrive: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Sources').last);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeShell)),
      );

      await container
          .read(googleDriveImportProvider.notifier)
          .importFileById('drive-doc', origin: DriveImportOrigin.sources);
      await tester.pump();

      expect(
        find.text(
          'RunThru needs read-only access to import that Drive file, or the file may no longer be available.',
        ),
        findsOneWidget,
      );
      expect(find.text('Grant access'), findsOneWidget);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      snackBar.action!.onPressed();
      await tester.pump();

      expect(driveAuth.grantAccessCalls, 1);
    });
  });

  // ── B-48: Instapaper articles in the Library ──────────────────────────────

  group('Instapaper articles', () {
    const connected = InstapaperAuthAuthenticated(
      user: InstapaperUser(userId: 1, username: 'reader@example.com'),
    );
    const noConnection = InstapaperApiException(
      kind: InstapaperFailureKind.network,
      errorCode: 0,
      message: 'Network request failed',
    );

    late _FakeInstapaperClient client;
    late List<Map<String, Object?>> opened;

    setUp(() {
      client = _FakeInstapaperClient();
      opened = [];
    });

    Future<void> pumpHome(
      WidgetTester tester, {
      InstapaperAuthState state = connected,
      Map<String, Object> prefs = const {},
    }) async {
      await tester.binding.setSurfaceSize(const Size(420, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _homeShellRouterHarness(
          driveAuthState: const GoogleDriveAuthUnauthenticated(),
          onReadDrive: (_) {},
          sharedPreferences: prefs,
          instapaperState: state,
          instapaperClient: client,
          onReadInstapaper: opened.add,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens the reader exactly once after Sources was built', (
      tester,
    ) async {
      // With both tabs alive, the Library and Sources each pushed the
      // reader: Back from an article landed on the same article again.
      await pumpHome(tester);
      await tester.tap(find.bySemanticsLabel('Sources').last);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Library').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('First Article'));
      await tester.pumpAndSettle();

      expect(find.text('Instapaper Reader'), findsOneWidget);
      expect(opened, hasLength(1));
      expect(opened.single['bookmarkId'], 1);
      expect(opened.single['title'], 'First Article');
      expect(opened.single['document'], isA<ExtractedDocument>());

      // One Back returns to the Library.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Instapaper Reader'), findsNothing);
      expect(find.text('First Article'), findsOneWidget);
    });

    testWidgets('shows which article is opening and ignores further taps', (
      tester,
    ) async {
      client.textGate = Completer<void>();
      await pumpHome(tester);

      await tester.tap(find.text('First Article'));
      await tester.pump();
      expect(find.text('Opening…'), findsOneWidget);

      await tester.tap(find.text('Second Article'));
      await tester.tap(find.text('First Article'));
      await tester.pump();
      expect(client.textCalls, [1]);

      client.textGate!.complete();
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(opened.single['bookmarkId'], 1);
    });

    testWidgets(
      'an article that finishes loading after the reader moved on opens nothing',
      (tester) async {
        client.textGate = Completer<void>();
        await pumpHome(tester);
        await tester.tap(find.text('First Article'));
        await tester.pump();

        GoRouter.of(tester.element(find.byType(HomeShell))).push('/elsewhere');
        await tester.pumpAndSettle();
        client.textGate!.complete();
        await tester.pumpAndSettle();

        expect(opened, isEmpty);
        expect(find.text('Elsewhere'), findsOneWidget);
      },
    );

    testWidgets('says why an article could not be opened', (tester) async {
      client.textError = const InstapaperApiException(
        kind: InstapaperFailureKind.textAccessDenied,
        errorCode: 1044,
        message: 'Instapaper API error 1044',
      );
      await pumpHome(tester);

      await tester.tap(find.text('First Article'));
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      expect(
        find.text(
          'Instapaper is not giving RunThru the text of articles right now.',
        ),
        findsOneWidget,
      );
      // Once, not once per tab.
      expect(find.byType(SnackBar), findsOneWidget);
      // The row is usable again.
      expect(find.text('Opening…'), findsNothing);
    });

    testWidgets('an article with no text does not open a blank reader', (
      tester,
    ) async {
      client.text = '<html><body><div id="story"></div></body></html>';
      await pumpHome(tester);

      await tester.tap(find.text('First Article'));
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      expect(
        find.text('Instapaper has no readable text for this article.'),
        findsOneWidget,
      );
    });

    testWidgets('rows say where an article is from, not a made-up time', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('example.com'), findsOneWidget);
      expect(find.text('news.example.org'), findsOneWidget);
      expect(find.text('2 articles'), findsOneWidget);
      // Every row used to read "Instapaper · 6 min" (or "1 min").
      expect(find.textContaining('6 min'), findsNothing);
      expect(find.textContaining('1 min'), findsNothing);
      expect(find.text('New'), findsNWidgets(2));
    });

    testWidgets('each row is one announcement and a button', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('First Article, unread, example.com'),
        ),
        matchesSemantics(
          label: 'First Article, unread, example.com',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a list that could not be loaded says why and can be retried', (
      tester,
    ) async {
      client.listError = noConnection;
      await pumpHome(tester);

      expect(
        find.text("Can't reach Instapaper. Check your connection."),
        findsOneWidget,
      );
      // Not the exception's own text.
      expect(find.textContaining('InstapaperApiException'), findsNothing);
      expect(find.textContaining('Failed to load'), findsNothing);

      client.listError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('First Article'), findsOneWidget);
    });

    testWidgets('a refresh that fails keeps the articles and says so', (
      tester,
    ) async {
      await pumpHome(tester);
      client.listError = noConnection;

      await tester.tap(find.byTooltip('Refresh articles'));
      await tester.pumpAndSettle();

      expect(find.text('First Article'), findsOneWidget);
      expect(find.text('Second Article'), findsOneWidget);
      expect(
        find.text("Can't reach Instapaper. Check your connection."),
        findsOneWidget,
      );
    });

    testWidgets('a refresh brings in an article saved elsewhere', (
      tester,
    ) async {
      await pumpHome(tester);
      client.bookmarks = [
        const InstapaperBookmark(
          bookmarkId: 3,
          url: 'https://example.net/new',
          title: 'Just Saved',
        ),
        ...client.bookmarks,
      ];

      await tester.tap(find.byTooltip('Refresh articles'));
      await tester.pumpAndSettle();

      expect(find.text('Just Saved'), findsOneWidget);
      expect(find.text('3 articles'), findsOneWidget);
      expect(tester.getSize(find.byTooltip('Refresh articles')).height, 48);
    });

    testWidgets('coming back to the app leaves a fresh list alone', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(client.listCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Fetched a moment ago: not again. (A stale list is fetched again:
      // see the provider tests.)
      expect(client.listCalls, 1);
    });

    testWidgets('connected with nothing unread says so', (tester) async {
      client.bookmarks = [];
      await pumpHome(tester);

      expect(
        find.text(
          'Nothing unread in Instapaper. Articles you save there show up here.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Connect Instapaper'), findsNothing);
    });

    testWidgets('a refused connection is reported and reconnects from there', (
      tester,
    ) async {
      client.listError = const InstapaperApiException(
        kind: InstapaperFailureKind.unauthorized,
        errorCode: 403,
        message: 'HTTP 403',
      );
      await pumpHome(tester);

      final notice = find.text(
        'Instapaper needs you to sign in again. Tap to reconnect.',
      );
      expect(notice, findsOneWidget);

      await tester.tap(notice);
      await tester.pumpAndSettle();
      expect(find.text('Sign in to Instapaper'), findsOneWidget);
    });

    testWidgets('Continue Reading resumes an article that is not in the list', (
      tester,
    ) async {
      // Archived on another device, or older than the newest 500: its text
      // needs only its ID.
      await pumpHome(
        tester,
        prefs: {
          'runthru_reading_progress': jsonEncode([
            {
              'contentId': 'instapaper://77',
              'source': 'instapaper',
              'title': 'Older Article',
              'wordIndex': 40,
              'totalWords': 400,
              'lastReadAt': DateTime(2026, 11, 1).toIso8601String(),
              'finished': false,
            },
          ]),
        },
      );

      await tester.tap(find.text('Older Article').first);
      await tester.pumpAndSettle();

      expect(client.textCalls, [77]);
      expect(opened.single['bookmarkId'], 77);
      expect(opened.single['title'], 'Older Article');
      expect(find.text('Instapaper Reader'), findsOneWidget);
    });

    testWidgets(
      'Continue Reading says the article is opening, and stops saying so',
      (tester) async {
        client.textGate = Completer<void>();
        await pumpHome(
          tester,
          prefs: {
            'runthru_reading_progress': jsonEncode([
              {
                'contentId': 'instapaper://77',
                'source': 'instapaper',
                'title': 'Older Article',
                'wordIndex': 40,
                'totalWords': 400,
                'lastReadAt': DateTime(2026, 11, 1).toIso8601String(),
                'finished': false,
              },
            ]),
          },
        );

        await tester.tap(find.text('Older Article').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text('Opening “Older Article”…'), findsOneWidget);

        // The reader goes elsewhere before the article arrives: the notice
        // must not follow them there once it has.
        GoRouter.of(tester.element(find.byType(HomeShell))).push('/elsewhere');
        await tester.pumpAndSettle();
        client.textGate!.complete();
        await tester.pumpAndSettle();

        expect(opened, isEmpty);
        expect(find.textContaining('Opening'), findsNothing);
      },
    );

    testWidgets('the add menu signs in when Instapaper is not connected', (
      tester,
    ) async {
      await pumpHome(tester, state: const InstapaperAuthUnauthenticated());
      await tester.tap(find.bySemanticsLabel('Sources').last);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Add from Instapaper'));
      await tester.pumpAndSettle();

      // The sheet, over the one Sources screen (a second one used to be
      // pushed on top).
      expect(find.text('Sign in to Instapaper'), findsOneWidget);
      expect(find.byType(SourcesScreen), findsOneWidget);
    });

    testWidgets('the add menu refreshes the list when connected', (
      tester,
    ) async {
      await pumpHome(tester);
      await tester.tap(find.bySemanticsLabel('Sources').last);
      await tester.pumpAndSettle();
      final before = client.listCalls;

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Add from Instapaper'));
      await tester.pumpAndSettle();

      expect(client.listCalls, before + 1);
      expect(find.text('Instapaper articles are up to date.'), findsOneWidget);
    });
  });
}
