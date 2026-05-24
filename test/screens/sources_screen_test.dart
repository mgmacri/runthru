import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/screens/home_shell.dart';
import 'package:runthru/screens/sources_screen.dart';
import 'package:runthru/store/library_source.dart';
import 'package:runthru/store/library_sources.dart';
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
}

class _FakeGoogleDriveAuth extends Notifier<GoogleDriveAuthState>
    implements GoogleDriveAuth {
  _FakeGoogleDriveAuth(this.initialState);

  final GoogleDriveAuthState initialState;

  @override
  GoogleDriveAuthState build() => initialState;

  @override
  Future<Map<String, String>> authorizationHeaders() async => {};

  @override
  Future<void> connect() async {
    state = const GoogleDriveAuthAuthenticated(
      user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
    );
  }

  @override
  Future<void> disconnect() async {
    state = const GoogleDriveAuthUnauthenticated();
  }
}

Widget _harness(Widget child) {
  SharedPreferences.setMockInitialValues({});
  return ProviderScope(
    overrides: [
      instapaperAuthProvider.overrideWith(
        () => _FakeInstapaperAuth(const InstapaperAuthUnauthenticated()),
      ),
      googleDriveAuthProvider.overrideWith(
        () => _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated()),
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
      instapaperAuthProvider.overrideWith(
        () => _FakeInstapaperAuth(const InstapaperAuthUnauthenticated()),
      ),
      googleDriveAuthProvider.overrideWith(
        () => _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated()),
      ),
    ],
    child: const MaterialApp(home: SourcesScreen()),
  );
}

class _FakeLibrarySources extends LibrarySourcesNotifier {
  _FakeLibrarySources(this.sources);

  final List<LibrarySource> sources;

  @override
  Future<List<LibrarySource>> build() async => sources;
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
      expect(find.text('Substack'), findsOneWidget);
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

      expect(find.text('Library'), findsWidgets);
      expect(find.text('Sources'), findsWidgets);
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('Sources').last);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Open reading sources'), findsOneWidget);
    });
  });
}
