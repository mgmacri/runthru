import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// Compact RunThru RT mark used in shell headers and empty states.
class RunThruMark extends StatelessWidget {
  /// Creates a raised RT mark.
  const RunThruMark({
    super.key,
    this.size = 42,
    this.semanticLabel = 'RunThru',
  });

  /// Square size of the mark.
  final double size;

  /// Accessibility label for the mark.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: RunThruDecorations.designerRaisedSmall(
          borderRadius: size * 0.28,
        ),
        child: RunThruGlyphMark(size: size * 0.52),
      ),
    );
  }
}

/// Text-only RT glyph mark for places that already provide a surface.
class RunThruGlyphMark extends StatelessWidget {
  /// Creates a glyph mark.
  const RunThruGlyphMark({super.key, this.size = 22});

  /// Font size of the glyph.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Text(
        'RT',
        style: RunThruTypography.badge.copyWith(
          color: RunThruTokens.shellTealDeep,
          fontSize: size,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// Compact shell screen header with the RT mark and optional actions.
class RunThruScreenHeader extends StatelessWidget {
  /// Creates a shell screen header.
  const RunThruScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(20, 16, 12, 8),
  });

  /// Header title.
  final String title;

  /// Optional metadata subtitle.
  final String? subtitle;

  /// Optional leading widget, replacing the RT mark.
  final Widget? leading;

  /// Trailing action widgets.
  final List<Widget> actions;

  /// Outer padding.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading ?? const RunThruMark(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: RunThruTypography.screenTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: RunThruTypography.metadata,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ...actions,
        ],
      ),
    );
  }
}

/// Header icon button styled as a raised designer thumb.
class RunThruHeaderIconButton extends StatefulWidget {
  /// Creates a header icon button.
  const RunThruHeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  /// Icon to display.
  final IconData icon;

  /// Tooltip and semantics label.
  final String tooltip;

  /// Tap handler.
  final VoidCallback onPressed;

  @override
  State<RunThruHeaderIconButton> createState() =>
      _RunThruHeaderIconButtonState();
}

class _RunThruHeaderIconButtonState extends State<RunThruHeaderIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = isReducedMotion(context);
    return Semantics(
      label: widget.tooltip,
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: Tooltip(
          message: widget.tooltip,
          child: AnimatedContainer(
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 120),
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: _pressed
                ? RunThruDecorations.designerInset(borderRadius: 14)
                : RunThruDecorations.designerRaisedSmall(borderRadius: 14),
            child: Icon(
              widget.icon,
              size: 21,
              color: RunThruTokens.shellInkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inset segmented filter control for shell lists.
class RunThruSegmentedFilter<T> extends StatelessWidget {
  /// Creates a segmented filter.
  const RunThruSegmentedFilter({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
  });

  /// Ordered values.
  final List<T> values;

  /// Currently selected value.
  final T selected;

  /// Label builder for each value.
  final String Function(T value) labelFor;

  /// Selection callback.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final reduced = isReducedMotion(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minHeight: 48),
      decoration: RunThruDecorations.designerInset(borderRadius: 16),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _SegmentButton<T>(
                  value: value,
                  label: labelFor(value),
                  selected: value == selected,
                  reducedMotion: reduced,
                  onChanged: onChanged,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentButton<T> extends StatelessWidget {
  const _SegmentButton({
    required this.value,
    required this.label,
    required this.selected,
    required this.reducedMotion,
    required this.onChanged,
  });

  final T value;
  final String label;
  final bool selected;
  final bool reducedMotion;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label filter',
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        onTap: () => onChanged(value),
        excludeFromSemantics: true,
        child: AnimatedContainer(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(
            minHeight: RunThruA11y.minTapTarget,
          ),
          alignment: Alignment.center,
          decoration: selected
              ? RunThruDecorations.designerRaisedSmall(borderRadius: 12)
              : const BoxDecoration(),
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: RunThruTypography.tinyLabel.copyWith(
                  color: selected
                      ? RunThruTokens.shellTealDeep
                      : RunThruTokens.shellInkSoft,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular progress indicator with an accessible percentage label.
class RunThruProgressRing extends StatelessWidget {
  /// Creates a progress ring.
  const RunThruProgressRing({
    super.key,
    required this.value,
    this.size = 46,
    this.strokeWidth = 4,
  });

  /// Progress from 0 to 1.
  final double value;

  /// Square size.
  final double size;

  /// Ring stroke width.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    final percent = (clamped * 100).round();
    return Semantics(
      label: '$percent percent read',
      container: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ProgressRingPainter(
            value: clamped,
            strokeWidth: strokeWidth,
          ),
          child: Center(
            child: Text(
              '$percent',
              style: RunThruTypography.tinyLabel.copyWith(
                color: RunThruTokens.shellInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({required this.value, required this.strokeWidth});

  final double value;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = strokeWidth / 2;
    final arcRect = rect.deflate(inset);
    final track = Paint()
      ..color = RunThruTokens.shellSandDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..color = RunThruTokens.shellTeal
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2, false, track);
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * value, false, progress);
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Text status pill with tokenized ready/neutral/error colors.
class RunThruStatusPill extends StatelessWidget {
  /// Creates a status pill.
  const RunThruStatusPill({
    super.key,
    required this.label,
    this.tone = RunThruStatusTone.neutral,
  });

  /// Pill text.
  final String label;

  /// Visual tone.
  final RunThruStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      RunThruStatusTone.ready => RunThruTokens.shellTealDeep,
      RunThruStatusTone.warning => RunThruTokens.shellProcessing,
      RunThruStatusTone.error => RunThruTokens.shellError,
      RunThruStatusTone.neutral => RunThruTokens.shellInkSoft,
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: RunThruDecorations.statusPill(
        emphasized: tone == RunThruStatusTone.ready,
      ),
      child: Text(
        label,
        style: RunThruTypography.statusPill.copyWith(color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Available status-pill tones.
enum RunThruStatusTone {
  /// Neutral/inactive tone.
  neutral,

  /// Ready/connected tone.
  ready,

  /// Warning/in-progress tone.
  warning,

  /// Error tone.
  error,
}

/// Teal primary shell button.
class RunThruPrimaryButton extends StatelessWidget {
  /// Creates a primary button.
  const RunThruPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  /// Button label.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Tap handler.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: RunThruDecorations.tealButton(borderRadius: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: RunThruTokens.shellCream),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: RunThruTypography.primaryButton,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// Flat teal thumbnail for compact shell rows.
class RunThruIconThumb extends StatelessWidget {
  /// Creates a thumbnail with an icon.
  const RunThruIconThumb({super.key, required this.icon, this.size = 42});

  /// Icon to display.
  final IconData icon;

  /// Square size.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: RunThruDecorations.iconThumb(borderRadius: size * 0.24),
      child: Icon(icon, size: size * 0.5, color: RunThruTokens.shellCream),
    );
  }
}

/// Dense grouped row used by shell lists and source panels.
class RunThruShellRow extends StatelessWidget {
  /// Creates a dense shell row.
  const RunThruShellRow({
    super.key,
    required this.title,
    required this.metadata,
    required this.icon,
    this.trailing,
    this.onTap,
    this.divider = true,
    this.semanticLabel,
  });

  /// Row title.
  final String title;

  /// Secondary metadata text.
  final String metadata;

  /// Leading thumbnail icon.
  final IconData icon;

  /// Optional trailing widget.
  final Widget? trailing;

  /// Optional tap handler.
  final VoidCallback? onTap;

  /// Whether to draw a row divider.
  final bool divider;

  /// Optional semantics label.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: divider ? RunThruDecorations.rowDivider() : null,
      ),
      child: Row(
        children: [
          RunThruIconThumb(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: RunThruTypography.rowTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  metadata,
                  style: RunThruTypography.metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
    return Semantics(
      label: semanticLabel ?? '$title, $metadata',
      button: onTap != null,
      child: onTap == null
          ? row
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: row,
            ),
    );
  }
}
