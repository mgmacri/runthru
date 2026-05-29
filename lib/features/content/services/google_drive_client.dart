/// Minimal Google Drive v3 REST client for RunThru imports.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/store/models.dart';

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

/// Retry/diagnostic classification for Drive failures.
enum GoogleDriveFailureClassification {
  /// The failure may succeed later without changing credentials.
  transient,

  /// The operation cannot recover without user or configuration changes.
  permanent,

  /// Required OAuth/app configuration is missing.
  missingConfig,

  /// A Google Workspace administrator may have blocked the app or scope.
  adminPolicyBlocked,

  /// Third-party app access appears to be blocked by policy.
  thirdPartyAppBlocked,

  /// The user or provider denied the requested access.
  accessDenied,

  /// The current grant is missing the Drive scope needed for this operation.
  insufficientScope,

  /// No finer-grained classification was provided.
  unknown,
}

enum _DriveAuthFailureKind {
  expiredOrInvalidAccessToken,
  insufficientScopeOrPermission,
  permanentAuthFailure,
  transientOrUnknown,
}

class _DriveAuthFailureMetadata {
  const _DriveAuthFailureMetadata({
    required this.kind,
    this.reason,
    this.status,
    this.domain,
  });

  final _DriveAuthFailureKind kind;
  final String? reason;
  final String? status;
  final String? domain;
}

/// Typed exception from Google Drive auth or API operations.
class GoogleDriveException implements Exception {
  /// Creates a typed Drive exception.
  const GoogleDriveException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.classification = GoogleDriveFailureClassification.unknown,
    this.shouldClearStoredCredentials = false,
  });

  /// Failure category.
  final GoogleDriveFailureKind kind;

  /// Safe diagnostic message. Never include tokens or file contents.
  final String message;

  /// HTTP status code, if one exists.
  final int? statusCode;

  /// Retry/diagnostic classification safe for logs.
  final GoogleDriveFailureClassification classification;

  /// Whether saved OAuth credentials are known to be unrecoverable.
  final bool shouldClearStoredCredentials;

  /// Whether the same operation can be retried later without reconnecting.
  bool get isRetryable =>
      classification == GoogleDriveFailureClassification.transient;

  @override
  String toString() =>
      'GoogleDriveException(kind: ${kind.name}, statusCode: $statusCode, '
      'classification: ${classification.name}, '
      'shouldClearStoredCredentials: $shouldClearStoredCredentials, '
      'message: $message)';
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
    GoogleDriveAccessMode accessMode = GoogleDriveAccessMode.fullDriveBrowser,
  }) : _headersProvider = headersProvider,
       _httpClient = httpClient ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse('https://www.googleapis.com/drive/v3'),
       _accessMode = accessMode;

  final GoogleDriveHeaderProvider _headersProvider;
  final http.Client _httpClient;
  final Uri _baseUri;
  final GoogleDriveAccessMode _accessMode;

  /// Lists supported Drive files, optionally filtered by [query].
  ///
  /// This is only available in [GoogleDriveAccessMode.fullDriveBrowser].
  Future<List<GoogleDriveFile>> listDriveFiles({String? query}) async {
    if (_accessMode != GoogleDriveAccessMode.fullDriveBrowser) {
      throw const GoogleDriveException(
        kind: GoogleDriveFailureKind.permission,
        message: 'Drive-wide listing requires full Drive browser mode.',
        classification: GoogleDriveFailureClassification.accessDenied,
      );
    }
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

      final response = await _authorizedSend(
        (headers) async => _httpClient.get(uri, headers: headers),
        failureMessage: 'Could not list Drive files',
      );
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
    final response = await _authorizedSend(
      (headers) async => _httpClient.get(uri, headers: headers),
      failureMessage: 'Could not fetch Drive file metadata',
    );
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

  /// Fetches metadata for a user-selected Drive file.
  Future<GoogleDriveFile> getSelectedFileMetadata(String fileId) {
    return metadata(fileId);
  }

  /// Downloads bytes for a user-selected Drive blob file.
  Future<List<int>> downloadSelectedFile(GoogleDriveFile file) async {
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
    final response = await _authorizedSend(
      (headers) async => _httpClient.get(uri, headers: headers),
      failureMessage: 'Could not download Drive file',
    );
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
    final response = await _authorizedSend(
      (headers) async => _httpClient.get(uri, headers: headers),
      failureMessage: 'Could not export Google Doc',
    );
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
        classification: GoogleDriveFailureClassification.transient,
      );
    }
  }

  Future<http.Response> _authorizedSend(
    Future<http.Response> Function(Map<String, String> headers) request, {
    required String failureMessage,
  }) async {
    final response = await _send(() async {
      return request(await _headersProvider());
    });
    if (!_isAuthFailureResponse(response)) return response;

    final metadata = _classifyDriveAuthFailure(response);
    final shouldRetry =
        response.statusCode == 401 &&
        metadata.kind == _DriveAuthFailureKind.expiredOrInvalidAccessToken;
    _logAuthorizedSendDecision(
      statusCode: response.statusCode,
      metadata: metadata,
      retryAttempted: shouldRetry,
    );
    if (shouldRetry) {
      final retryResponse = await _send(() async {
        return request(await _headersProvider());
      });
      if (!_isAuthFailureResponse(retryResponse)) return retryResponse;

      final retryMetadata = _classifyDriveAuthFailure(retryResponse);
      _logAuthorizedSendDecision(
        statusCode: retryResponse.statusCode,
        metadata: retryMetadata,
        retryAttempted: false,
      );
      throw _exceptionForAuthFailure(
        retryResponse,
        retryMetadata,
        failureMessage,
      );
    }

    throw _exceptionForAuthFailure(response, metadata, failureMessage);
  }

  static bool _isAuthFailureResponse(http.Response response) {
    return response.statusCode == 401 || response.statusCode == 403;
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
      classification: _classificationForStatus(response.statusCode),
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

  static GoogleDriveFailureClassification _classificationForStatus(
    int statusCode,
  ) {
    if (statusCode == 403) return GoogleDriveFailureClassification.accessDenied;
    if (statusCode == 429) return GoogleDriveFailureClassification.transient;
    return GoogleDriveFailureClassification.unknown;
  }

  static String _escapeDriveQueryValue(String value) {
    return value.replaceAll('\\', r'\\').replaceAll("'", r"\'");
  }

  static const int _maxAuthErrorBodyBytes = 16 * 1024;

  static GoogleDriveException _exceptionForAuthFailure(
    http.Response response,
    _DriveAuthFailureMetadata metadata,
    String message,
  ) {
    return switch (metadata.kind) {
      _DriveAuthFailureKind.expiredOrInvalidAccessToken => GoogleDriveException(
        kind: GoogleDriveFailureKind.expiredToken,
        message:
            '$message: the saved Google Drive access token expired. Connect again.',
        statusCode: response.statusCode,
        classification: GoogleDriveFailureClassification.permanent,
      ),
      _DriveAuthFailureKind.insufficientScopeOrPermission => GoogleDriveException(
        kind: GoogleDriveFailureKind.permission,
        message:
            '$message: the current Google Drive grant does not include the required access.',
        statusCode: response.statusCode,
        classification: GoogleDriveFailureClassification.insufficientScope,
      ),
      _DriveAuthFailureKind.permanentAuthFailure => GoogleDriveException(
        kind: GoogleDriveFailureKind.auth,
        message:
            '$message: the Google Drive authorization is no longer valid. Connect again.',
        statusCode: response.statusCode,
        classification: GoogleDriveFailureClassification.permanent,
        shouldClearStoredCredentials: true,
      ),
      _DriveAuthFailureKind.transientOrUnknown => GoogleDriveException(
        kind: GoogleDriveFailureKind.auth,
        message:
            '$message: Google Drive authorization failed. Try again later.',
        statusCode: response.statusCode,
        classification: GoogleDriveFailureClassification.transient,
      ),
    };
  }

  static _DriveAuthFailureMetadata _classifyDriveAuthFailure(
    http.Response response,
  ) {
    try {
      final values = <String>{};
      String? reason;
      String? status;
      String? domain;

      final authenticate = _headerValue(response.headers, 'www-authenticate');
      if (authenticate != null) {
        final headerValues = _normalizedAuthTerms(authenticate);
        values.addAll(headerValues);
        reason ??= _firstSafeValue(headerValues, _safeReasonValues);
        status ??= _firstSafeValue(headerValues, _safeStatusValues);
      }

      final decoded = _decodeBoundedAuthErrorJson(response);
      if (decoded != null) {
        final extracted = <String>{};
        _extractAuthErrorFields(decoded, extracted);
        values.addAll(extracted);
        reason ??= _firstSafeValue(extracted, _safeReasonValues);
        status ??= _firstSafeValue(extracted, _safeStatusValues);
        domain ??= _firstSafeValue(extracted, _safeDomainValues);
      }

      return _DriveAuthFailureMetadata(
        kind: _kindForAuthMetadata(response.statusCode, values),
        reason: reason,
        status: status,
        domain: domain,
      );
    } on Object {
      return const _DriveAuthFailureMetadata(
        kind: _DriveAuthFailureKind.transientOrUnknown,
      );
    }
  }

  static _DriveAuthFailureKind _kindForAuthMetadata(
    int statusCode,
    Set<String> values,
  ) {
    if (_containsAny(values, const {
      'admin_policy_enforced',
      'third_party_app_blocked',
      'invalid_grant',
      'access_denied',
      'unauthorized_client',
    })) {
      return _DriveAuthFailureKind.permanentAuthFailure;
    }

    if (_containsAny(values, const {
      'insufficientpermissions',
      'access_token_scope_insufficient',
      'permission_denied',
      'forbidden',
      'insufficient_scope',
      'insufficientauthenticationscopes',
    })) {
      return _DriveAuthFailureKind.insufficientScopeOrPermission;
    }

    if (_containsAny(values, const {
      'invalid_token',
      'expired',
      'expired_token',
      'invalidcredentials',
      'autherror',
      'unauthenticated',
    })) {
      return _DriveAuthFailureKind.expiredOrInvalidAccessToken;
    }

    if (statusCode == 403) {
      return _DriveAuthFailureKind.insufficientScopeOrPermission;
    }
    return _DriveAuthFailureKind.transientOrUnknown;
  }

  static Map<String, Object?>? _decodeBoundedAuthErrorJson(
    http.Response response,
  ) {
    if (response.bodyBytes.length > _maxAuthErrorBodyBytes) return null;

    final contentType = _headerValue(response.headers, 'content-type') ?? '';
    final body = response.body.trimLeft();
    if (!contentType.toLowerCase().contains('json') && !body.startsWith('{')) {
      return null;
    }

    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }

  static void _extractAuthErrorFields(
    Map<String, Object?> json,
    Set<String> values,
  ) {
    _addNormalizedString(values, json['error']);
    _addNormalizedString(values, json['error_description']);

    final error = json['error'];
    if (error is Map<String, Object?>) {
      _addNormalizedString(values, error['code']);
      _addNormalizedString(values, error['status']);
      _addNormalizedString(values, error['message']);

      final errors = error['errors'];
      if (errors is List<Object?>) {
        for (final item in errors) {
          if (item is! Map<String, Object?>) continue;
          _addNormalizedString(values, item['reason']);
          _addNormalizedString(values, item['domain']);
        }
      }
    }
  }

  static Set<String> _normalizedAuthTerms(String value) {
    final lower = value.toLowerCase();
    final terms = <String>{};
    for (final token in const [
      'invalid_token',
      'expired',
      'expired_token',
      'insufficient_scope',
      'invalid_grant',
      'access_denied',
      'unauthorized_client',
      'admin_policy_enforced',
      'third_party_app_blocked',
    ]) {
      if (lower.contains(token)) terms.add(token);
    }
    return terms;
  }

  static void _addNormalizedString(Set<String> values, Object? value) {
    if (value is num) {
      values.add(value.toString().toLowerCase());
      return;
    }
    if (value is! String || value.length > 256) return;
    values.add(value.trim().toLowerCase());
  }

  static String? _headerValue(Map<String, String> headers, String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) return entry.value;
    }
    return null;
  }

  static bool _containsAny(Set<String> values, Set<String> needles) {
    for (final value in values) {
      final normalized = value.replaceAll(RegExp(r'[^a-z0-9_]+'), '');
      for (final needle in needles) {
        final normalizedNeedle = needle.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9_]+'),
          '',
        );
        if (normalized == normalizedNeedle ||
            normalized.contains(normalizedNeedle)) {
          return true;
        }
      }
    }
    return false;
  }

  static String? _firstSafeValue(Set<String> values, Set<String> allowed) {
    for (final value in values) {
      final normalized = value.replaceAll(RegExp(r'[^a-z0-9_]+'), '');
      for (final allowedValue in allowed) {
        final normalizedAllowed = allowedValue.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9_]+'),
          '',
        );
        if (normalized == normalizedAllowed) return allowedValue;
      }
    }
    return null;
  }

  static const Set<String> _safeReasonValues = {
    'authError',
    'invalidCredentials',
    'insufficientPermissions',
    'forbidden',
    'invalid_token',
    'expired_token',
    'insufficient_scope',
    'invalid_grant',
    'access_denied',
    'unauthorized_client',
    'admin_policy_enforced',
    'third_party_app_blocked',
  };

  static const Set<String> _safeStatusValues = {
    'UNAUTHENTICATED',
    'PERMISSION_DENIED',
    'ACCESS_TOKEN_SCOPE_INSUFFICIENT',
    'UNAUTHORIZED_CLIENT',
  };

  static const Set<String> _safeDomainValues = {'global', 'usageLimits'};

  static void _logAuthorizedSendDecision({
    required int statusCode,
    required _DriveAuthFailureMetadata metadata,
    required bool retryAttempted,
  }) {
    final reason = metadata.reason == null ? '' : ' reason=${metadata.reason}';
    final status = metadata.status == null
        ? ''
        : ' authStatus=${metadata.status}';
    final domain = metadata.domain == null ? '' : ' domain=${metadata.domain}';
    appLog(
      'google-drive-client',
      'operation=drive_authorized_send statusCode=$statusCode '
          'classification=${metadata.kind.name} retryAttempted=$retryAttempted'
          '$reason$status$domain',
    );
  }
}
