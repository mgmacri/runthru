/// Riverpod providers for Google Drive file browsing and importing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/services/content_normaliser.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/services/epub_extractor.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_extractor.dart';

part 'google_drive_files_provider.g.dart';

/// Extracts a document from a local file path.
typedef DocumentFileExtractor =
    Future<ExtractedDocument> Function(String filePath);

/// Google Drive client dependency.
@Riverpod(keepAlive: true)
GoogleDriveClient googleDriveClient(GoogleDriveClientRef ref) {
  return GoogleDriveClient(
    headersProvider: () =>
        ref.read(googleDriveAuthProvider.notifier).authorizationHeaders(),
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
  const GoogleDriveFilesError({required this.message, required this.kind});

  /// User-safe error message.
  final String message;

  /// Diagnostic category.
  final GoogleDriveFailureKind kind;
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
    _load();
    return const GoogleDriveFilesLoading();
  }

  /// Refreshes supported Drive files.
  Future<void> refresh({String? query}) async {
    final current = state;
    if (current is GoogleDriveFilesLoaded) {
      state = GoogleDriveFilesLoaded(files: current.files, refreshing: true);
    } else {
      state = const GoogleDriveFilesLoading();
    }
    await _load(query: query);
  }

  Future<void> _load({String? query}) async {
    try {
      final files = await ref
          .read(googleDriveClientProvider)
          .listSupportedFiles(query: query);
      state = files.isEmpty
          ? const GoogleDriveFilesEmpty()
          : GoogleDriveFilesLoaded(files: files);
    } on GoogleDriveException catch (e) {
      state = GoogleDriveFilesError(kind: e.kind, message: _messageFor(e.kind));
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
      GoogleDriveFailureKind.userCancelled =>
        'Google Drive sign-in was canceled.',
      GoogleDriveFailureKind.uiUnavailable =>
        'Google sign-in is not available on this device.',
      GoogleDriveFailureKind.permission =>
        'RunThru needs read-only Drive access to list documents.',
      GoogleDriveFailureKind.rateLimit =>
        'Google Drive is rate-limiting this connection. Try again later.',
      GoogleDriveFailureKind.network =>
        'Network connection failed. Check your connection and try again.',
      GoogleDriveFailureKind.unsupportedMimeType =>
        'No supported Drive files were found.',
      GoogleDriveFailureKind.unexpectedResponse =>
        'Google Drive returned an unexpected response. Try again.',
    };
  }
}

/// State for importing a Drive file into the reader.
sealed class GoogleDriveImportState {
  /// Base constructor for Drive import states.
  const GoogleDriveImportState();
}

/// No Drive import is active.
class GoogleDriveImportIdle extends GoogleDriveImportState {
  /// Creates an idle state.
  const GoogleDriveImportIdle();
}

/// A Drive file is being imported.
class GoogleDriveImportLoading extends GoogleDriveImportState {
  /// Creates a loading state for [file].
  const GoogleDriveImportLoading({required this.file});

  /// Drive file currently importing.
  final GoogleDriveFile file;
}

/// A Drive file is ready to read.
class GoogleDriveImportDone extends GoogleDriveImportState {
  /// Creates a done state.
  const GoogleDriveImportDone({required this.file, required this.document});

  /// Imported Drive file.
  final GoogleDriveFile file;

  /// Extracted document ready for RunThru reading.
  final ExtractedDocument document;
}

/// A Drive import failed.
class GoogleDriveImportError extends GoogleDriveImportState {
  /// Creates an error state.
  const GoogleDriveImportError({required this.message});

  /// User-safe error message.
  final String message;
}

/// Imports supported Google Drive files into RunThru documents.
@riverpod
class GoogleDriveImport extends _$GoogleDriveImport {
  @override
  GoogleDriveImportState build() => const GoogleDriveImportIdle();

  /// Imports [file] and transitions to done when the document is ready.
  Future<void> importFile(GoogleDriveFile file) async {
    if (!file.isSupported) {
      state = const GoogleDriveImportError(
        message: 'That Drive file type is not supported.',
      );
      return;
    }

    state = GoogleDriveImportLoading(file: file);
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
      state = GoogleDriveImportDone(file: file, document: document);
    } on GoogleDriveException catch (e) {
      state = GoogleDriveImportError(message: _messageFor(e.kind));
    } on Object {
      state = const GoogleDriveImportError(
        message: 'Could not import that Drive file. Try again.',
      );
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
    final bytes = await client.downloadBinary(file);
    final text = utf8.decode(bytes);
    return ContentNormaliser.normalise(text, contentType);
  }

  static Future<ExtractedDocument> _importBinaryFile(
    GoogleDriveClient client,
    GoogleDriveFile file,
    DocumentFileExtractor extractor,
    Directory tempDir,
  ) async {
    final bytes = await client.downloadBinary(file);
    final tempFile = await _writeTempFile(file, bytes, tempDir);
    return extractor(tempFile.path);
  }

  static Future<File> _writeTempFile(
    GoogleDriveFile file,
    List<int> bytes,
    Directory tempDir,
  ) async {
    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final hasExtension = safeName.toLowerCase().endsWith('.${file.extension}');
    final name = hasExtension ? safeName : '$safeName.${file.extension}';
    final tempFile = File('${tempDir.path}/runthru-drive-${file.id}-$name');
    return tempFile.writeAsBytes(bytes, flush: true);
  }

  static String _messageFor(GoogleDriveFailureKind kind) {
    return switch (kind) {
      GoogleDriveFailureKind.authRequired => 'Connect Google Drive again.',
      GoogleDriveFailureKind.auth => 'Connect Google Drive again.',
      GoogleDriveFailureKind.expiredToken => 'Connect Google Drive again.',
      GoogleDriveFailureKind.userCancelled =>
        'Google Drive sign-in was canceled.',
      GoogleDriveFailureKind.uiUnavailable =>
        'Google sign-in is not available on this device.',
      GoogleDriveFailureKind.permission =>
        'RunThru needs read-only access to import that Drive file.',
      GoogleDriveFailureKind.rateLimit =>
        'Google Drive is rate-limiting this connection. Try again later.',
      GoogleDriveFailureKind.network =>
        'Network connection failed. Check your connection and try again.',
      GoogleDriveFailureKind.unsupportedMimeType =>
        'That Drive file type is not supported.',
      GoogleDriveFailureKind.unexpectedResponse =>
        'Google Drive returned an unexpected response. Try again.',
    };
  }
}
