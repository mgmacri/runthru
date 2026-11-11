/// Instapaper Full API (v1) client: xAuth sign-in and OAuth 1.0a signed calls.
///
/// Every request is a POST with form-encoded parameters and the OAuth
/// parameters in the `Authorization` header, signed with HMAC-SHA1.
///
/// See: https://www.instapaper.com/developers/v1/full-api
library;

import 'dart:async';
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
  ///
  /// Throws a [FormatException] when the object has no usable `user_id`.
  factory InstapaperUser.fromJson(Map<String, Object?> json) {
    final user = tryFromJson(json);
    if (user == null) throw const FormatException('Missing user_id');
    return user;
  }

  /// Parses a user, or returns null when the object has no usable `user_id`.
  static InstapaperUser? tryFromJson(Map<String, Object?> json) {
    final id = instapaperInt(json['user_id']);
    if (id == null) return null;
    return InstapaperUser(
      userId: id,
      username: instapaperString(json['username']),
    );
  }

  /// The Instapaper user ID. Stable; the username is not.
  final int userId;

  /// The user's email or username. Display only: it can change.
  final String username;
}

/// One response from `bookmarks/list`.
class InstapaperBookmarkPage {
  /// Creates a page of bookmarks.
  const InstapaperBookmarkPage({
    required this.bookmarks,
    this.user,
    this.skipped = 0,
  });

  /// The bookmarks that could be read, in the server's order.
  final List<InstapaperBookmark> bookmarks;

  /// The account the list belongs to, when the response names it.
  final InstapaperUser? user;

  /// How many entries were left out because they could not be read.
  final int skipped;
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

  /// Stored tokens are missing, invalid, or revoked.
  unauthorized,

  /// The app or account hit Instapaper's API rate limit.
  rateLimited,

  /// The application is suspended, or not approved for this account.
  suspended,

  /// Instapaper refused the request because this device's clock is wrong
  /// (signed requests carry a timestamp that must be within five minutes).
  clockSkew,

  /// The feature needs an Instapaper Premium account.
  premiumRequired,

  /// Instapaper could not make a text version of the article.
  textUnavailable,

  /// Instapaper will not hand this application the article text (its
  /// text service needs a parser key, or that key is rejected or used up).
  textAccessDenied,

  /// The bookmark no longer exists on the account.
  bookmarkNotFound,

  /// Instapaper rejected the request's parameters.
  invalidRequest,

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

  /// The Instapaper error code, or the HTTP status code when the response
  /// carried none. Zero when no response arrived at all.
  final int errorCode;

  /// A redacted, human-readable description of the error.
  final String message;

  /// Whether the same request can succeed later with nothing changed on the
  /// reader's side: no connection, a server hiccup, a rate limit.
  bool get isTransient => switch (kind) {
    InstapaperFailureKind.network ||
    InstapaperFailureKind.serviceUnavailable ||
    InstapaperFailureKind.rateLimited ||
    InstapaperFailureKind.unexpectedResponse ||
    InstapaperFailureKind.clockSkew => true,
    _ => false,
  };

  /// Whether this request can never succeed however often it is repeated:
  /// the bookmark is gone, or the parameters are wrong.
  bool get isPermanent =>
      kind == InstapaperFailureKind.bookmarkNotFound ||
      kind == InstapaperFailureKind.invalidRequest;

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
    DateTime Function()? now,
    String Function()? nonce,
    Duration requestTimeout = const Duration(seconds: 20),
    Duration textTimeout = const Duration(seconds: 45),
  }) : _http = httpClient ?? http.Client(),
       _config = config,
       _now = now ?? DateTime.now,
       _nonce = nonce ?? _randomNonce,
       _requestTimeout = requestTimeout,
       _textTimeout = textTimeout;

  final http.Client _http;
  final InstapaperClientConfig _config;
  final DateTime Function() _now;
  final String Function() _nonce;
  final Duration _requestTimeout;
  final Duration _textTimeout;

  static const _baseUrl = 'https://www.instapaper.com';

  /// Instapaper rejects a signed request whose timestamp is more than five
  /// minutes old. A device clock further off than this is corrected from the
  /// server's `Date` header.
  static const Duration _clockSkewTolerance = Duration(seconds: 90);

  /// The most bookmarks one `bookmarks/list` call may return.
  static const int maxListLimit = 500;

  String? _token;
  String? _tokenSecret;

  /// Server time minus device time, learned when a request is refused.
  Duration _clockOffset = Duration.zero;

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
      // The body is never logged or kept: on a refused signature Instapaper
      // echoes the signed parameters, the password among them.
      throw InstapaperAuthException(
        kind: _authKindFor(response),
        statusCode: response.statusCode,
        message: 'xAuth token exchange failed with HTTP ${response.statusCode}',
      );
    }

    final tokenPair = parseOAuthTokenResponse(_text(response));
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
    } on ArgumentError {
      // Uri.splitQueryString throws this on a malformed percent escape.
      throw const InstapaperAuthException(
        kind: InstapaperFailureKind.unexpectedResponse,
        statusCode: 200,
        message: 'Unexpected OAuth token response: malformed encoding',
      );
    }
  }

  /// Fetch saved bookmarks from Instapaper.
  ///
  /// [limit] controls page size (1-500). [folderId] filters by folder:
  /// `unread` (default), `starred`, `archive`, or a numeric folder ID.
  Future<List<InstapaperBookmark>> getBookmarks({
    int limit = maxListLimit,
    String folderId = 'unread',
  }) async =>
      (await fetchBookmarks(limit: limit, folderId: folderId)).bookmarks;

  /// Fetch saved bookmarks together with the account the list belongs to.
  ///
  /// An entry that cannot be read is left out (and counted in
  /// [InstapaperBookmarkPage.skipped]) instead of failing the whole list.
  Future<InstapaperBookmarkPage> fetchBookmarks({
    int limit = maxListLimit,
    String folderId = 'unread',
  }) async {
    final response = await _signedPost(
      '/api/1/bookmarks/list',
      body: {
        'limit': limit.clamp(1, maxListLimit).toString(),
        'folder_id': folderId,
      },
    );

    if (response.statusCode != 200) {
      throw _errorFor(response, 'Failed to fetch bookmarks');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(_text(response));
    } on FormatException {
      throw _unexpectedApiResponse('Bookmarks response was not valid JSON');
    }

    // `/api/1/bookmarks/list` answers with the standard array; the newer
    // shape is an object with the list under `bookmarks`.
    final List<Object?> items;
    InstapaperUser? user;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map<String, Object?> &&
        decoded['bookmarks'] is List) {
      items = decoded['bookmarks']! as List<Object?>;
      final userJson = decoded['user'];
      if (userJson is Map<String, Object?>) {
        user = InstapaperUser.tryFromJson(userJson);
      }
    } else {
      throw _unexpectedApiResponse('Bookmarks response did not include a list');
    }

    final bookmarks = <InstapaperBookmark>[];
    var skipped = 0;
    for (final item in items) {
      if (item is! Map<String, Object?>) continue;
      final type = item['type'];
      if (type == 'user') {
        user = InstapaperUser.tryFromJson(item) ?? user;
        continue;
      }
      if (type != null && type != 'bookmark') continue;
      final bookmark = InstapaperBookmark.tryFromJson(item);
      if (bookmark == null) {
        skipped++;
      } else {
        bookmarks.add(bookmark);
      }
    }
    return InstapaperBookmarkPage(
      bookmarks: bookmarks,
      user: user,
      skipped: skipped,
    );
  }

  /// Fetch the processed text-view HTML for a bookmark.
  ///
  /// Instapaper documents the response as `text/html` encoded as UTF-8, so
  /// the bytes are decoded as UTF-8 whatever the response header says.
  Future<String> getBookmarkText({required int bookmarkId}) async {
    final response = await _signedPost(
      '/api/1/bookmarks/get_text',
      body: {'bookmark_id': bookmarkId.toString()},
      timeout: _textTimeout,
    );

    if (response.statusCode == 200) {
      return _text(response);
    }

    throw _errorFor(response, 'Failed to fetch article text');
  }

  /// Update reading progress for a bookmark.
  ///
  /// [progress] must be in the range 0.0-1.0. [timestampSeconds] is when the
  /// reader was at that position (Unix seconds); Instapaper ignores an update
  /// older than the one it already has, so a position recorded offline must
  /// carry its own time, not the time it was finally sent.
  Future<void> updateReadProgress({
    required int bookmarkId,
    required double progress,
    int? timestampSeconds,
  }) async {
    final recordedAt =
        timestampSeconds ?? (_now().millisecondsSinceEpoch ~/ 1000);
    final response = await _signedPost(
      '/api/1/bookmarks/update_read_progress',
      body: {
        'bookmark_id': bookmarkId.toString(),
        'progress': progress.clamp(0.0, 1.0).toStringAsFixed(4),
        'progress_timestamp': (recordedAt + _clockOffset.inSeconds).toString(),
      },
    );

    if (response.statusCode != 200) {
      throw _errorFor(response, 'Failed to update read progress');
    }
  }

  /// Move a bookmark to the archive folder.
  Future<void> archiveBookmark({required int bookmarkId}) async {
    final response = await _signedPost(
      '/api/1/bookmarks/archive',
      body: {'bookmark_id': bookmarkId.toString()},
    );

    if (response.statusCode != 200) {
      throw _errorFor(response, 'Failed to archive bookmark');
    }
  }

  /// Verify current credentials.
  ///
  /// Returns user info if tokens are valid.
  Future<InstapaperUser> verifyCredentials() async {
    final response = await _signedPost('/api/1/account/verify_credentials');

    if (response.statusCode != 200) {
      throw _errorFor(response, 'Verify credentials failed');
    }

    try {
      final decoded = jsonDecode(_text(response));
      final candidates = switch (decoded) {
        final List<Object?> list => list.whereType<Map<String, Object?>>(),
        final Map<String, Object?> map => [map],
        _ => const Iterable<Map<String, Object?>>.empty(),
      };
      for (final candidate in candidates) {
        if (candidate['type'] != null && candidate['type'] != 'user') continue;
        final user = InstapaperUser.tryFromJson(candidate);
        if (user != null) return user;
      }
    } on FormatException {
      // Falls through to the unexpected-response error below.
    }
    throw _unexpectedApiResponse('Verify credentials response was invalid');
  }

  // ── Signing (RFC 5849) ────────────────────────────────────────────────────

  /// Percent-encodes [value] the way OAuth 1.0a requires (RFC 5849 §3.6):
  /// the UTF-8 bytes of everything except `A–Z a–z 0–9 - . _ ~` become `%XX`.
  ///
  /// `Uri.encodeComponent` is not this: it leaves `! * ' ( )` alone, which
  /// makes the signature wrong for any value that contains one of them (a
  /// password ending in "!" could never sign in).
  static String percentEncode(String value) {
    final out = StringBuffer();
    for (final byte in utf8.encode(value)) {
      final unreserved =
          (byte >= 0x41 && byte <= 0x5A) || // A–Z
          (byte >= 0x61 && byte <= 0x7A) || // a–z
          (byte >= 0x30 && byte <= 0x39) || // 0–9
          byte == 0x2D || // -
          byte == 0x2E || // .
          byte == 0x5F || // _
          byte == 0x7E; // ~
      if (unreserved) {
        out.writeCharCode(byte);
      } else {
        out
          ..write('%')
          ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return out.toString();
  }

  /// The signature base string for a request (RFC 5849 §3.4.1): the method,
  /// the URL and every parameter (OAuth and body alike), each encoded,
  /// with the parameters sorted by encoded name and then value.
  static String signatureBaseString({
    required String method,
    required String url,
    required Map<String, String> params,
  }) {
    final pairs = [
      for (final entry in params.entries)
        if (entry.key != 'oauth_signature')
          (percentEncode(entry.key), percentEncode(entry.value)),
    ];
    pairs.sort((a, b) {
      final byName = a.$1.compareTo(b.$1);
      return byName != 0 ? byName : a.$2.compareTo(b.$2);
    });
    final normalised = pairs.map((p) => '${p.$1}=${p.$2}').join('&');
    return '${method.toUpperCase()}&${percentEncode(url)}&${percentEncode(normalised)}';
  }

  /// The HMAC-SHA1 signature of [baseString], base64 encoded (RFC 5849 §3.4.2).
  static String sign({
    required String baseString,
    required String consumerSecret,
    String tokenSecret = '',
  }) {
    final key =
        '${percentEncode(consumerSecret)}&${percentEncode(tokenSecret)}';
    final hmac = Hmac(sha1, utf8.encode(key));
    return base64.encode(hmac.convert(utf8.encode(baseString)).bytes);
  }

  String _buildAuthHeader(
    String method,
    String url,
    Map<String, String> params,
  ) {
    final timestamp = _now().add(_clockOffset).millisecondsSinceEpoch ~/ 1000;
    final oauthParams = <String, String>{
      'oauth_consumer_key': _config.consumerKey,
      'oauth_nonce': _nonce(),
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp.toString(),
      'oauth_version': '1.0',
    };
    final token = _token;
    if (token != null) oauthParams['oauth_token'] = token;

    oauthParams['oauth_signature'] = sign(
      baseString: signatureBaseString(
        method: method,
        url: url,
        params: {...params, ...oauthParams},
      ),
      consumerSecret: _config.consumerSecret,
      tokenSecret: _tokenSecret ?? '',
    );

    final headerParts = oauthParams.entries
        .map((e) => '${percentEncode(e.key)}="${percentEncode(e.value)}"')
        .join(', ');
    return 'OAuth $headerParts';
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  Future<http.Response> _signedPost(
    String path, {
    Map<String, String> body = const {},
    Duration? timeout,
  }) async {
    _ensureConfigured();
    final uri = Uri.parse('$_baseUrl$path');
    final limit = timeout ?? _requestTimeout;
    var response = await _postOnce(uri, body, limit);
    // Every response teaches the client the server's clock. A request that
    // was refused while the device clock was off is signed again with the
    // server's time: one retry, and the offset then applies to every call.
    final clockChanged = _adoptServerClock(response);
    if (clockChanged &&
        (response.statusCode == 401 || response.statusCode == 403)) {
      response = await _postOnce(uri, body, limit);
    }
    return response;
  }

  Future<http.Response> _postOnce(
    Uri uri,
    Map<String, String> body,
    Duration timeout,
  ) async {
    final authHeader = _buildAuthHeader('POST', uri.toString(), body);
    try {
      return await _http
          .post(uri, headers: {'Authorization': authHeader}, body: body)
          .timeout(timeout);
    } on TimeoutException {
      throw const InstapaperApiException(
        kind: InstapaperFailureKind.network,
        errorCode: 0,
        message: 'Network request timed out',
      );
    } on http.ClientException {
      throw const InstapaperApiException(
        kind: InstapaperFailureKind.network,
        errorCode: 0,
        message: 'Network request failed',
      );
    } on IOException {
      // SocketException, TlsException, HttpException.
      throw const InstapaperApiException(
        kind: InstapaperFailureKind.network,
        errorCode: 0,
        message: 'Network request failed',
      );
    }
  }

  /// Takes the server's clock from a response's `Date` header when it
  /// disagrees with the one in use. Returns whether anything changed, so the
  /// caller knows a retry can do better.
  bool _adoptServerClock(http.Response response) {
    final header = response.headers['date'];
    if (header == null) return false;
    final DateTime serverNow;
    try {
      serverNow = HttpDate.parse(header);
    } on Object {
      return false;
    }
    final skew = serverNow.difference(_now());
    if ((skew - _clockOffset).abs() < _clockSkewTolerance) return false;
    _clockOffset = skew;
    return true;
  }

  void _ensureConfigured() {
    if (_config.isConfigured) return;
    throw InstapaperAuthException(
      kind: InstapaperFailureKind.missingConfiguration,
      message:
          'Missing Instapaper API consumer configuration: ${_config.diagnostics}',
    );
  }

  static String _randomNonce() {
    final random = Random.secure();
    return base64
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll(RegExp('[^a-zA-Z0-9]'), '');
  }

  /// The response body as text. Instapaper's strings are always UTF-8, but
  /// its `text/html` responses do not always say so, and `package:http`
  /// would then read them as Latin-1 (every curly quote and dash garbled).
  static String _text(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  // ── Errors ────────────────────────────────────────────────────────────────

  InstapaperApiException _unexpectedApiResponse(String message) =>
      InstapaperApiException(
        kind: InstapaperFailureKind.unexpectedResponse,
        errorCode: 503,
        message: message,
      );

  /// The failure a non-200 response stands for: Instapaper's own error code
  /// when the body carries one, the HTTP status otherwise.
  InstapaperApiException _errorFor(http.Response response, String what) {
    final body = _text(response);
    final parsed = _parseError(body);
    if (parsed != null) return parsed;
    return InstapaperApiException(
      kind: _kindForStatus(response.statusCode, body),
      errorCode: response.statusCode,
      message: '$what: HTTP ${response.statusCode}',
    );
  }

  InstapaperApiException? _parseError(String body) {
    try {
      final decoded = jsonDecode(body);
      final errors = switch (decoded) {
        final List<Object?> list => list.whereType<Map<String, Object?>>(),
        final Map<String, Object?> map => [map],
        _ => const Iterable<Map<String, Object?>>.empty(),
      };
      for (final error in errors) {
        if (error['type'] != 'error') continue;
        final code = instapaperInt(error['error_code']);
        if (code == null) continue;
        // The API's message is for developers and is not shown to readers.
        return InstapaperApiException(
          kind: _kindForCode(code),
          errorCode: code,
          message: 'Instapaper API error $code',
        );
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// Why xAuth was refused. Wrong credentials are a 401; a 403 is about the
  /// request itself (its timestamp, its signature, or the application).
  static InstapaperFailureKind _authKindFor(http.Response response) {
    final status = response.statusCode;
    if (status == 401) return InstapaperFailureKind.invalidCredentials;
    if (status == 403) {
      final reason = _refusalReason(_text(response));
      return reason == InstapaperFailureKind.unauthorized
          ? InstapaperFailureKind.unknown
          : reason;
    }
    if (status == 429) return InstapaperFailureKind.rateLimited;
    if (status >= 500) return InstapaperFailureKind.serviceUnavailable;
    return InstapaperFailureKind.unknown;
  }

  static InstapaperFailureKind _kindForStatus(int statusCode, String body) {
    if (statusCode == 401) return InstapaperFailureKind.unauthorized;
    if (statusCode == 403) return _refusalReason(body);
    if (statusCode == 429) return InstapaperFailureKind.rateLimited;
    if (statusCode >= 500) return InstapaperFailureKind.serviceUnavailable;
    return InstapaperFailureKind.unknown;
  }

  /// What a 403 means. Instapaper answers a missing or revoked token with an
  /// empty body, and names the problem in the page otherwise. Only the
  /// category is taken from the body; the text itself is never kept.
  static InstapaperFailureKind _refusalReason(String body) {
    final text = body.toLowerCase();
    if (text.contains('timestamp')) return InstapaperFailureKind.clockSkew;
    if (text.contains('signature') || text.contains('nonce')) {
      return InstapaperFailureKind.unexpectedResponse;
    }
    if (text.contains('suspended') || text.contains('not approved')) {
      return InstapaperFailureKind.suspended;
    }
    return InstapaperFailureKind.unauthorized;
  }

  static InstapaperFailureKind _kindForCode(int code) {
    return switch (code) {
      1040 || 1047 => InstapaperFailureKind.rateLimited,
      1041 => InstapaperFailureKind.premiumRequired,
      1042 => InstapaperFailureKind.suspended,
      1044 || 1045 || 1046 => InstapaperFailureKind.textAccessDenied,
      1241 => InstapaperFailureKind.bookmarkNotFound,
      1500 => InstapaperFailureKind.serviceUnavailable,
      1550 => InstapaperFailureKind.textUnavailable,
      >= 1200 && < 1300 => InstapaperFailureKind.invalidRequest,
      _ => InstapaperFailureKind.unknown,
    };
  }
}
