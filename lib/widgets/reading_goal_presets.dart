import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speedy_boy/core/reading_goal_presets.dart';
import 'package:speedy_boy/design/design.dart';

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
      _focusedIndex =
          (_focusedIndex + delta).clamp(0, readingGoalConfigs.length - 1);
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
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(readingGoalConfigs.length, (index) {
          final config = readingGoalConfigs[index];
          final isFocused = index == _focusedIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Semantics(
              label: '${config.name}, ${config.wpm} words per minute, '
                  '${config.description}',
              button: true,
              child: GestureDetector(
                onTap: () => widget.onSelected(config),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: SpeedyBoyDecorations.raisedDecoration(
                    SpeedyBoySurface.shell,
                    size: isFocused
                        ? SpeedyBoyShadowSize.large
                        : SpeedyBoyShadowSize.standard,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ExcludeSemantics(
                            child: Text(
                              config.name,
                              style: SpeedyBoyTypography.title.copyWith(
                                color: SpeedyBoyTokens.shellTextPrimary,
                              ),
                            ),
                          ),
                          ExcludeSemantics(
                            child: Text(
                              '${config.wpm} WPM',
                              style: SpeedyBoyTypography.caption.copyWith(
                                color: SpeedyBoyTokens.shellAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ExcludeSemantics(
                        child: Text(
                          config.description,
                          style: SpeedyBoyTypography.body.copyWith(
                            color: SpeedyBoyTokens.shellTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
