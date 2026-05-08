import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// Semi-transparent reading ruler overlay that highlights the current
/// reading line and dims surrounding content.
///
/// Uses shape + opacity (not color-only) for visibility.
/// Excluded from screen reader semantics to avoid confusing assistive tech.
class ReadingRuler extends StatelessWidget {
  const ReadingRuler({
    super.key,
    required this.visible,
    required this.viewportHeight,
  });

  /// Whether the ruler is visible.
  final bool visible;

  /// The height of the viewport in logical pixels.
  final double viewportHeight;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    const bandHeight = 80.0;
    final bandTop = viewportHeight * 0.4;
    final bandBottom = bandTop + bandHeight;
    final duration = isReducedMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Semantics(
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: duration,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: bandTop,
              child: Container(
                color: RunThruTokens.stageText.withValues(alpha: 0.15),
              ),
            ),
            Positioned(
              top: bandBottom,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: RunThruTokens.stageText.withValues(alpha: 0.15),
              ),
            ),
            Positioned(
              top: bandTop,
              left: 0,
              right: 0,
              height: bandHeight,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: RunThruTokens.shellAccent.withValues(alpha: 0.3),
                      width: 1,
                    ),
                    bottom: BorderSide(
                      color: RunThruTokens.shellAccent.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
