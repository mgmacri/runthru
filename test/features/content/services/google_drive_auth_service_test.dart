import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/services/google_drive_auth_service.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/store/models.dart';

class _MemoryTokenStore implements GoogleDriveTokenStore {
  GoogleDriveUser? user;
  var cleared = false;

  @override
  Future<void> clear() async {
    cleared = true;
    user = null;
  }

  @override
  Future<GoogleDriveUser?> readUser() async => user;

  @override
  Future<void> saveUser(GoogleDriveUser user) async {
    this.user = user;
  }
}

class _FakeAccount implements GoogleDriveSignedInAccount {
  const _FakeAccount({this.email = 'drive@example.com'});

  @override
  String get id => 'google-id';

  @override
  final String email;

  @override
  String? get displayName => 'Drive User';
}

class _AuthorizationCall {
  const _AuthorizationCall({
    required this.account,
    required this.scopes,
    required this.promptIfNecessary,
  });

  final GoogleDriveSignedInAccount account;
  final List<String> scopes;
  final bool promptIfNecessary;
}

class _FakeSignInAdapter implements GoogleDriveSignInAdapter {
  String? initializedClientId;
  String? initializedServerClientId;
  var initializeCalls = 0;
  var supportsAuthenticateValue = true;
  GoogleDriveSignedInAccount? lightweightAccount;
  GoogleDriveSignedInAccount? interactiveAccount = const _FakeAccount();
  Map<String, String>? headers = const {
    'Authorization': 'Bearer fake-access-token',
    'X-Goog-AuthUser': '0',
  };
  List<Map<String, String>?>? headerResponses;
  Object? initializeFailure;
  Object? lightweightFailure;
  Object? authenticateFailure;
  Object? authorizationFailure;
  Object? disconnectFailure;
  List<String> expectedScopeHint = googleDriveFileScopes;
  final authorizationCalls = <_AuthorizationCall>[];
  var authenticateCalls = 0;
  var signOutCalls = 0;
  var disconnectCalls = 0;
  var lightweightCalls = 0;

  @override
  Future<void> initialize({String? clientId, String? serverClientId}) async {
    initializeCalls++;
    initializedClientId = clientId;
    initializedServerClientId = serverClientId;
    final failure = initializeFailure;
    if (failure != null) throw failure;
  }

  @override
  bool supportsAuthenticate() => supportsAuthenticateValue;

  @override
  Future<GoogleDriveSignedInAccount?> attemptLightweightAuthentication() async {
    lightweightCalls++;
    final failure = lightweightFailure;
    if (failure != null) throw failure;
    return lightweightAccount;
  }

  @override
  Future<GoogleDriveSignedInAccount?> authenticate({
    List<String> scopeHint = const <String>[],
  }) async {
    authenticateCalls++;
    expect(scopeHint, expectedScopeHint);
    final failure = authenticateFailure;
    if (failure != null) throw failure;
    return interactiveAccount;
  }

  @override
  Future<Map<String, String>?> authorizationHeaders(
    GoogleDriveSignedInAccount account,
    List<String> scopes, {
    required bool promptIfNecessary,
  }) async {
    authorizationCalls.add(
      _AuthorizationCall(
        account: account,
        scopes: List<String>.of(scopes),
        promptIfNecessary: promptIfNecessary,
      ),
    );
    final failure = authorizationFailure;
    if (failure != null) throw failure;
    final responses = headerResponses;
    if (responses != null && authorizationCalls.length <= responses.length) {
      return responses[authorizationCalls.length - 1];
    }
    return headers;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    final failure = disconnectFailure;
    if (failure != null) throw failure;
  }
}

void main() {
  group('GoogleDriveAuthService Android config validation', () {
    test('requires GOOGLE_WEB_CLIENT_ID/serverClientId by default', () {
      final error = GoogleDriveAuthService.validateAndroidServerClientId(null);

      expect(error, isNotNull);
      expect(
        error!.classification,
        GoogleDriveFailureClassification.missingConfig,
      );
    });

    test(
      'allows missing serverClientId when google-services.json is selected',
      () {
        final error = GoogleDriveAuthService.validateAndroidServerClientId(
          null,
          allowGoogleServicesJson: true,
        );

        expect(error, isNull);
      },
    );

    test('rejects placeholder web client ID values safely', () {
      for (final value in const [
        'GOOGLE_WEB_CLIENT_ID',
        'YOUR_WEB_CLIENT_ID',
        'your_web_oauth_client_id.apps.googleusercontent.com',
      ]) {
        final error = GoogleDriveAuthService.validateAndroidServerClientId(
          value,
        );

        expect(error, isNotNull, reason: value);
        expect(
          error!.classification,
          GoogleDriveFailureClassification.missingConfig,
          reason: value,
        );
      }
    });

    test('rejects malformed web client ID values', () {
      final error = GoogleDriveAuthService.validateAndroidServerClientId(
        'com.googleusercontent.apps.726962831034-webclient',
      );

      expect(error, isNotNull);
      expect(
        error!.classification,
        GoogleDriveFailureClassification.missingConfig,
      );
    });

    test('accepts Google OAuth web client ID shape', () {
      final error = GoogleDriveAuthService.validateAndroidServerClientId(
        '726962831034-r1qhhcdl8vk8l26l6giipnuh8j5t7626.apps.googleusercontent.com',
      );

      expect(error, isNull);
    });
  });

  group('GoogleDriveAuthService google_sign_in lifecycle', () {
    test('Android initializes google_sign_in with GOOGLE_WEB_CLIENT_ID', () async {
      final adapter = _FakeSignInAdapter();
      final store = _MemoryTokenStore();
      final service = GoogleDriveAuthService(
        signInAdapter: adapter,
        tokenStore: store,
        isAndroid: true,
        isIOS: false,
        androidServerClientId:
            '726962831034-r1qhhcdl8vk8l26l6giipnuh8j5t7626.apps.googleusercontent.com',
      );

      final user = await service.signIn();

      expect(user.email, 'drive@example.com');
      expect(adapter.initializedClientId, isNull);
      expect(
        adapter.initializedServerClientId,
        '726962831034-r1qhhcdl8vk8l26l6giipnuh8j5t7626.apps.googleusercontent.com',
      );
      expect(adapter.authenticateCalls, 1);
      expect(adapter.authorizationCalls, hasLength(1));
      expect(adapter.authorizationCalls.single.scopes, googleDriveFileScopes);
      expect(adapter.authorizationCalls.single.promptIfNecessary, isTrue);
      expect(store.user?.email, 'drive@example.com');
    });

    test('full Drive browser sign-in requests drive.readonly', () async {
      final adapter = _FakeSignInAdapter()
        ..expectedScopeHint = googleDriveReadOnlyScopes;
      final service = GoogleDriveAuthService(
        signInAdapter: adapter,
        tokenStore: _MemoryTokenStore(),
        isAndroid: false,
        isIOS: false,
      );

      await service.signIn(accessMode: GoogleDriveAccessMode.fullDriveBrowser);

      expect(
        adapter.authorizationCalls.single.scopes,
        googleDriveReadOnlyScopes,
      );
      expect(adapter.authorizationCalls.single.promptIfNecessary, isTrue);
    });

    test(
      'Android may initialize from google-services.json without serverClientId',
      () async {
        final adapter = _FakeSignInAdapter();
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: _MemoryTokenStore(),
          isAndroid: true,
          isIOS: false,
          androidUsesGoogleServicesJson: true,
        );

        await service.signIn();

        expect(adapter.initializedServerClientId, isNull);
        expect(adapter.authenticateCalls, 1);
      },
    );

    test(
      'missing Android web client ID is classified as missingConfig',
      () async {
        AppLogger.clear();
        final adapter = _FakeSignInAdapter();
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: _MemoryTokenStore(),
          isAndroid: true,
          isIOS: false,
        );

        await expectLater(
          service.signIn(),
          throwsA(
            isA<GoogleDriveException>()
                .having((e) => e.kind, 'kind', GoogleDriveFailureKind.auth)
                .having(
                  (e) => e.classification,
                  'classification',
                  GoogleDriveFailureClassification.missingConfig,
                ),
          ),
        );

        expect(adapter.initializeCalls, 0);
        final logs = AppLogger.entries.join('\n');
        expect(logs, contains('GOOGLE_WEB_CLIENT_ID=missing'));
        expect(logs, contains('reason=web_client_id_missing'));
      },
    );

    test(
      'placeholder Android web client ID fails fast with safe logs',
      () async {
        AppLogger.clear();
        const placeholder = 'YOUR_WEB_CLIENT_ID';
        final adapter = _FakeSignInAdapter();
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: _MemoryTokenStore(),
          isAndroid: true,
          isIOS: false,
          androidServerClientId: placeholder,
        );

        await expectLater(
          service.signIn(),
          throwsA(
            isA<GoogleDriveException>().having(
              (e) => e.classification,
              'classification',
              GoogleDriveFailureClassification.missingConfig,
            ),
          ),
        );

        expect(adapter.initializeCalls, 0);
        final logs = AppLogger.entries.join('\n');
        expect(logs, contains('event=oauth_config_invalid'));
        expect(logs, contains('reason=web_client_id_placeholder'));
        expect(logs, isNot(contains(placeholder)));
        expect(logs, isNot(contains('secret-access-token')));
        expect(logs, isNot(contains('Authorization')));
      },
    );

    test('iOS initializes with GOOGLE_IOS_CLIENT_ID as clientId', () async {
      final adapter = _FakeSignInAdapter();
      final service = GoogleDriveAuthService(
        signInAdapter: adapter,
        tokenStore: _MemoryTokenStore(),
        isAndroid: false,
        isIOS: true,
        iosClientId: 'ios-client.apps.googleusercontent.com',
      );

      await service.signIn();

      expect(
        adapter.initializedClientId,
        'ios-client.apps.googleusercontent.com',
      );
      expect(adapter.initializedServerClientId, isNull);
    });

    test(
      'restore returns authenticated user when prior account is available',
      () async {
        final adapter = _FakeSignInAdapter()
          ..lightweightAccount = const _FakeAccount(
            email: 'restored@example.com',
          );
        final store = _MemoryTokenStore();
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: store,
          isAndroid: false,
          isIOS: false,
        );

        final user = await service.restoreSession();

        expect(user?.email, 'restored@example.com');
        expect(store.user?.email, 'restored@example.com');
        expect(adapter.authorizationCalls, isEmpty);
      },
    );

    test(
      'restore clears stored auth metadata when no account is available',
      () async {
        final store = _MemoryTokenStore()
          ..user = const GoogleDriveUser(id: 'id', email: 'old@example.com');
        final service = GoogleDriveAuthService(
          signInAdapter: _FakeSignInAdapter(),
          tokenStore: store,
          isAndroid: false,
          isIOS: false,
        );

        final user = await service.restoreSession();

        expect(user, isNull);
        expect(store.cleared, isTrue);
      },
    );

    test(
      'authorizationHeaders restores account and requests Drive scopes',
      () async {
        final adapter = _FakeSignInAdapter()
          ..lightweightAccount = const _FakeAccount(
            email: 'restored@example.com',
          );
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: _MemoryTokenStore(),
          isAndroid: false,
          isIOS: false,
        );

        final headers = await service.authorizationHeaders();

        expect(headers['Authorization'], 'Bearer fake-access-token');
        expect(adapter.authorizationCalls, hasLength(1));
        expect(adapter.authorizationCalls.single.scopes, googleDriveFileScopes);
        expect(adapter.authorizationCalls.single.promptIfNecessary, isFalse);
      },
    );

    test(
      'authorizationHeaders tries silently before explicit interactive prompt',
      () async {
        final adapter = _FakeSignInAdapter()
          ..lightweightAccount = const _FakeAccount()
          ..headerResponses = [
            null,
            const {'Authorization': 'Bearer fresh-access-token'},
          ];
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: _MemoryTokenStore(),
          isAndroid: false,
          isIOS: false,
        );

        final headers = await service.authorizationHeaders(
          allowInteractivePrompt: true,
        );

        expect(headers['Authorization'], 'Bearer fresh-access-token');
        expect(adapter.authorizationCalls, hasLength(2));
        expect(
          adapter.authorizationCalls.map((call) => call.promptIfNecessary),
          [false, true],
        );
      },
    );

    test(
      'authorizationHeaders does not prompt for non-interactive REST calls',
      () async {
        final adapter = _FakeSignInAdapter()
          ..lightweightAccount = const _FakeAccount()
          ..headers = null;
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: _MemoryTokenStore(),
          isAndroid: false,
          isIOS: false,
        );

        await expectLater(
          service.authorizationHeaders(),
          throwsA(
            isA<GoogleDriveException>()
                .having(
                  (e) => e.kind,
                  'kind',
                  GoogleDriveFailureKind.permission,
                )
                .having(
                  (e) => e.classification,
                  'classification',
                  GoogleDriveFailureClassification.insufficientScope,
                ),
          ),
        );

        expect(adapter.authorizationCalls, hasLength(1));
        expect(adapter.authorizationCalls.single.promptIfNecessary, isFalse);
      },
    );

    test('authorizationHeaders uses drive.readonly for full browser', () async {
      final adapter = _FakeSignInAdapter()
        ..lightweightAccount = const _FakeAccount();
      final service = GoogleDriveAuthService(
        signInAdapter: adapter,
        tokenStore: _MemoryTokenStore(),
        isAndroid: false,
        isIOS: false,
      );

      await service.authorizationHeaders(
        accessMode: GoogleDriveAccessMode.fullDriveBrowser,
      );

      expect(
        adapter.authorizationCalls.single.scopes,
        googleDriveReadOnlyScopes,
      );
    });

    test(
      'missing authorization headers preserves stored auth metadata',
      () async {
        final adapter = _FakeSignInAdapter()
          ..lightweightAccount = const _FakeAccount()
          ..headers = null;
        final store = _MemoryTokenStore()
          ..user = const GoogleDriveUser(id: 'id', email: 'old@example.com');
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: store,
          isAndroid: false,
          isIOS: false,
        );

        await expectLater(
          service.authorizationHeaders(),
          throwsA(
            isA<GoogleDriveException>().having(
              (e) => e.kind,
              'kind',
              GoogleDriveFailureKind.permission,
            ),
          ),
        );

        expect(store.cleared, isFalse);
        expect(store.user?.email, 'old@example.com');
        expect(adapter.authorizationCalls.single.promptIfNecessary, isFalse);
      },
    );

    test(
      'user cancellation is not classified as generic auth failure',
      () async {
        final adapter = _FakeSignInAdapter()..interactiveAccount = null;
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: _MemoryTokenStore(),
          isAndroid: false,
          isIOS: false,
        );

        await expectLater(
          service.signIn(),
          throwsA(
            isA<GoogleDriveException>().having(
              (e) => e.kind,
              'kind',
              GoogleDriveFailureKind.userCancelled,
            ),
          ),
        );
      },
    );

    test('network platform failures are transient', () async {
      final adapter = _FakeSignInAdapter()
        ..authenticateFailure = PlatformException(
          code: 'sign_in_failed',
          message: 'network timeout',
        );
      final service = GoogleDriveAuthService(
        signInAdapter: adapter,
        tokenStore: _MemoryTokenStore(),
        isAndroid: false,
        isIOS: false,
      );

      await expectLater(
        service.signIn(),
        throwsA(
          isA<GoogleDriveException>()
              .having((e) => e.kind, 'kind', GoogleDriveFailureKind.network)
              .having(
                (e) => e.classification,
                'classification',
                GoogleDriveFailureClassification.transient,
              ),
        ),
      );
    });

    test('revoked grant platform failures clear stored credentials', () async {
      final adapter = _FakeSignInAdapter()
        ..authenticateFailure = PlatformException(
          code: 'sign_in_failed',
          message: 'invalid_grant',
        );
      final service = GoogleDriveAuthService(
        signInAdapter: adapter,
        tokenStore: _MemoryTokenStore(),
        isAndroid: false,
        isIOS: false,
      );

      await expectLater(
        service.signIn(),
        throwsA(
          isA<GoogleDriveException>()
              .having((e) => e.kind, 'kind', GoogleDriveFailureKind.auth)
              .having(
                (e) => e.classification,
                'classification',
                GoogleDriveFailureClassification.permanent,
              )
              .having(
                (e) => e.shouldClearStoredCredentials,
                'shouldClearStoredCredentials',
                isTrue,
              ),
        ),
      );
    });

    test('known admin policy wording maps to Workspace-safe copy', () async {
      final adapter = _FakeSignInAdapter()
        ..authenticateFailure = PlatformException(
          code: 'sign_in_failed',
          message: 'admin_policy_enforced secret-oauth-payload',
        );
      final service = GoogleDriveAuthService(
        signInAdapter: adapter,
        tokenStore: _MemoryTokenStore(),
        isAndroid: false,
        isIOS: false,
      );

      await expectLater(
        service.signIn(),
        throwsA(
          isA<GoogleDriveException>()
              .having((e) => e.kind, 'kind', GoogleDriveFailureKind.permission)
              .having(
                (e) => e.classification,
                'classification',
                GoogleDriveFailureClassification.adminPolicyBlocked,
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains('secret-oauth-payload')),
              ),
        ),
      );
    });

    test(
      'unknown provider wording falls back without raw exception text',
      () async {
        final adapter = _FakeSignInAdapter()
          ..authenticateFailure = PlatformException(
            code: 'unknown_provider_code',
            message: 'raw secret oauth payload',
          );
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: _MemoryTokenStore(),
          isAndroid: false,
          isIOS: false,
        );

        await expectLater(
          service.signIn(),
          throwsA(
            isA<GoogleDriveException>()
                .having((e) => e.kind, 'kind', GoogleDriveFailureKind.auth)
                .having(
                  (e) => e.classification,
                  'classification',
                  GoogleDriveFailureClassification.transient,
                )
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains('Google Sign-In failed unexpectedly.'),
                    isNot(contains('raw secret oauth payload')),
                  ),
                ),
          ),
        );
      },
    );

    test(
      'disconnect clears stored account state and falls back to signOut',
      () async {
        final adapter = _FakeSignInAdapter()
          ..disconnectFailure = StateError('temporary revoke failure');
        final store = _MemoryTokenStore()
          ..user = const GoogleDriveUser(id: 'id', email: 'drive@example.com');
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: store,
          isAndroid: false,
          isIOS: false,
        );

        await service.signOut();

        expect(adapter.disconnectCalls, 1);
        expect(adapter.signOutCalls, 1);
        expect(store.cleared, isTrue);
      },
    );

    test(
      'safe logs do not include raw web client IDs, tokens, or headers',
      () async {
        AppLogger.clear();
        const webClientId =
            '726962831034-r1qhhcdl8vk8l26l6giipnuh8j5t7626.apps.googleusercontent.com';
        final adapter = _FakeSignInAdapter()
          ..headers = const {'Authorization': 'Bearer secret-access-token'};
        final service = GoogleDriveAuthService(
          signInAdapter: adapter,
          tokenStore: _MemoryTokenStore(),
          isAndroid: true,
          isIOS: false,
          androidServerClientId: webClientId,
        );

        await service.signIn();

        final logs = AppLogger.entries.join('\n');
        expect(logs, contains('GOOGLE_WEB_CLIENT_ID=present'));
        expect(logs, isNot(contains(webClientId)));
        expect(logs, isNot(contains('secret-access-token')));
        expect(logs, isNot(contains('Authorization')));
      },
    );
  });

  group('Android AppAuth removal', () {
    test('production auth service does not depend on FlutterAppAuth', () {
      final serviceSource = File(
        'lib/features/content/services/google_drive_auth_service.dart',
      ).readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final buildGradle = File('android/app/build.gradle').readAsStringSync();

      expect(serviceSource, isNot(contains('flutter_appauth')));
      expect(serviceSource, isNot(contains('FlutterAppAuth')));
      expect(serviceSource, isNot(contains('AuthorizationTokenRequest')));
      expect(serviceSource, isNot(contains('oauth2redirect')));
      expect(pubspec, isNot(contains('flutter_appauth')));
      expect(buildGradle, isNot(contains('appAuthRedirectScheme')));
    });

    test('scope selection does not use account-type detection', () {
      final serviceSource = File(
        'lib/features/content/services/google_drive_auth_service.dart',
      ).readAsStringSync();
      final providerSource = File(
        'lib/features/content/providers/google_drive_auth_provider.dart',
      ).readAsStringSync();
      final combined = '$serviceSource\n$providerSource';

      expect(combined, isNot(contains('tokeninfo')));
      expect(combined, isNot(contains("['hd']")));
      expect(combined, isNot(contains(".endsWith('@")));
      expect(combined, isNot(contains("split('@")));
    });
  });

  group('Google Drive cleanup invariants', () {
    test('production code has no fake refresh or dead capability surface', () {
      final sources = [
        File(
          'lib/features/content/services/google_drive_auth_service.dart',
        ).readAsStringSync(),
        File(
          'lib/features/content/providers/google_drive_auth_provider.dart',
        ).readAsStringSync(),
        File(
          'lib/features/content/providers/google_drive_files_provider.dart',
        ).readAsStringSync(),
        File(
          'lib/features/content/services/google_drive_client.dart',
        ).readAsStringSync(),
      ].join('\n');

      expect(sources, isNot(contains('forceRefresh')));
      expect(sources, isNot(contains('GoogleDriveAuthCapabilities')));
      expect(sources, isNot(contains('authStateLost')));
      expect(sources, isNot(contains('listSupportedFiles')));
      expect(sources, isNot(contains('downloadBinary')));
      expect(sources, isNot(contains('refreshHeadersProvider')));
    });

    test('CI and dart defines use current Google client ID names', () {
      final dartDefines = File(
        'dart_defines/development.json.example',
      ).readAsStringSync();
      final codemagic = File('codemagic.yaml').readAsStringSync();
      final combined = '$dartDefines\n$codemagic';

      expect(combined, contains('GOOGLE_WEB_CLIENT_ID'));
      expect(combined, contains('GOOGLE_IOS_CLIENT_ID'));
      expect(combined, isNot(contains('GOOGLE_ANDROID_CLIENT_ID')));
      expect(combined, isNot(contains('GOOGLE_SIGN_IN_')));
      expect(combined, isNot(contains('appAuthRedirectScheme')));
    });
  });
}
