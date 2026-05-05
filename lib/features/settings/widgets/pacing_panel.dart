import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/pacing/pacing_config.dart';
import 'package:runthru/features/reading/pacing/word_duration.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/widgets/neumorphic_card.dart';

/// Sample paragraph used for the live pacing preview.
const _sampleWords = [
  'The',
  'quick',
  'brown',
  'fox',
  'jumps',
  'over',
  'the',
  'lazy',
  'dog.',
  'NASA',
  'launched',
  'information',
  'about',
  'U.S.',
  'policy,',
  'well-known',
  'and',
  'verified.',
];

/// Settings panel for per-word adaptive pacing configuration.
///
/// Provides three independent scale sliders (long words, complexity,
/// punctuation) plus a live preview showing computed total time for a
/// sample paragraph. Part of M1.2.5 Pacing Engine milestone.
class PacingPanel extends ConsumerWidget {
  /// Creates a [PacingPanel].
  const PacingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(configProvider);
    final config = configAsync.valueOrNull;
    if (config == null) return const SizedBox.shrink();

    final pacingConfig = config.pacingConfig;
    final notifier = ref.read(configProvider.notifier);
    final baseIntervalMs = (60000 / config.defaultWpm).round();

    return NeumorphicCard(
      surface: RunThruSurface.shell,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Word Pacing', style: RunThruTypography.title),
              ),
              Semantics(
                label: 'About word pacing',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.info_outline, size: 20),
                  color: RunThruTokens.shellTextSecondary,
                  tooltip: 'About word pacing',
                  onPressed: () => _showAboutSheet(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Give longer, complex, and punctuated words extra time.',
            style: RunThruTypography.caption.copyWith(
              color: RunThruTokens.shellTextSecondary,
            ),
          ),
          const SizedBox(height: 12),

          // ── Live Preview ──
          _PacingPreview(
            pacingConfig: pacingConfig,
            baseIntervalMs: baseIntervalMs,
            wpm: config.defaultWpm,
          ),
          const SizedBox(height: 16),

          // ── Long Words Slider ──
          _PacingSlider(
            label: 'Long words',
            icon: Icons.text_fields,
            value: pacingConfig.longWordScalePercent,
            onChanged: (v) => notifier.updatePacingConfig(
              pacingConfig.copyWith(longWordScalePercent: v),
            ),
          ),
          const SizedBox(height: 12),

          // ── Complexity Slider ──
          _PacingSlider(
            label: 'Complexity',
            icon: Icons.psychology_outlined,
            value: pacingConfig.complexWordScalePercent,
            onChanged: (v) => notifier.updatePacingConfig(
              pacingConfig.copyWith(complexWordScalePercent: v),
            ),
          ),
          const SizedBox(height: 12),

          // ── Punctuation Slider ──
          _PacingSlider(
            label: 'Punctuation',
            icon: Icons.more_horiz,
            value: pacingConfig.punctuationScalePercent,
            onChanged: (v) => notifier.updatePacingConfig(
              pacingConfig.copyWith(punctuationScalePercent: v),
            ),
          ),
          const SizedBox(height: 16),

          // ── Reset Button ──
          Center(
            child: Semantics(
              label: 'Reset all pacing scales to default',
              button: true,
              child: TextButton.icon(
                onPressed: pacingConfig == defaultPacingConfig
                    ? null
                    : () => notifier.updatePacingConfig(defaultPacingConfig),
                icon: const Icon(Icons.replay, size: 18),
                label: const Text('Reset pacing'),
                style: TextButton.styleFrom(
                  foregroundColor: RunThruTokens.shellAccent,
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RunThruTokens.shellBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('About Word Pacing', style: RunThruTypography.title),
            const SizedBox(height: 12),
            Text(
              'Long words, complex words, and punctuation get extra display '
              'time so you can absorb each word naturally.\n\n'
              'Set each category to 25% (minimum) to nearly disable its '
              'bonus, or 200% to emphasise it. The default is 100% — a '
              'balanced starting point.\n\n'
              'This is not speed-reading — it\'s giving every word the time '
              'it deserves.',
              style: RunThruTypography.body.copyWith(
                color: RunThruTokens.shellTextPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: RunThruTokens.shellAccent,
                  minimumSize: const Size(48, 48),
                ),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays computed total time for the sample paragraph.
class _PacingPreview extends StatelessWidget {
  const _PacingPreview({
    required this.pacingConfig,
    required this.baseIntervalMs,
    required this.wpm,
  });

  final PacingConfig pacingConfig;
  final int baseIntervalMs;
  final int wpm;

  @override
  Widget build(BuildContext context) {
    var totalMs = 0;
    for (var i = 0; i < _sampleWords.length; i++) {
      final next = i + 1 < _sampleWords.length ? _sampleWords[i + 1] : null;
      totalMs += durationForWord(
        _sampleWords[i],
        nextWord: next,
        baseIntervalMs: baseIntervalMs,
        config: pacingConfig,
      );
    }
    final seconds = (totalMs / 1000).toStringAsFixed(1);

    return Semantics(
      label: 'Sample paragraph takes $seconds seconds at $wpm words per minute',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: RunThruTokens.stageBase,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.timer_outlined,
              size: 18,
              color: RunThruTokens.stageText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sample paragraph: ${seconds}s at $wpm WPM',
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.stageText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labeled slider for a pacing scale value (25–200%).
class _PacingSlider extends StatelessWidget {
  const _PacingSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: RunThruTokens.shellTextSecondary),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: RunThruTypography.body)),
            // Numeric label (no color-only signal — Rule 11)
            Semantics(
              label: '$label scale: $value percent',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: RunThruTokens.shellAccent.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$value%',
                  style: RunThruTypography.caption.copyWith(
                    color: RunThruTokens.shellAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Semantics(
          label: '$label pacing scale',
          slider: true,
          value: '$value percent',
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: RunThruTokens.shellAccent,
              inactiveTrackColor: RunThruTokens.shellDarkShadow,
              thumbColor: RunThruTokens.shellAccent,
              overlayColor: RunThruTokens.shellAccent.withAlpha(40),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              min: 25,
              max: 200,
              divisions: 7,
              value: value.toDouble(),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
      ],
    );
  }
}
