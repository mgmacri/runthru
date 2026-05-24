/// Auth service boundary for Instapaper token exchange and persistence.
///
/// This layer keeps credential capture separate from OAuth signing, secure
/// storage, and API calls. User passwords are accepted only as method
/// parameters and are never retained or written to storage.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';

/// Storage key for the Instapaper OAuth token.
const String instapaperOAuthTokenKey = 'instapaper_oauth_token';

/// Storage key for the Instapaper OAuth token secret.
const String instapaperOAuthTokenSecretKey = 'instapaper_oauth_token_secret';

/// Minimal secure token-store abstraction for Instapaper OAuth credentials.
abstract interface class InstapaperTokenStore {
  /// Loads the stored OAuth token pair, or null if none is stored.
  Future<InstapaperTokenPair?> loadTokens();

  /// Saves the OAuth token pair.
  Future<void> saveTokens(InstapaperTokenPair tokens);

  /// Deletes the OAuth token pair.
  Future<void> deleteTokens();
}

/// Secure token storage backed by `flutter_secure_storage`.
class SecureInstapaperTokenStore implements InstapaperTokenStore {
  /// Creates a secure token store.
  const SecureInstapaperTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<InstapaperTokenPair?> loadTokens() async {
    try {
      final token = await _storage.read(key: instapaperOAuthTokenKey);
      final secret = await _storage.read(key: instapaperOAuthTokenSecretKey);
      if (token == null || secret == null) return null;
      if (token.isEmpty || secret.isEmpty) return null;
      return InstapaperTokenPair(token: token, tokenSecret: secret);
    } on Object catch (e) {
      throw InstapaperSecureStorageException(
        'Could not load Instapaper tokens: ${InstapaperRedactor.redact('$e')}',
      );
    }
  }

  @override
  Future<void> saveTokens(InstapaperTokenPair tokens) async {
    try {
      await _storage.write(key: instapaperOAuthTokenKey, value: tokens.token);
      await _storage.write(
        key: instapaperOAuthTokenSecretKey,
        value: tokens.tokenSecret,
      );
    } on Object catch (e) {
      throw InstapaperSecureStorageException(
        'Could not save Instapaper tokens: ${InstapaperRedactor.redact('$e')}',
      );
    }
  }

  @override
  Future<void> deleteTokens() async {
    try {
      await _storage.delete(key: instapaperOAuthTokenKey);
      await _storage.delete(key: instapaperOAuthTokenSecretKey);
    } on Object catch (e) {
      throw InstapaperSecureStorageException(
        'Could not delete Instapaper tokens: ${InstapaperRedactor.redact('$e')}',
      );
    }
  }
}

/// Secure storage failure while loading, saving, or deleting tokens.
class InstapaperSecureStorageException implements Exception {
  /// Creates a secure storage exception.
  const InstapaperSecureStorageException(this.message);

  /// Redacted diagnostic message.
  final String message;

  @override
  String toString() =>
      'InstapaperSecureStorageException(kind: ${InstapaperFailureKind.secureStorage.name}, message: $message)';
}

/// Auth service for Instapaper token lifecycle operations.
class InstapaperAuthService {
  /// Creates an auth service.
  const InstapaperAuthService({
    required InstapaperClient client,
    required InstapaperTokenStore tokenStore,
    Future<InstapaperUser> Function()? officialSignIn,
  }) : _client = client,
       _tokenStore = tokenStore,
       _officialSignIn = officialSignIn;

  final InstapaperClient _client;
  final InstapaperTokenStore _tokenStore;
  final Future<InstapaperUser> Function()? _officialSignIn;

  /// The configured Instapaper API client.
  InstapaperClient get client => _client;

  /// Debug-safe setup diagnostic that reports presence but not values.
  String get configurationDiagnostics => _client.configurationDiagnostics;

  /// Whether this platform/build has an Instapaper browser/app auth flow.
  ///
  /// Instapaper's public Full API integration in this app currently exposes
  /// xAuth only, so official browser auth is unavailable unless a future
  /// adapter is provided.
  bool get supportsOfficialSignIn => _officialSignIn != null;

  /// Restore stored OAuth tokens and verify them with Instapaper.
  Future<InstapaperUser?> restoreSession() async {
    final tokens = await _tokenStore.loadTokens();
    if (tokens == null) {
      _client.clearTokens();
      return null;
    }

    _client.setTokens(token: tokens.token, tokenSecret: tokens.tokenSecret);
    try {
      return await _client.verifyCredentials();
    } on InstapaperApiException catch (e) {
      appLog(
        'instapaper-auth',
        'stored token verification failed category=${_categoryFor(e)}',
      );
      if (e.kind == InstapaperFailureKind.unauthorized) {
        _client.clearTokens();
        await _tokenStore.deleteTokens();
        return null;
      }
      rethrow;
    } on InstapaperAuthException catch (e) {
      appLog(
        'instapaper-auth',
        'stored token verification skipped category=${_categoryFor(e)}',
      );
      rethrow;
    }
  }

  /// Attempts the preferred browser/app sign-in flow.
  Future<InstapaperUser> connectWithOfficialSignIn() async {
    final officialSignIn = _officialSignIn;
    if (officialSignIn != null) return officialSignIn();
    throw const InstapaperAuthException(
      kind: InstapaperFailureKind.officialAuthUnavailable,
      message: 'Instapaper browser sign-in is not available.',
    );
  }

  /// Exchange transient legacy API credentials for OAuth tokens and save them.
  Future<InstapaperUser> connectWithLegacyCredentials({
    required String username,
    required String password,
  }) async {
    final tokens = await _client.authenticate(
      username: username,
      password: password,
    );
    final user = await _client.verifyCredentials();
    await _tokenStore.saveTokens(tokens);
    appLog('instapaper-auth', 'connected userId=${user.userId}');
    return user;
  }

  /// Clear local Instapaper tokens.
  Future<void> logout() async {
    _client.clearTokens();
    await _tokenStore.deleteTokens();
    appLog('instapaper-auth', 'local tokens cleared');
  }

  String _categoryFor(Object error) {
    if (error is InstapaperAuthException) return error.kind.name;
    if (error is InstapaperApiException) return error.kind.name;
    if (error is InstapaperSecureStorageException) {
      return InstapaperFailureKind.secureStorage.name;
    }
    return InstapaperFailureKind.unknown.name;
  }
}
