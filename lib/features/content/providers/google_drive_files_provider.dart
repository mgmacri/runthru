/// Riverpod providers for Google Drive file browsing and importing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/models/drive_content_identity.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/services/content_normaliser.dart';
import 'package:runthru/features/content/services/drive_local_store.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/services/book_identity.dart';
import 'package:runthru/services/content_identity.dart';
import 'package:runthru/services/content_store/content_store.dart';
import 'package:runthru/services/epub_extractor.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_extractor.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

part 'google_drive_files_provider.g.dart';

/// Extracts a document from a local file path.
typedef DocumentFileExtractor =
    Future<ExtractedDocument> Function(String filePath);

/// Google Drive client dependency.
@Riverpod(keepAlive: true)
GoogleDriveClient googleDriveClient(GoogleDriveClientRef ref) {
  final accessMode = ref.watch(
    configProvider.select(
      (value) =>
          value.valueOrNull?.googleDriveAccessMode ??
          GoogleDriveAccessMode.selectedFilesOnly,
    ),
  );
  return GoogleDriveClient(
    accessMode: accessMode,
    headersProvider: () => ref
        .read(googleDriveAuthProvider.notifier)
        .authorizationHeaders(accessMode: accessMode),
  );
}

/// PDF extractor dependency for Drive imports.
@riverpod
DocumentFileExtractor googleDrivePdfExtractor(GoogleDrivePdfExtractorRef ref) {
  return pdfExtract;
}

/// EPUB extractor dependency for Drive imports.
@riverpod
DocumentFileExtractor googleDriveEpubExtractor(
  GoogleDriveEpubExtractorRef ref,
) {
  return epubExtract;
}

/// Temporary directory dependency for downloaded Drive files.
@riverpod
Future<Directory> googleDriveTempDirectory(GoogleDriveTempDirectoryRef ref) {
  return getTemporaryDirectory();
}

/// State for the Drive file list.
sealed class GoogleDriveFileListState {
  /// Base constructor for Drive file list states.
  const GoogleDriveFileListState();
}

/// Drive is not connected.
class GoogleDriveFilesNotConnected extends GoogleDriveFileListState {
  /// Creates a not-connected state.
  const GoogleDriveFilesNotConnected();
}

/// Drive is in selected-files-only mode, so Drive-wide listing is unavailable.
class GoogleDriveFilesSelectedFilesOnly extends GoogleDriveFileListState {
  /// Creates a selected-files-only state.
  const GoogleDriveFilesSelectedFilesOnly();
}

/// Drive files are loading.
class GoogleDriveFilesLoading extends GoogleDriveFileListState {
  /// Creates a loading state.
  const GoogleDriveFilesLoading();
}

/// Drive files loaded.
class GoogleDriveFilesLoaded extends GoogleDriveFileListState {
  /// Creates a loaded state.
  const GoogleDriveFilesLoaded({required this.files, this.refreshing = false});

  /// Supported Drive files.
  final List<GoogleDriveFile> files;

  /// Whether a refresh is currently in progress.
  final bool refreshing;
}

/// Drive file list is empty.
class GoogleDriveFilesEmpty extends GoogleDriveFileListState {
  /// Creates an empty state.
  const GoogleDriveFilesEmpty();
}

/// Drive file loading failed.
class GoogleDriveFilesError extends GoogleDriveFileListState {
  /// Creates an error state.
  const GoogleDriveFilesError({
    required this.message,
    required this.kind,
    this.classification = GoogleDriveFailureClassification.unknown,
  });

  /// User-safe error message.
  final String message;

  /// Diagnostic category.
  final GoogleDriveFailureKind kind;

  /// Retry/config classification safe for UI decisions.
  final GoogleDriveFailureClassification classification;
}

/// Fetches and refreshes supported Google Drive files.
@Riverpod(keepAlive: true)
class GoogleDriveFiles extends _$GoogleDriveFiles {
  @override
  GoogleDriveFileListState build() {
    final auth = ref.watch(googleDriveAuthProvider);
    if (auth is! GoogleDriveAuthAuthenticated) {
      return const GoogleDriveFilesNotConnected();
    }
    final accessMode = ref.watch(
      configProvider.select(
        (value) =>
            value.valueOrNull?.googleDriveAccessMode ??
            GoogleDriveAccessMode.selectedFilesOnly,
      ),
    );
    if (accessMode != GoogleDriveAccessMode.fullDriveBrowser) {
      return const GoogleDriveFilesSelectedFilesOnly();
    }
    _load();
    return const GoogleDriveFilesLoading();
  }

  /// Refreshes supported Drive files.
  Future<void> refresh({String? query}) async {
    if (!_isFullDriveBrowserEnabled()) {
      state = const GoogleDriveFilesSelectedFilesOnly();
      return;
    }
    final current = state;
    if (current is GoogleDriveFilesLoaded) {
      state = GoogleDriveFilesLoaded(files: current.files, refreshing: true);
    } else {
      state = const GoogleDriveFilesLoading();
    }
    await _load(query: query);
  }

  /// Starts a user-triggered Drive access grant flow, then reloads files.
  Future<void> grantAccessAndRefresh() async {
    if (!_isFullDriveBrowserEnabled()) return;
    final granted = await ref
        .read(googleDriveAuthProvider.notifier)
        .grantDriveAccess();
    if (!granted) return;
    await refresh();
  }

  Future<void> _load({String? query}) async {
    if (!_isFullDriveBrowserEnabled()) {
      state = const GoogleDriveFilesSelectedFilesOnly();
      return;
    }
    try {
      final files = await ref
          .read(googleDriveClientProvider)
          .listDriveFiles(query: query);
      state = files.isEmpty
          ? const GoogleDriveFilesEmpty()
          : GoogleDriveFilesLoaded(files: files);
    } on GoogleDriveException catch (e) {
      state = GoogleDriveFilesError(
        kind: e.kind,
        message: _messageFor(e.kind),
        classification: e.classification,
      );
    } on Object {
      state = const GoogleDriveFilesError(
        kind: GoogleDriveFailureKind.unexpectedResponse,
        message: 'Could not load Google Drive files. Try again.',
      );
    }
  }

  static String _messageFor(GoogleDriveFailureKind kind) {
    return switch (kind) {
      GoogleDriveFailureKind.authRequired =>
        'Connect Google Drive to list documents.',
      GoogleDriveFailureKind.auth =>
        'Connect Google Drive again to refresh files.',
      GoogleDriveFailureKind.expiredToken =>
        'Connect Google Drive again to refresh files.',
      GoogleDriveFailureKind.userCancelled => 'Sign-in was cancelled.',
      GoogleDriveFailureKind.uiUnavailable =>
        'Google sign-in is not available on this device.',
      GoogleDriveFailureKind.permission =>
        'Full Drive browser may be blocked by your organization. You can still choose individual Drive files.',
      GoogleDriveFailureKind.rateLimit =>
        'Google Drive is rate-limiting this connection. Try again later.',
      GoogleDriveFailureKind.network =>
        'Network connection failed. Check your connection and try again.',
      GoogleDriveFailureKind.unsupportedMimeType =>
        'No supported Drive files were found.',
      GoogleDriveFailureKind.fileTooLarge =>
        'That Drive file is too large to import.',
      GoogleDriveFailureKind.unexpectedResponse =>
        'Google Drive returned an unexpected response. Try again.',
    };
  }

  bool _isFullDriveBrowserEnabled() {
    final config = ref.read(configProvider).valueOrNull;
    return config?.googleDriveAccessMode ==
        GoogleDriveAccessMode.fullDriveBrowser;
  }
}

/// State for importing a Drive file into the reader.
sealed class GoogleDriveImportState {
  /// Base constructor for Drive import states.
  const GoogleDriveImportState();
}

/// Surface that initiated a Google Drive import.
enum DriveImportOrigin {
  /// Import started from the Sources tab Drive file list.
  sources,

  /// Import started from the Library Continue Reading shelf.
  libraryResume,
}

/// No Drive import is active.
class GoogleDriveImportIdle extends GoogleDriveImportState {
  /// Creates an idle state.
  const GoogleDriveImportIdle();
}

/// A Drive file is being imported.
class GoogleDriveImportLoading extends GoogleDriveImportState {
  /// Creates a loading state for [file].
  const GoogleDriveImportLoading({required this.file, required this.origin});

  /// Drive file currently importing.
  final GoogleDriveFile file;

  /// Surface that initiated this import.
  final DriveImportOrigin origin;
}

/// A Drive file is ready to read.
class GoogleDriveImportDone extends GoogleDriveImportState {
  /// Creates a done state.
  const GoogleDriveImportDone({
    required this.file,
    required this.identity,
    required this.document,
    required this.origin,
  });

  /// Imported Drive file.
  final GoogleDriveFile file;

  /// Canonical Drive identity used for local progress persistence.
  final DriveContentIdentity identity;

  /// Extracted document ready for RunThru reading.
  final ExtractedDocument document;

  /// Surface that initiated this import.
  final DriveImportOrigin origin;
}

/// A Drive import failed.
class GoogleDriveImportError extends GoogleDriveImportState {
  /// Creates an error state.
  const GoogleDriveImportError({
    required this.message,
    required this.origin,
    required this.kind,
    this.classification = GoogleDriveFailureClassification.unknown,
  });

  /// User-safe error message.
  final String message;

  /// Surface that initiated this import.
  final DriveImportOrigin origin;

  /// Diagnostic category.
  final GoogleDriveFailureKind kind;

  /// Retry/config classification safe for UI decisions.
  final GoogleDriveFailureClassification classification;
}

/// Imports supported Google Drive files into RunThru documents.
@riverpod
class GoogleDriveImport extends _$GoogleDriveImport {
  @override
  GoogleDriveImportState build() => const GoogleDriveImportIdle();

  /// Import size ceiling for PDFs.
  static const int maxPdfImportBytes = 200 * 1024 * 1024;

  /// Import size ceiling for EPUBs.
  static const int maxEpubImportBytes = 50 * 1024 * 1024;

  /// Fetches Drive metadata for [fileId], then imports the supported file.
  ///
  /// Persisted imports short-circuit: "Continue Reading" serves the local
  /// copy and the content store — no re-download, no re-extraction (BK-9).
  Future<void> importFileById(
    String fileId, {
    DriveImportOrigin origin = DriveImportOrigin.sources,
  }) async {
    final trimmed = fileId.trim();
    if (trimmed.isEmpty) {
      state = GoogleDriveImportError(
        message: 'Could not find that Drive file.',
        origin: origin,
        kind: GoogleDriveFailureKind.unexpectedResponse,
      );
      return;
    }
    if (await _tryImportFromLocalCopy(trimmed, origin)) return;
    try {
      final file = await ref
          .read(googleDriveClientProvider)
          .getSelectedFileMetadata(trimmed);
      await importFile(file, origin: origin);
    } on GoogleDriveException catch (e) {
      state = GoogleDriveImportError(
        message: _messageFor(e.kind),
        origin: origin,
        kind: e.kind,
        classification: e.classification,
      );
    } on Object {
      state = GoogleDriveImportError(
        message: 'Could not import that Drive file. Try again.',
        origin: origin,
        kind: GoogleDriveFailureKind.unexpectedResponse,
      );
    }
  }

  /// Imports [file] and transitions to done when the document is ready.
  Future<void> importFile(
    GoogleDriveFile file, {
    DriveImportOrigin origin = DriveImportOrigin.sources,
  }) async {
    if (file.isFolder) {
      state = GoogleDriveImportError(
        message: 'Folders are not supported.',
        origin: origin,
        kind: GoogleDriveFailureKind.unsupportedMimeType,
      );
      return;
    }
    if (!file.isSupported) {
      state = GoogleDriveImportError(
        message: 'That Drive file type is not supported.',
        origin: origin,
        kind: GoogleDriveFailureKind.unsupportedMimeType,
      );
      return;
    }
    // Size guard before any bytes move (BK-9): oversized files are rejected
    // with a clear error instead of OOM-ing mid-download.
    final ceiling = switch (file.mimeType) {
      pdfMimeType => maxPdfImportBytes,
      epubMimeType => maxEpubImportBytes,
      _ => null,
    };
    final size = file.sizeBytes;
    if (ceiling != null && size != null && size > ceiling) {
      final limitMb = ceiling ~/ (1024 * 1024);
      state = GoogleDriveImportError(
        message:
            '"${file.name}" is too large to import '
            '(limit $limitMb MB for this file type).',
        origin: origin,
        kind: GoogleDriveFailureKind.fileTooLarge,
      );
      return;
    }

    state = GoogleDriveImportLoading(file: file, origin: origin);
    try {
      final client = ref.read(googleDriveClientProvider);
      final document = await switch (file.mimeType) {
        googleDocsMimeType => _importGoogleDoc(client, file),
        pdfMimeType => _importBinaryFile(
          client,
          file,
          ref.read(googleDrivePdfExtractorProvider),
          await ref.read(googleDriveTempDirectoryProvider.future),
        ),
        epubMimeType => _importBinaryFile(
          client,
          file,
          ref.read(googleDriveEpubExtractorProvider),
          await ref.read(googleDriveTempDirectoryProvider.future),
        ),
        plainTextMimeType => _importText(client, file, ContentType.plainText),
        htmlMimeType => _importText(client, file, ContentType.html),
        _ => throw const GoogleDriveException(
          kind: GoogleDriveFailureKind.unsupportedMimeType,
          message: 'Unsupported Drive file type.',
        ),
      };
      state = GoogleDriveImportDone(
        file: file,
        identity: DriveContentIdentity.fromGoogleDriveFile(file),
        document: document,
        origin: origin,
      );
    } on GoogleDriveException catch (e) {
      state = GoogleDriveImportError(
        message: _messageFor(e.kind),
        origin: origin,
        kind: e.kind,
        classification: e.classification,
      );
    } on Object {
      state = GoogleDriveImportError(
        message: 'Could not import that Drive file. Try again.',
        origin: origin,
        kind: GoogleDriveFailureKind.unexpectedResponse,
      );
    }
  }

  /// Fetches selected Drive file metadata by ID, then imports each file.
  Future<void> importPickedDriveFileIds(
    List<String> fileIds, {
    DriveImportOrigin origin = DriveImportOrigin.sources,
  }) async {
    final seenIds = <String>{};
    final ids = [
      for (final rawId in fileIds)
        if (rawId.trim().isNotEmpty && seenIds.add(rawId.trim())) rawId.trim(),
    ];
    if (ids.isEmpty) {
      state = const GoogleDriveImportIdle();
      return;
    }

    try {
      final client = ref.read(googleDriveClientProvider);
      final files = <GoogleDriveFile>[];
      for (final id in ids) {
        files.add(await client.getSelectedFileMetadata(id));
      }
      await importPickedDriveFiles(files, origin: origin);
    } on GoogleDriveException catch (e) {
      state = GoogleDriveImportError(
        message: _messageFor(e.kind),
        origin: origin,
        kind: e.kind,
        classification: e.classification,
      );
    } on Object {
      state = GoogleDriveImportError(
        message: 'Could not import that Drive file. Try again.',
        origin: origin,
        kind: GoogleDriveFailureKind.unexpectedResponse,
      );
    }
  }

  /// Imports user-picked Drive files in sequence.
  Future<void> importPickedDriveFiles(
    List<GoogleDriveFile> files, {
    DriveImportOrigin origin = DriveImportOrigin.sources,
  }) async {
    if (files.isEmpty) {
      state = const GoogleDriveImportIdle();
      return;
    }
    for (final file in files) {
      await importFile(file, origin: origin);
      if (state is GoogleDriveImportError) return;
    }
  }

  /// Clears the current import state after navigation.
  void clear() {
    state = const GoogleDriveImportIdle();
  }

  static Future<ExtractedDocument> _importGoogleDoc(
    GoogleDriveClient client,
    GoogleDriveFile file,
  ) async {
    final text = await client.exportGoogleDoc(file);
    return ContentNormaliser.normalise(text, ContentType.plainText);
  }

  static Future<ExtractedDocument> _importText(
    GoogleDriveClient client,
    GoogleDriveFile file,
    ContentType contentType,
  ) async {
    final bytes = await client.downloadSelectedFile(file);
    final text = utf8.decode(bytes);
    return ContentNormaliser.normalise(text, contentType);
  }

  /// Serves a previously imported Drive file from its local copy and the
  /// content store. Returns true when the import completed locally.
  Future<bool> _tryImportFromLocalCopy(
    String fileId,
    DriveImportOrigin origin,
  ) async {
    try {
      final local = await ref.read(driveLocalStoreProvider).lookup(fileId);
      if (local == null) return false;
      if (local.mimeType != pdfMimeType && local.mimeType != epubMimeType) {
        return false;
      }
      final file = GoogleDriveFile(
        id: local.fileId,
        name: local.name,
        mimeType: local.mimeType,
      );
      state = GoogleDriveImportLoading(file: file, origin: origin);

      var document = await ref
          .read(contentStoreProvider)
          .getDocument(local.contentHash);
      if (document == null) {
        // Store sections were evicted — re-extract from the local copy
        // (still no network involved).
        final extractor = local.mimeType == pdfMimeType
            ? ref.read(googleDrivePdfExtractorProvider)
            : ref.read(googleDriveEpubExtractorProvider);
        document = await extractor(local.localPath);
        await ref
            .read(contentStoreProvider)
            .putDocument(
              BookIdentity(
                contentHash: local.contentHash,
                sourceId: 'drive:${local.fileId}',
                displayName: local.name,
              ),
              document,
            );
      }
      state = GoogleDriveImportDone(
        file: file,
        identity: DriveContentIdentity.fromGoogleDriveFile(file),
        document: document,
        origin: origin,
      );
      appLog('google-drive-import', 'served from local copy name=${local.name}');
      return true;
    } on Object catch (e) {
      appLog('google-drive-import', 'local copy import failed: $e');
      return false; // fall back to the network path
    }
  }

  Future<ExtractedDocument> _importBinaryFile(
    GoogleDriveClient client,
    GoogleDriveFile file,
    DocumentFileExtractor extractor,
    Directory tempDir,
  ) async {
    final tempFile = _tempFileFor(file, tempDir);
    try {
      // Stream straight to disk — memory stays O(buffer) (BK-9).
      await client.downloadSelectedFileTo(file, tempFile);
      final document = await extractor(tempFile.path);
      await _persistLocalCopy(file, tempFile, document);
      return document;
    } finally {
      // Deterministic temp cleanup on success and failure (BK-9).
      try {
        if (tempFile.existsSync()) tempFile.deleteSync();
      } on Object catch (e) {
        appLog('google-drive-import', 'temp cleanup failed: $e');
      }
    }
  }

  /// Keeps the downloaded file under its content hash and ingests the
  /// extracted text into the content store, so future opens are local.
  /// Failures are non-fatal — the import itself already succeeded.
  Future<void> _persistLocalCopy(
    GoogleDriveFile file,
    File downloaded,
    ExtractedDocument document,
  ) async {
    try {
      final hash = await ref
          .read(contentIdentityProvider)
          .ensureHash(downloaded.path);
      if (hash == null) return;
      await ref
          .read(driveLocalStoreProvider)
          .persist(
            fileId: file.id,
            contentHash: hash,
            name: file.name,
            mimeType: file.mimeType,
            sourceFile: downloaded,
            extension: file.extension,
          );
      await ref
          .read(contentStoreProvider)
          .putDocument(
            BookIdentity(
              contentHash: hash,
              sourceId: 'drive:${file.id}',
              displayName: file.name,
            ),
            document,
          );
    } on Object catch (e) {
      appLog('google-drive-import', 'persist local copy failed: $e');
    }
  }

  static File _tempFileFor(GoogleDriveFile file, Directory tempDir) {
    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final hasExtension = safeName.toLowerCase().endsWith('.${file.extension}');
    final name = hasExtension ? safeName : '$safeName.${file.extension}';
    return File('${tempDir.path}/runthru-drive-${file.id}-$name');
  }

  static String _messageFor(GoogleDriveFailureKind kind) {
    return switch (kind) {
      GoogleDriveFailureKind.authRequired => 'Connect Google Drive again.',
      GoogleDriveFailureKind.auth => 'Connect Google Drive again.',
      GoogleDriveFailureKind.expiredToken => 'Connect Google Drive again.',
      GoogleDriveFailureKind.userCancelled => 'Sign-in was cancelled.',
      GoogleDriveFailureKind.uiUnavailable =>
        'Google sign-in is not available on this device.',
      GoogleDriveFailureKind.permission =>
        'RunThru needs read-only access to import that Drive file, or the file may no longer be available.',
      GoogleDriveFailureKind.rateLimit =>
        'Google Drive is rate-limiting this connection. Try again later.',
      GoogleDriveFailureKind.network =>
        'Network connection failed. Check your connection and try again.',
      GoogleDriveFailureKind.unsupportedMimeType =>
        'That Drive file type is not supported.',
      GoogleDriveFailureKind.fileTooLarge =>
        'That Drive file is too large to import.',
      GoogleDriveFailureKind.unexpectedResponse =>
        'Google Drive returned an unexpected response. Try again.',
    };
  }
}
