import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/features/content/widgets/instapaper_bookmark_list.dart';

class FakeInstapaperAuth extends Notifier<InstapaperAuthState>
    implements InstapaperAuth {
  FakeInstapaperAuth(this.initialState);

  final InstapaperAuthState initialState;
  String? submittedUsername;
  String? submittedPassword;
  int logoutCount = 0;

  @override
  InstapaperAuthState build() => initialState;

  @override
  InstapaperClient? get client => null;

  @override
  Future<void> login({
    required String username,
    required String password,
  }) async {
    submittedUsername = username;
    submittedPassword = password;
  }

  @override
  Future<void> logout() async {
    logoutCount++;
    state = const InstapaperAuthUnauthenticated();
  }

  @override
  Future<void> connect() async {
    state = const InstapaperAuthLegacyFallbackRequired(
      message: 'Use legacy sign-in instead.',
    );
  }
}

void main() {
  Widget harness(FakeInstapaperAuth auth) {
    return ProviderScope(
      overrides: [instapaperAuthProvider.overrideWith(() => auth)],
      child: const MaterialApp(home: Scaffold(body: InstapaperSection())),
    );
  }

  testWidgets('shows documented legacy connection copy and connect button', (
    tester,
  ) async {
    final auth = FakeInstapaperAuth(const InstapaperAuthUnauthenticated());

    await tester.pumpWidget(harness(auth));

    expect(find.text('Connect Instapaper'), findsOneWidget);
    expect(find.text('Email or username'), findsOneWidget);
    expect(find.text('Password, if you have one'), findsOneWidget);
    expect(find.textContaining('legacy sign-in'), findsOneWidget);
    expect(find.textContaining('OAuth tokens'), findsOneWidget);
  });

  testWidgets('submits password without retaining it in the text field', (
    tester,
  ) async {
    final auth = FakeInstapaperAuth(const InstapaperAuthUnauthenticated());

    await tester.pumpWidget(harness(auth));
    await tester.enterText(find.byType(TextField).at(0), ' user@test.com ');
    await tester.enterText(find.byType(TextField).at(1), 'raw-password');
    await tester.tap(find.text('Connect Instapaper'));
    await tester.pump();

    expect(auth.submittedUsername, equals('user@test.com'));
    expect(auth.submittedPassword, equals('raw-password'));
    expect(find.text('raw-password'), findsNothing);
  });

  testWidgets('shows actionable auth error and returns to connect form', (
    tester,
  ) async {
    final auth = FakeInstapaperAuth(
      const InstapaperAuthError(
        kind: InstapaperFailureKind.missingConfiguration,
        message: 'Instapaper API credentials are not configured.',
      ),
    );

    await tester.pumpWidget(harness(auth));

    expect(
      find.text('Instapaper API credentials are not configured.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Connect Instapaper'));
    await tester.pump();

    expect(auth.logoutCount, equals(1));
    expect(find.text('Email or username'), findsOneWidget);
  });

  testWidgets('authenticated state exposes logout action', (tester) async {
    final auth = FakeInstapaperAuth(
      const InstapaperAuthAuthenticated(
        user: InstapaperUser(userId: 123, username: 'TestUser'),
      ),
    );

    await tester.pumpWidget(harness(auth));
    await tester.pump();

    expect(find.text('TestUser'), findsOneWidget);
    await tester.tap(find.byTooltip('Sign out of Instapaper'));
    await tester.pump();

    expect(auth.logoutCount, equals(1));
  });
}
