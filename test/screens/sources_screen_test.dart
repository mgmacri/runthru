import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
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
  _FakeInstapaperAuth(this.initialState);

  final InstapaperAuthState initialState;

  @override
  InstapaperAuthState build() => initialState;

  @override
  InstapaperClient? get client => null;

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
  Future<void> sessionExpired() async {}

  @override
  Future<void> checkSession() async {}

  @override
  void updateUser(InstapaperUser user) {}

  @override
  void dismissError() {}
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
      GoRoute(path: '/sources', redirect: (_, __) => '/?tab=1'),
    ],
  );
  return ProviderScope(
    overrides: [
      instapaperAuthProvider.overrideWith(
        () => _FakeInstapaperAuth(const InstapaperAuthUnauthenticated()),
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
  const _ReadDriveProbe({required this.extra, required this.onShown});

  final Map<String, Object?> extra;
  final void Function(Map<String, Object?> extra) onShown;

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
    return const Scaffold(body: Text('Drive Reader'));
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
}
