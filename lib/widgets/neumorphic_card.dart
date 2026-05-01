import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// Reusable neumorphic card container.
class NeumorphicCard extends StatelessWidget {
  const NeumorphicCard({
    super.key,
    required this.surface,
    this.size = RunThruShadowSize.standard,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 8,
    ),
    this.inset = false,
    this.child,
  });

  final RunThruSurface surface;
  final RunThruShadowSize size;
  final double borderRadius;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final bool inset;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final decoration = inset
        ? RunThruDecorations.insetDecoration(
            surface,
            size: size,
            borderRadius: borderRadius,
          )
        : RunThruDecorations.raisedDecoration(
            surface,
            size: size,
            borderRadius: borderRadius,
          );

    return Container(
      margin: margin,
      padding: padding,
      decoration: decoration,
      child: child,
    );
  }
}
