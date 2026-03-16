import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/widgets/neumorphic_ripple_loading.dart';

/// 3D neumorphic PDF card with press/release animations.
class PdfCard3D extends StatefulWidget {
  const PdfCard3D({
    super.key,
    required this.entry,
    this.readingProgress = 0.0,
    this.rangeLabel,
    this.onTap,
    this.onLongPress,
  });

  final PdfEntry entry;
  final double readingProgress;

  /// Optional label like "Pages 42–87" shown when a range is set.
  final String? rangeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<PdfCard3D> createState() => _PdfCard3DState();
}

class _PdfCard3DState extends State<PdfCard3D> with TickerProviderStateMixin {
  late final AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.cardPressDuration,
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  Color _statusColor() {
    switch (widget.entry.status) {
      case PdfStatus.ready:
        return SpeedyBoyTokens.shellReady;
      case PdfStatus.processing:
      case PdfStatus.preview:
        return SpeedyBoyTokens.shellProcessing;
      case PdfStatus.error:
      case PdfStatus.unsupported:
      case PdfStatus.permanentlyFailed:
        return SpeedyBoyTokens.shellError;
      case PdfStatus.pending:
      case PdfStatus.queued:
        return SpeedyBoyTokens.shellTextSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = isReducedMotion(context);

    return GestureDetector(
      onTapDown: (_) {
        if (!reducedMotion) {
          _pressController.forward();
        }
      },
      onTapUp: (_) {
        if (!reducedMotion) {
          _pressController.animateWith(
            SpeedyBoyAnimations.cardReleaseSimulation(),
          );
        }
        widget.onTap?.call();
      },
      onTapCancel: () {
        if (!reducedMotion) {
          _pressController.animateWith(
            SpeedyBoyAnimations.cardReleaseSimulation(),
          );
        }
      },
      onLongPress: widget.onLongPress,
      child: ListenableBuilder(
        listenable: _pressController,
        builder: (context, child) {
          final pressValue = _pressController.value;
          final zTranslate = 3.0 - (3.0 * pressValue);
          return Transform(
            transform: Matrix4.translationValues(
              0,
              0,
              zTranslate,
            ),
            child: child,
          );
        },
        child: NeumorphicRippleLoading(
          isLoading: widget.entry.status == PdfStatus.processing ||
              widget.entry.status == PdfStatus.preview,
          surface: SpeedyBoySurface.shell,
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            padding: const EdgeInsets.all(16),
            decoration: SpeedyBoyDecorations.raisedDecoration(
              SpeedyBoySurface.shell,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── PDF name ──
                Text(
                  widget.entry.fileName,
                  style: SpeedyBoyTypography.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // ── Progress bar (inset) ──
                Container(
                  height: 6,
                  decoration: SpeedyBoyDecorations.insetDecoration(
                    SpeedyBoySurface.shell,
                    size: SpeedyBoyShadowSize.small,
                    borderRadius: 3,
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widget.readingProgress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: SpeedyBoyTokens.shellAccent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Status row ──
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _statusColor(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _statusLabel(),
                      style: SpeedyBoyTypography.caption,
                    ),
                    if (widget.rangeLabel != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        widget.rangeLabel!,
                        style: SpeedyBoyTypography.caption.copyWith(
                          color: SpeedyBoyTokens.shellAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel() {
    switch (widget.entry.status) {
      case PdfStatus.ready:
        return 'Ready';
      case PdfStatus.processing:
        return 'Preparing…';
      case PdfStatus.preview:
        return 'Preview ready';
      case PdfStatus.error:
        return 'Error (retry ${widget.entry.retryCount}/${PdfEntry.maxRetries})';
      case PdfStatus.unsupported:
        return 'Not supported';
      case PdfStatus.permanentlyFailed:
        return 'Failed';
      case PdfStatus.pending:
      case PdfStatus.queued:
        return 'Pending';
    }
  }
}
