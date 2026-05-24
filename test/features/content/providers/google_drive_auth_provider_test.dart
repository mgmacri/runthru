import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';

class _FakeGoogleDriveAuthService extends GoogleDriveAuthService {
  _FakeGoogleDriveAuthService({this.restoredUser, this.signInFailure});

  GoogleDriveUser? restoredUser;
  GoogleDriveException? signInFailure;
  var signedOut = false;

  @override
  Future<GoogleDriveUser?> restoreSession() async => restoredUser;

  @override
  Future<GoogleDriveUser> signIn() async {
    final failure = signInFailure;
    if (failure != null) throw failure;
    return const GoogleDriveUser(id: 'id', email: 'drive@example.com');
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }

  @override
  Future<Map<String, String>> authorizationHeaders() async {
    return {'Authorization': 'Bearer test'};
  }
}

void main() {
  ProviderContainer containerFor(_FakeGoogleDriveAuthService service) {
    return ProviderContainer(
      overrides: [googleDriveAuthServiceProvider.overrideWithValue(service)],
    );
  }

  group('GoogleDriveAuth', () {
    test('starts unauthenticated when restore finds no session', () async {
      final container = containerFor(_FakeGoogleDriveAuthService());
      addTearDown(container.dispose);

      expect(
        container.read(googleDriveAuthProvider),
        isA<GoogleDriveAuthChecking>(),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

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
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

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
      await Future<void>.delayed(Duration.zero);

      await container.read(googleDriveAuthProvider.notifier).connect();

      expect(
        container.read(googleDriveAuthProvider),
        isA<GoogleDriveAuthAuthenticated>(),
      );

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
      await Future<void>.delayed(Duration.zero);

      await container.read(googleDriveAuthProvider.notifier).connect();

      final state = container.read(googleDriveAuthProvider);
      expect(state, isA<GoogleDriveAuthError>());
      expect(
        (state as GoogleDriveAuthError).kind,
        GoogleDriveFailureKind.userCancelled,
      );
    });

    test('connect surfaces uiUnavailable distinctly from cancellation', () async {
      final service = _FakeGoogleDriveAuthService(
        signInFailure: const GoogleDriveException(
          kind: GoogleDriveFailureKind.uiUnavailable,
          message: 'Chrome Custom Tabs not available',
        ),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      await container.read(googleDriveAuthProvider.notifier).connect();

      final state = container.read(googleDriveAuthProvider);
      expect(state, isA<GoogleDriveAuthError>());
      expect(
        (state as GoogleDriveAuthError).kind,
        GoogleDriveFailureKind.uiUnavailable,
      );
    });

    test('expired token becomes reconnect error', () async {
      final service = _FakeGoogleDriveAuthService(
        signInFailure: const GoogleDriveException(
          kind: GoogleDriveFailureKind.expiredToken,
          message: 'expired',
        ),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      await container.read(googleDriveAuthProvider.notifier).connect();

      final state = container.read(googleDriveAuthProvider);
      expect(state, isA<GoogleDriveAuthError>());
      expect(
        (state as GoogleDriveAuthError).kind,
        GoogleDriveFailureKind.expiredToken,
      );
    });
  });
}
