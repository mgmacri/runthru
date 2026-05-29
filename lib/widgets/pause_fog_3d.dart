import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Premium pause overlay with:
///   • Bottom-to-top rising warm gradient with wavy sinusoidal leading edge
///   • Neumorphic play/resume button with 3-step z-axis jiggle bounce
///   • Real gyroscope-driven parallax (iOS/Meta 3D-photo style)
///   • Pointer-based parallax fallback on desktop / when gyro unavailable
///
/// When [externalPosition] is supplied (e.g. from [MotionParallaxController]
/// inside a reading screen), the widget uses that shared notifier instead of
/// running its own gyroscope subscription. This prevents double subscriptions
/// when the pause overlay and the reading room share a sensor stream.
class PauseFog3D extends StatefulWidget {
  const PauseFog3D({
    super.key,
    required this.isPaused,
    required this.wpm,
    this.onResume,
    this.showUpgradeTip = false,
    this.onUpgradeTap,
    this.externalPosition,
    this.onRecalibrate,
  });

  final bool isPaused;
  final int wpm;

  /// Called when the user taps the Play/Resume button.
  final VoidCallback? onResume;

  /// When true, shows a tasteful "try 3D reading" tip below the pause controls.
  final bool showUpgradeTip;

  /// Called when the user taps the upgrade tip. Typically navigates to settings.
  final VoidCallback? onUpgradeTap;

  /// Optional shared parallax position notifier (x/y in −1..1).
  ///
  /// When provided, the widget uses this instead of its own gyroscope stream.
  final ValueNotifier<Offset>? externalPosition;

  /// Called when the pause overlay becomes active, signalling that the shared
  /// [MotionParallaxController] should recalibrate to the current orientation.
  final VoidCallback? onRecalibrate;

  @override
  State<PauseFog3D> createState() => _PauseFog3DState();
}

class _PauseFog3DState extends State<PauseFog3D> with TickerProviderStateMixin {
  // ── Animation controllers ──
  late final AnimationController _fadeController;
  late final CurvedAnimation _fade;
  late final AnimationController _riseController;
  late final CurvedAnimation _rise;
  late final AnimationController _jiggleController;
  late final AnimationController _breatheController;
  late final AnimationController _flowController;

  // ── Jiggle TweenSequence (3 diminishing z-excursions → settle) ──
  late final Animation<double> _jiggle;

  // ── Parallax ──
  // Normalised tilt offset: x/y in −1..1 range.
  // Updated by gyroscope stream or pointer events.
  final ValueNotifier<Offset> _parallaxOffset = ValueNotifier(Offset.zero);
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Offset _tiltAngle = Offset.zero;
  DateTime _lastGyroTime = DateTime.now();
  bool _gyroAvailable = false;

  // Pending jiggle timer (cancelled on dispose)
  Timer? _jiggleTimer;
  // Pending jiggle status listener cleanup
  void Function(AnimationStatus)? _jiggleStatusListener;

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

    _jiggleController = AnimationController(
      vsync: this,
      duration: RunThruAnimations.pauseButtonJiggleDuration,
    );

    // 3-step diminishing z-bounce then settle at 0.78 resting depth
    _jiggle = TweenSequence<double>([
      // Jiggle 1 up (200ms)
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 28,
      ),
      // Jiggle 1 back (100ms)
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.55,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 14,
      ),
      // Jiggle 2 up (150ms)
      TweenSequenceItem(
        tween: Tween(
          begin: 0.55,
          end: 0.88,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 21,
      ),
      // Jiggle 2 back (70ms)
      TweenSequenceItem(
        tween: Tween(
          begin: 0.88,
          end: 0.70,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 10,
      ),
      // Jiggle 3 up (100ms)
      TweenSequenceItem(
        tween: Tween(
          begin: 0.70,
          end: 0.82,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 14,
      ),
      // Settle (130ms)
      TweenSequenceItem(
        tween: Tween(
          begin: 0.82,
          end: 0.78,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 13,
      ),
    ]).animate(_jiggleController);

    _breatheController = AnimationController(
      vsync: this,
      duration: RunThruAnimations.cubeBreatheDuration,
    );

    _flowController = AnimationController(
      vsync: this,
      duration: RunThruAnimations.pauseWaveFlowDuration,
    );

    if (widget.isPaused) {
      _fadeController.value = 1.0;
      _riseController.value = 1.0;
      _jiggleController.value = 1.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !isReducedMotion(context)) {
          _breatheController.repeat(reverse: true);
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
        _jiggleController.value = 1.0;
      } else {
        _fadeController.forward();
        _riseController.forward();

        // Start jiggle slightly after fog is visible
        _flowController.repeat();

        // Start jiggle slightly after fog is visible
        _jiggleTimer = Timer(const Duration(milliseconds: 180), () {
          if (!mounted) return;
          _jiggleController.forward(from: 0.0);

          // Once jiggle settles, start ambient breathe
          final listener = _makeJiggleListener();
          _jiggleStatusListener = listener;
          _jiggleController.addStatusListener(listener);
        });

        _startParallax();
      }
    } else {
      _jiggleTimer?.cancel();
      _jiggleTimer = null;
      if (_jiggleStatusListener != null) {
        _jiggleController.removeStatusListener(_jiggleStatusListener!);
        _jiggleStatusListener = null;
      }

      if (reduced) {
        _fadeController.value = 0.0;
        _riseController.value = 0.0;
      } else {
        _fadeController.reverse();
        _riseController.reverse();
      }
      _jiggleController.value = 0.0;
      _breatheController
        ..stop()
        ..value = 0.0;
      _flowController.stop();
      _stopParallax();
    }
  }

  void Function(AnimationStatus) _makeJiggleListener() {
    return (AnimationStatus status) {
      if (status == AnimationStatus.completed && mounted) {
        if (!isReducedMotion(context)) {
          _breatheController.repeat(reverse: true);
        }
        if (_jiggleStatusListener != null) {
          _jiggleController.removeStatusListener(_jiggleStatusListener!);
          _jiggleStatusListener = null;
        }
      }
    };
  }

  void _startParallax() {
    if (widget.externalPosition != null) {
      // Shared controller handles the sensor subscription — just recalibrate.
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
            // Gyroscope unavailable on this device/platform — fall back to pointer
            _gyroAvailable = false;
            _gyroSub?.cancel();
            _gyroSub = null;
          },
        );
    _gyroAvailable = true;
  }

  void _stopParallax() {
    if (widget.externalPosition != null) {
      // Shared controller owns the subscription — don't touch it.
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
    if (dtSec <= 0 || dtSec > 0.5) return; // skip stale/first events

    // Integrate angular velocity to accumulate tilt angle
    // event.y = roll (tilting left/right) → horizontal parallax
    // event.x = pitch (tilting forward/back) → vertical parallax
    var nx = (_tiltAngle.dx + event.y * dtSec).clamp(-_maxTiltRad, _maxTiltRad);
    var ny = (_tiltAngle.dy + event.x * dtSec).clamp(-_maxTiltRad, _maxTiltRad);

    // Low-pass filter: smooths noise without introducing lag
    nx = _tiltAngle.dx * 0.88 + nx * 0.12;
    ny = _tiltAngle.dy * 0.88 + ny * 0.12;

    // Slow drift correction: pulls angle back toward zero each sample
    nx *= 0.997;
    ny *= 0.997;

    _tiltAngle = Offset(nx, ny);
    _parallaxOffset.value = _tiltAngle / _maxTiltRad; // normalise to −1..1
  }

  void _onPointerMove(Offset localPosition, Size screenSize) {
    if (_gyroAvailable) return; // gyro takes priority
    if (widget.externalPosition != null) return; // shared controller handles it
    final nx = ((localPosition.dx / screenSize.width) - 0.5) * 2;
    final ny = ((localPosition.dy / screenSize.height) - 0.5) * 2;
    _parallaxOffset.value = Offset(nx.clamp(-1.0, 1.0), ny.clamp(-1.0, 1.0));
  }

  /// The active parallax position notifier: external when provided, else own.
  ValueNotifier<Offset> get _activeParallax =>
      widget.externalPosition ?? _parallaxOffset;

  @override
  void dispose() {
    _jiggleTimer?.cancel();
    if (_jiggleStatusListener != null) {
      _jiggleController.removeStatusListener(_jiggleStatusListener!);
    }
    _gyroSub?.cancel();
    _parallaxOffset.dispose();
    _fade.dispose();
    _fadeController.dispose();
    _rise.dispose();
    _riseController.dispose();
    _jiggleController.dispose();
    _breatheController.dispose();
    _flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parallax = _activeParallax;
    return Listener(
      onPointerHover: (e) =>
          _onPointerMove(e.localPosition, MediaQuery.sizeOf(context)),
      onPointerMove: (e) =>
          _onPointerMove(e.localPosition, MediaQuery.sizeOf(context)),
      behavior: HitTestBehavior.translucent,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _fade,
          _rise,
          _jiggleController,
          _breatheController,
          _flowController,
        ]),
        builder: (context, _) {
          final fadeVal = _fade.value;
          if (fadeVal == 0) return const SizedBox.shrink();

          final riseVal = _rise.value;
          final breatheT = _breatheController.value;

          // Base z-depth from jiggle tween; after jiggle completes, breathe takes over
          final jiggleZ = _jiggle.value;
          final settledZ = 0.78 + math.sin(breatheT * math.pi) * 0.05;
          final zDepth = _jiggleController.isCompleted ? settledZ : jiggleZ;

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── Radial veil — layer 1 (slowest parallax via repaint notifier) ──
              CustomPaint(
                painter: _VeilPainter(
                  color: RunThruTokens.stageDarkShadow,
                  opacity: fadeVal * 0.24,
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

              // ── Play/Resume button + labels — layer 3 (strongest parallax) ──
              if (fadeVal > 0.1)
                _buildCenterContent(context, zDepth, fadeVal, parallax),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCenterContent(
    BuildContext context,
    double zDepth,
    double fadeVal,
    ValueNotifier<Offset> parallaxNotifier,
  ) {
    return Align(
      alignment: const Alignment(0, 0.15), // slightly below centre
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Neumorphic play button ──
          ValueListenableBuilder<Offset>(
            valueListenable: parallaxNotifier,
            builder: (context, parallax, _) {
              final scale = 1.0 + zDepth * 0.06;
              final shadowOffset = 4.0 + zDepth * 10.0;
              final shadowBlur = 8.0 + zDepth * 18.0;

              // Parallax shifts light/dark shadows in opposite directions
              final lightOffset = Offset(
                -shadowOffset + parallax.dx * 5,
                -shadowOffset + parallax.dy * 5,
              );
              final darkOffset = Offset(
                shadowOffset + parallax.dx * 3,
                shadowOffset + parallax.dy * 3,
              );

              // Subtle perspective tilt from parallax
              final tiltMatrix = Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(parallax.dx * 0.06)
                ..rotateX(-parallax.dy * 0.06);

              return Semantics(
                button: true,
                label: 'Resume reading',
                child: GestureDetector(
                  onTap: widget.onResume,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: tiltMatrix,
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: RunThruTokens.stageBase,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: RunThruTokens.stageLightShadow,
                              offset: lightOffset,
                              blurRadius: shadowBlur,
                            ),
                            BoxShadow(
                              color: RunThruTokens.stageDarkShadow,
                              offset: darkOffset,
                              blurRadius: shadowBlur,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 36,
                          color: RunThruTokens.stageText.withValues(
                            alpha: 0.75 + zDepth * 0.25,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          DecoratedBox(
            decoration: BoxDecoration(
              color: RunThruTokens.stageBase.withValues(alpha: fadeVal * 0.48),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: RunThruTokens.stageLightShadow.withValues(
                    alpha: fadeVal * 0.42,
                  ),
                  offset: const Offset(-2, -2),
                  blurRadius: 6,
                ),
                BoxShadow(
                  color: RunThruTokens.stageDarkShadow.withValues(
                    alpha: fadeVal * 0.50,
                  ),
                  offset: const Offset(2, 2),
                  blurRadius: 7,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Paused',
                    style: RunThruTypography.caption.copyWith(
                      color: RunThruTokens.stageText.withValues(
                        alpha: fadeVal * 0.70,
                      ),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to resume',
                    style: RunThruTypography.caption.copyWith(
                      color: RunThruTokens.stageText.withValues(
                        alpha: fadeVal * 0.46,
                      ),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 3D mode upgrade tip ──
          if (widget.showUpgradeTip) ...[
            const SizedBox(height: 32),
            _UpgradeTip(fadeVal: fadeVal, onTap: widget.onUpgradeTap),
          ],
        ],
      ),
    );
  }
}

/// Soft neumorphic card nudging the user to try the 3D reading environment.
///
/// References the Yerkes-Dodson arousal principle: peripheral ambient stimulation
/// anchors sustained attention without competing with foveal word processing.
class _UpgradeTip extends StatelessWidget {
  const _UpgradeTip({required this.fadeVal, this.onTap});

  final double fadeVal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final contentOpacity = (fadeVal * 0.85).clamp(0.0, 1.0);

    return Opacity(
      opacity: contentOpacity,
      child: Semantics(
        button: onTap != null,
        label: 'Enable 3D reading mode',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: RunThruTokens.stageBase,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: RunThruTokens.stageLightShadow,
                  offset: Offset(-4, -4),
                  blurRadius: 8,
                ),
                BoxShadow(
                  color: RunThruTokens.stageDarkShadow,
                  offset: Offset(4, 4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.view_in_ar_rounded,
                  size: 18,
                  color: RunThruTokens.shellAccent.withValues(alpha: 0.80),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Try 3D reading mode',
                        style: RunThruTypography.caption.copyWith(
                          color: RunThruTokens.stageText.withValues(
                            alpha: 0.80,
                          ),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Peripheral depth keeps your attention anchored — Yerkes-Dodson research on sustained focus.',
                        style: RunThruTypography.caption.copyWith(
                          color: RunThruTokens.stageText.withValues(
                            alpha: 0.45,
                          ),
                          fontSize: 10,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 10,
                    color: RunThruTokens.shellAccent.withValues(alpha: 0.50),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Painters ─────────────────────────────────────────────────────────────────

/// Subtle full-screen radial veil — clearer at centre, denser at edges.
///
/// The radial focal point shifts slightly with [parallaxNotifier] to create
/// the shallowest depth layer of the multi-layer parallax effect.
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
    // Shift focal point ~3% of screen width for depth illusion (layer 1).
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
///
/// The wave is NOT a persistent mid-screen decoration — it travels with the
/// blind. At rest the blind has fully risen and the wavy edge has passed off
/// the top of the screen, leaving a calm fog behind the play control.
class _WavyRisePainter extends CustomPainter {
  _WavyRisePainter({
    required this.riseProgress,
    required this.fadeProgress,
    required this.flowPhase,
    required this.parallaxNotifier,
  }) : super(repaint: parallaxNotifier);

  final double riseProgress; // 0..1 — how far the blind has risen
  final double fadeProgress; // 0..1 — overall overlay opacity
  final double flowPhase; // 0..1 — horizontal flow of the wave
  final ValueNotifier<Offset> parallaxNotifier;

  // Wave + stroke geometry (mirrors the reference FlowingWavyLine proportions)
  static const double _amplitude = 16;
  static const double _wavelength = 110;
  static const double _strokeWidth = 16;
  static const double _step = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (riseProgress <= 0 || fadeProgress <= 0) return;

    const amp = _amplitude;
    // Parallax horizontal shift for layer 2 depth (~30px at full tilt).
    final parallaxShiftX = parallaxNotifier.value.dx * 30;

    // Leading-edge centre line: starts below the bottom, ends above the top.
    final startEdgeY = size.height + amp * 2;
    const restEdgeY = -amp * 2;
    final edgeY = startEdgeY + (restEdgeY - startEdgeY) * riseProgress;

    // Positive phase makes the wave appear to flow right → left.
    final phase = flowPhase * math.pi * 2;

    // ── Wavy leading-edge line path (shifted by parallax) ──
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

    // ── Blind fill below the wavy edge ──
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
              alpha: fadeProgress * 0.56,
            ),
            RunThruTokens.stageBase.withValues(alpha: fadeProgress * 0.76),
            RunThruTokens.stageLightShadow.withValues(
              alpha: fadeProgress * 0.62,
            ),
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(fillRect),
    );

    // ── Soft shadow beneath the wavy line (neumorphic depth) ──
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
              alpha: fadeProgress * 0.46,
            ),
            RunThruTokens.stageBase.withValues(alpha: fadeProgress * 0.10),
          ],
        ).createShader(Rect.fromLTWH(0, edgeY - amp, size.width, amp * 2))
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth * 0.86
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.restore();

    // ── Main wavy stroke (warm neumorphic gradient body) ──
    canvas.drawPath(
      linePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            RunThruTokens.stageDarkShadow.withValues(
              alpha: fadeProgress * 0.70,
            ),
            RunThruTokens.stageBase.withValues(alpha: fadeProgress * 0.84),
            RunThruTokens.stageLightShadow.withValues(
              alpha: fadeProgress * 0.76,
            ),
          ],
          stops: const [0.0, 0.46, 1.0],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth * 0.70
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ── Top highlight (embossed sheen) ──
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
