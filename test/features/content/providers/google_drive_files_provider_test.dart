import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/services/models.dart';
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
  _FakeGoogleDriveClient({
    this.files = const [],
    this.listErrors = const [],
    this.exportedText = 'Hello from a Google Doc.',
    this.downloadedBytes = const [],
    this.metadataFile,
    this.error,
  }) : super(headersProvider: () async => {});

  final List<GoogleDriveFile> files;
  final List<GoogleDriveException> listErrors;
  final String exportedText;
  final List<int> downloadedBytes;
  final GoogleDriveFile? metadataFile;
  final GoogleDriveException? error;
  var listCalls = 0;
  final metadataIds = <String>[];

  @override
  Future<List<GoogleDriveFile>> listDriveFiles({String? query}) async {
    listCalls++;
    if (listCalls <= listErrors.length) throw listErrors[listCalls - 1];
    if (error != null) throw error!;
    return files;
  }

  @override
  Future<GoogleDriveFile> metadata(String fileId) async {
    metadataIds.add(fileId);
    if (error != null) throw error!;
    final file = metadataFile;
    if (file != null) return file;
    return GoogleDriveFile(
      id: fileId,
      name: 'Metadata Doc',
      mimeType: googleDocsMimeType,
    );
  }

  @override
  Future<String> exportGoogleDoc(
    GoogleDriveFile file, {
    String exportMimeType = plainTextMimeType,
  }) async {
    return exportedText;
  }

  @override
  Future<List<int>> downloadSelectedFile(GoogleDriveFile file) async {
    return downloadedBytes;
  }
}

const _connected = GoogleDriveAuthAuthenticated(
  user: GoogleDriveUser(id: 'id', email: 'drive@example.com'),
);

ProviderContainer _container({
  GoogleDriveAuthState authState = _connected,
  _FakeGoogleDriveAuth? auth,
  GoogleDriveClient? client,
  ExtractedDocument? pdfDocument,
  ExtractedDocument? epubDocument,
  GoogleDriveAccessMode accessMode = GoogleDriveAccessMode.fullDriveBrowser,
}) {
  final authNotifier = auth ?? _FakeGoogleDriveAuth(authState);
  return ProviderContainer(
    overrides: [
      googleDriveAuthProvider.overrideWith(() => authNotifier),
      configProvider.overrideWith(
        () => _FakeConfigNotifier(AppConfig(googleDriveAccessMode: accessMode)),
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
  Future<void> loadConfig(ProviderContainer container) async {
    await container.read(configProvider.future);
  }

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
      await loadConfig(container);

      expect(
        container.read(googleDriveFilesProvider),
        isA<GoogleDriveFilesLoading>(),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(googleDriveFilesProvider);
      expect(state, isA<GoogleDriveFilesLoaded>());
      expect((state as GoogleDriveFilesLoaded).files.single.id, 'doc1');
    });

    test('selected-files mode does not call Drive-wide listing', () async {
      final client = _FakeGoogleDriveClient(
        files: const [
          GoogleDriveFile(
            id: 'doc1',
            name: 'Doc',
            mimeType: googleDocsMimeType,
          ),
        ],
      );
      final container = _container(
        client: client,
        accessMode: GoogleDriveAccessMode.selectedFilesOnly,
      );
      addTearDown(container.dispose);

      expect(
        container.read(googleDriveFilesProvider),
        isA<GoogleDriveFilesSelectedFilesOnly>(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(client.listCalls, 0);
      expect(
        container.read(googleDriveFilesProvider),
        isA<GoogleDriveFilesSelectedFilesOnly>(),
      );
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
      await loadConfig(container);

      container.read(googleDriveFilesProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(googleDriveFilesProvider),
        isA<GoogleDriveFilesError>(),
      );
    });

    test(
      'permission list errors keep auth connected and expose typed kind',
      () async {
        final auth = _FakeGoogleDriveAuth(_connected);
        final container = _container(
          auth: auth,
          client: _FakeGoogleDriveClient(
            error: const GoogleDriveException(
              kind: GoogleDriveFailureKind.permission,
              message: 'forbidden',
            ),
          ),
        );
        addTearDown(container.dispose);
        await loadConfig(container);

        container.read(googleDriveFilesProvider);
        await Future<void>.delayed(Duration.zero);

        final filesState = container.read(googleDriveFilesProvider);
        expect(filesState, isA<GoogleDriveFilesError>());
        expect(
          (filesState as GoogleDriveFilesError).kind,
          GoogleDriveFailureKind.permission,
        );
        expect(
          container.read(googleDriveAuthProvider),
          isA<GoogleDriveAuthAuthenticated>(),
        );
        expect(auth.disconnectCalls, 0);
      },
    );

    test('successful grant access reloads Drive files', () async {
      final auth = _FakeGoogleDriveAuth(_connected);
      final client = _FakeGoogleDriveClient(
        listErrors: const [
          GoogleDriveException(
            kind: GoogleDriveFailureKind.permission,
            message: 'forbidden',
          ),
        ],
        files: const [
          GoogleDriveFile(
            id: 'doc1',
            name: 'Doc',
            mimeType: googleDocsMimeType,
          ),
        ],
      );
      final container = _container(auth: auth, client: client);
      addTearDown(container.dispose);
      await loadConfig(container);

      container.read(googleDriveFilesProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(googleDriveFilesProvider),
        isA<GoogleDriveFilesError>(),
      );

      await container
          .read(googleDriveFilesProvider.notifier)
          .grantAccessAndRefresh();

      final filesState = container.read(googleDriveFilesProvider);
      expect(auth.grantAccessCalls, 1);
      expect(client.listCalls, 2);
      expect(filesState, isA<GoogleDriveFilesLoaded>());
      expect((filesState as GoogleDriveFilesLoaded).files.single.id, 'doc1');
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
      final done = state as GoogleDriveImportDone;
      expect(done.document.totalWords, 4);
      expect(done.identity.sourceId, 'drive://doc1');
      expect(done.identity.name, 'Doc');
    });

    test(
      'imports by Drive file ID using metadata and stable source ID',
      () async {
        final container = _container(
          client: _FakeGoogleDriveClient(
            metadataFile: const GoogleDriveFile(
              id: 'same-file',
              name: 'Renamed Doc',
              mimeType: googleDocsMimeType,
            ),
            exportedText: 'Drive resume text.',
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
            .importFileById('same-file');

        final state = container.read(googleDriveImportProvider);
        expect(state, isA<GoogleDriveImportDone>());
        final done = state as GoogleDriveImportDone;
        expect(done.file.name, 'Renamed Doc');
        expect(done.identity.sourceId, 'drive://same-file');
        expect(done.document.totalWords, 3);
      },
    );

    test('imports picked Drive file IDs through metadata lookup', () async {
      final client = _FakeGoogleDriveClient(
        metadataFile: const GoogleDriveFile(
          id: 'picked-id',
          name: 'Picked Doc',
          mimeType: googleDocsMimeType,
        ),
        exportedText: 'Picked Drive text.',
      );
      final container = _container(
        client: client,
        accessMode: GoogleDriveAccessMode.selectedFilesOnly,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        googleDriveImportProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(googleDriveImportProvider.notifier)
          .importPickedDriveFileIds(['picked-id']);

      final state = container.read(googleDriveImportProvider);
      expect(state, isA<GoogleDriveImportDone>());
      final done = state as GoogleDriveImportDone;
      expect(done.file.id, 'picked-id');
      expect(done.identity.sourceId, 'drive://picked-id');
      expect(client.metadataIds, ['picked-id']);
    });

    test('deduplicates picked Drive file IDs in first-seen order', () async {
      final client = _FakeGoogleDriveClient(exportedText: 'Picked text.');
      final container = _container(
        client: client,
        accessMode: GoogleDriveAccessMode.selectedFilesOnly,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        googleDriveImportProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(googleDriveImportProvider.notifier)
          .importPickedDriveFileIds([' doc1 ', 'doc2', 'doc1']);

      final state = container.read(googleDriveImportProvider);
      expect(state, isA<GoogleDriveImportDone>());
      expect((state as GoogleDriveImportDone).file.id, 'doc2');
      expect(client.metadataIds, ['doc1', 'doc2']);
    });

    test('empty picked Drive IDs are treated as cancellation', () async {
      final container = _container(
        accessMode: GoogleDriveAccessMode.selectedFilesOnly,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        googleDriveImportProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(googleDriveImportProvider.notifier)
          .importPickedDriveFileIds(const []);

      expect(
        container.read(googleDriveImportProvider),
        isA<GoogleDriveImportIdle>(),
      );
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

    test('selected-files import rejects folders', () async {
      final container = _container(
        accessMode: GoogleDriveAccessMode.selectedFilesOnly,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        googleDriveImportProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(googleDriveImportProvider.notifier)
          .importPickedDriveFiles(const [
            GoogleDriveFile(
              id: 'folder1',
              name: 'Folder',
              mimeType: googleDriveFolderMimeType,
            ),
          ]);

      final state = container.read(googleDriveImportProvider);
      expect(state, isA<GoogleDriveImportError>());
      expect(
        (state as GoogleDriveImportError).message,
        'Folders are not supported.',
      );
    });

    test('selected-files import accepts multiple picked files', () async {
      final container = _container(
        client: _FakeGoogleDriveClient(exportedText: 'First. Second.'),
        accessMode: GoogleDriveAccessMode.selectedFilesOnly,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        googleDriveImportProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container
          .read(googleDriveImportProvider.notifier)
          .importPickedDriveFiles(const [
            GoogleDriveFile(
              id: 'doc1',
              name: 'Doc 1',
              mimeType: googleDocsMimeType,
            ),
            GoogleDriveFile(
              id: 'doc2',
              name: 'Doc 2',
              mimeType: googleDocsMimeType,
            ),
          ]);

      final state = container.read(googleDriveImportProvider);
      expect(state, isA<GoogleDriveImportDone>());
      expect((state as GoogleDriveImportDone).file.id, 'doc2');
      expect(state.identity.sourceId, 'drive://doc2');
    });

    test(
      'permission import errors expose typed kind and cautious copy',
      () async {
        final container = _container(
          client: _FakeGoogleDriveClient(
            error: const GoogleDriveException(
              kind: GoogleDriveFailureKind.permission,
              message: 'forbidden',
            ),
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
            .importFileById('doc1');

        final state = container.read(googleDriveImportProvider);
        expect(state, isA<GoogleDriveImportError>());
        final error = state as GoogleDriveImportError;
        expect(error.kind, GoogleDriveFailureKind.permission);
        expect(error.message, contains('file may no longer be available'));
      },
    );
  });
}
