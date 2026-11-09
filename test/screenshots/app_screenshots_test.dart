/// Store-screenshot generator, not a gate test. Excluded from the default
/// `flutter test` run via `dart_test.yaml`. Generate with:
///   flutter test --tags screenshots --run-skipped test/screenshots
@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/app.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/features/content/providers/google_drive_auth_provider.dart';
import 'package:runthru/features/content/providers/google_drive_files_provider.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/services/drive_local_store.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/screens/home_shell.dart';
import 'package:runthru/screens/parallax_reading_screen.dart';
import 'package:runthru/screens/range_picker_screen.dart';
import 'package:runthru/screens/settings_sources_screen.dart';
import 'package:runthru/services/analytics_service.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/store/analytics_models.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const phoneSize = Size(390, 844);
  final outputDir = Directory('screenshots/app');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    outputDir.createSync(recursive: true);
  });

  testWidgets('captures app screens', (tester) async {
    // The reading screen enters desktop fullscreen when the host is
    // Linux/macOS/Windows; stub the plugin channel so it is a no-op here.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (_) async => null,
    );
    await tester.binding.setSurfaceSize(phoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _capture(
      tester,
      outputDir,
      '01-library.png',
      const HomeShell(initialTab: 0),
    );
    await _capture(
      tester,
      outputDir,
      '02-sources.png',
      const HomeShell(initialTab: 1),
    );
    await _capture(
      tester,
      outputDir,
      '03-analytics.png',
      const HomeShell(initialTab: 2),
    );
    await _capture(
      tester,
      outputDir,
      '04-settings.png',
      const HomeShell(initialTab: 3),
    );
    await _capture(
      tester,
      outputDir,
      '05-settings-sources.png',
      const SettingsSourcesScreen(),
    );
    await _capture(
      tester,
      outputDir,
      '06-reading.png',
      ParallaxReadingScreen(
        filePath: 'clipboard://screenshot',
        contentSource: 'clipboard',
        clipboardDocument: ClipboardDocument(
          title: 'Screenshot Sample',
          fullText: '',
          document: const ExtractedDocument(
            sentences: [
              Sentence(words: ['Quiet', 'focus', 'starts', 'here']),
              Sentence(words: ['Every', 'word', 'has', 'room', 'to', 'land']),
            ],
          ),
          pastedAt: DateTime(2026, 6, 17),
        ),
      ),
      config: const AppConfig(
        hasSeenReadingGoalOnboarding: true,
        shownHints: {'tap_pause'},
      ),
      settle: false,
    );
    await _capture(
      tester,
      outputDir,
      '07-range-picker.png',
      const RangePickerScreen(filePath: 'clipboard://screenshot'),
      config: const AppConfig(hasSeenReadingGoalOnboarding: true),
    );

    // Unmount and drain timers left by the reading screen (hints, autosave).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}

Future<void> _capture(
  WidgetTester tester,
  Directory outputDir,
  String filename,
  Widget screen, {
  AppConfig config = const AppConfig(
    hasSeenReadingGoalOnboarding: true,
    googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
  ),
  bool settle = true,
}) async {
  final key = GlobalKey();

  await tester.pumpWidget(
    _providers(
      config: config,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildRunThruTheme(),
        home: RepaintBoundary(key: key, child: screen),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  } else {
    await tester.pump(const Duration(milliseconds: 500));
  }

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // toImage/toByteData complete on the real event loop; under testWidgets'
  // fake async they never resolve and the test hangs until timeout.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File(
      '${outputDir.path}/$filename',
    ).writeAsBytesSync(byteData!.buffer.asUint8List());
  });
}

Widget _providers({required AppConfig config, required Widget child}) {
  return ProviderScope(
    overrides: [
      configProvider.overrideWith(() => _FakeConfigNotifier(config)),
      analyticsServiceProvider.overrideWithValue(_FakeAnalyticsService()),
      instapaperAuthProvider.overrideWith(
        () => _FakeInstapaperAuth(const InstapaperAuthUnauthenticated()),
      ),
      googleDriveAuthProvider.overrideWith(
        () => _FakeGoogleDriveAuth(const GoogleDriveAuthUnauthenticated()),
      ),
      // Store builds ship with Drive OAuth config; show the source.
      googleDriveAvailableProvider.overrideWithValue(true),
      googleDriveClientProvider.overrideWithValue(_FakeGoogleDriveClient()),
      driveLocalStoreProvider.overrideWithValue(
        DriveLocalStore(rootResolver: () async => null),
      ),
    ],
    child: child,
  );
}

class _FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  _FakeConfigNotifier(this._config);

  final AppConfig _config;

  @override
  Future<AppConfig> build() async => _config;

  @override
  bool hasHintBeenShown(String id) {
    return state.valueOrNull?.shownHints.contains(id) ?? false;
  }

  @override
  Future<void> markHintShown(String id) async {
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(shownHints: {...current.shownHints, id}),
    );
  }

  @override
  Future<void> setHasSeenReadingGoalOnboarding(bool seen) async {
    state = AsyncData(
      state.requireValue.copyWith(hasSeenReadingGoalOnboarding: seen),
    );
  }

  @override
  Future<void> applyReadingGoalPreset(ReadingGoalConfig goal) async {
    state = AsyncData(
      state.requireValue.copyWith(
        defaultWpm: goal.wpm,
        parallaxIntensity: goal.parallaxIntensity,
        readingGoalPreset: goal.preset,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAnalyticsService extends AnalyticsService {
  @override
  Future<ReadingStats> calculateStats() async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return ReadingStats(
      totalSessions: 8,
      totalWordsRead: 12200,
      avgWpm: 310,
      streak: 4,
      totalReadingTime: const Duration(hours: 3, minutes: 20),
      todayReadingTime: const Duration(minutes: 18),
      weekReadingTime: const Duration(hours: 1, minutes: 40),
      readingTimeHistory: [
        for (var i = 6; i >= 0; i--)
          DailyReadingTime(
            date: todayDate.subtract(Duration(days: i)),
            readingTime: Duration(minutes: i.isEven ? 16 : 8),
          ),
      ],
    );
  }
}

class _FakeInstapaperAuth extends InstapaperAuth {
  _FakeInstapaperAuth(this._state);

  final InstapaperAuthState _state;

  @override
  InstapaperAuthState build() => _state;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGoogleDriveAuth extends GoogleDriveAuth {
  _FakeGoogleDriveAuth(this._state);

  final GoogleDriveAuthState _state;

  @override
  GoogleDriveAuthState build() => _state;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGoogleDriveClient implements GoogleDriveClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
