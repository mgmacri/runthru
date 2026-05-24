/// Riverpod auth provider for Google Drive.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';

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
  const GoogleDriveAuthError({required this.message, required this.kind});

  /// User-safe error message.
  final String message;

  /// Diagnostic category safe for logs.
  final GoogleDriveFailureKind kind;
}

/// Google Drive auth service dependency.
final googleDriveAuthServiceProvider = Provider<GoogleDriveAuthService>((ref) {
  const clientId = String.fromEnvironment('GOOGLE_SIGN_IN_CLIENT_ID');
  const serverClientId = String.fromEnvironment(
    'GOOGLE_SIGN_IN_SERVER_CLIENT_ID',
  );
  return GoogleDriveAuthService(
    clientId: clientId.isEmpty ? null : clientId,
    serverClientId: serverClientId.isEmpty ? null : serverClientId,
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
  Future<void> connect() async {
    _epoch++;
    state = const GoogleDriveAuthLoading();
    try {
      final user = await _service.signIn();
      state = GoogleDriveAuthAuthenticated(user: user);
    } on GoogleDriveException catch (e) {
      appLog('google-drive-auth', 'connect failed category=${e.kind.name}');
      state = e.kind == GoogleDriveFailureKind.authRequired
          ? const GoogleDriveAuthUnauthenticated()
          : GoogleDriveAuthError(kind: e.kind, message: _messageFor(e.kind));
    } on Object {
      appLog('google-drive-auth', 'connect failed category=unknown');
      state = const GoogleDriveAuthError(
        kind: GoogleDriveFailureKind.unexpectedResponse,
        message: 'Could not connect Google Drive. Try again.',
      );
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
  Future<Map<String, String>> authorizationHeaders() {
    return _service.authorizationHeaders();
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
      state = e.kind == GoogleDriveFailureKind.authRequired
          ? const GoogleDriveAuthUnauthenticated()
          : GoogleDriveAuthError(kind: e.kind, message: _messageFor(e.kind));
    } on Object {
      if (epoch != _epoch || state is GoogleDriveAuthLoading) return;
      state = const GoogleDriveAuthUnauthenticated();
    }
  }

  static String _messageFor(GoogleDriveFailureKind kind) {
    return switch (kind) {
      GoogleDriveFailureKind.authRequired =>
        'Connect Google Drive to import documents.',
      GoogleDriveFailureKind.auth =>
        'The saved Google Drive connection is no longer available. Connect again.',
      GoogleDriveFailureKind.expiredToken =>
        'The saved Google Drive connection expired. Connect again.',
      GoogleDriveFailureKind.userCancelled =>
        'Google Drive sign-in was canceled.',
      GoogleDriveFailureKind.uiUnavailable =>
        'Google sign-in is not available on this device. Check Play Services or browser access.',
      GoogleDriveFailureKind.permission =>
        'RunThru needs read-only Drive access to import documents.',
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
}
