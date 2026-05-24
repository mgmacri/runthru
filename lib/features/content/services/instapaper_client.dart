/// Instapaper Full API client with OAuth 1.0a xAuth authentication.
///
/// Uses HMAC-SHA1 request signing per the Instapaper Full API specification.
/// All requests are POST with OAuth params in the Authorization header.
///
/// See: https://www.instapaper.com/developers/v1/full-api
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:runthru/features/content/models/instapaper_bookmark.dart';

/// OAuth token pair from xAuth authentication.
class InstapaperTokenPair {
  /// Creates a token pair with the given [token] and [tokenSecret].
  const InstapaperTokenPair({required this.token, required this.tokenSecret});

  /// The OAuth access token.
  final String token;

  /// The OAuth token secret used for request signing.
  final String tokenSecret;
}

/// Instapaper user account info.
class InstapaperUser {
  /// Creates a user with the given [userId] and [username].
  const InstapaperUser({required this.userId, required this.username});

  /// Parses a user from the Instapaper API JSON response.
  factory InstapaperUser.fromJson(Map<String, Object?> json) => InstapaperUser(
    userId: (json['user_id'] as num).toInt(),
    username: json['username'] as String,
  );

  /// The Instapaper user ID.
  final int userId;

  /// The user's email or username.
  final String username;
}

/// Compile-time Instapaper consumer credential configuration.
class InstapaperClientConfig {
  /// Creates client configuration.
  const InstapaperClientConfig({
    required this.consumerKey,
    required this.consumerSecret,
  });

  /// Configuration loaded from Flutter dart-defines.
  static const fromEnvironment = InstapaperClientConfig(
    consumerKey: String.fromEnvironment('INSTAPAPER_CONSUMER_KEY'),
    consumerSecret: String.fromEnvironment('INSTAPAPER_CONSUMER_SECRET'),
  );

  /// The OAuth consumer key.
  final String consumerKey;

  /// The OAuth consumer secret.
  final String consumerSecret;

  /// Whether both required consumer credentials are present.
  bool get isConfigured =>
      consumerKey.trim().isNotEmpty && consumerSecret.trim().isNotEmpty;

  /// Debug-safe status string that never includes credential values.
  String get diagnostics =>
      'INSTAPAPER_CONSUMER_KEY=${consumerKey.trim().isNotEmpty ? 'present' : 'missing'}, '
      'INSTAPAPER_CONSUMER_SECRET=${consumerSecret.trim().isNotEmpty ? 'present' : 'missing'}';
}

/// High-level category for safe user-facing errors and diagnostics.
enum InstapaperFailureKind {
  /// Browser/app-based sign-in is not available in this build or platform.
  officialAuthUnavailable,

  /// The user canceled browser/app-based sign-in.
  userCancelled,

  /// The user denied sign-in or read access.
  permissionDenied,

  /// Consumer key or secret is missing from build configuration.
  missingConfiguration,

  /// Instapaper rejected the supplied user credentials.
  invalidCredentials,

  /// The network request could not be completed.
  network,

  /// Instapaper is unavailable or returned a transient server error.
  serviceUnavailable,

  /// Instapaper returned a response that did not match its documented format.
  unexpectedResponse,

  /// Secure token storage failed.
  secureStorage,

  /// Stored tokens are missing, invalid, or expired.
  unauthorized,

  /// The app or account hit Instapaper's API rate limit.
  rateLimited,

  /// The application has been suspended by Instapaper.
  suspended,

  /// A failure that does not fit a more specific category.
  unknown,
}

/// Redacts sensitive values from diagnostic strings.
class InstapaperRedactor {
  InstapaperRedactor._();

  static final List<RegExp> _patterns = [
    RegExp(r'Authorization\s*[:=]\s*OAuth[^\n]+', caseSensitive: false),
    RegExp(r'OAuth\s+[A-Za-z0-9%_~\-.,=" ]+', caseSensitive: false),
    RegExp(
      r'(oauth_signature|oauth_token_secret|oauth_token|x_auth_password|x_auth_username|password|username)\s*[:=]\s*[^&,\s\]]+',
      caseSensitive: false,
    ),
  ];

  /// Returns [value] with token, password, username, and auth header data hidden.
  static String redact(String value) {
    var redacted = value;
    for (final pattern in _patterns) {
      redacted = redacted.replaceAllMapped(pattern, (match) {
        final text = match.group(0)!;
        final separator = text.contains(':') ? ':' : '=';
        if (text.toLowerCase().startsWith('oauth ')) {
          return 'OAuth [REDACTED]';
        }
        return '${text.split(separator).first}$separator[REDACTED]';
      });
    }
    return redacted;
  }
}

/// Authentication failure during xAuth token acquisition.
class InstapaperAuthException implements Exception {
  /// Creates an auth exception with the given [kind].
  const InstapaperAuthException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  /// The safe diagnostic category.
  final InstapaperFailureKind kind;

  /// The HTTP status code returned by the API, if any.
  final int? statusCode;

  /// A redacted, human-readable description of the error.
  final String message;

  @override
  String toString() =>
      'InstapaperAuthException(kind: ${kind.name}, statusCode: $statusCode, message: ${InstapaperRedactor.redact(message)})';
}

/// API call failure after authentication.
class InstapaperApiException implements Exception {
  /// Creates an API exception with the given [kind].
  const InstapaperApiException({
    required this.kind,
    required this.errorCode,
    required this.message,
  });

  /// The safe diagnostic category.
  final InstapaperFailureKind kind;

  /// The Instapaper error code or HTTP status code.
  final int errorCode;

  /// A redacted, human-readable description of the error.
  final String message;

  @override
  String toString() =>
      'InstapaperApiException(kind: ${kind.name}, errorCode: $errorCode, message: ${InstapaperRedactor.redact(message)})';
}

/// HTTP client for the Instapaper Full API.
///
/// Handles OAuth 1.0a request signing and xAuth token acquisition. Consumer
/// key/secret are compile-time constants by default; tests may inject a config.
/// Access tokens are acquired via [authenticate] and must be set via
/// [setTokens] on subsequent app launches.
class InstapaperClient {
  /// Creates an [InstapaperClient] with optional test dependencies.
  InstapaperClient({
    http.Client? httpClient,
    InstapaperClientConfig config = InstapaperClientConfig.fromEnvironment,
  }) : _http = httpClient ?? http.Client(),
       _config = config;

  final http.Client _http;
  final InstapaperClientConfig _config;

  static const _baseUrl = 'https://www.instapaper.com';

  String? _token;
  String? _tokenSecret;

  /// Whether this client has valid OAuth tokens in memory.
  bool get isAuthenticated => _token != null && _tokenSecret != null;

  /// Whether the required consumer key and secret are configured.
  bool get isConfigured => _config.isConfigured;

  /// Debug-safe consumer configuration status.
  String get configurationDiagnostics => _config.diagnostics;

  /// Set previously stored tokens, for example from secure storage on app start.
  void setTokens({required String token, required String tokenSecret}) {
    _token = token;
    _tokenSecret = tokenSecret;
  }

  /// Clear in-memory tokens.
  void clearTokens() {
    _token = null;
    _tokenSecret = null;
  }

  /// Authenticate via Instapaper's documented xAuth compatibility flow.
  ///
  /// Sends username/password only to `/api/1/oauth/access_token`.
  /// Returns the token pair on success. The password is not retained.
  Future<InstapaperTokenPair> authenticate({
    required String username,
    required String password,
  }) async {
    _ensureConfigured();

    final params = {
      'x_auth_username': username,
      'x_auth_password': password,
      'x_auth_mode': 'client_auth',
    };

    // xAuth uses consumer credentials only; never include stale user tokens.
    _token = null;
    _tokenSecret = null;

    final response = await _signedPost(
      '/api/1/oauth/access_token',
      body: params,
    );

    if (response.statusCode != 200) {
      throw InstapaperAuthException(
        kind: _authKindForStatus(response.statusCode),
        statusCode: response.statusCode,
        message: 'xAuth token exchange failed with HTTP ${response.statusCode}',
      );
    }

    final tokenPair = parseOAuthTokenResponse(response.body);
    _token = tokenPair.token;
    _tokenSecret = tokenPair.tokenSecret;

    return tokenPair;
  }

  /// Parse the form-encoded OAuth token response documented by Instapaper.
  static InstapaperTokenPair parseOAuthTokenResponse(String body) {
    try {
      final parsed = Uri.splitQueryString(body.trim());
      final token = parsed['oauth_token'];
      final secret = parsed['oauth_token_secret'];

      if (token == null ||
          token.trim().isEmpty ||
          secret == null ||
          secret.trim().isEmpty) {
        throw const FormatException('Missing OAuth token fields');
      }

      return InstapaperTokenPair(token: token, tokenSecret: secret);
    } on FormatException catch (e) {
      throw InstapaperAuthException(
        kind: InstapaperFailureKind.unexpectedResponse,
        statusCode: 200,
        message: 'Unexpected OAuth token response: ${e.message}',
      );
    }
  }

  /// Fetch saved bookmarks from Instapaper.
  ///
  /// [limit] controls page size (1-500, default 25). [folderId] filters by
  /// folder: `unread` (default), `starred`, `archive`, or a numeric folder ID.
  Future<List<InstapaperBookmark>> getBookmarks({
    int limit = 25,
    String folderId = 'unread',
  }) async {
    final response = await _signedPost(
      '/api/1/bookmarks/list',
      body: {'limit': limit.clamp(1, 500).toString(), 'folder_id': folderId},
    );

    if (response.statusCode != 200) {
      throw _parseError(response) ??
          _httpApiException(response.statusCode, 'Failed to fetch bookmarks');
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, Object?>>()
            .where((b) => b['type'] == 'bookmark')
            .map(InstapaperBookmark.fromJson)
            .toList();
      }
      if (decoded is Map<String, Object?>) {
        final bookmarks = decoded['bookmarks'];
        if (bookmarks is List) {
          return bookmarks
              .whereType<Map<String, Object?>>()
              .map(InstapaperBookmark.fromJson)
              .toList();
        }
      }
    } on FormatException {
      throw _unexpectedApiResponse('Bookmarks response was not valid JSON');
    }
    throw _unexpectedApiResponse('Bookmarks response did not include a list');
  }

  /// Fetch the processed text-view HTML for a bookmark.
  ///
  /// Returns the article's HTML content as a UTF-8 string. The response is raw
  /// `text/html`, not JSON.
  Future<String> getBookmarkText({required int bookmarkId}) async {
    final response = await _signedPost(
      '/api/1/bookmarks/get_text',
      body: {'bookmark_id': bookmarkId.toString()},
    );

    if (response.statusCode == 200) {
      return response.body;
    }

    throw _parseError(response) ??
        _httpApiException(response.statusCode, 'Failed to fetch article text');
  }

  /// Update reading progress for a bookmark.
  ///
  /// [progress] must be in the range 0.0-1.0.
  Future<void> updateReadProgress({
    required int bookmarkId,
    required double progress,
  }) async {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final response = await _signedPost(
      '/api/1/bookmarks/update_read_progress',
      body: {
        'bookmark_id': bookmarkId.toString(),
        'progress': progress.clamp(0.0, 1.0).toStringAsFixed(4),
        'progress_timestamp': timestamp,
      },
    );

    if (response.statusCode != 200) {
      throw _parseError(response) ??
          _httpApiException(
            response.statusCode,
            'Failed to update read progress',
          );
    }
  }

  /// Move a bookmark to the archive folder.
  Future<void> archiveBookmark({required int bookmarkId}) async {
    final response = await _signedPost(
      '/api/1/bookmarks/archive',
      body: {'bookmark_id': bookmarkId.toString()},
    );

    if (response.statusCode != 200) {
      throw _parseError(response) ??
          _httpApiException(response.statusCode, 'Failed to archive bookmark');
    }
  }

  /// Verify current credentials.
  ///
  /// Returns user info if tokens are valid.
  Future<InstapaperUser> verifyCredentials() async {
    final response = await _signedPost('/api/1/account/verify_credentials');

    if (response.statusCode != 200) {
      final error = _parseError(response);
      if (error != null) throw error;
      throw _httpApiException(response.statusCode, 'Verify credentials failed');
    }

    try {
      final list = jsonDecode(response.body) as List<Object?>;
      final user = list.whereType<Map<String, Object?>>().firstWhere(
        (e) => e['type'] == 'user',
      );
      return InstapaperUser.fromJson(user);
    } on Object {
      throw _unexpectedApiResponse('Verify credentials response was invalid');
    }
  }

  Future<http.Response> _signedPost(
    String path, {
    Map<String, String> body = const {},
  }) async {
    _ensureConfigured();
    final url = '$_baseUrl$path';
    final authHeader = _buildAuthHeader('POST', url, body);
    try {
      return await _http.post(
        Uri.parse(url),
        headers: {'Authorization': authHeader},
        body: body,
      );
    } on SocketException {
      throw const InstapaperApiException(
        kind: InstapaperFailureKind.network,
        errorCode: 0,
        message: 'Network request failed',
      );
    } on http.ClientException {
      throw const InstapaperApiException(
        kind: InstapaperFailureKind.network,
        errorCode: 0,
        message: 'Network request failed',
      );
    }
  }

  String _buildAuthHeader(
    String method,
    String url,
    Map<String, String> params,
  ) {
    final oauthParams = <String, String>{
      'oauth_consumer_key': _config.consumerKey,
      'oauth_nonce': _generateNonce(),
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000)
          .toString(),
      'oauth_version': '1.0',
    };
    if (_token != null) {
      oauthParams['oauth_token'] = _token!;
    }

    final allParams = <String, String>{...oauthParams, ...params}
      ..remove('oauth_signature');
    final sortedParams = SplayTreeMap<String, String>.from(allParams);
    final paramString = sortedParams.entries
        .map((e) => '${_percentEncode(e.key)}=${_percentEncode(e.value)}')
        .join('&');

    final baseString =
        '${method.toUpperCase()}&${_percentEncode(url)}&${_percentEncode(paramString)}';
    final signingKey =
        '${_percentEncode(_config.consumerSecret)}&${_percentEncode(_tokenSecret ?? '')}';

    final hmac = Hmac(sha1, utf8.encode(signingKey));
    final signature = base64.encode(
      hmac.convert(utf8.encode(baseString)).bytes,
    );

    oauthParams['oauth_signature'] = signature;

    final headerParts = oauthParams.entries
        .map((e) => '${_percentEncode(e.key)}="${_percentEncode(e.value)}"')
        .join(', ');
    return 'OAuth $headerParts';
  }

  void _ensureConfigured() {
    if (_config.isConfigured) return;
    throw InstapaperAuthException(
      kind: InstapaperFailureKind.missingConfiguration,
      message:
          'Missing Instapaper API consumer configuration: ${_config.diagnostics}',
    );
  }

  String _generateNonce() => base64
      .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
      .replaceAll(RegExp('[^a-zA-Z0-9]'), '');

  String _percentEncode(String value) =>
      Uri.encodeComponent(value).replaceAll('+', '%20');

  InstapaperApiException _unexpectedApiResponse(String message) =>
      InstapaperApiException(
        kind: InstapaperFailureKind.unexpectedResponse,
        errorCode: 503,
        message: message,
      );

  InstapaperApiException _httpApiException(int statusCode, String message) =>
      InstapaperApiException(
        kind: _apiKindForStatus(statusCode),
        errorCode: statusCode,
        message: '$message: HTTP $statusCode',
      );

  InstapaperApiException? _parseError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      final errors = switch (decoded) {
        final List<Object?> list => list.whereType<Map<String, Object?>>(),
        final Map<String, Object?> map => [map],
        _ => const Iterable<Map<String, Object?>>.empty(),
      };
      final first = errors.firstWhere(
        (e) => e['type'] == 'error',
        orElse: () => const <String, Object?>{},
      );
      final code = (first['error_code'] as num?)?.toInt();
      if (code == null) return null;
      return InstapaperApiException(
        kind: _apiKindForCode(code, response.statusCode),
        errorCode: code,
        message: first['message'] as String? ?? 'Instapaper API error',
      );
    } on Object {
      return null;
    }
  }

  static InstapaperFailureKind _authKindForStatus(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return InstapaperFailureKind.invalidCredentials;
    }
    if (statusCode == 429) return InstapaperFailureKind.rateLimited;
    if (statusCode >= 500) return InstapaperFailureKind.serviceUnavailable;
    return InstapaperFailureKind.unknown;
  }

  static InstapaperFailureKind _apiKindForStatus(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return InstapaperFailureKind.unauthorized;
    }
    if (statusCode == 429) return InstapaperFailureKind.rateLimited;
    if (statusCode >= 500) return InstapaperFailureKind.serviceUnavailable;
    return InstapaperFailureKind.unknown;
  }

  static InstapaperFailureKind _apiKindForCode(int code, int statusCode) {
    return switch (code) {
      1040 => InstapaperFailureKind.rateLimited,
      1042 => InstapaperFailureKind.suspended,
      1500 || 1550 => InstapaperFailureKind.serviceUnavailable,
      _ => _apiKindForStatus(statusCode),
    };
  }
}
