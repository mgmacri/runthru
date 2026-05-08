import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/neumorphic_card.dart';

/// Adaptive spacing controls for reading accessibility.
///
/// Provides sliders for letter spacing, word spacing, and a
/// toggle for the reading ruler overlay. All controls are free
/// (never paywalled per project ethical commitment).
class SpacingControls extends ConsumerWidget {
  const SpacingControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(
      configProvider.select((ac) => ac.valueOrNull ?? const AppConfig()),
    );
    final notifier = ref.read(configProvider.notifier);

    return NeumorphicCard(
      surface: RunThruSurface.shell,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reading Comfort', style: RunThruTypography.title),
            const SizedBox(height: 20),
            Semantics(
              label: 'Letter spacing, currently ${config.letterSpacing} pixels',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Slider(
                    value: config.letterSpacing,
                    min: 0.0,
                    max: 5.0,
                    divisions: 10,
                    label:
                        'Letter spacing: ${config.letterSpacing.toStringAsFixed(1)}',
                    onChanged: notifier.setLetterSpacing,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                    child: Text(
                      'Letter spacing: ${config.letterSpacing.toStringAsFixed(1)}',
                      style: RunThruTypography.body,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Word spacing, currently ${config.wordSpacing} pixels',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Slider(
                    value: config.wordSpacing,
                    min: 0.0,
                    max: 20.0,
                    divisions: 20,
                    label:
                        'Word spacing: ${config.wordSpacing.toStringAsFixed(1)}',
                    onChanged: notifier.setWordSpacing,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                    child: Text(
                      'Word spacing: ${config.wordSpacing.toStringAsFixed(1)}',
                      style: RunThruTypography.body,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label:
                  'Reading ruler, currently ${config.readingRulerEnabled ? "on" : "off"}',
              child: Row(
                children: [
                  Switch.adaptive(
                    value: config.readingRulerEnabled,
                    onChanged: notifier.setReadingRulerEnabled,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Show reading ruler',
                    style: RunThruTypography.body,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: RunThruTokens.shellAccent,
                  foregroundColor: RunThruTokens.shellBase,
                  minimumSize: const Size(0, 48),
                ),
                onPressed: () {
                  notifier.setLetterSpacing(0.0);
                  notifier.setWordSpacing(0.0);
                  notifier.setReadingRulerEnabled(false);
                },
                child: const Text('Reset to defaults'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
