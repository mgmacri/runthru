import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/providers/reading_mode_provider.dart';

/// A compact chip-style button that cycles between reading modes.
///
/// Displays the current mode icon and short label. Positioned by
/// the parent (reading screen) — this widget does not position itself.
class ModeSwitcher extends ConsumerWidget {
  /// Creates a [ModeSwitcher].
  const ModeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(readingModeNotifierProvider);

    final (IconData icon, String label) = switch (mode) {
      ReadingMode.rsvp => (Icons.text_fields, 'Word'),
      ReadingMode.sentence => (Icons.short_text, 'Sentence'),
      ReadingMode.paragraph => (Icons.subject, 'Paragraph'),
    };

    return Semantics(
      button: true,
      label: 'Reading mode: ${mode.name}. Tap to switch.',
      child: GestureDetector(
        onTap: () => ref.read(readingModeNotifierProvider.notifier).cycleMode(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: RunThruDecorations.raisedDecoration(
              RunThruSurface.shell,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: RunThruTokens.stageText),
                const SizedBox(width: 6),
                Text(label, style: RunThruTypography.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
