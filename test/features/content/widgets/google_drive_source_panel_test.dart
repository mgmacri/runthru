import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/features/content/widgets/google_drive_source_panel.dart';

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
  Future<void> disconnect() async {}
}

class _FakeGoogleDriveClient extends GoogleDriveClient {
  _FakeGoogleDriveClient() : super(headersProvider: () async => {});

  @override
  Future<List<GoogleDriveFile>> listSupportedFiles({String? query}) async {
    return const [
      GoogleDriveFile(
        id: 'doc1',
        name: 'Drive Doc',
        mimeType: googleDocsMimeType,
      ),
    ];
  }

  @override
  Future<String> exportGoogleDoc(
    GoogleDriveFile file, {
    String exportMimeType = plainTextMimeType,
  }) async {
    return 'Drive document text.';
  }
}

Widget _harness({required GoogleDriveAuthState authState}) {
  return ProviderScope(
    overrides: [
      googleDriveAuthProvider.overrideWith(
        () => _FakeGoogleDriveAuth(authState),
      ),
      googleDriveClientProvider.overrideWithValue(_FakeGoogleDriveClient()),
    ],
    child: const MaterialApp(home: Scaffold(body: GoogleDriveSourcePanel())),
  );
}

void main() {
  group('GoogleDriveSourcePanel', () {
    testWidgets('shows disconnected state', (tester) async {
      await tester.pumpWidget(
        _harness(authState: const GoogleDriveAuthUnauthenticated()),
      );
      await tester.pump();

      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('shows connected files and imports on tap', (tester) async {
      await tester.pumpWidget(
        _harness(
          authState: const GoogleDriveAuthAuthenticated(
            user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
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
  });
}
