/// Google account auth service for read-only Drive access.
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';

/// Minimal read-only Drive scopes used by RunThru.
const List<String> googleDriveReadOnlyScopes = [
  'https://www.googleapis.com/auth/drive.readonly',
];

const String _driveUserIdKey = 'google_drive_user_id';
const String _driveUserEmailKey = 'google_drive_user_email';
const String _driveUserNameKey = 'google_drive_user_name';
const String _driveAccessTokenKey = 'google_drive_access_token';
const String _driveRefreshTokenKey = 'google_drive_refresh_token';
const String _driveTokenExpiryKey = 'google_drive_token_expiry';

const _authorizationEndpoint =
    'https://accounts.google.com/o/oauth2/v2/auth';
const _tokenEndpoint = 'https://oauth2.googleapis.com/token';

const _appAuth = FlutterAppAuth();

/// Authenticated Google Drive account metadata safe for UI.
class GoogleDriveUser {
  /// Creates a user metadata value.
  const GoogleDriveUser({
    required this.id,
    required this.email,
    this.displayName,
  });

  /// Stable Google account ID.
  final String id;

  /// Account email address.
  final String email;

  /// Account display name, if available.
  final String? displayName;

  /// User-visible account label.
  String get label =>
      displayName?.trim().isNotEmpty == true ? displayName!.trim() : email;
}

/// Secure store abstraction for Google Drive account metadata.
abstract class GoogleDriveTokenStore {
  /// Loads a previously saved user, if present.
  Future<GoogleDriveUser?> readUser();

  /// Persists account metadata in secure storage.
  Future<void> saveUser(GoogleDriveUser user);

  /// Clears saved account metadata.
  Future<void> clear();

  /// Returns the stored OAuth access token if valid (Android PKCE flow).
  Future<String?> readAccessToken() async => null;

  /// Saves an OAuth access token (Android PKCE flow).
  Future<void> saveAccessToken(
    String accessToken, {
    String? refreshToken,
    DateTime? expiry,
  }) async {}
}

/// Flutter secure storage implementation for Drive account metadata.
class SecureGoogleDriveTokenStore implements GoogleDriveTokenStore {
  /// Creates a secure token store.
  const SecureGoogleDriveTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<GoogleDriveUser?> readUser() async {
    final id = await _storage.read(key: _driveUserIdKey);
    final email = await _storage.read(key: _driveUserEmailKey);
    final name = await _storage.read(key: _driveUserNameKey);
    if (id == null || email == null) return null;
    return GoogleDriveUser(id: id, email: email, displayName: name);
  }

  @override
  Future<void> saveUser(GoogleDriveUser user) async {
    await _storage.write(key: _driveUserIdKey, value: user.id);
    await _storage.write(key: _driveUserEmailKey, value: user.email);
    await _storage.write(key: _driveUserNameKey, value: user.displayName);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _driveUserIdKey);
    await _storage.delete(key: _driveUserEmailKey);
    await _storage.delete(key: _driveUserNameKey);
    await _storage.delete(key: _driveAccessTokenKey);
    await _storage.delete(key: _driveRefreshTokenKey);
    await _storage.delete(key: _driveTokenExpiryKey);
  }

  /// Reads the stored access token for Android PKCE flow.
  @override
  Future<String?> readAccessToken() async {
    final expiry = await _storage.read(key: _driveTokenExpiryKey);
    if (expiry != null) {
      final expiryTime = DateTime.tryParse(expiry);
      if (expiryTime != null && DateTime.now().isAfter(expiryTime)) {
        return null; // expired
      }
    }
    return _storage.read(key: _driveAccessTokenKey);
  }

  /// Saves an access token from the Android PKCE flow.
  @override
  Future<void> saveAccessToken(
    String accessToken, {
    String? refreshToken,
    DateTime? expiry,
  }) async {
    await _storage.write(key: _driveAccessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _driveRefreshTokenKey, value: refreshToken);
    }
    if (expiry != null) {
      await _storage.write(
        key: _driveTokenExpiryKey,
        value: expiry.toIso8601String(),
      );
    }
  }
}

/// Handles Google Sign-In initialization, restore, connect, and disconnect.
class GoogleDriveAuthService {
  /// Creates a Google Drive auth service.
  GoogleDriveAuthService({
    GoogleSignIn? signIn,
    GoogleDriveTokenStore tokenStore = const SecureGoogleDriveTokenStore(),
    String? clientId,
    String? serverClientId,
  }) : _signIn = signIn ?? GoogleSignIn.instance,
       _tokenStore = tokenStore,
       _clientId = clientId,
       _serverClientId = serverClientId;

  final GoogleSignIn _signIn;
  final GoogleDriveTokenStore _tokenStore;
  final String? _clientId;
  final String? _serverClientId;

  GoogleSignInAccount? _account;
  bool _initialized = false;

  /// Restores a lightweight Google Sign-In session if available.
  Future<GoogleDriveUser?> restoreSession() async {
    if (Platform.isAndroid) {
      final token = await _tokenStore.readAccessToken();
      if (token == null) {
        await _tokenStore.clear();
        return null;
      }
      return _tokenStore.readUser();
    }
    try {
      await _initialize();
      final restored = await _signIn.attemptLightweightAuthentication();
      if (restored != null) {
        _account = restored;
        final user = _userFromAccount(restored);
        await _tokenStore.saveUser(user);
        return user;
      }
      await _tokenStore.clear();
      return null;
    } on GoogleSignInException catch (e) {
      throw GoogleDriveException(
        kind: _kindForSignInCode(e.code),
        message: 'Google lightweight sign-in failed: ${e.code.name}',
      );
    }
  }

  /// Starts interactive Google Sign-In and asks for Drive read-only access.
  Future<GoogleDriveUser> signIn() async {
    if (Platform.isAndroid) {
      return _signInAndroid();
    }
    await _initialize();
    if (!_signIn.supportsAuthenticate()) {
      throw const GoogleDriveException(
        kind: GoogleDriveFailureKind.auth,
        message: 'Google Sign-In is not available on this platform.',
      );
    }
    try {
      final account = await _signIn.authenticate(
        scopeHint: googleDriveReadOnlyScopes,
      );
      final headers = await account.authorizationClient.authorizationHeaders(
        googleDriveReadOnlyScopes,
        promptIfNecessary: true,
      );
      if (headers == null) {
        throw const GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message: 'Drive read-only access was not granted.',
        );
      }
      _account = account;
      final user = _userFromAccount(account);
      await _tokenStore.saveUser(user);
      return user;
    } on GoogleSignInException catch (e) {
      throw GoogleDriveException(
        kind: _kindForSignInCode(e.code),
        message: 'Google Sign-In failed: ${e.code.name}',
      );
    }
  }

  Future<GoogleDriveUser> _signInAndroid() async {
    final clientId = (_clientId?.isNotEmpty ?? false) ? _clientId! : null;
    if (clientId == null) {
      throw const GoogleDriveException(
        kind: GoogleDriveFailureKind.auth,
        message: 'Google Sign-In client ID is not configured.',
      );
    }
    try {
      final redirectUri = _redirectUriForClientId(clientId);
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: _authorizationEndpoint,
            tokenEndpoint: _tokenEndpoint,
          ),
          scopes: googleDriveReadOnlyScopes,
          promptValues: ['select_account'],
        ),
      );
      final accessToken = result.accessToken;
      if (accessToken == null) {
        throw const GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message: 'Drive read-only access was not granted.',
        );
      }
      await _tokenStore.saveAccessToken(
        accessToken,
        refreshToken: result.refreshToken,
        expiry: result.accessTokenExpirationDateTime,
      );
      final email = _emailFromIdToken(result.idToken) ?? 'unknown@drive';
      final user = GoogleDriveUser(id: email, email: email);
      await _tokenStore.saveUser(user);
      return user;
    } on PlatformException catch (e) {
      final desc = (e.message ?? '').toLowerCase();
      final isCancelled =
          desc.contains('cancel') || desc.contains('user_cancelled');
      appLog('google-drive-auth', 'android pkce error code=${e.code}');
      throw GoogleDriveException(
        kind: isCancelled
            ? GoogleDriveFailureKind.userCancelled
            : GoogleDriveFailureKind.uiUnavailable,
        message: isCancelled
            ? 'Google Sign-In was cancelled.'
            : 'Google Sign-In could not open the sign-in page.',
      );
    } on GoogleDriveException {
      rethrow;
    } on Object {
      appLog('google-drive-auth', 'android pkce unexpected error');
      throw const GoogleDriveException(
        kind: GoogleDriveFailureKind.auth,
        message: 'Google Sign-In failed unexpectedly.',
      );
    }
  }

  /// Revokes the Drive connection and clears local metadata.
  Future<void> signOut() async {
    if (Platform.isAndroid) {
      await _tokenStore.clear();
      return;
    }
    await _initialize();
    try {
      await _signIn.disconnect();
    } on Object {
      await _signIn.signOut();
    } finally {
      _account = null;
      await _tokenStore.clear();
    }
  }

  /// Returns scoped authorization headers for Drive REST calls.
  Future<Map<String, String>> authorizationHeaders() async {
    if (Platform.isAndroid) {
      final token = await _tokenStore.readAccessToken();
      if (token == null) {
        throw const GoogleDriveException(
          kind: GoogleDriveFailureKind.authRequired,
          message: 'Not connected to Google Drive.',
        );
      }
      return {'Authorization': 'Bearer $token'};
    }
    await _initialize();
    var account = _account;
    account ??= await _signIn.attemptLightweightAuthentication();
    if (account == null) {
      throw const GoogleDriveException(
        kind: GoogleDriveFailureKind.authRequired,
        message: 'Not connected to Google Drive.',
      );
    }
    _account = account;
    final headers = await account.authorizationClient.authorizationHeaders(
      googleDriveReadOnlyScopes,
      promptIfNecessary: true,
    );
    if (headers == null) {
      throw const GoogleDriveException(
        kind: GoogleDriveFailureKind.expiredToken,
        message: 'Drive authorization has expired or was revoked.',
      );
    }
    return headers;
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    await _signIn.initialize(
      clientId: _clientId,
      serverClientId: _serverClientId,
    );
    _initialized = true;
  }

  /// Builds the OAuth2 redirect URI for [clientId].
  ///
  /// Google OAuth web clients use a reverse-domain scheme derived from the
  /// client ID: `com.googleusercontent.apps.{id_without_suffix}:/oauth2redirect`.
  static String _redirectUriForClientId(String clientId) {
    const suffix = '.apps.googleusercontent.com';
    final id = clientId.endsWith(suffix)
        ? clientId.substring(0, clientId.length - suffix.length)
        : clientId;
    return 'com.googleusercontent.apps.$id:/oauth2redirect';
  }

  static GoogleDriveUser _userFromAccount(GoogleSignInAccount account) {
    return GoogleDriveUser(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
    );
  }

  static String? _emailFromIdToken(String? idToken) {
    if (idToken == null) return null;
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return null;
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      return json['email'] as String?;
    } on Object {
      return null;
    }
  }

  static GoogleDriveFailureKind _kindForSignInCode(
    GoogleSignInExceptionCode code,
  ) {
    return switch (code) {
      GoogleSignInExceptionCode.canceled =>
        GoogleDriveFailureKind.userCancelled,
      GoogleSignInExceptionCode.interrupted ||
      GoogleSignInExceptionCode.uiUnavailable =>
        GoogleDriveFailureKind.uiUnavailable,
      GoogleSignInExceptionCode.providerConfigurationError =>
        GoogleDriveFailureKind.uiUnavailable,
      GoogleSignInExceptionCode.userMismatch =>
        GoogleDriveFailureKind.expiredToken,
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.unknownError => GoogleDriveFailureKind.auth,
    };
  }
}
