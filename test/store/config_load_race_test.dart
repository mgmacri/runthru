import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _configKey = 'runthru_config';

Future<AppConfig> _onDisk() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_configKey)!;
  return AppConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
}

void main() {
  group('ConfigNotifier: a change made before the saved settings load', () {
    const saved = AppConfig(
      defaultWpm: 450,
      hasSeenReadingGoalOnboarding: true,
      letterSpacing: 2,
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({
        _configKey: jsonEncode(saved.toJson()),
      });
    });

    test('a purchase delivered at launch keeps the saved settings', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // The store can deliver a purchase the moment the app starts, before
      // anything has waited for the saved settings.
      await container.read(configProvider.notifier).setHasPremium(true);
      final inMemory = await container.read(configProvider.future);

      expect(inMemory.hasPremium, isTrue);
      expect(inMemory.defaultWpm, 450);

      final onDisk = await _onDisk();
      expect(onDisk.hasPremium, isTrue);
      expect(onDisk.defaultWpm, 450);
      expect(onDisk.hasSeenReadingGoalOnboarding, isTrue);
      expect(onDisk.letterSpacing, 2);
    });

    test('the change is still there once loading has finished', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final pending = container
          .read(configProvider.notifier)
          .setHasPremium(true);
      // Let the first load and the change both run to completion.
      await pending;
      await Future<void>.delayed(Duration.zero);

      final settled = container.read(configProvider).requireValue;
      expect(settled.hasPremium, isTrue);
      expect(settled.defaultWpm, 450);
    });
  });
}
