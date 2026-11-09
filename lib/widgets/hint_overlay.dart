import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// Reusable coach-card overlay for onboarding gesture hints.
///
/// Displays a designer-styled tooltip card that slides in from [slideFrom],
/// auto-dismisses after [RunThruTiming.hintAutoDismissMs], and provides a
/// small manual dismiss target.
///
/// The card itself is wrapped in [IgnorePointer] so reading gestures pass
/// through the overlay. Only the dismiss button participates in hit testing.
/// When `isReducedMotion(context)` is true, movement and fades are skipped.
class HintOverlay extends StatefulWidget {
  const HintOverlay({
    super.key,
    required this.text,
    required this.position,
    required this.slideFrom,
    required this.onDismiss,
    this.eyebrow = 'Reading hint',
    this.dismissLabel = 'Dismiss hint',
  });

  /// Hint message text displayed inside the tooltip.
  final String text;

  /// Short label displayed above [text].
  final String eyebrow;

  /// Where on screen the tooltip is positioned.
  final Alignment position;

  /// Direction the tooltip slides in from during the entrance animation.
  final AxisDirection slideFrom;

  /// Called when the hint is dismissed.
  final VoidCallback onDismiss;

  /// Accessibility label for the manual dismiss control.
  final String dismissLabel;

  @override
  State<HintOverlay> createState() => _HintOverlayState();
}

class _HintOverlayState extends State<HintOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: RunThruTiming.hintSlideInMs),
    );

    _slideAnimation = Tween<Offset>(
      begin: _beginOffset(),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _autoDismissTimer = Timer(
      const Duration(milliseconds: RunThruTiming.hintAutoDismissMs),
      _dismiss,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (isReducedMotion(context)) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = isReducedMotion(context);
    final slide = reduced
        ? const AlwaysStoppedAnimation(Offset.zero)
        : _slideAnimation;
    final fade = reduced ? const AlwaysStoppedAnimation(1.0) : _fadeAnimation;

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: widget.position,
                child: SlideTransition(
                  position: slide,
                  child: FadeTransition(
                    opacity: fade,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      child: _HintCard(
                        text: widget.text,
                        eyebrow: widget.eyebrow,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Semantics(
                liveRegion: true,
                label: '${widget.eyebrow}. ${widget.text}',
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: widget.position,
              child: SlideTransition(
                position: slide,
                child: FadeTransition(
                  opacity: fade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: SizedBox(
                      width: 304,
                      height: 96,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Semantics(
                          button: true,
                          label: widget.dismissLabel,
                          // Flat icon — no raised surface, stays inside the
                          // card's bounds.
                          child: IconButton(
                            tooltip: widget.dismissLabel,
                            onPressed: _dismiss,
                            icon: const Icon(Icons.close_rounded),
                            color: RunThruTokens.shellInkSoft,
                            iconSize: 18,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              tapTargetSize: MaterialTapTargetSize.padded,
                              backgroundColor: Colors.transparent,
                              overlayColor: RunThruTokens.shellSandHi,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.text, required this.eyebrow});

  final String text;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 304, minHeight: 86),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -7,
            child: Transform.rotate(
              angle: 0.785398,
              child: DecoratedBox(
                key: const ValueKey('hint-tooltip-pointer'),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFECE3CF), Color(0xFFDDD4BF)],
                  ),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: RunThruTokens.shellCream.withValues(alpha: 0.48),
                      offset: const Offset(-2, -2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const SizedBox(width: 16, height: 16),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFECE3CF), Color(0xFFDDD4BF)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: RunThruTokens.shellTeal.withValues(alpha: 0.32),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: RunThruTokens.shellCream.withValues(alpha: 0.64),
                  offset: const Offset(-6, -6),
                  blurRadius: 14,
                ),
                BoxShadow(
                  color: const Color(0xFF3C301C).withValues(alpha: 0.34),
                  offset: const Offset(8, 9),
                  blurRadius: 22,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 48, 15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: RunThruTokens.shellTealTint,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: RunThruTokens.shellTeal.withValues(alpha: 0.30),
                        width: 1.2,
                      ),
                    ),
                    child: const Icon(
                      Icons.touch_app_outlined,
                      color: RunThruTokens.shellTealDeep,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow.toUpperCase(),
                          style: RunThruTypography.tinyLabel.copyWith(
                            color: RunThruTokens.shellTealDeep,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          text,
                          style: RunThruTypography.body.copyWith(
                            color: RunThruTokens.shellInk,
                            fontWeight: FontWeight.w800,
                            height: 1.28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
