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

/// Storage key for the connected account's numeric ID.
const String instapaperUserIdKey = 'instapaper_user_id';

/// Storage key for the connected account's username (display only).
const String instapaperUsernameKey = 'instapaper_username';

/// Minimal secure token-store abstraction for Instapaper OAuth credentials.
abstract interface class InstapaperTokenStore {
  /// Loads the stored OAuth token pair, or null if none is stored.
  Future<InstapaperTokenPair?> loadTokens();

  /// Saves the OAuth token pair.
  Future<void> saveTokens(InstapaperTokenPair tokens);

  /// Deletes the OAuth token pair.
  Future<void> deleteTokens();
}

/// Remembers which account the saved tokens belong to.
///
/// Instapaper tokens do not expire, so with the account on hand the app can
/// show the connection at launch without asking Instapaper first (which
/// would fail, and used to look like a broken connection, when offline).
abstract interface class InstapaperAccountStore {
  /// The remembered account, or null if none is stored.
  Future<InstapaperUser?> loadUser();

  /// Remembers [user] as the connected account.
  Future<void> saveUser(InstapaperUser user);

  /// Forgets the connected account.
  Future<void> deleteUser();
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
    final String? token;
    final String? secret;
    try {
      token = await _storage.read(key: instapaperOAuthTokenKey);
      secret = await _storage.read(key: instapaperOAuthTokenSecretKey);
    } on Object catch (e) {
      // Values written under a key this device no longer has (app data
      // restored from a backup onto a new phone) can never be read again.
      // Dropping them lets the reader connect afresh; keeping them would
      // leave the connection in an error nobody can clear.
      appLog('instapaper-auth', 'saved tokens unreadable; discarding them');
      try {
        await deleteTokens();
      } on InstapaperSecureStorageException {
        throw InstapaperSecureStorageException(
          'Could not load Instapaper tokens: ${InstapaperRedactor.redact('$e')}',
        );
      }
      return null;
    }
    if (token == null || secret == null) return null;
    if (token.isEmpty || secret.isEmpty) return null;
    return InstapaperTokenPair(token: token, tokenSecret: secret);
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

/// Account storage backed by `flutter_secure_storage` (the username is
/// usually an email address).
///
/// Never throws: the remembered account is a convenience, and without it
/// the app asks Instapaper who the tokens belong to.
class SecureInstapaperAccountStore implements InstapaperAccountStore {
  /// Creates a secure account store.
  const SecureInstapaperAccountStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<InstapaperUser?> loadUser() async {
    try {
      final id = int.tryParse(
        await _storage.read(key: instapaperUserIdKey) ?? '',
      );
      if (id == null) return null;
      final username = await _storage.read(key: instapaperUsernameKey) ?? '';
      return InstapaperUser(userId: id, username: username);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveUser(InstapaperUser user) async {
    try {
      await _storage.write(key: instapaperUserIdKey, value: '${user.userId}');
      await _storage.write(key: instapaperUsernameKey, value: user.username);
    } on Object {
      appLog('instapaper-auth', 'could not remember the connected account');
    }
  }

  @override
  Future<void> deleteUser() async {
    try {
      await _storage.delete(key: instapaperUserIdKey);
      await _storage.delete(key: instapaperUsernameKey);
    } on Object {
      appLog('instapaper-auth', 'could not forget the connected account');
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
    InstapaperAccountStore? accountStore,
    Future<InstapaperUser> Function()? officialSignIn,
  }) : _client = client,
       _tokenStore = tokenStore,
       _accountStore = accountStore,
       _officialSignIn = officialSignIn;

  final InstapaperClient _client;
  final InstapaperTokenStore _tokenStore;
  final InstapaperAccountStore? _accountStore;
  final Future<InstapaperUser> Function()? _officialSignIn;

  /// The configured Instapaper API client.
  InstapaperClient get client => _client;

  /// Whether this build carries the consumer key and secret Instapaper needs.
  bool get isConfigured => _client.isConfigured;

  /// Debug-safe setup diagnostic that reports presence but not values.
  String get configurationDiagnostics => _client.configurationDiagnostics;

  /// Whether this platform/build has an Instapaper browser/app auth flow.
  ///
  /// Instapaper's public Full API integration in this app currently exposes
  /// xAuth only, so official browser auth is unavailable unless a future
  /// adapter is provided.
  bool get supportsOfficialSignIn => _officialSignIn != null;

  /// Restore the saved connection.
  ///
  /// With the account remembered from an earlier launch this needs no
  /// network: Instapaper tokens do not expire, and a connection revoked in
  /// the meantime shows itself on the first request. Otherwise (an install
  /// from before accounts were remembered) Instapaper is asked once who the
  /// tokens belong to; if it cannot be reached the connection still stands,
  /// under an empty username until the next successful request.
  ///
  /// Returns null when nothing is saved, or when Instapaper says the saved
  /// tokens are no longer valid (they are then deleted).
  Future<InstapaperUser?> restoreSession() async {
    final tokens = await _tokenStore.loadTokens();
    if (tokens == null) {
      _client.clearTokens();
      return null;
    }
    if (!_client.isConfigured) {
      // The tokens stay: a build with the key can use them again.
      throw InstapaperAuthException(
        kind: InstapaperFailureKind.missingConfiguration,
        message:
            'Missing Instapaper API consumer configuration: $configurationDiagnostics',
      );
    }

    _client.setTokens(token: tokens.token, tokenSecret: tokens.tokenSecret);
    final remembered = await _accountStore?.loadUser();
    if (remembered != null) return remembered;

    try {
      final user = await _client.verifyCredentials();
      await _accountStore?.saveUser(user);
      return user;
    } on InstapaperApiException catch (e) {
      appLog(
        'instapaper-auth',
        'stored token verification failed category=${_categoryFor(e)}',
      );
      if (e.kind == InstapaperFailureKind.unauthorized) {
        _client.clearTokens();
        await _tokenStore.deleteTokens();
        await _accountStore?.deleteUser();
        return null;
      }
      if (e.isTransient) return unverifiedUser;
      rethrow;
    } on InstapaperAuthException catch (e) {
      appLog(
        'instapaper-auth',
        'stored token verification skipped category=${_categoryFor(e)}',
      );
      rethrow;
    }
  }

  /// Stands in for the account while Instapaper has not yet been asked who
  /// the saved tokens belong to.
  static const InstapaperUser unverifiedUser = InstapaperUser(
    userId: 0,
    username: '',
  );

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

    InstapaperUser user;
    try {
      user = await _client.verifyCredentials();
    } on InstapaperApiException catch (e) {
      if (!e.isTransient) {
        _client.clearTokens();
        rethrow;
      }
      // Instapaper has just issued the tokens; only the follow-up lookup
      // failed. The reader should not have to type the password again for
      // that. The name they signed in with stands in until a later request
      // returns the account.
      user = InstapaperUser(userId: 0, username: username);
    }

    try {
      await _tokenStore.saveTokens(tokens);
    } on InstapaperSecureStorageException {
      // Not connected unless the connection can be kept.
      _client.clearTokens();
      rethrow;
    }
    if (user.userId != 0) await _accountStore?.saveUser(user);
    appLog('instapaper-auth', 'connected userId=${user.userId}');
    return user;
  }

  /// Remember [user] as the account behind the saved tokens (its username
  /// can change on Instapaper's side).
  Future<void> rememberUser(InstapaperUser user) async {
    if (user.userId == 0) return;
    await _accountStore?.saveUser(user);
  }

  /// Clear local Instapaper tokens.
  Future<void> logout() async {
    _client.clearTokens();
    await _accountStore?.deleteUser();
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
