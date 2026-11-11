import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/features/reading/pacing/pacing_config.dart';
import 'package:runthru/store/models.dart';

/// A reading goal sets the speed, the word pacing and (with RunThru Unlock)
/// the 3D room. Settings shows the goal as chosen while those are still its
/// own, and lights Custom only once one of them has been changed by hand.
void main() {
  ReadingGoalConfig goalFor(ReadingGoalPreset preset) =>
      readingGoalConfigs.firstWhere((g) => g.preset == preset);

  List<int> scales(PacingConfig p) => [
    p.longWordScalePercent,
    p.complexWordScalePercent,
    p.punctuationScalePercent,
  ];

  group('choosing a goal', () {
    test('sets speed and word pacing, and keeps free readers flat', () {
      for (final goal in readingGoalConfigs) {
        final config = const AppConfig().withReadingGoal(goal);
        expect(config.readingGoalPreset, goal.preset);
        expect(config.defaultWpm, goal.wpm);
        expect(config.pacingConfig, goal.pacing);
        expect(config.parallaxIntensity, ParallaxIntensity.none);
      }
    });

    test('sets the 3D room for RunThru Unlock owners', () {
      for (final goal in readingGoalConfigs) {
        final config = const AppConfig(hasPremium: true).withReadingGoal(goal);
        expect(config.parallaxIntensity, goal.parallaxIntensity);
      }
    });

    test('a goal just chosen is in effect, with or without Unlock', () {
      // B-54: without Unlock, Settings compared the goal's room with the flat
      // background every free reader has, so no goal ever showed as chosen
      // and Custom stayed lit.
      for (final premium in [false, true]) {
        for (final goal in readingGoalConfigs) {
          final config = AppConfig(
            hasPremium: premium,
            defaultWpm: 512,
            pacingConfig: const PacingConfig(punctuationScalePercent: 175),
            parallaxIntensity: ParallaxIntensity.full,
          ).withReadingGoal(goal);
          final reason = '${goal.name}, Unlock: $premium';
          expect(config.readingGoalInEffect, goal.preset, reason: reason);
          expect(config.readingGoalCustomized, isFalse, reason: reason);
        }
      }
    });

    test(
      'Deep Read gives words more time than Comfortable, Quick Scan less',
      () {
        final deep = scales(goalFor(ReadingGoalPreset.deepRead).pacing);
        final comfortable = goalFor(ReadingGoalPreset.comfortable).pacing;
        final quick = scales(goalFor(ReadingGoalPreset.quickScan).pacing);
        expect(comfortable, defaultPacingConfig);
        for (var i = 0; i < 3; i++) {
          expect(deep[i], greaterThan(scales(comfortable)[i]));
          expect(quick[i], lessThan(scales(comfortable)[i]));
        }
      },
    );

    test('goal pacing sits on the Word Pacing sliders\' steps', () {
      // The sliders run from 25% to 200% in steps of 25. A value between
      // steps would show rounded and turn into Custom at the first touch.
      for (final goal in readingGoalConfigs) {
        for (final value in scales(goal.pacing)) {
          expect(value, inInclusiveRange(25, 200), reason: goal.name);
          expect(value % 25, 0, reason: goal.name);
        }
        expect(
          goal.pacing.longWordDelayMs,
          defaultPacingConfig.longWordDelayMs,
        );
        expect(
          goal.pacing.complexWordDelayMs,
          defaultPacingConfig.complexWordDelayMs,
        );
        expect(
          goal.pacing.punctuationDelayMs,
          defaultPacingConfig.punctuationDelayMs,
        );
      }
    });
  });

  group('Custom', () {
    test('is not lit before a goal is chosen, whatever the settings', () {
      const config = AppConfig(defaultWpm: 275);
      expect(config.readingGoalInEffect, isNull);
      expect(config.readingGoalCustomized, isFalse);
    });

    test('lights up when the speed is changed by hand', () {
      final chosen = const AppConfig().withReadingGoal(
        goalFor(ReadingGoalPreset.comfortable),
      );
      final changed = chosen.copyWith(defaultWpm: 260);
      expect(changed.readingGoalInEffect, isNull);
      expect(changed.readingGoalCustomized, isTrue);
    });

    test('lights up when word pacing is changed by hand', () {
      final chosen = const AppConfig().withReadingGoal(
        goalFor(ReadingGoalPreset.deepRead),
      );
      final changed = chosen.copyWith(
        pacingConfig: chosen.pacingConfig.copyWith(longWordScalePercent: 175),
      );
      expect(changed.readingGoalInEffect, isNull);
      expect(changed.readingGoalCustomized, isTrue);
    });

    test('goes out when the goal is chosen again', () {
      final goal = goalFor(ReadingGoalPreset.quickScan);
      final changed = const AppConfig()
          .withReadingGoal(goal)
          .copyWith(defaultWpm: 400);
      expect(changed.readingGoalCustomized, isTrue);

      final again = changed.withReadingGoal(goal);
      expect(again.readingGoalInEffect, ReadingGoalPreset.quickScan);
      expect(again.readingGoalCustomized, isFalse);
    });

    test('lights up when an Unlock owner picks another 3D room', () {
      final chosen = const AppConfig(
        hasPremium: true,
      ).withReadingGoal(goalFor(ReadingGoalPreset.comfortable));
      expect(chosen.parallaxIntensity, ParallaxIntensity.subtle);
      for (final room in [ParallaxIntensity.off, ParallaxIntensity.full]) {
        final changed = chosen.copyWith(parallaxIntensity: room);
        expect(changed.readingGoalCustomized, isTrue, reason: room.name);
      }
    });

    test('stays out after Unlock is bought or restored with a goal chosen', () {
      // Chosen while free, so the room is flat; Unlock arrives later and
      // leaves the room as it was.
      final owner = const AppConfig()
          .withReadingGoal(goalFor(ReadingGoalPreset.comfortable))
          .copyWith(hasPremium: true);
      expect(owner.parallaxIntensity, ParallaxIntensity.none);
      expect(owner.readingGoalInEffect, ReadingGoalPreset.comfortable);
      expect(owner.readingGoalCustomized, isFalse);
    });
  });
}
