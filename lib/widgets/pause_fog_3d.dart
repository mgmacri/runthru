import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Atmospheric pause overlay with:
///   • Bottom-to-top rising warm gradient with wavy sinusoidal leading edge
///   • Real gyroscope-driven parallax (iOS/Meta 3D-photo style)
///   • Pointer-based parallax fallback on desktop / when gyro unavailable
///
/// Primary transport controls (play/pause, prev/next sentence, speed selector)
/// live on the reader screen permanently — not here. This widget owns only the
/// atmospheric fog and Focus Mode toggle.
///
/// When [externalPosition] is supplied (e.g. from [MotionParallaxController]
/// inside a reading screen), the widget uses that shared notifier instead of
/// running its own gyroscope subscription.
class PauseFog3D extends StatefulWidget {
  const PauseFog3D({
    super.key,
    required this.isPaused,
    required this.wpm,
    this.externalPosition,
    this.onRecalibrate,
    this.focusModeEnabled = false,
    this.onFocusModeChanged,
  });

  final bool isPaused;
  final int wpm;

  /// Optional shared parallax position notifier (x/y in −1..1).
  ///
  /// When provided, the widget uses this instead of its own gyroscope stream.
  final ValueNotifier<Offset>? externalPosition;

  /// Called when the pause overlay becomes active, signalling that the shared
  /// [MotionParallaxController] should recalibrate to the current orientation.
  final VoidCallback? onRecalibrate;

  /// Whether Focus Mode is hiding explicit reading controls.
  final bool focusModeEnabled;

  /// Persists Focus Mode from the pause overlay.
  final ValueChanged<bool>? onFocusModeChanged;

  @override
  State<PauseFog3D> createState() => _PauseFog3DState();
}

class _PauseFog3DState extends State<PauseFog3D> with TickerProviderStateMixin {
  // ── Animation controllers ──
  late final AnimationController _fadeController;
  late final CurvedAnimation _fade;
  late final AnimationController _riseController;
  late final CurvedAnimation _rise;
  late final AnimationController _flowController;

  // ── Parallax ──
  final ValueNotifier<Offset> _parallaxOffset = ValueNotifier(Offset.zero);
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Offset _tiltAngle = Offset.zero;
  DateTime _lastGyroTime = DateTime.now();
  bool _gyroAvailable = false;

  static const double _maxTiltRad = 0.35; // ~20°

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: RunThruAnimations.pauseFogDuration,
      reverseDuration: RunThruAnimations.resumeClearDuration,
    );
    _fade = CurvedAnimation(
      parent: _fadeController,
      curve: RunThruAnimations.pauseFogCurve,
      reverseCurve: RunThruAnimations.resumeClearCurve,
    );

    _riseController = AnimationController(
      vsync: this,
      duration: RunThruAnimations.pauseGradientRiseDuration,
      reverseDuration: RunThruAnimations.resumeClearDuration,
    );
    _rise = CurvedAnimation(
      parent: _riseController,
      curve: RunThruAnimations.pauseGradientRiseCurve,
      reverseCurve: Curves.easeIn,
    );

    _flowController = AnimationController(
      vsync: this,
      duration: RunThruAnimations.pauseWaveFlowDuration,
    );

    if (widget.isPaused) {
      _fadeController.value = 1.0;
      _riseController.value = 1.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !isReducedMotion(context)) {
          _flowController.repeat();
          _startParallax();
        }
      });
    }
  }

  @override
  void didUpdateWidget(PauseFog3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused == oldWidget.isPaused) return;

    final reduced = isReducedMotion(context);

    if (widget.isPaused) {
      if (reduced) {
        _fadeController.value = 1.0;
        _riseController.value = 1.0;
      } else {
        _fadeController.forward();
        _riseController.forward();
        _flowController.repeat();
        _startParallax();
      }
    } else {
      if (reduced) {
        _fadeController.value = 0.0;
        _riseController.value = 0.0;
      } else {
        _fadeController.reverse();
        _riseController.reverse();
      }
      _flowController.stop();
      _stopParallax();
    }
  }

  void _startParallax() {
    if (widget.externalPosition != null) {
      widget.onRecalibrate?.call();
      return;
    }

    _gyroSub?.cancel();
    _lastGyroTime = DateTime.now();
    _tiltAngle = Offset.zero;

    _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen(
          _onGyro,
          onError: (_) {
            _gyroAvailable = false;
            _gyroSub?.cancel();
            _gyroSub = null;
          },
        );
    _gyroAvailable = true;
  }

  void _stopParallax() {
    if (widget.externalPosition != null) {
      _tiltAngle = Offset.zero;
      return;
    }

    _gyroSub?.cancel();
    _gyroSub = null;
    _parallaxOffset.value = Offset.zero;
    _tiltAngle = Offset.zero;
  }

  void _onGyro(GyroscopeEvent event) {
    final now = DateTime.now();
    final dtSec = now.difference(_lastGyroTime).inMicroseconds / 1e6;
    _lastGyroTime = now;
    if (dtSec <= 0 || dtSec > 0.5) return;

    var nx = (_tiltAngle.dx + event.y * dtSec).clamp(-_maxTiltRad, _maxTiltRad);
    var ny = (_tiltAngle.dy + event.x * dtSec).clamp(-_maxTiltRad, _maxTiltRad);

    nx = _tiltAngle.dx * 0.88 + nx * 0.12;
    ny = _tiltAngle.dy * 0.88 + ny * 0.12;

    nx *= 0.997;
    ny *= 0.997;

    _tiltAngle = Offset(nx, ny);
    _parallaxOffset.value = _tiltAngle / _maxTiltRad;
  }

  void _onPointerMove(Offset localPosition, Size screenSize) {
    if (_gyroAvailable) return;
    if (widget.externalPosition != null) return;
    final nx = ((localPosition.dx / screenSize.width) - 0.5) * 2;
    final ny = ((localPosition.dy / screenSize.height) - 0.5) * 2;
    _parallaxOffset.value = Offset(nx.clamp(-1.0, 1.0), ny.clamp(-1.0, 1.0));
  }

  ValueNotifier<Offset> get _activeParallax =>
      widget.externalPosition ?? _parallaxOffset;

  @override
  void dispose() {
    _gyroSub?.cancel();
    _parallaxOffset.dispose();
    _fade.dispose();
    _fadeController.dispose();
    _rise.dispose();
    _riseController.dispose();
    _flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parallax = _activeParallax;
    return IgnorePointer(
      // Interactive even in focus mode — the Focus Mode toggle on the pause
      // overlay is the only way to leave focus mode.
      ignoring: false,
      child: Listener(
        onPointerHover: (e) =>
            _onPointerMove(e.localPosition, MediaQuery.sizeOf(context)),
        onPointerMove: (e) =>
            _onPointerMove(e.localPosition, MediaQuery.sizeOf(context)),
        behavior: HitTestBehavior.translucent,
        child: AnimatedBuilder(
          animation: Listenable.merge([_fade, _rise, _flowController]),
          builder: (context, _) {
            final fadeVal = _fade.value;
            if (fadeVal == 0) return const SizedBox.shrink();

            final riseVal = _rise.value;

            return Stack(
              fit: StackFit.expand,
              children: [
                // ── Radial veil — layer 1 ──
                CustomPaint(
                  painter: _VeilPainter(
                    color: RunThruTokens.stageDarkShadow,
                    opacity: fadeVal * 0.45,
                    parallaxNotifier: parallax,
                  ),
                  size: Size.infinite,
                ),

                // ── Rising "blind" with flowing wavy leading edge — layer 2 ──
                if (riseVal > 0)
                  CustomPaint(
                    painter: _WavyRisePainter(
                      riseProgress: riseVal,
                      fadeProgress: fadeVal,
                      flowPhase: _flowController.value,
                      parallaxNotifier: parallax,
                    ),
                    size: Size.infinite,
                  ),

                // ── Overlay content (Focus Mode toggle + upgrade tip) ──
                if (fadeVal > 0.1) _buildCenterContent(context, fadeVal),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCenterContent(BuildContext context, double fadeVal) {
    // Sits just below the reader header. Centred, it covered the paused
    // focal word in Word mode (and the reading band in the text modes), so
    // the reader could not see where they stopped.
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 128),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onFocusModeChanged != null) ...[
              _FocusModeToggle(
                enabled: widget.focusModeEnabled,
                onChanged: widget.onFocusModeChanged!,
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _FocusModeToggle extends StatelessWidget {
  const _FocusModeToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: enabled,
      button: true,
      label: 'Focus Mode',
      onTap: () => onChanged(!enabled),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!enabled),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: RunThruTokens.stageBase.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: RunThruTokens.stageLightShadow,
                offset: Offset(-2, -2),
                blurRadius: 6,
              ),
              BoxShadow(
                color: RunThruTokens.stageDarkShadow,
                offset: Offset(2, 2),
                blurRadius: 7,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.center_focus_strong_rounded,
                size: 18,
                color: enabled
                    ? RunThruTokens.shellAccent
                    : RunThruTokens.stageText.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 8),
              Text(
                'Focus Mode',
                style: RunThruTypography.caption.copyWith(
                  color: RunThruTokens.stageText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                label: 'Toggle: focus mode',
                child: Switch.adaptive(
                  key: const ValueKey('pause-focus-mode-switch'),
                  value: enabled,
                  activeThumbColor: RunThruTokens.shellAccent,
                  activeTrackColor: RunThruTokens.shellAccent.withValues(
                    alpha: 0.34,
                  ),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Painters ─────────────────────────────────────────────────────────────────

/// Subtle full-screen radial veil — clearer at centre, denser at edges.
class _VeilPainter extends CustomPainter {
  _VeilPainter({
    required this.color,
    required this.opacity,
    required this.parallaxNotifier,
  }) : super(repaint: parallaxNotifier);

  final Color color;
  final double opacity;
  final ValueNotifier<Offset> parallaxNotifier;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final parallax = parallaxNotifier.value;
    final shift = size.width * 0.03;
    final center = Offset(
      size.width / 2 + parallax.dx * shift,
      size.height / 2 + parallax.dy * shift,
    );
    final maxR = math.sqrt(center.dx * center.dx + center.dy * center.dy);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity * 0.25),
            color.withValues(alpha: opacity * 0.60),
            color.withValues(alpha: opacity),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: maxR)),
    );
  }

  @override
  bool shouldRepaint(_VeilPainter old) =>
      opacity != old.opacity || parallaxNotifier != old.parallaxNotifier;
}

/// A translucent warm blind that sweeps from the bottom of the screen up to the
/// top on pause. Its leading edge is rendered as a subtle neumorphic lip.
class _WavyRisePainter extends CustomPainter {
  _WavyRisePainter({
    required this.riseProgress,
    required this.fadeProgress,
    required this.flowPhase,
    required this.parallaxNotifier,
  }) : super(repaint: parallaxNotifier);

  final double riseProgress;
  final double fadeProgress;
  final double flowPhase;
  final ValueNotifier<Offset> parallaxNotifier;

  static const double _amplitude = 16;
  static const double _wavelength = 110;
  static const double _strokeWidth = 16;
  static const double _step = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (riseProgress <= 0 || fadeProgress <= 0) return;

    const amp = _amplitude;
    final parallaxShiftX = parallaxNotifier.value.dx * 30;

    final startEdgeY = size.height + amp * 2;
    const restEdgeY = -amp * 2;
    final edgeY = startEdgeY + (restEdgeY - startEdgeY) * riseProgress;

    final phase = flowPhase * math.pi * 2;

    final linePath = Path();
    var first = true;
    for (double x = -_wavelength; x <= size.width + _wavelength; x += _step) {
      final shiftedX = x + parallaxShiftX;
      final y =
          edgeY +
          math.sin((shiftedX / _wavelength) * math.pi * 2 + phase) * amp;
      if (first) {
        linePath.moveTo(x, y);
        first = false;
      } else {
        linePath.lineTo(x, y);
      }
    }

    final fillPath = Path.from(linePath)
      ..lineTo(size.width + _wavelength, size.height)
      ..lineTo(-_wavelength, size.height)
      ..close();

    final fillTop = edgeY - amp;
    final fillRect = Rect.fromLTWH(
      0,
      fillTop,
      size.width,
      size.height - fillTop,
    );
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            RunThruTokens.stageDarkShadow.withValues(
              alpha: fadeProgress * 0.88,
            ),
            RunThruTokens.stageBase.withValues(alpha: fadeProgress * 0.96),
            RunThruTokens.stageLightShadow.withValues(
              alpha: fadeProgress * 0.90,
            ),
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(fillRect),
    );

    canvas.save();
    canvas.translate(0, 5);
    canvas.drawPath(
      linePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            RunThruTokens.stageDarkShadow.withValues(
              alpha: fadeProgress * 0.72,
            ),
            RunThruTokens.stageBase.withValues(alpha: fadeProgress * 0.20),
          ],
        ).createShader(Rect.fromLTWH(0, edgeY - amp, size.width, amp * 2))
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth * 0.86
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.restore();

    canvas.drawPath(
      linePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            RunThruTokens.stageDarkShadow.withValues(
              alpha: fadeProgress * 0.90,
            ),
            RunThruTokens.stageBase.withValues(alpha: fadeProgress * 0.96),
            RunThruTokens.stageLightShadow.withValues(
              alpha: fadeProgress * 0.92,
            ),
          ],
          stops: const [0.0, 0.46, 1.0],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth * 0.70
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.save();
    canvas.translate(0, -_strokeWidth * 0.18);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = RunThruTokens.stageLightShadow.withValues(
          alpha: fadeProgress * 0.45,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth * 0.28
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavyRisePainter old) =>
      riseProgress != old.riseProgress ||
      fadeProgress != old.fadeProgress ||
      flowPhase != old.flowPhase ||
      parallaxNotifier != old.parallaxNotifier;
}
