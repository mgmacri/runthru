import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

class _FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  _FakeConfigNotifier(this._config);

  AppConfig _config;

  @override
  Future<AppConfig> build() async => _config;

  @override
  Future<void> setGoogleDriveAccessMode(GoogleDriveAccessMode mode) async {
    _config = _config.copyWith(googleDriveAccessMode: mode);
    state = AsyncData(_config);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGoogleDriveAuthService extends GoogleDriveAuthService {
  _FakeGoogleDriveAuthService({
    this.restoredUser,
    this.restoreFailure,
    this.signInFailure,
    this.signOutFailure,
  });

  GoogleDriveUser? restoredUser;
  GoogleDriveException? restoreFailure;
  GoogleDriveException? signInFailure;
  Object? signOutFailure;
  var signedOut = false;
  var signInCalls = 0;
  final signInAccessModes = <GoogleDriveAccessMode>[];
  final headerAccessModes = <GoogleDriveAccessMode>[];
  final headerAllowInteractivePrompts = <bool>[];
  Completer<GoogleDriveUser?>? restoreCompleter;

  @override
  Future<GoogleDriveUser?> restoreSession() async {
    final completer = restoreCompleter;
    if (completer != null) return completer.future;
    final failure = restoreFailure;
    if (failure != null) throw failure;
    return restoredUser;
  }

  @override
  Future<GoogleDriveUser> signIn({
    GoogleDriveAccessMode accessMode = GoogleDriveAccessMode.selectedFilesOnly,
  }) async {
    signInCalls++;
    signInAccessModes.add(accessMode);
    final failure = signInFailure;
    if (failure != null) throw failure;
    return const GoogleDriveUser(id: 'id', email: 'drive@example.com');
  }

  @override
  Future<void> signOut() async {
    final failure = signOutFailure;
    if (failure != null) throw failure;
    signedOut = true;
  }

  @override
  Future<Map<String, String>> authorizationHeaders({
    GoogleDriveAccessMode accessMode = GoogleDriveAccessMode.selectedFilesOnly,
    bool allowInteractivePrompt = false,
  }) async {
    headerAccessModes.add(accessMode);
    headerAllowInteractivePrompts.add(allowInteractivePrompt);
    return {'Authorization': 'Bearer test'};
  }
}

void main() {
  ProviderContainer containerFor(
    _FakeGoogleDriveAuthService service, {
    AppConfig config = const AppConfig(),
  }) {
    return ProviderContainer(
      overrides: [
        googleDriveAuthServiceProvider.overrideWithValue(service),
        configProvider.overrideWith(() => _FakeConfigNotifier(config)),
      ],
    );
  }

  Future<T> waitForAuthState<T extends GoogleDriveAuthState>(
    ProviderContainer container,
  ) async {
    final completer = Completer<T>();
    late final ProviderSubscription<GoogleDriveAuthState> subscription;
    subscription = container.listen<GoogleDriveAuthState>(
      googleDriveAuthProvider,
      (_, next) {
        if (!completer.isCompleted && next is T) {
          completer.complete(next);
        }
      },
      fireImmediately: true,
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 1));
    } finally {
      subscription.close();
    }
  }

  group('GoogleDriveAuth', () {
    test('starts unauthenticated when restore finds no session', () async {
      final container = containerFor(_FakeGoogleDriveAuthService());
      addTearDown(container.dispose);

      expect(
        container.read(googleDriveAuthProvider),
        isA<GoogleDriveAuthChecking>(),
      );
      await waitForAuthState<GoogleDriveAuthUnauthenticated>(container);

      expect(
        container.read(googleDriveAuthProvider),
        isA<GoogleDriveAuthUnauthenticated>(),
      );
    });

    test('restores an authenticated session', () async {
      final container = containerFor(
        _FakeGoogleDriveAuthService(
          restoredUser: const GoogleDriveUser(
            id: 'id',
            email: 'drive@example.com',
          ),
        ),
      );
      addTearDown(container.dispose);

      expect(
        container.read(googleDriveAuthProvider),
        isA<GoogleDriveAuthChecking>(),
      );
      await waitForAuthState<GoogleDriveAuthAuthenticated>(container);

      final state = container.read(googleDriveAuthProvider);
      expect(state, isA<GoogleDriveAuthAuthenticated>());
      expect(
        (state as GoogleDriveAuthAuthenticated).user.email,
        'drive@example.com',
      );
    });

    test('connect and disconnect transition auth state', () async {
      final service = _FakeGoogleDriveAuthService();
      final container = containerFor(service);
      addTearDown(container.dispose);
      await waitForAuthState<GoogleDriveAuthUnauthenticated>(container);

      await container.read(googleDriveAuthProvider.notifier).connect();

      expect(
        container.read(googleDriveAuthProvider),
        isA<GoogleDriveAuthAuthenticated>(),
      );
      expect(service.signInAccessModes, [
        GoogleDriveAccessMode.selectedFilesOnly,
      ]);

      await container.read(googleDriveAuthProvider.notifier).disconnect();

      expect(service.signedOut, isTrue);
      expect(
        container.read(googleDriveAuthProvider),
        isA<GoogleDriveAuthUnauthenticated>(),
      );
    });

    test('connect surfaces user cancellation distinctly', () async {
      final service = _FakeGoogleDriveAuthService(
        signInFailure: const GoogleDriveException(
          kind: GoogleDriveFailureKind.userCancelled,
          message: 'canceled',
        ),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);
      await waitForAuthState<GoogleDriveAuthUnauthenticated>(container);

      await container.read(googleDriveAuthProvider.notifier).connect();

      final state = container.read(googleDriveAuthProvider);
      expect(state, isA<GoogleDriveAuthError>());
      expect(
        (state as GoogleDriveAuthError).kind,
        GoogleDriveFailureKind.userCancelled,
      );
      expect(state.message, 'Sign-in was cancelled.');
    });

    test('full browser preference requests drive.readonly path', () async {
      final service = _FakeGoogleDriveAuthService();
      final container = containerFor(
        service,
        config: const AppConfig(
          googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
        ),
      );
      addTearDown(container.dispose);
      await waitForAuthState<GoogleDriveAuthUnauthenticated>(container);

      await container.read(googleDriveAuthProvider.notifier).connect();

      expect(service.signInAccessModes, [
        GoogleDriveAccessMode.fullDriveBrowser,
      ]);
      final state = container.read(googleDriveAuthProvider);
      expect(state, isA<GoogleDriveAuthAuthenticated>());
    });

    test(
      'authorizationHeaders defaults to non-interactive prompting',
      () async {
        final service = _FakeGoogleDriveAuthService();
        final container = containerFor(service);
        addTearDown(container.dispose);

        await container
            .read(googleDriveAuthProvider.notifier)
            .authorizationHeaders();

        expect(service.headerAccessModes, [
          GoogleDriveAccessMode.selectedFilesOnly,
        ]);
        expect(service.headerAllowInteractivePrompts, [false]);
      },
    );

    test('authorizationHeaders passes explicit interactive opt-in', () async {
      final service = _FakeGoogleDriveAuthService();
      final container = containerFor(service);
      addTearDown(container.dispose);

      await container
          .read(googleDriveAuthProvider.notifier)
          .authorizationHeaders(allowInteractivePrompt: true);

      expect(service.headerAllowInteractivePrompts, [true]);
    });

    test(
      'connect surfaces uiUnavailable distinctly from cancellation',
      () async {
        final service = _FakeGoogleDriveAuthService(
          signInFailure: const GoogleDriveException(
            kind: GoogleDriveFailureKind.uiUnavailable,
            message: 'Chrome Custom Tabs not available',
            classification: GoogleDriveFailureClassification.transient,
          ),
        );
        final container = containerFor(service);
        addTearDown(container.dispose);
        await waitForAuthState<GoogleDriveAuthUnauthenticated>(container);

        await container.read(googleDriveAuthProvider.notifier).connect();

        final state = container.read(googleDriveAuthProvider);
        expect(state, isA<GoogleDriveAuthError>());
        expect(
          (state as GoogleDriveAuthError).kind,
          GoogleDriveFailureKind.uiUnavailable,
        );
        expect(
          state.classification,
          GoogleDriveFailureClassification.transient,
        );
        expect(state.message, isNot(contains('cancel')));
      },
    );

    test('expired token becomes reconnect error', () async {
      final service = _FakeGoogleDriveAuthService(
        signInFailure: const GoogleDriveException(
          kind: GoogleDriveFailureKind.expiredToken,
          message: 'expired',
        ),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);
      await waitForAuthState<GoogleDriveAuthUnauthenticated>(container);

      await container.read(googleDriveAuthProvider.notifier).connect();

      final state = container.read(googleDriveAuthProvider);
      expect(state, isA<GoogleDriveAuthError>());
      expect(
        (state as GoogleDriveAuthError).kind,
        GoogleDriveFailureKind.expiredToken,
      );
    });

    test('restore revoked token becomes unauthenticated', () async {
      final service = _FakeGoogleDriveAuthService(
        restoreFailure: const GoogleDriveException(
          kind: GoogleDriveFailureKind.authRequired,
          message: 'secret-token-value',
        ),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);

      expect(
        container.read(googleDriveAuthProvider),
        isA<GoogleDriveAuthChecking>(),
      );
      await waitForAuthState<GoogleDriveAuthUnauthenticated>(container);

      expect(
        container.read(googleDriveAuthProvider),
        isA<GoogleDriveAuthUnauthenticated>(),
      );
    });

    test('restore missing config becomes safe error state', () async {
      final service = _FakeGoogleDriveAuthService(
        restoreFailure: const GoogleDriveException(
          kind: GoogleDriveFailureKind.auth,
          message: 'secret-client-id',
          classification: GoogleDriveFailureClassification.missingConfig,
        ),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);

      final state = await waitForAuthState<GoogleDriveAuthError>(container);

      expect(state.kind, GoogleDriveFailureKind.auth);
      expect(state.message, isNot(contains('secret-client-id')));
    });

    test('restore transient failure soft-fails to unauthenticated', () async {
      final service = _FakeGoogleDriveAuthService(
        restoreFailure: const GoogleDriveException(
          kind: GoogleDriveFailureKind.network,
          message: 'network timeout',
          classification: GoogleDriveFailureClassification.transient,
        ),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);

      await waitForAuthState<GoogleDriveAuthUnauthenticated>(container);

      expect(
        container.read(googleDriveAuthProvider),
        isA<GoogleDriveAuthUnauthenticated>(),
      );
    });

    test(
      'restore unknown Drive failure soft-fails to unauthenticated',
      () async {
        final service = _FakeGoogleDriveAuthService(
          restoreFailure: const GoogleDriveException(
            kind: GoogleDriveFailureKind.unexpectedResponse,
            message: 'raw secret detail',
          ),
        );
        final container = containerFor(service);
        addTearDown(container.dispose);

        await waitForAuthState<GoogleDriveAuthUnauthenticated>(container);

        expect(
          container.read(googleDriveAuthProvider),
          isA<GoogleDriveAuthUnauthenticated>(),
        );
      },
    );

    test(
      'restore unexpected exception soft-fails to unauthenticated',
      () async {
        AppLogger.clear();
        final service = _FakeGoogleDriveAuthService()
          ..restoreCompleter = Completer<GoogleDriveUser?>();
        final container = containerFor(service);
        addTearDown(container.dispose);

        final restored = waitForAuthState<GoogleDriveAuthUnauthenticated>(
          container,
        );
        service.restoreCompleter!.completeError(
          StateError('secret-token-value'),
        );
        await restored;

        final logs = AppLogger.entries.join('\n');
        expect(logs, contains('operation=drive_auth_restore'));
        expect(logs, contains('classification=unknown'));
        expect(logs, isNot(contains('restore failed category=unknown')));
      },
    );

    test(
      'connect surfaces missing client ID as safe configuration error',
      () async {
        final service = _FakeGoogleDriveAuthService(
          signInFailure: const GoogleDriveException(
            kind: GoogleDriveFailureKind.auth,
            message:
                'Google Android client ID is not configured: secret-client-id',
            classification: GoogleDriveFailureClassification.missingConfig,
          ),
        );
        final container = containerFor(service);
        addTearDown(container.dispose);
        await waitForAuthState<GoogleDriveAuthUnauthenticated>(container);

        await container.read(googleDriveAuthProvider.notifier).connect();

        final state = container.read(googleDriveAuthProvider);
        expect(state, isA<GoogleDriveAuthError>());
        expect(
          (state as GoogleDriveAuthError).kind,
          GoogleDriveFailureKind.auth,
        );
        expect(
          state.message,
          'Google sign-in is not configured for Android. Check the Android Google Sign-In configuration, then try again.',
        );
        expect(state.message, isNot(contains('secret-client-id')));
      },
    );

    test('disconnect failure leaves safe error state', () async {
      final service = _FakeGoogleDriveAuthService(
        restoredUser: const GoogleDriveUser(
          id: 'id',
          email: 'drive@example.com',
        ),
        signOutFailure: StateError('secret-token-value'),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);
      await waitForAuthState<GoogleDriveAuthAuthenticated>(container);

      await container.read(googleDriveAuthProvider.notifier).disconnect();

      final state = container.read(googleDriveAuthProvider);
      expect(state, isA<GoogleDriveAuthError>());
      expect(
        (state as GoogleDriveAuthError).message,
        isNot(contains('secret')),
      );
    });

    test(
      'grantDriveAccess uses interactive sign-in without clearing auth on cancel',
      () async {
        final service = _FakeGoogleDriveAuthService(
          restoredUser: const GoogleDriveUser(
            id: 'id',
            email: 'drive@example.com',
          ),
          signInFailure: const GoogleDriveException(
            kind: GoogleDriveFailureKind.userCancelled,
            message: 'cancelled',
            classification: GoogleDriveFailureClassification.permanent,
          ),
        );
        final container = containerFor(service);
        addTearDown(container.dispose);
        await waitForAuthState<GoogleDriveAuthAuthenticated>(container);

        final granted = await container
            .read(googleDriveAuthProvider.notifier)
            .grantDriveAccess();

        expect(granted, isFalse);
        expect(service.signInCalls, 1);
        expect(service.signedOut, isFalse);
        expect(
          container.read(googleDriveAuthProvider),
          isA<GoogleDriveAuthAuthenticated>(),
        );
      },
    );

    test('grantDriveAccess updates authenticated user on success', () async {
      final service = _FakeGoogleDriveAuthService(
        restoredUser: const GoogleDriveUser(
          id: 'old',
          email: 'old@example.com',
        ),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);
      await waitForAuthState<GoogleDriveAuthAuthenticated>(container);

      final granted = await container
          .read(googleDriveAuthProvider.notifier)
          .grantDriveAccess();

      expect(granted, isTrue);
      expect(service.signInCalls, 1);
      final state = container.read(googleDriveAuthProvider);
      expect(state, isA<GoogleDriveAuthAuthenticated>());
      expect(
        (state as GoogleDriveAuthAuthenticated).user.email,
        'drive@example.com',
      );
    });

    test(
      'grantDriveAccess re-emits authenticated state for same user after mode change',
      () async {
        final service = _FakeGoogleDriveAuthService(
          restoredUser: const GoogleDriveUser(
            id: 'id',
            email: 'drive@example.com',
          ),
        );
        final container = containerFor(
          service,
          config: const AppConfig(
            googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
          ),
        );
        addTearDown(container.dispose);
        await waitForAuthState<GoogleDriveAuthAuthenticated>(container);
        final states = <GoogleDriveAuthState>[];
        final subscription = container.listen<GoogleDriveAuthState>(
          googleDriveAuthProvider,
          (_, next) => states.add(next),
        );
        addTearDown(subscription.close);

        final granted = await container
            .read(googleDriveAuthProvider.notifier)
            .grantDriveAccess();

        expect(granted, isTrue);
        expect(service.signInAccessModes, [
          GoogleDriveAccessMode.fullDriveBrowser,
        ]);
        expect(states.whereType<GoogleDriveAuthAuthenticated>(), hasLength(1));
      },
    );
  });
}
