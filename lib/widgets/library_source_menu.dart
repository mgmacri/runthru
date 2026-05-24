/// Library source menu — a single bottom-right neumorphic `+` entry point that
/// reveals reading-source actions as a right-leaning, cascading stack of
/// embossed cards.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runthru/design/design.dart';

/// One source action exposed in the cascading stack.
class LibrarySourceAction {
  const LibrarySourceAction({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticsLabel;
  final VoidCallback onTap;
}

/// Bottom-right `+` source menu for the Library screen.
///
/// Renders absolutely positioned content (a backdrop, the cascading stack of
/// source cards, and the `+` button) — host it inside a [Stack] that fills the
/// screen.
class LibrarySourceMenu extends StatefulWidget {
  const LibrarySourceMenu({
    super.key,
    required this.actions,
    this.bottomInset = 24,
    this.rightInset = 24,
  });

  /// Ordered actions to render in the stack. Index 0 sits closest to the `+`.
  final List<LibrarySourceAction> actions;

  /// Distance of the `+` button from the bottom edge.
  final double bottomInset;

  /// Distance of the `+` button from the right edge.
  final double rightInset;

  @override
  State<LibrarySourceMenu> createState() => _LibrarySourceMenuState();
}

class _LibrarySourceMenuState extends State<LibrarySourceMenu>
    with SingleTickerProviderStateMixin {
  /// Duration of a single card emerging.
  static const Duration _cardDuration = Duration(milliseconds: 240);

  late final AnimationController _controller;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _resolvedDuration(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    final reduced = isReducedMotion(context);
    _controller.duration = reduced ? Duration.zero : _resolvedDuration();
    if (_open) {
      HapticFeedback.selectionClick();
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  /// Total open duration = last card's start + one card duration.
  /// Each card starts at 50% of the previous card's duration, so the last
  /// card (index n-1) starts at (n-1) * 0.5 * cardDuration.
  Duration _resolvedDuration() {
    final n = widget.actions.length;
    final totalMs =
        (_cardDuration.inMilliseconds * (1 + 0.5 * (n - 1).clamp(0, n)))
            .round();
    return Duration(milliseconds: totalMs);
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _controller.reverse();
  }

  void _runAction(LibrarySourceAction action) {
    _close();
    action.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = isReducedMotion(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Tap-outside dismissal — only intercepts when open.
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const SizedBox.shrink(),
            ),
          ),
        // Cascading stack of source actions.
        Positioned(
          right: widget.rightInset,
          bottom: widget.bottomInset + 56 + 16,
          child: IgnorePointer(
            ignoring: !_open,
            child: CascadingSourceStack(
              actions: widget.actions,
              controller: _controller,
              cardDuration: _cardDuration,
              reducedMotion: reduced,
              onSelect: _runAction,
            ),
          ),
        ),
        // The + button itself.
        Positioned(
          right: widget.rightInset,
          bottom: widget.bottomInset,
          child: NeumorphicPlusButton(
            isOpen: _open,
            onTap: _toggle,
          ),
        ),
      ],
    );
  }
}

/// Round neumorphic `+` button. Embosses by default; debosses (inset) when
/// pressed or while the source stack is open.
class NeumorphicPlusButton extends StatefulWidget {
  const NeumorphicPlusButton({
    super.key,
    required this.isOpen,
    required this.onTap,
    this.size = 56,
  });

  final bool isOpen;
  final VoidCallback onTap;
  final double size;

  @override
  State<NeumorphicPlusButton> createState() => _NeumorphicPlusButtonState();
}

class _NeumorphicPlusButtonState extends State<NeumorphicPlusButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final inset = _pressed || widget.isOpen;
    final reduced = isReducedMotion(context);
    final decoration = inset
        ? RunThruDecorations.insetDecoration(
            RunThruSurface.shell,
            size: RunThruShadowSize.small,
            borderRadius: widget.size / 2,
          )
        : RunThruDecorations.raisedDecoration(
            RunThruSurface.shell,
            size: RunThruShadowSize.standard,
            borderRadius: widget.size / 2,
          );
    return Semantics(
      button: true,
      label: widget.isOpen ? 'Close reading sources' : 'Open reading sources',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: widget.size,
          height: widget.size,
          decoration: decoration,
          alignment: Alignment.center,
          child: AnimatedRotation(
            duration:
                reduced ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            turns: widget.isOpen ? 0.125 : 0.0,
            child: const Icon(
              Icons.add_rounded,
              size: 28,
              color: RunThruTokens.shellAccent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Right-leaning cascading stack of [EmbossedSourceActionCard]s, staggered so
/// each card starts at 50% of the previous card's duration.
class CascadingSourceStack extends StatelessWidget {
  const CascadingSourceStack({
    super.key,
    required this.actions,
    required this.controller,
    required this.cardDuration,
    required this.reducedMotion,
    required this.onSelect,
  });

  final List<LibrarySourceAction> actions;
  final AnimationController controller;
  final Duration cardDuration;
  final bool reducedMotion;
  final ValueChanged<LibrarySourceAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final n = actions.length;
    final totalMs = controller.duration!.inMilliseconds == 0
        ? 1
        : controller.duration!.inMilliseconds;

    // Stack children: index 0 = closest to button. Render bottom-up.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Fully closed (at rest): render nothing so the cards leave the tree.
        if (controller.value == 0) return const SizedBox.shrink();
        return SizedBox(
          width: 220,
          height: (n * 56 + (n - 1) * 16).toDouble().clamp(64, 400),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomRight,
            children: [
              for (int i = 0; i < n; i++)
                _buildPositioned(
                  context,
                  index: i,
                  totalMs: totalMs,
                  action: actions[i],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPositioned(
    BuildContext context, {
    required int index,
    required int totalMs,
    required LibrarySourceAction action,
  }) {
    // Per-card timing: start at 50% of previous card's duration → index * 0.5 * cardDuration.
    final startMs =
        (index * 0.5 * cardDuration.inMilliseconds).round();
    final endMs = startMs + cardDuration.inMilliseconds;
    final start = (startMs / totalMs).clamp(0.0, 1.0);
    final end = (endMs / totalMs).clamp(0.0, 1.0);

    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    // Open-state positioning: each card stacks higher and leans right.
    final verticalOffset = -index * 56.0 - index * 16.0;
    final rightLeanOffset = index * 14.0;
    final rotation = index * 0.018; // ~1° per step

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = reducedMotion
            ? (controller.value > 0 ? 1.0 : 0.0)
            : animation.value;
        // Hidden state: card is "embedded" in surface — slight scale,
        // collapsed offset, no rotation, fully transparent.
        final dy = (1 - t) * 24 + verticalOffset * t;
        final dx = rightLeanOffset * t;
        final scale = 0.92 + 0.08 * t;
        final angle = reducedMotion ? 0.0 : rotation * t;

        return Positioned(
          right: -dx,
          bottom: -dy,
          child: Opacity(
            opacity: t,
            child: Transform.rotate(
              angle: angle,
              alignment: Alignment.bottomRight,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.bottomRight,
                child: EmbossedSourceActionCard(
                  action: action,
                  depth: t,
                  onTap: () => onSelect(action),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A single embossed source-action card. Shows an icon and label, sized to a
/// 48dp minimum touch target.
class EmbossedSourceActionCard extends StatefulWidget {
  const EmbossedSourceActionCard({
    super.key,
    required this.action,
    required this.depth,
    required this.onTap,
  });

  final LibrarySourceAction action;

  /// Animation progress 0..1 — used to scale shadow strength so the card
  /// looks like it's emerging from the surface.
  final double depth;

  final VoidCallback onTap;

  @override
  State<EmbossedSourceActionCard> createState() =>
      _EmbossedSourceActionCardState();
}

class _EmbossedSourceActionCardState extends State<EmbossedSourceActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final shadowSize = widget.depth > 0.6
        ? RunThruShadowSize.standard
        : RunThruShadowSize.small;
    final decoration = _pressed
        ? RunThruDecorations.insetDecoration(
            RunThruSurface.shell,
            size: RunThruShadowSize.small,
            borderRadius: 14,
          )
        : RunThruDecorations.raisedDecoration(
            RunThruSurface.shell,
            size: shadowSize,
            borderRadius: 14,
          );
    return Semantics(
      button: true,
      label: widget.action.semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: decoration,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.action.icon,
                size: 20,
                color: RunThruTokens.shellAccent,
              ),
              const SizedBox(width: 10),
              Text(
                widget.action.label,
                style: RunThruTypography.body.copyWith(
                  color: RunThruTokens.shellTextPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
