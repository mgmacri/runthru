import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// Reusable hint overlay pill for onboarding gesture hints (Rule 27).
///
/// Displays a semi-transparent pill with white text that slides in from
/// [slideFrom], auto-dismisses after [RunThruTiming.hintAutoDismissMs],
/// and can be dismissed immediately by any touch.
///
/// When `isReducedMotion(context)` is true, the slide-in animation is
/// skipped — the pill appears and disappears instantly (Rule 5).
class HintOverlay extends StatefulWidget {
  const HintOverlay({
    super.key,
    required this.text,
    required this.position,
    required this.slideFrom,
    required this.onDismiss,
  });

  /// Hint message text displayed inside the pill.
  final String text;

  /// Where on screen the pill is positioned.
  final Alignment position;

  /// Direction the pill slides in from during the entrance animation.
  final AxisDirection slideFrom;

  /// Called when the hint is dismissed (by touch or auto-dismiss timer).
  final VoidCallback onDismiss;

  @override
  State<HintOverlay> createState() => _HintOverlayState();
}

class _HintOverlayState extends State<HintOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: RunThruTiming.hintSlideInMs),
    );

    _slideAnimation = Tween<Offset>(
      begin: _beginOffset(),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    // Start auto-dismiss timer.
    // P6 Grade D — auto-dismiss after 4 seconds
    _autoDismissTimer = Timer(
      const Duration(milliseconds: RunThruTiming.hintAutoDismissMs),
      _dismiss,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rule 5 — skip slide animation if reduced motion is enabled.
    if (isReducedMotion(context)) {
      _slideController.value = 1.0;
    } else {
      _slideController.forward();
    }
  }

  Offset _beginOffset() {
    return switch (widget.slideFrom) {
      AxisDirection.up => const Offset(0, -1),
      AxisDirection.down => const Offset(0, 1),
      AxisDirection.left => const Offset(-1, 0),
      AxisDirection.right => const Offset(1, 0),
    };
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    widget.onDismiss();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismiss,
        child: Align(
          alignment: widget.position,
          child: SlideTransition(
            position: _slideAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Semantics(
                liveRegion: true,
                label: widget.text,
                child: DecoratedBox(
                  // P6 Grade D — 60% black background pill
                  decoration: BoxDecoration(
                    color: RunThruTokens.shellTextPrimary.withAlpha(153),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Text(
                      widget.text,
                      style: RunThruTypography.body.copyWith(
                        color: RunThruTokens.shellBase,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
