import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/features/content/providers/google_drive_picker_provider.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/features/content/services/google_drive_picker.dart';
import 'package:runthru/features/content/widgets/google_drive_source_panel.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

class _FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  _FakeConfigNotifier(this._config);

  AppConfig _config;

  @override
  Future<AppConfig> build() async => _config;

  @override
  Future<void> setGoogleDriveAccessMode(GoogleDriveAccessMode mode) async {
    _config = _config.copyWith(googleDriveAccessMode: mode);
    state = AsyncData(_config);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGoogleDriveAuth extends Notifier<GoogleDriveAuthState>
    implements GoogleDriveAuth {
  _FakeGoogleDriveAuth(this.initialState);

  final GoogleDriveAuthState initialState;
  var connectCalls = 0;
  var disconnectCalls = 0;
  var grantAccessCalls = 0;
  final connectAccessModes = <GoogleDriveAccessMode?>[];

  @override
  GoogleDriveAuthState build() => initialState;

  @override
  Future<Map<String, String>> authorizationHeaders({
    GoogleDriveAccessMode? accessMode,
    bool allowInteractivePrompt = false,
  }) async => {};

  @override
  Future<void> connect({GoogleDriveAccessMode? accessMode}) async {
    connectCalls++;
    connectAccessModes.add(accessMode);
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
    disconnectCalls++;
  }
}

class _FakeGoogleDriveClient extends GoogleDriveClient {
  _FakeGoogleDriveClient({this.error}) : super(headersProvider: () async => {});

  final GoogleDriveException? error;
  final metadataIds = <String>[];

  @override
  Future<List<GoogleDriveFile>> listDriveFiles({String? query}) async {
    final failure = error;
    if (failure != null) throw failure;
    return const [
      GoogleDriveFile(
        id: 'doc1',
        name: 'Drive Doc',
        mimeType: googleDocsMimeType,
      ),
    ];
  }

  @override
  Future<GoogleDriveFile> metadata(String fileId) async {
    metadataIds.add(fileId);
    return GoogleDriveFile(
      id: fileId,
      name: 'Picked Drive Doc',
      mimeType: googleDocsMimeType,
    );
  }

  @override
  Future<String> exportGoogleDoc(
    GoogleDriveFile file, {
    String exportMimeType = plainTextMimeType,
  }) async {
    return 'Drive document text.';
  }
}

class _FakeGoogleDrivePicker implements GoogleDrivePicker {
  _FakeGoogleDrivePicker(this.files);

  final List<GoogleDrivePickedFile> files;
  var calls = 0;
  bool? allowMultiple;
  List<String>? mimeTypes;

  @override
  Future<List<GoogleDrivePickedFile>> pickFiles({
    required bool allowMultiple,
    required List<String> mimeTypes,
  }) async {
    calls++;
    this.allowMultiple = allowMultiple;
    this.mimeTypes = mimeTypes;
    return files;
  }
}

Widget _harness({
  required GoogleDriveAuthState authState,
  _FakeGoogleDriveAuth? auth,
  GoogleDriveClient? client,
  GoogleDrivePicker? picker,
  AppConfig config = const AppConfig(
    googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
  ),
  Widget child = const GoogleDriveSourcePanel(),
}) {
  final authNotifier = auth ?? _FakeGoogleDriveAuth(authState);
  return ProviderScope(
    overrides: [
      googleDriveAuthProvider.overrideWith(() => authNotifier),
      googleDriveClientProvider.overrideWithValue(
        client ?? _FakeGoogleDriveClient(),
      ),
      if (picker != null) googleDrivePickerProvider.overrideWithValue(picker),
      configProvider.overrideWith(() => _FakeConfigNotifier(config)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

class _ChooseDriveFilesButton extends ConsumerWidget {
  const _ChooseDriveFilesButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(googleDriveImportProvider);
    return TextButton(
      onPressed: () => chooseGoogleDriveFilesForReading(context, ref),
      child: const Text('Choose files'),
    );
  }
}

void main() {
  group('GoogleDriveSourcePanel', () {
    testWidgets('shows disconnected state', (tester) async {
      await tester.pumpWidget(
        _harness(
          authState: const GoogleDriveAuthUnauthenticated(),
          config: const AppConfig(),
        ),
      );
      await tester.pump();

      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(
        find.text('RunThru can only access files you choose'),
        findsOneWidget,
      );
      expect(find.text('Choose files from Google Drive'), findsNothing);
      expect(find.text('Use full Drive browser'), findsNothing);
      expect(find.byTooltip('Google Drive settings'), findsOneWidget);
    });

    testWidgets('settings cog uses provided settings callback', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        _harness(
          authState: const GoogleDriveAuthUnauthenticated(),
          config: const AppConfig(),
          child: GoogleDriveSourcePanel(
            onOpenBrowserSetting: () => opened = true,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Google Drive settings'));
      await tester.pump();

      expect(opened, isTrue);
    });

    testWidgets('ui unavailable auth error shows retry copy', (tester) async {
      await tester.pumpWidget(
        _harness(
          authState: const GoogleDriveAuthError(
            kind: GoogleDriveFailureKind.uiUnavailable,
            message:
                'Google sign-in is not available on this device. Check Play Services or browser access.',
            classification: GoogleDriveFailureClassification.transient,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Needs attention'), findsOneWidget);
      expect(
        find.text(
          'Google sign-in is not available on this device. Check Play Services or browser access.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('cancel'), findsNothing);
    });

    testWidgets('selected-files CTA uses Drive picker and Drive import path', (
      tester,
    ) async {
      final picker = _FakeGoogleDrivePicker(const [
        GoogleDrivePickedFile(
          id: 'picked-doc',
          name: 'Picked Drive Doc',
          mimeType: googleDocsMimeType,
        ),
      ]);
      final client = _FakeGoogleDriveClient();
      await tester.pumpWidget(
        _harness(
          authState: const GoogleDriveAuthAuthenticated(
            user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
          ),
          config: const AppConfig(),
          client: client,
          picker: picker,
          child: const _ChooseDriveFilesButton(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Choose files'));
      await tester.pump();
      await tester.pump();

      expect(picker.calls, 1);
      expect(picker.allowMultiple, isTrue);
      expect(picker.mimeTypes, contains(googleDocsMimeType));
      expect(client.metadataIds, ['picked-doc']);
      final context = tester.element(find.byType(_ChooseDriveFilesButton));
      final container = ProviderScope.containerOf(context);
      final state = container.read(googleDriveImportProvider);
      expect(state, isA<GoogleDriveImportDone>());
      expect(
        (state as GoogleDriveImportDone).identity.sourceId,
        'drive://picked-doc',
      );
    });

    testWidgets('selected-files CTA deduplicates picked IDs in order', (
      tester,
    ) async {
      final picker = _FakeGoogleDrivePicker(const [
        GoogleDrivePickedFile(
          id: 'doc-a',
          name: 'Doc A',
          mimeType: googleDocsMimeType,
        ),
        GoogleDrivePickedFile(
          id: 'doc-b',
          name: 'Doc B',
          mimeType: googleDocsMimeType,
        ),
        GoogleDrivePickedFile(
          id: 'doc-a',
          name: 'Doc A again',
          mimeType: googleDocsMimeType,
        ),
      ]);
      final client = _FakeGoogleDriveClient();
      await tester.pumpWidget(
        _harness(
          authState: const GoogleDriveAuthAuthenticated(
            user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
          ),
          config: const AppConfig(),
          client: client,
          picker: picker,
          child: const _ChooseDriveFilesButton(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Choose files'));
      await tester.pump();
      await tester.pump();

      expect(client.metadataIds, ['doc-a', 'doc-b']);
      final context = tester.element(find.byType(_ChooseDriveFilesButton));
      final container = ProviderScope.containerOf(context);
      final state = container.read(googleDriveImportProvider);
      expect(state, isA<GoogleDriveImportDone>());
      expect((state as GoogleDriveImportDone).file.id, 'doc-b');
    });

    testWidgets('selected-files CTA requests selected-file access only', (
      tester,
    ) async {
      final picker = _FakeGoogleDrivePicker(const [
        GoogleDrivePickedFile(
          id: 'picked-doc',
          name: 'Picked Drive Doc',
          mimeType: googleDocsMimeType,
        ),
      ]);
      final auth = _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated());
      await tester.pumpWidget(
        _harness(
          authState: auth.initialState,
          auth: auth,
          config: const AppConfig(
            googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
          ),
          picker: picker,
          child: const _ChooseDriveFilesButton(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Choose files'));
      await tester.pump();
      await tester.pump();

      expect(picker.calls, 1);
      expect(auth.connectAccessModes, [
        GoogleDriveAccessMode.selectedFilesOnly,
      ]);
    });

    testWidgets('selected-files CTA treats empty picker result as no-op', (
      tester,
    ) async {
      final picker = _FakeGoogleDrivePicker(const []);
      final auth = _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated());
      await tester.pumpWidget(
        _harness(
          authState: auth.initialState,
          auth: auth,
          config: const AppConfig(),
          picker: picker,
          child: const _ChooseDriveFilesButton(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Choose files'));
      await tester.pump();

      expect(picker.calls, 1);
      expect(auth.connectAccessModes, [
        GoogleDriveAccessMode.selectedFilesOnly,
      ]);
      final context = tester.element(find.byType(_ChooseDriveFilesButton));
      final container = ProviderScope.containerOf(context);
      expect(
        container.read(googleDriveImportProvider),
        isA<GoogleDriveImportIdle>(),
      );
    });

    testWidgets('selected-files CTA rejects Drive folders safely', (
      tester,
    ) async {
      final picker = _FakeGoogleDrivePicker(const [
        GoogleDrivePickedFile(
          id: 'folder',
          name: 'Folder',
          mimeType: googleDriveFolderMimeType,
        ),
      ]);
      final auth = _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated());
      await tester.pumpWidget(
        _harness(
          authState: auth.initialState,
          auth: auth,
          config: const AppConfig(),
          picker: picker,
          child: const _ChooseDriveFilesButton(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Choose files'));
      await tester.pump();

      expect(auth.connectAccessModes, [
        GoogleDriveAccessMode.selectedFilesOnly,
      ]);
      expect(find.text('Folders are not supported.'), findsWidgets);
    });

    testWidgets('selected-files CTA rejects unsupported Drive MIME types', (
      tester,
    ) async {
      final picker = _FakeGoogleDrivePicker(const [
        GoogleDrivePickedFile(
          id: 'sheet',
          name: 'Sheet',
          mimeType: 'application/vnd.google-apps.spreadsheet',
        ),
      ]);
      final auth = _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated());
      await tester.pumpWidget(
        _harness(
          authState: auth.initialState,
          auth: auth,
          config: const AppConfig(),
          picker: picker,
          child: const _ChooseDriveFilesButton(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Choose files'));
      await tester.pump();

      expect(auth.connectAccessModes, [
        GoogleDriveAccessMode.selectedFilesOnly,
      ]);
      expect(
        find.text('That Drive file type is not supported.'),
        findsOneWidget,
      );
    });

    testWidgets('selected-files CTA rejects mixed invalid picks after auth', (
      tester,
    ) async {
      final picker = _FakeGoogleDrivePicker(const [
        GoogleDrivePickedFile(
          id: 'doc',
          name: 'Doc',
          mimeType: googleDocsMimeType,
        ),
        GoogleDrivePickedFile(
          id: 'sheet',
          name: 'Sheet',
          mimeType: 'application/vnd.google-apps.spreadsheet',
        ),
        GoogleDrivePickedFile(
          id: 'folder',
          name: 'Folder',
          mimeType: googleDriveFolderMimeType,
        ),
      ]);
      final auth = _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated());
      final client = _FakeGoogleDriveClient();
      await tester.pumpWidget(
        _harness(
          authState: auth.initialState,
          auth: auth,
          client: client,
          config: const AppConfig(),
          picker: picker,
          child: const _ChooseDriveFilesButton(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Choose files'));
      await tester.pump();

      expect(auth.connectAccessModes, [
        GoogleDriveAccessMode.selectedFilesOnly,
      ]);
      expect(client.metadataIds, isEmpty);
      expect(
        find.text('That Drive file type is not supported.'),
        findsOneWidget,
      );
    });

    testWidgets('unavailable production picker is reported after Drive auth', (
      tester,
    ) async {
      final auth = _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated());
      await tester.pumpWidget(
        _harness(
          authState: auth.initialState,
          auth: auth,
          config: const AppConfig(),
          child: const _ChooseDriveFilesButton(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Choose files'));
      await tester.pump();

      expect(auth.connectAccessModes, [
        GoogleDriveAccessMode.selectedFilesOnly,
      ]);
      expect(
        find.text(
          'Google Drive file picker is not available in this build yet.',
        ),
        findsOneWidget,
      );
    });

    test('selected-files CTA does not call local OS file picker', () {
      final source = File(
        'lib/features/content/widgets/google_drive_source_panel.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('LibraryImport.pickFiles')));
      expect(source, contains('googleDrivePickerProvider'));
      expect(source, contains('importPickedDriveFileIds'));
    });

    testWidgets('configuration auth error shows actionable copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          authState: const GoogleDriveAuthError(
            kind: GoogleDriveFailureKind.auth,
            message:
                'Google sign-in is not configured for Android. Check the Android Google Sign-In configuration, then try again.',
            classification: GoogleDriveFailureClassification.missingConfig,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Needs attention'), findsOneWidget);
      expect(
        find.textContaining('Check the Android Google Sign-In configuration'),
        findsOneWidget,
      );
    });

    testWidgets('user cancellation is not shown as needs attention', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          authState: const GoogleDriveAuthError(
            kind: GoogleDriveFailureKind.userCancelled,
            message: 'Sign-in was cancelled.',
            classification: GoogleDriveFailureClassification.permanent,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Sign-in was cancelled.'), findsOneWidget);
      expect(find.text('Needs attention'), findsNothing);
    });

    testWidgets('shows connected files and imports on tap', (tester) async {
      await tester.pumpWidget(
        _harness(
          authState: const GoogleDriveAuthAuthenticated(
            user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
          ),
          config: const AppConfig(
            googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Drive Doc'), findsOneWidget);

      await tester.tap(find.text('Drive Doc'));
      await tester.pump();
      await tester.pump();

      final context = tester.element(find.byType(GoogleDriveSourcePanel));
      final container = ProviderScope.containerOf(context);
      expect(
        container.read(googleDriveImportProvider),
        isA<GoogleDriveImportDone>(),
      );
    });

    testWidgets(
      'permission list failure shows Grant access and keeps disconnect',
      (tester) async {
        final auth = _FakeGoogleDriveAuth(
          const GoogleDriveAuthAuthenticated(
            user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
          ),
        );
        await tester.pumpWidget(
          _harness(
            authState: auth.initialState,
            auth: auth,
            client: _FakeGoogleDriveClient(
              error: const GoogleDriveException(
                kind: GoogleDriveFailureKind.permission,
                message: 'forbidden',
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.text(
            'Full Drive browser may be blocked by your organization. You can still choose individual Drive files.',
          ),
          findsOneWidget,
        );
        expect(find.text('Grant access'), findsOneWidget);
        expect(find.byTooltip('Disconnect Google Drive'), findsOneWidget);

        await tester.tap(find.text('Grant access'));
        await tester.pump();

        expect(auth.grantAccessCalls, 1);
      },
    );

    testWidgets('Grant access is hidden for transient list errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          authState: const GoogleDriveAuthAuthenticated(
            user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
          ),
          config: const AppConfig(
            googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
          ),
          client: _FakeGoogleDriveClient(
            error: const GoogleDriveException(
              kind: GoogleDriveFailureKind.network,
              message: 'offline',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'Network connection failed. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Grant access'), findsNothing);
    });

    testWidgets('Grant access is hidden when signed out', (tester) async {
      await tester.pumpWidget(
        _harness(authState: const GoogleDriveAuthUnauthenticated()),
      );
      await tester.pump();

      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Grant access'), findsNothing);
    });
  });
}
