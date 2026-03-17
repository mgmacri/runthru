import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';

/// Shows the "Are you sure?" modal when the user changes a reading range
/// while they have existing progress.
///
/// Returns `true` if the user confirmed, `false` if they cancelled.
Future<bool> showRangeConfirmationModal({
  required BuildContext context,
  required int currentPage,
  required String currentWord,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss range confirmation',
    barrierColor: SpeedyBoyTokens.shellDarkShadow.withValues(alpha: 0.5),
    transitionDuration: SpeedyBoyAnimations.dialEmergeDuration,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final reducedMotion = isReducedMotion(context);
      if (reducedMotion) return child;

      final scaleAnimation = Tween<double>(
        begin: 0.8,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
      final fadeAnimation = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

      return FadeTransition(
        opacity: fadeAnimation,
        child: ScaleTransition(scale: scaleAnimation, child: child),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return Center(
        child: _RangeConfirmationCard(
          currentPage: currentPage,
          currentWord: currentWord,
        ),
      );
    },
  );
  return result ?? false;
}

class _RangeConfirmationCard extends StatelessWidget {
  const _RangeConfirmationCard({
    required this.currentPage,
    required this.currentWord,
  });

  final int currentPage;
  final String currentWord;

  @override
  Widget build(BuildContext context) {
    final wordDisplay = currentWord.isNotEmpty ? ", word '$currentWord'" : '';

    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: SpeedyBoyDecorations.raisedDecoration(
          SpeedyBoySurface.shell,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You have progress saved at page $currentPage$wordDisplay.',
              style: SpeedyBoyTypography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Setting a new range will reset your position to the new start.',
              style: SpeedyBoyTypography.body.copyWith(
                color: SpeedyBoyTokens.shellTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: SpeedyBoyDecorations.pillDecoration(
                      SpeedyBoySurface.shell,
                    ),
                    child: const Text(
                      'Cancel',
                      style: SpeedyBoyTypography.body,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: SpeedyBoyDecorations.pillDecoration(
                      SpeedyBoySurface.shell,
                    ),
                    child: Text(
                      "I'm Sure",
                      style: SpeedyBoyTypography.body.copyWith(
                        color: SpeedyBoyTokens.shellAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
