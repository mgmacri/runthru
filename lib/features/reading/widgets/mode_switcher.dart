import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/providers/reading_mode_provider.dart';

/// A compact pill button that opens the reading-mode popover.
///
/// Styled after the design spec's ModePill (modes-views.jsx): raised sand
/// pill with teal icon + label, opening a rounded popover where the active
/// mode sits on a teal-tint row with a trailing check.
class ModeSwitcher extends ConsumerWidget {
  /// Creates a [ModeSwitcher].
  const ModeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(readingModeNotifierProvider);

    final current = _modeMeta(mode);

    return Semantics(
      button: true,
      label: 'Reading mode: ${current.label}. Tap to choose mode.',
      child: PopupMenuButton<ReadingMode>(
        tooltip: 'Reading mode',
        color: RunThruTokens.shellSandHi,
        elevation: 10,
        shadowColor: RunThruTokens.shellSandDeep,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        offset: const Offset(0, 50),
        menuPadding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 180),
        onSelected: (selected) =>
            ref.read(readingModeNotifierProvider.notifier).setMode(selected),
        itemBuilder: (context) => [
          for (final itemMode in availableReadingModes)
            PopupMenuItem<ReadingMode>(
              value: itemMode,
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: _ModeMenuItem(
                meta: _modeMeta(itemMode),
                selected: itemMode == mode,
              ),
            ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: DecoratedBox(
            decoration: RunThruDecorations.raisedDecoration(
              RunThruSurface.stage,
              size: RunThruShadowSize.small,
              borderRadius: 999,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(current.icon, size: 17, color: RunThruTokens.shellTeal),
                  const SizedBox(width: 7),
                  Text(
                    current.label,
                    style: RunThruTypography.rowTitle.copyWith(
                      color: RunThruTokens.shellTealDeep,
                      fontSize: 14,
                    ),
                    textScaler: TextScaler.noScaling,
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 15,
                    color: RunThruTokens.shellTealDeep.withValues(alpha: 0.55),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeMenuItem extends StatelessWidget {
  const _ModeMenuItem({required this.meta, required this.selected});

  final _ModeMeta meta;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? RunThruTokens.shellTealTint : null,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(
            meta.icon,
            size: 17,
            color: selected
                ? RunThruTokens.shellTeal
                : RunThruTokens.shellInkFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              meta.label,
              style: RunThruTypography.rowTitle.copyWith(
                fontSize: 14.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected
                    ? RunThruTokens.shellTealDeep
                    : RunThruTokens.shellInkSoft,
              ),
              textScaler: TextScaler.noScaling,
            ),
          ),
          if (selected)
            const Icon(
              Icons.check_rounded,
              size: 16,
              color: RunThruTokens.shellTealDeep,
            ),
        ],
      ),
    );
  }
}

typedef _ModeMeta = ({IconData icon, String label});

_ModeMeta _modeMeta(ReadingMode mode) => switch (mode) {
  ReadingMode.singleWord => (icon: Icons.text_fields_rounded, label: 'Word'),
  ReadingMode.sentence => (icon: Icons.short_text_rounded, label: 'Sentence'),
  ReadingMode.paragraph => (icon: Icons.subject_rounded, label: 'Paragraph'),
  ReadingMode.fullPage => (icon: Icons.article_outlined, label: 'Full Page'),
};
