import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/features/content/widgets/instapaper_auth_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth extends Notifier<InstapaperAuthState>
    implements InstapaperAuth {
  _FakeAuth(this.initialState);

  final InstapaperAuthState initialState;
  final logins = <(String, String)>[];
  int logoutCount = 0;

  /// What a sign-in attempt ends in; null leaves it "connecting".
  InstapaperAuthState? loginResult;

  @override
  InstapaperAuthState build() => initialState;

  @override
  InstapaperClient? get client => null;

  @override
  Future<void> login({
    required String username,
    required String password,
  }) async {
    logins.add((username, password));
    state = const InstapaperAuthLoading();
    final result = loginResult;
    if (result != null) state = result;
  }

  @override
  Future<void> logout() async {
    logoutCount++;
    state = const InstapaperAuthUnauthenticated();
  }

  @override
  Future<void> connect() async {}

  @override
  Future<void> sessionExpired() async {}

  @override
  Future<void> checkSession() async {}

  @override
  void updateUser(InstapaperUser user) {}

  @override
  void dismissError() {
    if (state is InstapaperAuthError) {
      state = const InstapaperAuthUnauthenticated();
    }
  }
}

const _connected = InstapaperAuthAuthenticated(
  user: InstapaperUser(userId: 7, username: 'reader@example.com'),
);

void main() {
  Future<_FakeAuth> pumpTile(
    WidgetTester tester,
    InstapaperAuthState state, {
    Size size = const Size(411, 915),
    double textScale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final auth = _FakeAuth(state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [instapaperAuthProvider.overrideWith(() => auth)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          // As in the app: the row sits inside a scaffold, which takes the
          // keyboard out of its own layout.
          home: const Scaffold(
            body: Column(children: [InstapaperAuthTile(showDivider: true)]),
          ),
        ),
      ),
    );
    await tester.pump();
    return auth;
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Connect Instapaper'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  group('sign-in sheet', () {
    testWidgets('asks for an email or username and an optional password', (
      tester,
    ) async {
      await pumpTile(tester, const InstapaperAuthUnauthenticated());

      await openSheet(tester);

      expect(find.text('Sign in to Instapaper'), findsOneWidget);
      expect(field('Email or username'), findsOneWidget);
      // Instapaper accounts often have no password; its own form says so.
      expect(field('Password, if you have one'), findsOneWidget);
    });

    testWidgets('stays above the keyboard', (tester) async {
      await pumpTile(tester, const InstapaperAuthUnauthenticated());
      await openSheet(tester);

      // The keyboard comes up: 300 logical pixels at the bottom.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      const keyboardTop = 915 - 300;
      final connect = tester.getRect(
        find.widgetWithText(ElevatedButton, 'Connect'),
      );
      final password = tester.getRect(field('Password, if you have one'));
      expect(connect.bottom, lessThanOrEqualTo(keyboardTop));
      expect(password.bottom, lessThanOrEqualTo(keyboardTop));
    });

    testWidgets('scrolls instead of overflowing on a short screen', (
      tester,
    ) async {
      await pumpTile(
        tester,
        const InstapaperAuthUnauthenticated(),
        size: const Size(320, 480),
        textScale: 1.3,
      );
      await openSheet(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('signs in with an empty password', (tester) async {
      final auth = await pumpTile(
        tester,
        const InstapaperAuthUnauthenticated(),
      );
      await openSheet(tester);

      await tester.enterText(field('Email or username'), '  reader  ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
      await tester.pump();

      expect(auth.logins, [('reader', '')]);
      expect(find.text('Connecting…'), findsWidgets);
    });

    testWidgets('does not submit without an email or username', (tester) async {
      final auth = await pumpTile(
        tester,
        const InstapaperAuthUnauthenticated(),
      );
      await openSheet(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
      await tester.pump();

      expect(auth.logins, isEmpty);
      expect(
        find.text('Enter your Instapaper email or username.'),
        findsOneWidget,
      );
    });

    testWidgets('shows why a sign-in failed and announces it', (tester) async {
      final handle = tester.ensureSemantics();
      final auth = await pumpTile(
        tester,
        const InstapaperAuthUnauthenticated(),
      );
      auth.loginResult = const InstapaperAuthError(
        kind: InstapaperFailureKind.invalidCredentials,
        message: 'Instapaper did not accept that.',
      );
      await openSheet(tester);

      await tester.enterText(field('Email or username'), 'reader');
      await tester.enterText(field('Password, if you have one'), 'wrong');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
      await tester.pump();

      // In the sheet (the row behind it shows the same state).
      final inSheet = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Instapaper did not accept that.'),
      );
      expect(inSheet, findsOneWidget);
      expect(
        tester.getSemantics(inSheet),
        matchesSemantics(
          label: 'Instapaper did not accept that.',
          isLiveRegion: true,
        ),
      );
      // The form is still there, with what was typed, to try again.
      expect(find.text('reader'), findsOneWidget);

      // Typing again clears the message.
      await tester.enterText(field('Password, if you have one'), 'right');
      await tester.pump();
      expect(inSheet, findsNothing);
      handle.dispose();
    });

    testWidgets('closes on success', (tester) async {
      final auth = await pumpTile(
        tester,
        const InstapaperAuthUnauthenticated(),
      );
      auth.loginResult = _connected;
      await openSheet(tester);

      await tester.enterText(field('Email or username'), 'reader@example.com');
      await tester.enterText(field('Password, if you have one'), 'secret');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to Instapaper'), findsNothing);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('reader@example.com'), findsOneWidget);
    });

    testWidgets('a failed sign-in does not stick to the row once dismissed', (
      tester,
    ) async {
      final auth = await pumpTile(
        tester,
        const InstapaperAuthUnauthenticated(),
      );
      auth.loginResult = const InstapaperAuthError(
        kind: InstapaperFailureKind.invalidCredentials,
        message: 'Instapaper did not accept that.',
      );
      await openSheet(tester);
      await tester.enterText(field('Email or username'), 'reader');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
      await tester.pump();

      // Dismiss the sheet by tapping the scrim above it.
      await tester.tapAt(const Offset(200, 120));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to Instapaper'), findsNothing);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Instapaper did not accept that.'), findsNothing);
    });
  });

  group('row', () {
    testWidgets('Connect is a 48dp target announced once', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTile(tester, const InstapaperAuthUnauthenticated());

      final target = find.bySemanticsLabel('Connect Instapaper');
      final size = tester.getSize(target);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(target),
        matchesSemantics(
          label: 'Connect Instapaper',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('Disconnect is a 48dp target and asks first', (tester) async {
      final auth = await pumpTile(tester, _connected);

      final target = find.bySemanticsLabel('Disconnect Instapaper');
      final size = tester.getSize(target);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));

      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('Disconnect Instapaper?'), findsOneWidget);
      expect(auth.logoutCount, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.logoutCount, 0);
      expect(find.text('Connected'), findsOneWidget);

      await tester.tap(target);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(auth.logoutCount, 1);
      expect(find.text('Not connected'), findsOneWidget);
    });

    testWidgets('a long username does not overflow a narrow, large-text row', (
      tester,
    ) async {
      await pumpTile(
        tester,
        const InstapaperAuthAuthenticated(
          user: InstapaperUser(
            userId: 7,
            username: 'a.very.long.reader.name@a-long-domain.example.com',
          ),
        ),
        size: const Size(320, 640),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('a connection without a known name shows no empty pill', (
      tester,
    ) async {
      await pumpTile(
        tester,
        const InstapaperAuthAuthenticated(
          user: InstapaperUser(userId: 0, username: ''),
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text(''), findsNothing);
    });

    testWidgets('an expired connection says so and offers to reconnect', (
      tester,
    ) async {
      await pumpTile(
        tester,
        const InstapaperAuthError(
          kind: InstapaperFailureKind.unauthorized,
          message: 'Instapaper needs you to sign in again.',
        ),
      );

      expect(
        find.text('Instapaper needs you to sign in again.'),
        findsOneWidget,
      );
      final target = find.bySemanticsLabel('Reconnect Instapaper');
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));

      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('Sign in to Instapaper'), findsOneWidget);
    });

    testWidgets('the status line is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTile(tester, const InstapaperAuthChecking());

      expect(
        tester.getSemantics(find.text('Checking…')),
        matchesSemantics(label: 'Checking…', isLiveRegion: true),
      );
      handle.dispose();
    });
  });
}
