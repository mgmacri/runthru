/// Minimal Google Drive v3 REST client for read-only RunThru imports.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:runthru/features/content/models/google_drive_file.dart';

/// Drive API failure categories safe for logs and UI mapping.
enum GoogleDriveFailureKind {
  /// The user is signed out or no saved account is available.
  authRequired,

  /// Authorization is missing or expired.
  auth,

  /// Saved authorization has expired or was revoked.
  expiredToken,

  /// The user canceled the Google sign-in flow.
  userCancelled,

  /// Google Sign-In cannot display the required provider/browser UI.
  uiUnavailable,

  /// The user lacks access to the requested file.
  permission,

  /// Google Drive rate-limited the request.
  rateLimit,

  /// Network transport failed.
  network,

  /// File MIME type is not supported by RunThru.
  unsupportedMimeType,

  /// Google returned an unexpected response.
  unexpectedResponse,
}

/// Typed exception from Google Drive auth or API operations.
class GoogleDriveException implements Exception {
  /// Creates a typed Drive exception.
  const GoogleDriveException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  /// Failure category.
  final GoogleDriveFailureKind kind;

  /// Safe diagnostic message. Never include tokens or file contents.
  final String message;

  /// HTTP status code, if one exists.
  final int? statusCode;

  @override
  String toString() =>
      'GoogleDriveException(kind: ${kind.name}, statusCode: $statusCode, message: $message)';
}

/// Provides scoped authorization headers for Drive REST requests.
typedef GoogleDriveHeaderProvider = Future<Map<String, String>> Function();

/// Read-only Google Drive REST client.
class GoogleDriveClient {
  /// Creates a Drive client.
  GoogleDriveClient({
    required GoogleDriveHeaderProvider headersProvider,
    http.Client? httpClient,
    Uri? baseUri,
  }) : _headersProvider = headersProvider,
       _httpClient = httpClient ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse('https://www.googleapis.com/drive/v3');

  final GoogleDriveHeaderProvider _headersProvider;
  final http.Client _httpClient;
  final Uri _baseUri;

  /// Lists supported Drive files, optionally filtered by [query].
  Future<List<GoogleDriveFile>> listSupportedFiles({String? query}) async {
    final mimeQuery = supportedDriveMimeQuery();
    final escapedName = _escapeDriveQueryValue(query?.trim() ?? '');
    final q = [
      'trashed = false',
      '($mimeQuery)',
      if (escapedName.isNotEmpty) "name contains '$escapedName'",
    ].join(' and ');

    final files = <GoogleDriveFile>[];
    String? pageToken;
    do {
      final uri = _baseUri.replace(
        path: '${_baseUri.path}/files',
        queryParameters: {
          'q': q,
          'pageSize': '50',
          'orderBy': 'modifiedTime desc',
          'fields': 'files(id,name,mimeType,modifiedTime,size),nextPageToken',
          if (pageToken != null) 'pageToken': pageToken,
        },
      );

      final response = await _send(() async {
        return _httpClient.get(uri, headers: await _headersProvider());
      });
      _throwIfFailed(response, 'Could not list Drive files');

      final decoded = _decodeJson(response.body);
      final rawFiles = decoded['files'] as List<Object?>? ?? const [];
      files.addAll(
        rawFiles
            .whereType<Map<String, Object?>>()
            .map(GoogleDriveFile.fromJson)
            .where((file) => file.isSupported),
      );
      pageToken = decoded['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);

    return files;
  }

  /// Fetches metadata for one Drive file.
  Future<GoogleDriveFile> metadata(String fileId) async {
    final uri = _baseUri.replace(
      path: '${_baseUri.path}/files/$fileId',
      queryParameters: {'fields': 'id,name,mimeType,modifiedTime,size'},
    );
    final response = await _send(() async {
      return _httpClient.get(uri, headers: await _headersProvider());
    });
    _throwIfFailed(response, 'Could not fetch Drive file metadata');
    final file = GoogleDriveFile.fromJson(_decodeJson(response.body));
    if (!file.isSupported) {
      throw GoogleDriveException(
        kind: GoogleDriveFailureKind.unsupportedMimeType,
        message: 'Unsupported Drive file type: ${file.mimeType}',
      );
    }
    return file;
  }

  /// Downloads bytes for a blob file such as PDF, EPUB, text, or HTML.
  Future<List<int>> downloadBinary(GoogleDriveFile file) async {
    if (file.isGoogleDoc) {
      throw const GoogleDriveException(
        kind: GoogleDriveFailureKind.unsupportedMimeType,
        message: 'Google Docs must be exported, not downloaded.',
      );
    }
    final uri = _baseUri.replace(
      path: '${_baseUri.path}/files/${file.id}',
      queryParameters: {'alt': 'media'},
    );
    final response = await _send(() async {
      return _httpClient.get(uri, headers: await _headersProvider());
    });
    _throwIfFailed(response, 'Could not download Drive file');
    return response.bodyBytes;
  }

  /// Exports a Google Docs file as [exportMimeType].
  Future<String> exportGoogleDoc(
    GoogleDriveFile file, {
    String exportMimeType = plainTextMimeType,
  }) async {
    if (!file.isGoogleDoc) {
      throw const GoogleDriveException(
        kind: GoogleDriveFailureKind.unsupportedMimeType,
        message: 'Only Google Docs files can be exported.',
      );
    }
    final uri = _baseUri.replace(
      path: '${_baseUri.path}/files/${file.id}/export',
      queryParameters: {'mimeType': exportMimeType},
    );
    final response = await _send(() async {
      return _httpClient.get(uri, headers: await _headersProvider());
    });
    _throwIfFailed(response, 'Could not export Google Doc');
    return utf8.decode(response.bodyBytes);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on http.ClientException catch (e) {
      throw GoogleDriveException(
        kind: GoogleDriveFailureKind.network,
        message: 'Network failure: ${e.message}',
      );
    }
  }

  static Map<String, Object?> _decodeJson(String body) {
    try {
      return (jsonDecode(body) as Map<String, Object?>?) ?? {};
    } on FormatException {
      throw const GoogleDriveException(
        kind: GoogleDriveFailureKind.unexpectedResponse,
        message: 'Drive returned invalid JSON.',
      );
    }
  }

  static void _throwIfFailed(http.Response response, String message) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw GoogleDriveException(
      kind: _kindForStatus(response.statusCode),
      message: '$message: HTTP ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  static GoogleDriveFailureKind _kindForStatus(int statusCode) {
    if (statusCode == 401) return GoogleDriveFailureKind.expiredToken;
    if (statusCode == 403) return GoogleDriveFailureKind.permission;
    if (statusCode == 429) return GoogleDriveFailureKind.rateLimit;
    if (statusCode == 400 || statusCode == 415) {
      return GoogleDriveFailureKind.unsupportedMimeType;
    }
    return GoogleDriveFailureKind.unexpectedResponse;
  }

  static String _escapeDriveQueryValue(String value) {
    return value.replaceAll('\\', r'\\').replaceAll("'", r"\'");
  }
}
