/// Riverpod provider managing Instapaper authentication lifecycle.
///
/// Delegates token exchange, secure storage, and API verification to
/// [InstapaperAuthService]. Password values stay scoped to the login call and
/// are not retained in provider state.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/services/instapaper_auth_service.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';

part 'instapaper_auth_provider.g.dart';

/// Authentication state for Instapaper integration.
sealed class InstapaperAuthState {
  /// Base constructor for auth state.
  const InstapaperAuthState();
}

/// Session restoration is checking secure storage.
class InstapaperAuthChecking extends InstapaperAuthState {
  /// Creates the checking state.
  const InstapaperAuthChecking();
}

/// Not authenticated; show the connect UI.
class InstapaperAuthUnauthenticated extends InstapaperAuthState {
  /// Creates the unauthenticated state.
  const InstapaperAuthUnauthenticated();
}

/// Official sign-in is unavailable; the user can choose legacy sign-in.
class InstapaperAuthLegacyFallbackRequired extends InstapaperAuthState {
  /// Creates the legacy fallback prompt state.
  const InstapaperAuthLegacyFallbackRequired({required this.message});

  /// User-safe explanation.
  final String message;
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
  /// Creates the error state with a safe [message].
  const InstapaperAuthError({required this.message, required this.kind});

  /// Human-readable error message.
  final String message;

  /// Diagnostic category safe to log.
  final InstapaperFailureKind kind;
}

/// Instapaper auth service dependency.
final instapaperAuthServiceProvider = Provider<InstapaperAuthService>((ref) {
  final client = InstapaperClient();
  return InstapaperAuthService(
    client: client,
    tokenStore: const SecureInstapaperTokenStore(),
  );
});

/// Manages Instapaper authentication lifecycle.
///
/// Uses [InstapaperAuthService] to keep secure storage, credential exchange,
/// and API verification outside UI state management.
@Riverpod(keepAlive: true)
class InstapaperAuth extends _$InstapaperAuth {
  int _epoch = 0;

  /// Resolves the keep-alive auth service.
  ///
  /// Implemented as a getter rather than a `late final` field so that a
  /// repeated [build] (hot reload re-runs `build` on the existing notifier
  /// instance) cannot trigger a double-initialization
  /// `LateInitializationError`. The service provider is keep-alive, so this
  /// returns the same instance on every read.
  InstapaperAuthService get _service =>
      ref.read(instapaperAuthServiceProvider);

  @override
  InstapaperAuthState build() {
    _restoreSession(++_epoch);
    appLog('instapaper-auth', 'config ${_service.configurationDiagnostics}');
    return const InstapaperAuthChecking();
  }

  /// Restore session from stored tokens.
  Future<void> _restoreSession(int epoch) async {
    try {
      final user = await _service.restoreSession();
      if (epoch != _epoch || state is InstapaperAuthLoading) return;
      state = user == null
          ? const InstapaperAuthUnauthenticated()
          : InstapaperAuthAuthenticated(user: user);
    } on InstapaperSecureStorageException catch (_) {
      if (epoch != _epoch || state is InstapaperAuthLoading) return;
      state = const InstapaperAuthError(
        kind: InstapaperFailureKind.secureStorage,
        message:
            'RunThru could not read the saved Instapaper connection from secure storage.',
      );
    } on InstapaperAuthException catch (e) {
      if (epoch != _epoch || state is InstapaperAuthLoading) return;
      state = InstapaperAuthError(kind: e.kind, message: _messageFor(e.kind));
    } on InstapaperApiException catch (e) {
      if (epoch != _epoch || state is InstapaperAuthLoading) return;
      state = InstapaperAuthError(kind: e.kind, message: _messageFor(e.kind));
    } on Object {
      if (epoch != _epoch || state is InstapaperAuthLoading) return;
      state = const InstapaperAuthUnauthenticated();
    }
  }

  /// Attempts the preferred official Instapaper sign-in flow first.
  Future<void> connect() async {
    _epoch++;
    state = const InstapaperAuthLoading();
    try {
      final user = await _service.connectWithOfficialSignIn();
      state = InstapaperAuthAuthenticated(user: user);
    } on InstapaperAuthException catch (e) {
      appLog('instapaper-auth', 'official auth category=${e.kind.name}');
      if (e.kind == InstapaperFailureKind.officialAuthUnavailable) {
        state = InstapaperAuthLegacyFallbackRequired(
          message: _messageFor(e.kind),
        );
        return;
      }
      state = InstapaperAuthError(kind: e.kind, message: _messageFor(e.kind));
    } on Object {
      appLog('instapaper-auth', 'official auth category=unknown');
      state = const InstapaperAuthError(
        kind: InstapaperFailureKind.unknown,
        message: 'Could not connect Instapaper. Try again.',
      );
    }
  }

  /// Authenticate with Instapaper via the documented xAuth compatibility path.
  ///
  /// [username] is email or username. [password] may be empty because
  /// Instapaper documents passwordless accounts.
  Future<void> login({
    required String username,
    required String password,
  }) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) {
      state = const InstapaperAuthError(
        kind: InstapaperFailureKind.invalidCredentials,
        message: 'Enter an Instapaper email or username.',
      );
      return;
    }

    _epoch++;
    state = const InstapaperAuthLoading();
    try {
      final user = await _service.connectWithLegacyCredentials(
        username: trimmedUsername,
        password: password,
      );
      state = InstapaperAuthAuthenticated(user: user);
    } on InstapaperAuthException catch (e) {
      appLog(
        'instapaper-auth',
        'login failed category=${e.kind.name} status=${e.statusCode ?? 0}',
      );
      state = InstapaperAuthError(kind: e.kind, message: _messageFor(e.kind));
    } on InstapaperApiException catch (e) {
      appLog(
        'instapaper-auth',
        'post-login verify failed category=${e.kind.name} code=${e.errorCode}',
      );
      state = InstapaperAuthError(kind: e.kind, message: _messageFor(e.kind));
    } on InstapaperSecureStorageException catch (_) {
      appLog('instapaper-auth', 'secure storage failure during login');
      state = const InstapaperAuthError(
        kind: InstapaperFailureKind.secureStorage,
        message:
            'RunThru could not save the Instapaper connection securely on this device.',
      );
    } on Object {
      appLog('instapaper-auth', 'login failed category=unknown');
      state = const InstapaperAuthError(
        kind: InstapaperFailureKind.unknown,
        message: 'Could not connect Instapaper. Try again.',
      );
    }
  }

  /// Log out and clear locally stored Instapaper tokens.
  Future<void> logout() async {
    _epoch++;
    try {
      await _service.logout();
    } on InstapaperSecureStorageException catch (_) {
      state = const InstapaperAuthError(
        kind: InstapaperFailureKind.secureStorage,
        message:
            'RunThru could not clear the saved Instapaper connection from secure storage.',
      );
      return;
    }
    state = const InstapaperAuthUnauthenticated();
  }

  /// Access the authenticated client for Instapaper data providers.
  InstapaperClient? get client =>
      _service.client.isAuthenticated ? _service.client : null;

  static String _messageFor(InstapaperFailureKind kind) {
    return switch (kind) {
      InstapaperFailureKind.officialAuthUnavailable =>
        'Instapaper browser sign-in is not available here. Use legacy sign-in instead.',
      InstapaperFailureKind.userCancelled => 'Instapaper sign-in was canceled.',
      InstapaperFailureKind.permissionDenied =>
        'Instapaper sign-in permission was denied.',
      InstapaperFailureKind.missingConfiguration =>
        'Instapaper API credentials are not configured. Rebuild with --dart-define=INSTAPAPER_CONSUMER_KEY=... and --dart-define=INSTAPAPER_CONSUMER_SECRET=....',
      InstapaperFailureKind.invalidCredentials =>
        'Instapaper rejected these credentials. Check the email or username and password, if this account has one.',
      InstapaperFailureKind.network =>
        'Network connection failed. Check your connection and try again.',
      InstapaperFailureKind.serviceUnavailable =>
        'Instapaper is temporarily unavailable. Try again later.',
      InstapaperFailureKind.unexpectedResponse =>
        'Instapaper returned an unexpected response. Try again later.',
      InstapaperFailureKind.secureStorage =>
        'RunThru could not use secure storage for this Instapaper connection.',
      InstapaperFailureKind.unauthorized =>
        'The saved Instapaper connection is no longer valid. Connect again.',
      InstapaperFailureKind.rateLimited =>
        'Instapaper rate-limited this connection. Try again later.',
      InstapaperFailureKind.suspended =>
        'This Instapaper API connection is unavailable. Contact support if it continues.',
      InstapaperFailureKind.unknown =>
        'Could not connect Instapaper. Try again.',
    };
  }
}
