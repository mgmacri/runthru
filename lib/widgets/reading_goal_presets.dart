import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/store/models.dart';

/// Displays the 3 reading goal preset cards.
///
/// Cards use shell surface tokens (Rule 7). Each card shows name,
/// description, and WPM. On tap, [onSelected] fires with the chosen config.
///
/// Supports keyboard navigation: arrow keys move focus, Enter/Space selects.
class ReadingGoalPresets extends StatefulWidget {
  const ReadingGoalPresets({super.key, required this.onSelected});

  /// Called when the user taps a preset card.
  final void Function(ReadingGoalConfig config) onSelected;

  @override
  State<ReadingGoalPresets> createState() => _ReadingGoalPresetsState();
}

class _ReadingGoalPresetsState extends State<ReadingGoalPresets> {
  int _focusedIndex = 1; // Default focus on "Comfortable"
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _moveFocus(int delta) {
    setState(() {
      _focusedIndex = (_focusedIndex + delta).clamp(
        0,
        readingGoalConfigs.length - 1,
      );
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _moveFocus(-1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _moveFocus(1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      widget.onSelected(readingGoalConfigs[_focusedIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = isReducedMotion(context);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 620;
          final cards = List.generate(readingGoalConfigs.length, (index) {
            final config = readingGoalConfigs[index];
            final isFocused = index == _focusedIndex;
            return _ReadingGoalPresetCard(
              config: config,
              isFocused: isFocused,
              reducedMotion: reduced,
              onTap: () => widget.onSelected(config),
            );
          });

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  Expanded(child: cards[i]),
                  if (i != cards.length - 1) const SizedBox(width: 12),
                ],
              ],
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ReadingGoalPresetCard extends StatelessWidget {
  const _ReadingGoalPresetCard({
    required this.config,
    required this.isFocused,
    required this.reducedMotion,
    required this.onTap,
  });

  final ReadingGoalConfig config;
  final bool isFocused;
  final bool reducedMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = switch (config.preset) {
      ReadingGoalPreset.deepRead => const Color(0xFF46776B),
      ReadingGoalPreset.comfortable => const Color(0xFFC48B2E),
      ReadingGoalPreset.quickScan => const Color(0xFFBF4733),
    };
    final icon = switch (config.preset) {
      ReadingGoalPreset.deepRead => Icons.auto_stories_outlined,
      ReadingGoalPreset.comfortable => Icons.spa_outlined,
      ReadingGoalPreset.quickScan => Icons.bolt_rounded,
    };

    return Semantics(
      label:
          '${config.name}, ${config.wpm} words per minute, '
          '${config.description}',
      button: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 88),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  RunThruTokens.shellSandHi,
                  RunThruTokens.shellSandDeep,
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isFocused ? accent : RunThruTokens.shellSandHi,
                width: isFocused ? 1.8 : 0.7,
              ),
              boxShadow: [
                BoxShadow(
                  color: RunThruTokens.shellCream.withValues(alpha: 0.72),
                  offset: const Offset(-5, -5),
                  blurRadius: 12,
                ),
                BoxShadow(
                  color: RunThruTokens.shellSandDeep.withValues(alpha: 0.88),
                  offset: const Offset(6, 7),
                  blurRadius: isFocused ? 18 : 12,
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.30),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(icon, color: accent, size: 23),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              config.name,
                              style: RunThruTypography.title.copyWith(
                                color: RunThruTokens.shellInk,
                                fontWeight: FontWeight.w800,
                                height: 1.12,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.24),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                '${config.wpm} WPM',
                                style: RunThruTypography.tinyLabel.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          config.description,
                          style: RunThruTypography.body.copyWith(
                            color: RunThruTokens.shellInkSoft,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
