import 'package:speedy_boy/store/models.dart';

/// Configuration for a reading goal preset.
///
/// Presets are presented as reading intentions (Deep Read, Comfortable,
/// Quick Scan) — NOT speed tiers (Slow, Medium, Fast).
class ReadingGoalConfig {
  const ReadingGoalConfig({
    required this.preset,
    required this.name,
    required this.description,
    required this.wpm,
    required this.parallaxIntensity,
  });

  final ReadingGoalPreset preset;
  final String name;
  final String description;
  final int wpm;
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
    parallaxIntensity: ParallaxIntensity.subtle,
  ),
  ReadingGoalConfig(
    preset: ReadingGoalPreset.comfortable,
    name: 'Comfortable',
    description: 'Your everyday reading pace.',
    wpm: 250,
    parallaxIntensity: ParallaxIntensity.subtle,
  ),
  ReadingGoalConfig(
    preset: ReadingGoalPreset.quickScan,
    name: 'Quick Scan',
    description: 'Get the gist of material you already know.',
    wpm: 350,
    parallaxIntensity: ParallaxIntensity.off,
  ),
];
