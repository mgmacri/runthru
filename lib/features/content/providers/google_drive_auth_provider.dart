/// Riverpod auth provider for Google Drive.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

part 'google_drive_auth_provider.g.dart';

/// Authentication state for Google Drive.
sealed class GoogleDriveAuthState {
  /// Base constructor for Google Drive auth states.
  const GoogleDriveAuthState();
}

/// Session restoration is in progress.
class GoogleDriveAuthChecking extends GoogleDriveAuthState {
  /// Creates a checking state.
  const GoogleDriveAuthChecking();
}

/// No Google Drive connection is active.
class GoogleDriveAuthUnauthenticated extends GoogleDriveAuthState {
  /// Creates an unauthenticated state.
  const GoogleDriveAuthUnauthenticated();
}

/// Interactive sign-in is in progress.
class GoogleDriveAuthLoading extends GoogleDriveAuthState {
  /// Creates a loading state.
  const GoogleDriveAuthLoading();
}

/// Google Drive is connected.
class GoogleDriveAuthAuthenticated extends GoogleDriveAuthState {
  /// Creates an authenticated state.
  const GoogleDriveAuthAuthenticated({required this.user});

  /// Connected Google account metadata.
  final GoogleDriveUser user;
}

/// Google Drive auth failed.
class GoogleDriveAuthError extends GoogleDriveAuthState {
  /// Creates an error state.
  const GoogleDriveAuthError({
    required this.message,
    required this.kind,
    this.classification = GoogleDriveFailureClassification.unknown,
  });

  /// User-safe error message.
  final String message;

  /// Diagnostic category safe for logs.
  final GoogleDriveFailureKind kind;

  /// Retry/config classification safe for UI decisions.
  final GoogleDriveFailureClassification classification;
}

/// Google Drive auth service dependency.
final googleDriveAuthServiceProvider = Provider<GoogleDriveAuthService>((ref) {
  const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  const androidServerClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  const androidUsesGoogleServicesJson = bool.fromEnvironment(
    'GOOGLE_ANDROID_USES_GOOGLE_SERVICES_JSON',
  );
  return GoogleDriveAuthService(
    iosClientId: iosClientId.isEmpty ? null : iosClientId,
    androidServerClientId: androidServerClientId.isEmpty
        ? null
        : androidServerClientId,
    androidUsesGoogleServicesJson: androidUsesGoogleServicesJson,
  );
});

/// Manages the Google Drive authentication lifecycle.
@Riverpod(keepAlive: true)
class GoogleDriveAuth extends _$GoogleDriveAuth {
  int _epoch = 0;

  /// Resolves the keep-alive auth service.
  ///
  /// Implemented as a getter rather than a `late final` field so that a
  /// repeated [build] (hot reload re-runs `build` on the existing notifier
  /// instance) cannot trigger a double-initialization
  /// `LateInitializationError`. The service provider is keep-alive, so this
  /// returns the same instance on every read.
  GoogleDriveAuthService get _service =>
      ref.read(googleDriveAuthServiceProvider);

  @override
  GoogleDriveAuthState build() {
    _restoreSession(++_epoch);
    return const GoogleDriveAuthChecking();
  }

  /// Starts interactive Google Drive connection.
  Future<void> connect({GoogleDriveAccessMode? accessMode}) async {
    _epoch++;
    state = const GoogleDriveAuthLoading();
    try {
      final resolvedAccessMode = accessMode ?? await _accessMode();
      final user = await _service.signIn(accessMode: resolvedAccessMode);
      state = GoogleDriveAuthAuthenticated(user: user);
    } on GoogleDriveException catch (e) {
      appLog(
        'google-drive-auth',
        'operation=drive_auth_connect kind=${e.kind.name} '
            'classification=${e.classification.name}',
      );
      state = e.kind == GoogleDriveFailureKind.authRequired
          ? const GoogleDriveAuthUnauthenticated()
          : GoogleDriveAuthError(
              kind: e.kind,
              message: _messageForException(e),
              classification: e.classification,
            );
    } on Object {
      appLog('google-drive-auth', 'connect failed category=unknown');
      state = const GoogleDriveAuthError(
        kind: GoogleDriveFailureKind.unexpectedResponse,
        message: 'Could not connect Google Drive. Try again.',
      );
    }
  }

  /// Starts a user-initiated Drive access grant flow.
  ///
  /// Unlike [connect], this keeps an existing authenticated session visible
  /// while the user grants missing Drive scopes or chooses another account.
  Future<bool> grantDriveAccess() async {
    final previous = state;
    final grantEpoch = ++_epoch;
    appLog('google-drive-auth', 'operation=drive_grant_access result=started');
    try {
      final accessMode = await _accessMode();
      final user = await _service.signIn(accessMode: accessMode);
      if (grantEpoch != _epoch) return false;
      state = GoogleDriveAuthAuthenticated(user: user);
      appLog(
        'google-drive-auth',
        'operation=drive_grant_access result=succeeded',
      );
      return true;
    } on GoogleDriveException catch (e) {
      final result = e.kind == GoogleDriveFailureKind.userCancelled
          ? 'cancelled'
          : 'failed';
      appLog(
        'google-drive-auth',
        'operation=drive_grant_access result=$result kind=${e.kind.name} '
            'classification=${e.classification.name} '
            'exceptionType=${e.runtimeType}',
      );
      if (previous is GoogleDriveAuthChecking && grantEpoch == _epoch) {
        _restoreSession(++_epoch);
      }
      return false;
    } on Object catch (e) {
      appLog(
        'google-drive-auth',
        'operation=drive_grant_access result=failed '
            'exceptionType=${e.runtimeType}',
      );
      if (previous is GoogleDriveAuthChecking && grantEpoch == _epoch) {
        _restoreSession(++_epoch);
      }
      return false;
    }
  }

  /// Disconnects Google Drive and clears local auth metadata.
  Future<void> disconnect() async {
    _epoch++;
    try {
      await _service.signOut();
    } on Object {
      state = const GoogleDriveAuthError(
        kind: GoogleDriveFailureKind.auth,
        message: 'Could not disconnect Google Drive. Try again.',
      );
      return;
    }
    state = const GoogleDriveAuthUnauthenticated();
  }

  /// Returns scoped Drive REST auth headers.
  Future<Map<String, String>> authorizationHeaders({
    GoogleDriveAccessMode? accessMode,
    bool allowInteractivePrompt = false,
  }) async {
    final resolvedAccessMode = accessMode ?? await _accessMode();
    return _service.authorizationHeaders(
      accessMode: resolvedAccessMode,
      allowInteractivePrompt: allowInteractivePrompt,
    );
  }

  Future<void> _restoreSession(int epoch) async {
    try {
      final user = await _service.restoreSession();
      if (epoch != _epoch || state is GoogleDriveAuthLoading) return;
      state = user == null
          ? const GoogleDriveAuthUnauthenticated()
          : GoogleDriveAuthAuthenticated(user: user);
    } on GoogleDriveException catch (e) {
      if (epoch != _epoch || state is GoogleDriveAuthLoading) return;
      state = _shouldSurfaceRestoreError(e)
          ? GoogleDriveAuthError(
              kind: e.kind,
              message: _messageForException(e),
              classification: e.classification,
            )
          : const GoogleDriveAuthUnauthenticated();
    } on Object catch (e) {
      if (epoch != _epoch || state is GoogleDriveAuthLoading) return;
      appLog(
        'google-drive-auth',
        'operation=drive_auth_restore kind=unexpectedResponse '
            'classification=unknown exceptionType=${e.runtimeType}',
      );
      state = const GoogleDriveAuthUnauthenticated();
    }
  }

  static bool _shouldSurfaceRestoreError(GoogleDriveException exception) {
    if (exception.kind == GoogleDriveFailureKind.authRequired ||
        exception.kind == GoogleDriveFailureKind.userCancelled) {
      return false;
    }
    if (exception.kind == GoogleDriveFailureKind.auth ||
        exception.kind == GoogleDriveFailureKind.expiredToken ||
        exception.kind == GoogleDriveFailureKind.uiUnavailable) {
      return true;
    }
    return switch (exception.classification) {
      GoogleDriveFailureClassification.missingConfig ||
      GoogleDriveFailureClassification.adminPolicyBlocked ||
      GoogleDriveFailureClassification.thirdPartyAppBlocked ||
      GoogleDriveFailureClassification.accessDenied ||
      GoogleDriveFailureClassification.insufficientScope => true,
      GoogleDriveFailureClassification.transient ||
      GoogleDriveFailureClassification.permanent ||
      GoogleDriveFailureClassification.unknown => false,
    };
  }

  static String _messageFor(GoogleDriveFailureKind kind) {
    return switch (kind) {
      GoogleDriveFailureKind.authRequired =>
        'Connect Google Drive to import documents.',
      GoogleDriveFailureKind.auth =>
        'The saved Google Drive connection is no longer available. Connect again.',
      GoogleDriveFailureKind.expiredToken =>
        'The saved Google Drive connection expired. Connect again.',
      GoogleDriveFailureKind.userCancelled => 'Sign-in was cancelled.',
      GoogleDriveFailureKind.uiUnavailable =>
        'Google sign-in is not available on this device. Check Play Services or browser access.',
      GoogleDriveFailureKind.permission =>
        'RunThru needs access to the Drive files you choose.',
      GoogleDriveFailureKind.rateLimit =>
        'Google Drive is rate-limiting this connection. Try again later.',
      GoogleDriveFailureKind.network =>
        'Network connection failed. Check your connection and try again.',
      GoogleDriveFailureKind.unsupportedMimeType =>
        'That Drive file type is not supported.',
      GoogleDriveFailureKind.unexpectedResponse =>
        'Google Drive returned an unexpected response. Try again.',
    };
  }

  static String _messageForException(GoogleDriveException exception) {
    if (exception.classification ==
            GoogleDriveFailureClassification.adminPolicyBlocked ||
        exception.classification ==
            GoogleDriveFailureClassification.thirdPartyAppBlocked) {
      return 'Your Google Workspace admin may need to allow RunThru before you can use this Drive access mode.';
    }
    if (exception.classification ==
            GoogleDriveFailureClassification.missingConfig &&
        exception.kind == GoogleDriveFailureKind.auth) {
      return 'Google sign-in is not configured for Android. Check the Android Google Sign-In configuration, then try again.';
    }
    return _messageFor(exception.kind);
  }

  Future<GoogleDriveAccessMode> _accessMode() async {
    try {
      return (await ref.read(configProvider.future)).googleDriveAccessMode;
    } on Object {
      return GoogleDriveAccessMode.selectedFilesOnly;
    }
  }
}
