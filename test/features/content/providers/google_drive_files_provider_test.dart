import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/services/models.dart';

class _FakeGoogleDriveAuth extends Notifier<GoogleDriveAuthState>
    implements GoogleDriveAuth {
  _FakeGoogleDriveAuth(this.initialState);

  final GoogleDriveAuthState initialState;

  @override
  GoogleDriveAuthState build() => initialState;

  @override
  Future<Map<String, String>> authorizationHeaders() async => {};

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}
}

class _FakeGoogleDriveClient extends GoogleDriveClient {
  _FakeGoogleDriveClient({
    this.files = const [],
    this.exportedText = 'Hello from a Google Doc.',
    this.downloadedBytes = const [],
    this.error,
  }) : super(headersProvider: () async => {});

  final List<GoogleDriveFile> files;
  final String exportedText;
  final List<int> downloadedBytes;
  final GoogleDriveException? error;

  @override
  Future<List<GoogleDriveFile>> listSupportedFiles({String? query}) async {
    if (error != null) throw error!;
    return files;
  }

  @override
  Future<String> exportGoogleDoc(
    GoogleDriveFile file, {
    String exportMimeType = plainTextMimeType,
  }) async {
    return exportedText;
  }

  @override
  Future<List<int>> downloadBinary(GoogleDriveFile file) async {
    return downloadedBytes;
  }
}

const _connected = GoogleDriveAuthAuthenticated(
  user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
);

ProviderContainer _container({
  GoogleDriveAuthState authState = _connected,
  GoogleDriveClient? client,
  ExtractedDocument? pdfDocument,
  ExtractedDocument? epubDocument,
}) {
  return ProviderContainer(
    overrides: [
      googleDriveAuthProvider.overrideWith(
        () => _FakeGoogleDriveAuth(authState),
      ),
      googleDriveClientProvider.overrideWithValue(
        client ?? _FakeGoogleDriveClient(),
      ),
      googleDrivePdfExtractorProvider.overrideWithValue(
        (_) async => pdfDocument ?? const ExtractedDocument(sentences: []),
      ),
      googleDriveEpubExtractorProvider.overrideWithValue(
        (_) async => epubDocument ?? const ExtractedDocument(sentences: []),
      ),
      googleDriveTempDirectoryProvider.overrideWith(
        (ref) async =>
            Directory.systemTemp.createTempSync('runthru_drive_test_'),
      ),
    ],
  );
}

void main() {
  group('GoogleDriveFiles', () {
    test('is not connected when auth is absent', () {
      final container = _container(
        authState: const GoogleDriveAuthUnauthenticated(),
      );
      addTearDown(container.dispose);

      expect(
        container.read(googleDriveFilesProvider),
        isA<GoogleDriveFilesNotConnected>(),
      );
    });

    test('loads supported files when connected', () async {
      final container = _container(
        client: _FakeGoogleDriveClient(
          files: const [
            GoogleDriveFile(
              id: 'doc1',
              name: 'Doc',
              mimeType: googleDocsMimeType,
            ),
          ],
        ),
      );
      addTearDown(container.dispose);

      expect(
        container.read(googleDriveFilesProvider),
        isA<GoogleDriveFilesLoading>(),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(googleDriveFilesProvider);
      expect(state, isA<GoogleDriveFilesLoaded>());
      expect((state as GoogleDriveFilesLoaded).files.single.id, 'doc1');
    });

    test('maps list errors to error state', () async {
      final container = _container(
        client: _FakeGoogleDriveClient(
          error: const GoogleDriveException(
            kind: GoogleDriveFailureKind.network,
            message: 'offline',
          ),
        ),
      );
      addTearDown(container.dispose);

      container.read(googleDriveFilesProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(googleDriveFilesProvider),
        isA<GoogleDriveFilesError>(),
      );
    });
  });

  group('GoogleDriveImport', () {
    test('normalizes exported Google Docs', () async {
      final container = _container(
        client: _FakeGoogleDriveClient(
          exportedText: 'First sentence. Second sentence.',
        ),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        googleDriveImportProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(googleDriveImportProvider.notifier)
          .importFile(
            const GoogleDriveFile(
              id: 'doc1',
              name: 'Doc',
              mimeType: googleDocsMimeType,
            ),
          );

      final state = container.read(googleDriveImportProvider);
      expect(state, isA<GoogleDriveImportDone>());
      expect((state as GoogleDriveImportDone).document.totalWords, 4);
    });

    test('delegates PDF import to the PDF extractor', () async {
      const expected = ExtractedDocument(
        sentences: [
          Sentence(words: ['pdf']),
        ],
      );
      final container = _container(
        client: _FakeGoogleDriveClient(downloadedBytes: [37, 80, 68, 70]),
        pdfDocument: expected,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        googleDriveImportProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(googleDriveImportProvider.notifier)
          .importFile(
            const GoogleDriveFile(
              id: 'pdf1',
              name: 'Paper.pdf',
              mimeType: pdfMimeType,
            ),
          );

      final state = container.read(googleDriveImportProvider);
      expect(state, isA<GoogleDriveImportDone>());
      expect((state as GoogleDriveImportDone).document, expected);
    });

    test('delegates EPUB import to the EPUB extractor', () async {
      const expected = ExtractedDocument(
        sentences: [
          Sentence(words: ['epub']),
        ],
      );
      final container = _container(
        client: _FakeGoogleDriveClient(downloadedBytes: [80, 75]),
        epubDocument: expected,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        googleDriveImportProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(googleDriveImportProvider.notifier)
          .importFile(
            const GoogleDriveFile(
              id: 'epub1',
              name: 'Book.epub',
              mimeType: epubMimeType,
            ),
          );

      final state = container.read(googleDriveImportProvider);
      expect(state, isA<GoogleDriveImportDone>());
      expect((state as GoogleDriveImportDone).document, expected);
    });

    test('enters error state for unsupported MIME types', () async {
      final container = _container();
      addTearDown(container.dispose);
      final subscription = container.listen(
        googleDriveImportProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(googleDriveImportProvider.notifier)
          .importFile(
            const GoogleDriveFile(
              id: 'sheet1',
              name: 'Sheet',
              mimeType: 'application/vnd.google-apps.spreadsheet',
            ),
          );

      expect(
        container.read(googleDriveImportProvider),
        isA<GoogleDriveImportError>(),
      );
    });
  });
}
