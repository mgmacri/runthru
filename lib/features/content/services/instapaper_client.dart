/// Instapaper Full API client with OAuth 1.0a xAuth authentication.
///
/// Uses HMAC-SHA1 request signing per the Instapaper Full API specification.
/// All requests are POST with OAuth params in the Authorization header.
///
/// See: https://www.instapaper.com/api/full
library;

import 'dart:collection';
import 'dart:convert';
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
    userId: json['user_id'] as int,
    username: json['username'] as String,
  );

  /// The Instapaper user ID.
  final int userId;

  /// The user's email or username.
  final String username;
}

/// Authentication failure (invalid credentials, rate limit).
class InstapaperAuthException implements Exception {
  /// Creates an auth exception with the given [statusCode] and [message].
  const InstapaperAuthException({
    required this.statusCode,
    required this.message,
  });

  /// The HTTP status code returned by the API.
  final int statusCode;

  /// A human-readable description of the error.
  final String message;

  @override
  String toString() => 'InstapaperAuthException($statusCode): $message';
}

/// API call failure (non-auth errors).
class InstapaperApiException implements Exception {
  /// Creates an API exception with the given [errorCode] and [message].
  const InstapaperApiException({
    required this.errorCode,
    required this.message,
  });

  /// The Instapaper error code (e.g. 1040 for rate limit).
  final int errorCode;

  /// A human-readable description of the error.
  final String message;

  @override
  String toString() => 'InstapaperApiException($errorCode): $message';
}

/// HTTP client for the Instapaper Full API.
///
/// Handles OAuth 1.0a request signing and xAuth token acquisition.
/// Consumer key/secret are compile-time constants; access tokens are
/// acquired via [authenticate] and must be set via [setTokens] on
/// subsequent app launches.
class InstapaperClient {
  /// Creates an [InstapaperClient] with an optional [httpClient] for testing.
  InstapaperClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  // Consumer credentials — set from environment or const.
  // DO NOT hardcode real keys. Use --dart-define or a config file.
  static const _consumerKey = String.fromEnvironment('INSTAPAPER_CONSUMER_KEY');
  static const _consumerSecret = String.fromEnvironment(
    'INSTAPAPER_CONSUMER_SECRET',
  );

  static const _baseUrl = 'https://www.instapaper.com';

  String? _token;
  String? _tokenSecret;

  /// Whether this client has valid OAuth tokens.
  bool get isAuthenticated => _token != null && _tokenSecret != null;

  /// Set previously stored tokens (e.g. from secure storage on app start).
  void setTokens({required String token, required String tokenSecret}) {
    _token = token;
    _tokenSecret = tokenSecret;
  }

  /// Clear stored tokens (logout).
  void clearTokens() {
    _token = null;
    _tokenSecret = null;
  }

  /// Authenticate via xAuth.
  ///
  /// Sends username/password to `/api/1/oauth/access_token`.
  /// Returns the token pair on success.
  /// Throws [InstapaperAuthException] on failure.
  Future<InstapaperTokenPair> authenticate({
    required String username,
    required String password,
  }) async {
    final params = {
      'x_auth_username': username,
      'x_auth_password': password,
      'x_auth_mode': 'client_auth',
    };

    // xAuth uses consumer credentials only (no token yet)
    _token = null;
    _tokenSecret = null;

    final response = await _signedPost(
      '/api/1/oauth/access_token',
      body: params,
    );

    if (response.statusCode != 200) {
      throw InstapaperAuthException(
        statusCode: response.statusCode,
        message: 'Authentication failed: HTTP ${response.statusCode}',
      );
    }

    // Response is form-encoded: oauth_token=xxx&oauth_token_secret=yyy
    final parsed = Uri.splitQueryString(response.body);
    final token = parsed['oauth_token'];
    final secret = parsed['oauth_token_secret'];

    if (token == null || secret == null) {
      throw InstapaperAuthException(
        statusCode: response.statusCode,
        message: 'Invalid token response',
      );
    }

    _token = token;
    _tokenSecret = secret;

    return InstapaperTokenPair(token: token, tokenSecret: secret);
  }

  /// Fetch saved bookmarks from Instapaper.
  ///
  /// [limit] controls page size (1–500, default 25).
  /// [folderId] filters by folder: 'unread' (default), 'starred', 'archive',
  /// or a numeric folder ID.
  ///
  /// Throws [InstapaperApiException] on failure.
  Future<List<InstapaperBookmark>> getBookmarks({
    int limit = 25,
    String folderId = 'unread',
  }) async {
    final response = await _signedPost(
      '/api/1/bookmarks/list',
      body: {'limit': limit.clamp(1, 500).toString(), 'folder_id': folderId},
    );

    if (response.statusCode != 200) {
      final error = _parseError(response);
      throw error ??
          InstapaperApiException(
            errorCode: response.statusCode,
            message: 'Failed to fetch bookmarks: HTTP ${response.statusCode}',
          );
    }

    // Response is a JSON array with user, bookmark, and meta objects.
    final list = jsonDecode(response.body) as List<Object?>;

    return list
        .cast<Map<String, Object?>>()
        .where((b) => b['type'] == 'bookmark')
        .map(InstapaperBookmark.fromJson)
        .toList();
  }

  /// Fetch the processed text-view HTML for a bookmark.
  ///
  /// Returns the article's HTML content as a UTF-8 string.
  /// The response is raw `text/html`, not the standard JSON format.
  ///
  /// Throws [InstapaperApiException] with error code 1041 if the
  /// bookmark requires an Instapaper Premium subscription.
  /// Throws [InstapaperApiException] with error code 1550 if the
  /// service cannot generate text for this URL.
  Future<String> getBookmarkText({required int bookmarkId}) async {
    final response = await _signedPost(
      '/api/1/bookmarks/get_text',
      body: {'bookmark_id': bookmarkId.toString()},
    );

    if (response.statusCode == 200) {
      return response.body;
    }

    // Error responses are standard JSON format
    final error = _parseError(response);
    throw error ??
        InstapaperApiException(
          errorCode: response.statusCode,
          message: 'Failed to fetch article text: HTTP ${response.statusCode}',
        );
  }

  /// Verify current credentials.
  ///
  /// Returns user info if tokens are valid.
  /// Throws [InstapaperApiException] on failure.
  Future<InstapaperUser> verifyCredentials() async {
    final response = await _signedPost('/api/1/account/verify_credentials');

    if (response.statusCode != 200) {
      final error = _parseError(response);
      if (error != null) throw error;
      throw InstapaperApiException(
        errorCode: response.statusCode,
        message: 'Verify credentials failed: HTTP ${response.statusCode}',
      );
    }

    final list = jsonDecode(response.body) as List<Object?>;
    final user =
        list.firstWhere((e) => (e as Map<String, Object?>)['type'] == 'user')
            as Map<String, Object?>;

    return InstapaperUser.fromJson(user);
  }

  // ---------------------------------------------------------------------------
  // Private: OAuth signing
  // ---------------------------------------------------------------------------

  /// Make a signed POST request to the Instapaper API.
  Future<http.Response> _signedPost(
    String path, {
    Map<String, String> body = const {},
  }) async {
    final url = '$_baseUrl$path';
    final authHeader = _buildAuthHeader('POST', url, body);
    final response = await _http.post(
      Uri.parse(url),
      headers: {'Authorization': authHeader},
      body: body,
    );
    return response;
  }

  /// Build OAuth Authorization header value.
  String _buildAuthHeader(
    String method,
    String url,
    Map<String, String> params,
  ) {
    final oauthParams = <String, String>{
      'oauth_consumer_key': _consumerKey,
      'oauth_nonce': _generateNonce(),
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000)
          .toString(),
      'oauth_version': '1.0',
    };
    if (_token != null) {
      oauthParams['oauth_token'] = _token!;
    }

    // Combine all params for signature base
    final allParams = <String, String>{...oauthParams, ...params}
      ..remove('oauth_signature');
    final sortedParams = SplayTreeMap<String, String>.from(allParams);
    final paramString = sortedParams.entries
        .map((e) => '${_percentEncode(e.key)}=${_percentEncode(e.value)}')
        .join('&');

    final baseString =
        '${method.toUpperCase()}&${_percentEncode(url)}&${_percentEncode(paramString)}';
    final signingKey =
        '${_percentEncode(_consumerSecret)}&${_percentEncode(_tokenSecret ?? '')}';

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

  String _generateNonce() => base64
      .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
      .replaceAll(RegExp('[^a-zA-Z0-9]'), '');

  String _percentEncode(String value) =>
      Uri.encodeComponent(value).replaceAll('+', '%20');

  /// Parse Instapaper API error response.
  ///
  /// API errors are JSON arrays:
  /// `[{"type":"error","error_code":1040,"message":"..."}]`
  InstapaperApiException? _parseError(http.Response response) {
    try {
      final list = jsonDecode(response.body) as List<Object?>;
      final error = list.cast<Map<String, Object?>>().where(
        (e) => e['type'] == 'error',
      );
      if (error.isNotEmpty) {
        final first = error.first;
        return InstapaperApiException(
          errorCode: first['error_code'] as int,
          message: first['message'] as String,
        );
      }
    } on Object catch (_) {
      // Response body is not valid JSON — fall through.
    }
    return null;
  }
}
