import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/services/models.dart';

/// 3D neumorphic PDF card with press/release animations.
class PdfCard3D extends StatefulWidget {
  const PdfCard3D({
    super.key,
    required this.entry,
    this.readingProgress = 0.0,
    this.onTap,
  });

  final PdfEntry entry;
  final double readingProgress;
  final VoidCallback? onTap;

  @override
  State<PdfCard3D> createState() => _PdfCard3DState();
}

class _PdfCard3DState extends State<PdfCard3D> with TickerProviderStateMixin {
  late final AnimationController _pressController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.cardPressDuration,
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.processingPulseDuration,
    );

    if (widget.entry.status == PdfStatus.processing) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PdfCard3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.status == PdfStatus.processing) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Color _statusColor() {
    switch (widget.entry.status) {
      case PdfStatus.ready:
        return SpeedyBoyTokens.shellReady;
      case PdfStatus.processing:
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
      child: AnimatedBuilder(
        animation: _pressController,
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
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      return Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor().withOpacity(
                            widget.entry.status == PdfStatus.processing
                                ? 0.5 + 0.5 * _pulseController.value
                                : 1.0,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusLabel(),
                    style: SpeedyBoyTypography.caption,
                  ),
                ],
              ),
            ],
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
