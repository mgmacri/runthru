import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/screens/range_picker_screen.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  @override
  Future<AppConfig> build() async =>
      const AppConfig(hasSeenReadingGoalOnboarding: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Regression (B-02): dispose() used `ref.read`, which Riverpod forbids once
  // the element is unmounting. That threw, skipped the rest of dispose, and
  // leaked the animation controller and notifiers.
  testWidgets('unmounting the range picker does not throw', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [configProvider.overrideWith(_FakeConfigNotifier.new)],
        child: const MaterialApp(
          home: RangePickerScreen(filePath: 'clipboard://test'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });
}
