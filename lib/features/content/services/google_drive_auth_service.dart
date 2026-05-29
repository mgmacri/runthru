/// Google account auth service for selected-file and opt-in Drive access.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/store/models.dart';

/// Default Drive scope used for files explicitly chosen by the user.
const List<String> googleDriveFileScopes = [
  'https://www.googleapis.com/auth/drive.file',
];

/// Opt-in Drive scope used only for the full Drive browser.
const List<String> googleDriveReadOnlyScopes = [
  'https://www.googleapis.com/auth/drive.readonly',
];

const String _driveUserIdKey = 'google_drive_user_id';
const String _driveUserEmailKey = 'google_drive_user_email';
const String _driveUserNameKey = 'google_drive_user_name';
const String _legacyDriveAccessTokenKey = 'google_drive_access_token';
const String _legacyDriveRefreshTokenKey = 'google_drive_refresh_token';
const String _legacyDriveTokenExpiryKey = 'google_drive_token_expiry';
const String _googleOAuthClientIdSuffix = '.apps.googleusercontent.com';

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

  /// Clears saved account metadata and any legacy OAuth token values.
  Future<void> clear();
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
    await _storage.delete(key: _legacyDriveAccessTokenKey);
    await _storage.delete(key: _legacyDriveRefreshTokenKey);
    await _storage.delete(key: _legacyDriveTokenExpiryKey);
  }
}

/// Safe account metadata returned by the Drive sign-in adapter.
abstract class GoogleDriveSignedInAccount {
  /// Stable Google account ID.
  String get id;

  /// Account email address.
  String get email;

  /// Account display name, if available.
  String? get displayName;
}

/// Injectable Google Sign-In surface used by [GoogleDriveAuthService].
abstract class GoogleDriveSignInAdapter {
  /// Initializes Google Sign-In before any other operation.
  Future<void> initialize({String? clientId, String? serverClientId});

  /// Whether this platform supports interactive sign-in.
  bool supportsAuthenticate();

  /// Attempts to restore a prior account without prompting.
  Future<GoogleDriveSignedInAccount?> attemptLightweightAuthentication();

  /// Starts an interactive sign-in flow.
  Future<GoogleDriveSignedInAccount?> authenticate({
    List<String> scopeHint = const <String>[],
  });

  /// Returns scoped REST authorization headers for [account].
  Future<Map<String, String>?> authorizationHeaders(
    GoogleDriveSignedInAccount account,
    List<String> scopes, {
    required bool promptIfNecessary,
  });

  /// Signs out the current Google account.
  Future<void> signOut();

  /// Disconnects/revokes the current Google account where supported.
  Future<void> disconnect();
}

/// Production Google Sign-In adapter.
class GoogleSignInDriveAdapter implements GoogleDriveSignInAdapter {
  /// Creates a production Google Sign-In adapter.
  GoogleSignInDriveAdapter([GoogleSignIn? signIn])
    : _signIn = signIn ?? GoogleSignIn.instance;

  final GoogleSignIn _signIn;

  @override
  Future<void> initialize({String? clientId, String? serverClientId}) {
    return _signIn.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
    );
  }

  @override
  bool supportsAuthenticate() => _signIn.supportsAuthenticate();

  @override
  Future<GoogleDriveSignedInAccount?> attemptLightweightAuthentication() async {
    final future = _signIn.attemptLightweightAuthentication();
    final account = future == null ? null : await future;
    return account == null ? null : _GoogleSignInAccountAdapter(account);
  }

  @override
  Future<GoogleDriveSignedInAccount?> authenticate({
    List<String> scopeHint = const <String>[],
  }) async {
    final account = await _signIn.authenticate(scopeHint: scopeHint);
    return _GoogleSignInAccountAdapter(account);
  }

  @override
  Future<Map<String, String>?> authorizationHeaders(
    GoogleDriveSignedInAccount account,
    List<String> scopes, {
    required bool promptIfNecessary,
  }) {
    final googleAccount = (account as _GoogleSignInAccountAdapter)._account;
    return googleAccount.authorizationClient.authorizationHeaders(
      scopes,
      promptIfNecessary: promptIfNecessary,
    );
  }

  @override
  Future<void> signOut() => _signIn.signOut();

  @override
  Future<void> disconnect() => _signIn.disconnect();
}

class _GoogleSignInAccountAdapter implements GoogleDriveSignedInAccount {
  const _GoogleSignInAccountAdapter(this._account);

  final GoogleSignInAccount _account;

  @override
  String get id => _account.id;

  @override
  String get email => _account.email;

  @override
  String? get displayName => _account.displayName;
}

/// Handles Google Sign-In initialization, restore, connect, and disconnect.
class GoogleDriveAuthService {
  /// Creates a Google Drive auth service.
  ///
  /// [iosClientId] is the iOS-type OAuth client registered in Google Cloud
  /// Console. It is used as `clientId` in `GoogleSignIn.initialize()` on iOS.
  ///
  /// [androidServerClientId] is the Web OAuth client ID used as
  /// `serverClientId` on Android. If [androidUsesGoogleServicesJson] is true,
  /// Android initialization may omit [androidServerClientId] and rely on the
  /// web client configuration supplied through `google-services.json`.
  GoogleDriveAuthService({
    GoogleDriveSignInAdapter? signInAdapter,
    GoogleDriveTokenStore tokenStore = const SecureGoogleDriveTokenStore(),
    bool? isAndroid,
    bool? isIOS,
    String? iosClientId,
    String? androidServerClientId,
    bool androidUsesGoogleServicesJson = false,
  }) : _signIn = signInAdapter ?? GoogleSignInDriveAdapter(),
       _tokenStore = tokenStore,
       _isAndroidOverride = isAndroid,
       _isIOSOverride = isIOS,
       _iosClientId = iosClientId,
       _androidServerClientId = androidServerClientId,
       _androidUsesGoogleServicesJson = androidUsesGoogleServicesJson;

  final GoogleDriveSignInAdapter _signIn;
  final GoogleDriveTokenStore _tokenStore;
  final bool? _isAndroidOverride;
  final bool? _isIOSOverride;

  /// iOS-type OAuth client ID (Google Cloud Console client type: iOS).
  final String? _iosClientId;

  /// Web OAuth client ID used as Android serverClientId.
  final String? _androidServerClientId;

  final bool _androidUsesGoogleServicesJson;

  GoogleDriveSignedInAccount? _account;
  bool _initialized = false;
  bool _androidConfigPresenceLogged = false;

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;

  bool get _isIOS => _isIOSOverride ?? Platform.isIOS;

  /// Restores a lightweight Google Sign-In session if available.
  Future<GoogleDriveUser?> restoreSession() async {
    try {
      await _initialize();
      final restored = await _signIn.attemptLightweightAuthentication();
      if (restored == null) {
        _account = null;
        await _tokenStore.clear();
        return null;
      }
      _account = restored;
      final user = _userFromAccount(restored);
      await _tokenStore.saveUser(user);
      return user;
    } on GoogleDriveException catch (e) {
      _logAuthFailure(
        operation: 'drive_auth_restore',
        classification: e.classification,
        exception: e,
        storageAction: e.shouldClearStoredCredentials ? 'cleared' : 'preserved',
      );
      if (e.shouldClearStoredCredentials) {
        await _tokenStore.clear();
      }
      rethrow;
    } on Object catch (e) {
      final failure = _exceptionToDriveException(
        e,
        fallbackKind: GoogleDriveFailureKind.unexpectedResponse,
        fallbackMessage: 'Could not restore Google Drive.',
      );
      _logAuthFailure(
        operation: 'drive_auth_restore',
        classification: failure.classification,
        exception: e,
        storageAction: failure.shouldClearStoredCredentials
            ? 'cleared'
            : 'preserved',
      );
      if (failure.shouldClearStoredCredentials) {
        await _tokenStore.clear();
      }
      throw failure;
    }
  }

  /// Starts interactive Google Sign-In and asks for the selected Drive scope.
  Future<GoogleDriveUser> signIn({
    GoogleDriveAccessMode accessMode = GoogleDriveAccessMode.selectedFilesOnly,
  }) async {
    try {
      await _initialize();
      if (!_signIn.supportsAuthenticate()) {
        throw const GoogleDriveException(
          kind: GoogleDriveFailureKind.uiUnavailable,
          message: 'Google Sign-In is not available on this platform.',
          classification: GoogleDriveFailureClassification.missingConfig,
        );
      }
      final scopes = _scopesForAccessMode(accessMode);
      final account = await _signIn.authenticate(scopeHint: scopes);
      if (account == null) {
        throw const GoogleDriveException(
          kind: GoogleDriveFailureKind.userCancelled,
          message: 'Google Sign-In was cancelled.',
          classification: GoogleDriveFailureClassification.permanent,
        );
      }
      final headers = await _signIn.authorizationHeaders(
        account,
        scopes,
        promptIfNecessary: true,
      );
      if (headers == null) {
        throw GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message: _authorizationDeniedMessage(accessMode),
          classification: GoogleDriveFailureClassification.accessDenied,
        );
      }
      _account = account;
      final user = _userFromAccount(account);
      await _tokenStore.saveUser(user);
      return user;
    } on GoogleDriveException {
      rethrow;
    } on Object catch (e) {
      throw _exceptionToDriveException(
        e,
        fallbackKind: GoogleDriveFailureKind.auth,
        fallbackMessage: 'Google Sign-In failed unexpectedly.',
      );
    }
  }

  /// Revokes the Drive connection and clears local metadata.
  Future<void> signOut() async {
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
  Future<Map<String, String>> authorizationHeaders({
    GoogleDriveAccessMode accessMode = GoogleDriveAccessMode.selectedFilesOnly,
    bool allowInteractivePrompt = false,
  }) async {
    try {
      await _initialize();
      var account = _account;
      account ??= await _signIn.attemptLightweightAuthentication();
      if (account == null) {
        throw const GoogleDriveException(
          kind: GoogleDriveFailureKind.authRequired,
          message: 'Not connected to Google Drive.',
          classification: GoogleDriveFailureClassification.permanent,
          shouldClearStoredCredentials: true,
        );
      }
      _account = account;
      final scopes = _scopesForAccessMode(accessMode);
      final silentHeaders = await _signIn.authorizationHeaders(
        account,
        scopes,
        promptIfNecessary: false,
      );
      if (silentHeaders != null) return silentHeaders;

      if (!allowInteractivePrompt) {
        throw GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message: _authorizationDeniedMessage(accessMode),
          classification: GoogleDriveFailureClassification.insufficientScope,
        );
      }

      final headers = await _signIn.authorizationHeaders(
        account,
        scopes,
        promptIfNecessary: true,
      );
      if (headers == null) {
        throw GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message: _authorizationDeniedMessage(accessMode),
          classification: GoogleDriveFailureClassification.accessDenied,
        );
      }
      return headers;
    } on GoogleDriveException catch (e) {
      _logAuthFailure(
        operation: 'drive_auth_headers',
        classification: e.classification,
        exception: e,
        storageAction: e.shouldClearStoredCredentials ? 'cleared' : 'preserved',
      );
      if (e.shouldClearStoredCredentials) {
        await _tokenStore.clear();
      }
      rethrow;
    } on Object catch (e) {
      final failure = _exceptionToDriveException(
        e,
        fallbackKind: GoogleDriveFailureKind.auth,
        fallbackMessage: 'Could not authorize Google Drive.',
      );
      _logAuthFailure(
        operation: 'drive_auth_headers',
        classification: failure.classification,
        exception: e,
        storageAction: failure.shouldClearStoredCredentials
            ? 'cleared'
            : 'preserved',
      );
      if (failure.shouldClearStoredCredentials) {
        await _tokenStore.clear();
      }
      throw failure;
    }
  }

  Future<void> _initialize() async {
    if (_initialized) return;

    final androidServerClientId = _androidServerClientId?.trim();
    if (_isAndroid) {
      _logAndroidConfigPresenceOnce(androidServerClientId);
      final validationError = validateAndroidServerClientId(
        androidServerClientId,
        allowGoogleServicesJson: _androidUsesGoogleServicesJson,
      );
      if (validationError != null) {
        appLog(
          'google-drive-auth',
          'operation=drive_auth_initialize platform=android '
              'event=oauth_config_invalid '
              'reason=${_androidServerClientIdValidationReason(androidServerClientId)} '
              'classification=${validationError.classification.name}',
        );
        throw validationError;
      }
    }

    await _signIn.initialize(
      clientId: _isIOS ? _emptyToNull(_iosClientId) : null,
      serverClientId: _isAndroid ? _emptyToNull(androidServerClientId) : null,
    );
    _initialized = true;
  }

  /// Validates the Web OAuth client ID used as Android `serverClientId`.
  ///
  /// Returns a [GoogleDriveException] classified as [missingConfig] if the
  /// client ID is absent or clearly wrong. Returns null if the ID passes format
  /// checks, or if [allowGoogleServicesJson] permits a missing value.
  static GoogleDriveException? validateAndroidServerClientId(
    String? clientId, {
    bool allowGoogleServicesJson = false,
  }) {
    final value = clientId?.trim();
    if (value == null || value.isEmpty) {
      if (allowGoogleServicesJson) return null;
      return const GoogleDriveException(
        kind: GoogleDriveFailureKind.auth,
        message: 'Google web client ID is not configured.',
        classification: GoogleDriveFailureClassification.missingConfig,
      );
    }

    final normalizedLiteral = value.toUpperCase();
    const literalPlaceholders = {
      'GOOGLE_WEB_CLIENT_ID',
      'YOUR_WEB_CLIENT_ID',
      'YOUR_ANDROID_CLIENT_ID',
      'GOOGLE_IOS_CLIENT_ID',
      'YOUR_IOS_CLIENT_ID',
    };
    if (literalPlaceholders.contains(normalizedLiteral)) {
      return const GoogleDriveException(
        kind: GoogleDriveFailureKind.auth,
        message:
            'Google web client ID is misconfigured. Provide the Web OAuth client ID from Google Cloud Console.',
        classification: GoogleDriveFailureClassification.missingConfig,
      );
    }

    if (!value.endsWith(_googleOAuthClientIdSuffix)) {
      return const GoogleDriveException(
        kind: GoogleDriveFailureKind.auth,
        message:
            'Google web client ID is malformed. Expected a Google OAuth client ID ending in .apps.googleusercontent.com.',
        classification: GoogleDriveFailureClassification.missingConfig,
      );
    }

    final prefix = value.substring(
      0,
      value.length - _googleOAuthClientIdSuffix.length,
    );
    final lowerPrefix = prefix.toLowerCase();
    if (prefix.isEmpty ||
        _containsAny(prefix, const [' ', '/', ':', '_']) ||
        _containsAny(lowerPrefix, const [
          'your_',
          'placeholder',
          'replace',
          'dummy',
          'example',
          'google_web_client_id',
          'google_ios_client_id',
          'your-web',
          'your_web',
          'web-client',
          'web_client',
        ])) {
      return const GoogleDriveException(
        kind: GoogleDriveFailureKind.auth,
        message:
            'Google web client ID is misconfigured. Provide the Web OAuth client ID from Google Cloud Console.',
        classification: GoogleDriveFailureClassification.missingConfig,
      );
    }

    return null;
  }

  static GoogleDriveUser _userFromAccount(GoogleDriveSignedInAccount account) {
    return GoogleDriveUser(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
    );
  }

  static List<String> _scopesForAccessMode(GoogleDriveAccessMode accessMode) {
    return switch (accessMode) {
      GoogleDriveAccessMode.selectedFilesOnly => googleDriveFileScopes,
      GoogleDriveAccessMode.fullDriveBrowser => googleDriveReadOnlyScopes,
    };
  }

  static String _authorizationDeniedMessage(GoogleDriveAccessMode accessMode) {
    return switch (accessMode) {
      GoogleDriveAccessMode.selectedFilesOnly =>
        'Drive selected-file access was not granted.',
      GoogleDriveAccessMode.fullDriveBrowser =>
        'Full Drive browser access was not granted.',
    };
  }

  static GoogleDriveException _exceptionToDriveException(
    Object exception, {
    required GoogleDriveFailureKind fallbackKind,
    required String fallbackMessage,
  }) {
    if (exception is GoogleDriveException) return exception;
    if (exception is GoogleSignInException) {
      final message = _signInExceptionSearchText(exception);
      if (_isAdminPolicySignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message:
              'Your Google Workspace admin may need to allow RunThru before you can use this Drive access mode.',
          classification: GoogleDriveFailureClassification.adminPolicyBlocked,
        );
      }
      if (_isThirdPartyAppBlockedSignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message:
              'Your Google Workspace admin may need to allow RunThru before you can use this Drive access mode.',
          classification: GoogleDriveFailureClassification.thirdPartyAppBlocked,
        );
      }
      if (_isRevokedGrantSignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.auth,
          message: 'The saved Google Drive connection is no longer valid.',
          classification: GoogleDriveFailureClassification.permanent,
          shouldClearStoredCredentials: true,
        );
      }
      if (_isAccessDeniedSignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message: 'Drive access was not granted.',
          classification: GoogleDriveFailureClassification.accessDenied,
        );
      }
      return GoogleDriveException(
        kind: _kindForSignInCode(exception.code),
        message: _safeMessageForSignInCode(exception.code),
        classification: _classificationForSignInCode(exception.code),
        shouldClearStoredCredentials:
            exception.code == GoogleSignInExceptionCode.userMismatch,
      );
    }
    if (exception is PlatformException) {
      final message = _platformExceptionSearchText(exception);
      if (_isAdminPolicySignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message:
              'Your Google Workspace admin may need to allow RunThru before you can use this Drive access mode.',
          classification: GoogleDriveFailureClassification.adminPolicyBlocked,
        );
      }
      if (_isThirdPartyAppBlockedSignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message:
              'Your Google Workspace admin may need to allow RunThru before you can use this Drive access mode.',
          classification: GoogleDriveFailureClassification.thirdPartyAppBlocked,
        );
      }
      if (_isRevokedGrantSignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.auth,
          message: 'The saved Google Drive connection is no longer valid.',
          classification: GoogleDriveFailureClassification.permanent,
          shouldClearStoredCredentials: true,
        );
      }
      if (_isAccessDeniedSignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.permission,
          message: 'Drive access was not granted.',
          classification: GoogleDriveFailureClassification.accessDenied,
        );
      }
      if (_isCancellationSignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.userCancelled,
          message: 'Google Sign-In was cancelled.',
          classification: GoogleDriveFailureClassification.permanent,
        );
      }
      if (_isNetworkSignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.network,
          message: 'Network connection failed during Google Sign-In.',
          classification: GoogleDriveFailureClassification.transient,
        );
      }
      if (_isConfigSignal(message)) {
        return const GoogleDriveException(
          kind: GoogleDriveFailureKind.auth,
          message: 'Google Sign-In configuration is invalid.',
          classification: GoogleDriveFailureClassification.missingConfig,
        );
      }
    }
    return GoogleDriveException(
      kind: fallbackKind,
      message: fallbackMessage,
      classification: GoogleDriveFailureClassification.transient,
    );
  }

  static String _signInExceptionSearchText(GoogleSignInException exception) {
    final values = <String>[exception.code.name];
    final description = exception.description;
    if (description != null && description.length <= 2000) {
      values.add(description);
    }
    final details = exception.details;
    if (details is String && details.length <= 2000) {
      values.add(details);
    } else if (details is Map<Object?, Object?>) {
      for (final key in const [
        'error',
        'error_description',
        'code',
        'message',
      ]) {
        final value = details[key];
        if (value is String && value.length <= 1000) values.add(value);
      }
    }
    return values.join(' ').toLowerCase();
  }

  static GoogleDriveFailureKind _kindForSignInCode(
    GoogleSignInExceptionCode code,
  ) {
    return switch (code) {
      GoogleSignInExceptionCode.canceled =>
        GoogleDriveFailureKind.userCancelled,
      GoogleSignInExceptionCode.interrupted ||
      GoogleSignInExceptionCode.uiUnavailable ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        GoogleDriveFailureKind.uiUnavailable,
      GoogleSignInExceptionCode.userMismatch =>
        GoogleDriveFailureKind.expiredToken,
      GoogleSignInExceptionCode.clientConfigurationError =>
        GoogleDriveFailureKind.auth,
      GoogleSignInExceptionCode.unknownError => GoogleDriveFailureKind.auth,
    };
  }

  static GoogleDriveFailureClassification _classificationForSignInCode(
    GoogleSignInExceptionCode code,
  ) {
    return switch (code) {
      GoogleSignInExceptionCode.canceled =>
        GoogleDriveFailureClassification.permanent,
      GoogleSignInExceptionCode.providerConfigurationError ||
      GoogleSignInExceptionCode.clientConfigurationError =>
        GoogleDriveFailureClassification.missingConfig,
      GoogleSignInExceptionCode.userMismatch =>
        GoogleDriveFailureClassification.permanent,
      GoogleSignInExceptionCode.interrupted ||
      GoogleSignInExceptionCode.uiUnavailable ||
      GoogleSignInExceptionCode.unknownError =>
        GoogleDriveFailureClassification.transient,
    };
  }

  static String _safeMessageForSignInCode(GoogleSignInExceptionCode code) {
    return switch (code) {
      GoogleSignInExceptionCode.canceled => 'Google Sign-In was cancelled.',
      GoogleSignInExceptionCode.interrupted =>
        'Google Sign-In did not complete. Try again.',
      GoogleSignInExceptionCode.uiUnavailable ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google Sign-In is not available on this device.',
      GoogleSignInExceptionCode.userMismatch =>
        'The saved Google Drive connection expired. Connect again.',
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Google Sign-In configuration is invalid.',
      GoogleSignInExceptionCode.unknownError =>
        'Google Sign-In failed unexpectedly.',
    };
  }

  static String _platformExceptionSearchText(PlatformException exception) {
    final values = <String>[exception.code];
    final message = exception.message;
    if (message != null) values.add(message);
    final details = exception.details;
    if (details is Map<Object?, Object?>) {
      for (final key in const [
        'error',
        'error_description',
        'code',
        'message',
      ]) {
        final value = details[key];
        if (value is String) values.add(value);
      }
    } else if (details is String && details.length <= 2000) {
      values.add(details);
    }
    return values.join(' ').toLowerCase();
  }

  static String _androidServerClientIdValidationReason(String? clientId) {
    final value = clientId?.trim();
    if (value == null || value.isEmpty) return 'web_client_id_missing';
    final lowerValue = value.toLowerCase();
    if (_containsAny(lowerValue, const [
      'google_web_client_id',
      'google_ios_client_id',
      'your_web',
      'your_android',
      'your_ios',
      'placeholder',
      'dummy',
      'example',
    ])) {
      return 'web_client_id_placeholder';
    }
    if (!value.endsWith(_googleOAuthClientIdSuffix)) {
      return 'web_client_id_malformed';
    }
    return 'web_client_id_invalid';
  }

  static bool _isCancellationSignal(String message) =>
      _containsAny(message, const [
        'cancel',
        'canceled',
        'cancelled',
        'user_canceled',
        'user_cancelled',
        'user cancelled',
        'user canceled',
      ]);

  static bool _isNetworkSignal(String message) => _containsAny(message, const [
    'network',
    'offline',
    'socket',
    'timeout',
    'timed out',
    'dns',
    'host',
    'service_unavailable',
    'temporarily_unavailable',
  ]);

  static bool _isConfigSignal(String message) => _containsAny(message, const [
    'invalid_client',
    'invalid client',
    'unauthorized_client',
    'configuration',
    'developer_error',
    'sign_in_failed',
  ]);

  // Provider/platform auth errors do not expose a stable structured taxonomy
  // for every Workspace policy block. These matchers are best-effort
  // heuristics over bounded provider text; wording may change, unknown text
  // must fall back to a generic safe auth error, and raw exception text must
  // not be shown to users because it can contain OAuth payload details.
  static bool _isAdminPolicySignal(String message) =>
      _containsAny(message, const [
        'admin_policy_enforced',
        'admin policy',
        'domain policy',
        'blocked by admin',
        'blocked by your administrator',
        'administrator has blocked',
      ]);

  static bool _isThirdPartyAppBlockedSignal(String message) =>
      _containsAny(message, const [
        'third-party app',
        'third party app',
        'app access blocked',
        'access to this app is blocked',
      ]);

  static bool _isAccessDeniedSignal(String message) =>
      _containsAny(message, const [
        'access_denied',
        'access denied',
        'permission denied',
        'not granted',
      ]);

  static bool _isRevokedGrantSignal(String message) =>
      _containsAny(message, const [
        'invalid_grant',
        'token has been expired or revoked',
        'grant was revoked',
        'revoked grant',
      ]);

  static bool _containsAny(String value, Iterable<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) return true;
    }
    return false;
  }

  void _logAndroidConfigPresenceOnce(String? serverClientId) {
    if (_androidConfigPresenceLogged) return;
    _androidConfigPresenceLogged = true;
    appLog(
      'google-drive-auth',
      'config GOOGLE_WEB_CLIENT_ID=${serverClientId?.trim().isNotEmpty == true ? 'present' : 'missing'} '
          'googleServicesJson=${_androidUsesGoogleServicesJson ? 'selected' : 'notSelected'}',
    );
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static void _logAuthFailure({
    required String operation,
    required GoogleDriveFailureClassification classification,
    required Object exception,
    required String storageAction,
  }) {
    final platformCode = exception is PlatformException
        ? ' platformCode=${exception.code}'
        : '';
    final signInCode = exception is GoogleSignInException
        ? ' signInCode=${exception.code.name}'
        : '';
    appLog(
      'google-drive-auth',
      'operation=$operation kind=${exception is GoogleDriveException ? exception.kind.name : 'unexpectedResponse'} '
          'classification=${classification.name} '
          'storage=$storageAction '
          'exceptionType=${exception.runtimeType}'
          '$platformCode$signInCode',
    );
  }
}
