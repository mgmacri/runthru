import 'package:runthru/features/reading/pacing/pacing_config.dart';
import 'package:runthru/store/models.dart';

/// Configuration for a reading goal preset.
///
/// Presets are presented as reading intentions (Deep Read, Comfortable,
/// Quick Scan) — NOT speed tiers (Slow, Medium, Fast). Each one sets the
/// speed, the word pacing and, for RunThru Unlock owners, the 3D room.
class ReadingGoalConfig {
  const ReadingGoalConfig({
    required this.preset,
    required this.name,
    required this.description,
    required this.wpm,
    required this.pacing,
    required this.parallaxIntensity,
  });

  final ReadingGoalPreset preset;
  final String name;
  final String description;
  final int wpm;

  /// How much extra time long words, complex words and punctuation get.
  /// The values sit on the Word Pacing sliders' 25% steps.
  final PacingConfig pacing;

  final ParallaxIntensity parallaxIntensity;
}

/// The 3 canonical reading goal presets.
// P8 Grade B — reading intentions, not speed tiers
const List<ReadingGoalConfig> readingGoalConfigs = [
  ReadingGoalConfig(
    preset: ReadingGoalPreset.deepRead,
    name: 'Deep Read',
    description: 'Take your time with difficult material.',
    wpm: 200,
    // Difficult material: half as much again for long words, complex words
    // and the pause at punctuation.
    pacing: PacingConfig(
      longWordScalePercent: 150,
      complexWordScalePercent: 150,
      punctuationScalePercent: 150,
    ),
    parallaxIntensity: ParallaxIntensity.subtle,
  ),
  ReadingGoalConfig(
    preset: ReadingGoalPreset.comfortable,
    name: 'Comfortable',
    description: 'Your everyday reading pace.',
    wpm: 250,
    pacing: defaultPacingConfig,
    parallaxIntensity: ParallaxIntensity.subtle,
  ),
  ReadingGoalConfig(
    preset: ReadingGoalPreset.quickScan,
    name: 'Quick Scan',
    description: 'Get the gist of material you already know.',
    wpm: 350,
    // Familiar material: half the usual extra time, so the pace stays even.
    pacing: PacingConfig(
      longWordScalePercent: 50,
      complexWordScalePercent: 50,
      punctuationScalePercent: 50,
    ),
    parallaxIntensity: ParallaxIntensity.off,
  ),
];

/// The settings a reading goal sets, and whether they are still the goal's.
///
/// Choosing a goal and checking it use the same rules, so a goal the reader
/// has just chosen always shows as chosen.
extension ReadingGoalSettings on AppConfig {
  /// This config with [goal] chosen: its speed and word pacing, and its 3D
  /// room for RunThru Unlock owners.
  AppConfig withReadingGoal(ReadingGoalConfig goal) => copyWith(
    readingGoalPreset: goal.preset,
    defaultWpm: goal.wpm,
    pacingConfig: goal.pacing,
    // The 3D room is part of RunThru Unlock; free users stay flat.
    parallaxIntensity: hasPremium
        ? goal.parallaxIntensity
        : ParallaxIntensity.none,
  );

  /// The chosen reading goal while every setting it sets is still its own.
  /// Null when no goal has been chosen, or one of them was changed by hand.
  ReadingGoalPreset? get readingGoalInEffect {
    final preset = readingGoalPreset;
    if (preset == null) return null;
    final goal = readingGoalConfigs.firstWhere((c) => c.preset == preset);
    return _keeps(goal) ? preset : null;
  }

  /// True when a reading goal was chosen and a setting it sets has been
  /// changed by hand since. Never true before a goal is chosen.
  bool get readingGoalCustomized =>
      readingGoalPreset != null && readingGoalInEffect == null;

  bool _keeps(ReadingGoalConfig goal) =>
      defaultWpm == goal.wpm &&
      pacingConfig == goal.pacing &&
      // The flat background keeps any goal: it is all a reader without
      // RunThru Unlock has, and where an owner starts after buying or
      // restoring Unlock, so it is never a change made by hand.
      (parallaxIntensity == ParallaxIntensity.none ||
          parallaxIntensity == goal.parallaxIntensity);
}
