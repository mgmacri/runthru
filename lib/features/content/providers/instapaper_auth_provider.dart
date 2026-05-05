/// Riverpod provider managing Instapaper authentication lifecycle.
///
/// Handles login via xAuth, logout, and session restoration from
/// secure storage. Tokens are persisted in flutter_secure_storage
/// (iOS Keychain / Android EncryptedSharedPreferences).
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';

part 'instapaper_auth_provider.g.dart';

/// Authentication state for Instapaper integration.
sealed class InstapaperAuthState {
  /// Base constructor for auth state.
  const InstapaperAuthState();
}

/// Not authenticated — show login UI.
class InstapaperAuthUnauthenticated extends InstapaperAuthState {
  /// Creates the unauthenticated state.
  const InstapaperAuthUnauthenticated();
}

/// Authentication in progress.
class InstapaperAuthLoading extends InstapaperAuthState {
  /// Creates the loading state.
  const InstapaperAuthLoading();
}

/// Successfully authenticated.
class InstapaperAuthAuthenticated extends InstapaperAuthState {
  /// Creates the authenticated state with the given [user].
  const InstapaperAuthAuthenticated({required this.user});

  /// The authenticated Instapaper user.
  final InstapaperUser user;
}

/// Authentication failed.
class InstapaperAuthError extends InstapaperAuthState {
  /// Creates the error state with the given [message].
  const InstapaperAuthError({required this.message});

  /// Human-readable error message.
  final String message;
}

/// Manages Instapaper authentication lifecycle.
///
/// Persists OAuth tokens in flutter_secure_storage. On [build], checks
/// for existing tokens and attempts session restoration. Use [login] to
/// authenticate and [logout] to clear tokens.
@Riverpod(keepAlive: true)
class InstapaperAuth extends _$InstapaperAuth {
  static const _tokenKey = 'instapaper_oauth_token';
  static const _tokenSecretKey = 'instapaper_oauth_token_secret';

  late final InstapaperClient _client;
  late final FlutterSecureStorage _storage;

  @override
  InstapaperAuthState build() {
    _client = InstapaperClient();
    _storage = const FlutterSecureStorage();
    // Attempt session restoration asynchronously
    _restoreSession();
    return const InstapaperAuthUnauthenticated();
  }

  /// Restore session from stored tokens.
  Future<void> _restoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    final secret = await _storage.read(key: _tokenSecretKey);
    if (token != null && secret != null) {
      _client.setTokens(token: token, tokenSecret: secret);
      try {
        final user = await _client.verifyCredentials();
        state = InstapaperAuthAuthenticated(user: user);
      } catch (_) {
        // Stored tokens invalid — clear and stay unauthenticated
        await _clearStoredTokens();
        _client.clearTokens();
      }
    }
  }

  /// Authenticate with Instapaper via xAuth.
  ///
  /// [username] is email or username. [password] may be empty (Instapaper
  /// allows passwordless accounts).
  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = const InstapaperAuthLoading();
    try {
      final tokens = await _client.authenticate(
        username: username,
        password: password,
      );

      // Persist tokens securely
      await _storage.write(key: _tokenKey, value: tokens.token);
      await _storage.write(key: _tokenSecretKey, value: tokens.tokenSecret);

      // Verify and get user info
      final user = await _client.verifyCredentials();
      state = InstapaperAuthAuthenticated(user: user);
    } on InstapaperAuthException catch (e) {
      state = InstapaperAuthError(
        message: e.statusCode == 403
            ? 'Invalid email or password'
            : 'Connection error. Please try again.',
      );
    } catch (_) {
      state = const InstapaperAuthError(
        message: 'Connection error. Please try again.',
      );
    }
  }

  /// Log out and clear all stored tokens.
  Future<void> logout() async {
    _client.clearTokens();
    await _clearStoredTokens();
    state = const InstapaperAuthUnauthenticated();
  }

  /// Access the authenticated client for other providers.
  ///
  /// Returns null if not authenticated.
  InstapaperClient? get client => _client.isAuthenticated ? _client : null;

  Future<void> _clearStoredTokens() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _tokenSecretKey);
  }
}
