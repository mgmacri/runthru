import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';

/// Callback types for the three actions on the finished range overlay.
typedef OnContinueReading = void Function();
typedef OnSetNewRange = void Function();
typedef OnGoToLibrary = void Function();

/// Overlay displayed when the user reaches the end of their reading range.
/// Shows stats and provides Continue / Set New Range / Library options.
class FinishedRangeOverlay extends StatefulWidget {
  const FinishedRangeOverlay({
    super.key,
    required this.visible,
    required this.startPage,
    required this.endPage,
    required this.wordCount,
    required this.averageWpm,
    required this.onContinueReading,
    required this.onSetNewRange,
    required this.onGoToLibrary,
  });

  final bool visible;
  final int startPage;
  final int endPage;
  final int wordCount;
  final int averageWpm;
  final OnContinueReading onContinueReading;
  final OnSetNewRange onSetNewRange;
  final OnGoToLibrary onGoToLibrary;

  @override
  State<FinishedRangeOverlay> createState() => _FinishedRangeOverlayState();
}

class _FinishedRangeOverlayState extends State<FinishedRangeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.dialEmergeDuration,
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    if (widget.visible) _show();
  }

  @override
  void didUpdateWidget(FinishedRangeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _show();
    } else if (!widget.visible && oldWidget.visible) {
      _hide();
    }
  }

  void _show() {
    final reducedMotion = isReducedMotion(context);
    if (reducedMotion) {
      _controller.value = 1.0;
    } else {
      _controller.forward(from: 0);
    }
  }

  void _hide() {
    final reducedMotion = isReducedMotion(context);
    if (reducedMotion) {
      _controller.value = 0.0;
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_fadeAnimation.value == 0) return const SizedBox.shrink();

        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Center(
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
                    // Checkmark + title.
                    const Icon(
                      Icons.check_circle_outline,
                      color: SpeedyBoyTokens.shellReady,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Range Complete',
                      style: SpeedyBoyTypography.title,
                    ),
                    const SizedBox(height: 16),

                    // Stats.
                    Text(
                      'Pages ${widget.startPage + 1}\u2013${widget.endPage + 1}'
                      '  \u00B7  '
                      '${_formatWordCount(widget.wordCount)} words',
                      style: SpeedyBoyTypography.body.copyWith(
                        color: SpeedyBoyTokens.shellTextSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.averageWpm > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Average: ${widget.averageWpm} WPM',
                          style: SpeedyBoyTypography.caption,
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Continue Reading button (primary).
                    _ActionButton(
                      label: 'Continue Reading  \u2192',
                      isPrimary: true,
                      onTap: widget.onContinueReading,
                    ),
                    const SizedBox(height: 12),

                    // Set New Range + Library (secondary row).
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            label: 'Set New Range',
                            onTap: widget.onSetNewRange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ActionButton(
                            label: 'Library',
                            onTap: widget.onGoToLibrary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatWordCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: SpeedyBoyDecorations.pillDecoration(
          SpeedyBoySurface.shell,
        ),
        child: Text(
          label,
          style: SpeedyBoyTypography.body.copyWith(
            color: isPrimary
                ? SpeedyBoyTokens.shellAccent
                : SpeedyBoyTokens.shellTextPrimary,
            fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
