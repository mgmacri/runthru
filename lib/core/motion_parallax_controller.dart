import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show Offset, Size, ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/head_position.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Smoothing alpha for low-pass filter (lower = smoother, more lag).
const _kSmoothingAlpha = 0.12;

/// Dead zone: normalised offsets below this threshold snap to zero.
const _kDeadZone = 0.025;

/// Maximum integrated tilt angle in radians (~20°).
const _kMaxTiltRad = 0.35;

/// Per-sample drift correction factor (pulls angle toward zero).
const _kDriftCorrection = 0.997;

// ── Pure logic helpers — tested independently ────────────────────────────────

/// Exponential low-pass: blend [current] toward [raw] by [alpha].
double applySmoothing(double current, double raw, double alpha) =>
    current * (1.0 - alpha) + raw * alpha;

/// Snap values within [deadZone] of zero to exactly zero.
double applyDeadZone(double v, double deadZone) =>
    v.abs() < deadZone ? 0.0 : v;

/// Clamp [angle] to [−maxRad, maxRad] then normalise to [−1, 1].
double normalizeTilt(double angle, double maxRad) =>
    (angle / maxRad).clamp(-1.0, 1.0);

// ─────────────────────────────────────────────────────────────────────────────

/// Manages gyroscope/pointer input and emits normalised head position.
///
/// Consumers read from [positionNotifier] for high-frequency updates without
/// triggering widget-tree rebuilds on the caller's side.
///
/// Lifecycle:
/// 1. Call [start] when the reading screen or pause overlay becomes active.
/// 2. Call [recalibrate] whenever the user returns to a calibrated neutral
///    (e.g. on pause entry).
/// 3. Call [stop] / [dispose] when the screen disposes.
class MotionParallaxController {
  /// High-frequency Offset updates (sensor rate, typically 60 Hz).
  /// x ∈ −1..1 (horizontal), y ∈ −1..1 (vertical).
  final ValueNotifier<Offset> positionNotifier = ValueNotifier(Offset.zero);

  HeadPosition _state = HeadPosition.zero;

  /// Full head-position state including availability and source metadata.
  HeadPosition get state => _state;

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Offset _tiltAngle = Offset.zero;
  DateTime _lastGyroTime = DateTime.now();
  bool _gyroAvailable = false;
  bool _reducedMotion = false;

  /// Starts sensor tracking.
  ///
  /// Pass [reducedMotion] from `isReducedMotion(context)`.
  /// Pass [isDesktop] to skip gyroscope and use pointer-only mode.
  void start({required bool reducedMotion, bool isDesktop = false}) {
    _reducedMotion = reducedMotion;

    if (reducedMotion) {
      _state = HeadPosition.zero;
      positionNotifier.value = Offset.zero;
      return;
    }

    recalibrate();

    if (!kIsWeb && !isDesktop) {
      _startGyro();
    } else {
      _state = _state.copyWith(
        isAvailable: true,
        source: MotionSource.pointer,
      );
    }
  }

  void _startGyro() {
    _gyroSub?.cancel();
    _lastGyroTime = DateTime.now();

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      _onGyro,
      onError: (_) {
        // Gyroscope unavailable — fall back to pointer mode.
        _gyroAvailable = false;
        _gyroSub?.cancel();
        _gyroSub = null;
        _state = _state.copyWith(
          isAvailable: true,
          source: MotionSource.pointer,
        );
      },
    );
    _gyroAvailable = true;
    _state = _state.copyWith(
      isAvailable: true,
      isCalibrated: true,
      source: MotionSource.sensor,
    );
  }

  void _onGyro(GyroscopeEvent event) {
    final now = DateTime.now();
    final dtSec = now.difference(_lastGyroTime).inMicroseconds / 1e6;
    _lastGyroTime = now;
    if (dtSec <= 0 || dtSec > 0.5) return; // skip stale / first frames

    // Integrate angular velocity → tilt angle, then clamp.
    var nx = (_tiltAngle.dx + event.y * dtSec).clamp(-_kMaxTiltRad, _kMaxTiltRad);
    var ny = (_tiltAngle.dy + event.x * dtSec).clamp(-_kMaxTiltRad, _kMaxTiltRad);

    // Low-pass smoothing.
    nx = applySmoothing(_tiltAngle.dx, nx, _kSmoothingAlpha);
    ny = applySmoothing(_tiltAngle.dy, ny, _kSmoothingAlpha);

    // Slow drift correction.
    nx *= _kDriftCorrection;
    ny *= _kDriftCorrection;

    _tiltAngle = Offset(nx, ny);

    // Normalise → dead zone → emit.
    var x = normalizeTilt(nx, _kMaxTiltRad);
    var y = normalizeTilt(ny, _kMaxTiltRad);
    x = applyDeadZone(x, _kDeadZone);
    y = applyDeadZone(y, _kDeadZone);

    final offset = Offset(x, y);
    _state = _state.copyWith(x: x, y: y);
    positionNotifier.value = offset;
  }

  /// Updates position from pointer/mouse events (desktop fallback).
  ///
  /// Ignored when gyroscope is active or reduced motion is on.
  void onPointerMove(Offset localPosition, Size screenSize) {
    if (_gyroAvailable || _reducedMotion) return;
    final x = ((localPosition.dx / screenSize.width) - 0.5) * 2;
    final y = ((localPosition.dy / screenSize.height) - 0.5) * 2;
    final offset = Offset(
      applyDeadZone(x.clamp(-1.0, 1.0), _kDeadZone),
      applyDeadZone(y.clamp(-1.0, 1.0), _kDeadZone),
    );
    _state = _state.copyWith(x: offset.dx, y: offset.dy);
    positionNotifier.value = offset;
  }

  /// Treats the current device orientation as neutral centre.
  ///
  /// The first few sensor frames after calling [recalibrate] are discarded
  /// (dtSec > 0.5 guard) so there is no jump on re-entry.
  void recalibrate() {
    _tiltAngle = Offset.zero;
    _lastGyroTime = DateTime.now();
    _state = _state.copyWith(isCalibrated: true);
    positionNotifier.value = Offset.zero;
  }

  /// Stops sensor tracking and resets position to neutral.
  void stop() {
    _gyroSub?.cancel();
    _gyroSub = null;
    _gyroAvailable = false;
    _tiltAngle = Offset.zero;
    _state = HeadPosition.zero;
    positionNotifier.value = Offset.zero;
  }

  /// Cancels subscriptions and releases resources.
  void dispose() {
    stop();
    positionNotifier.dispose();
  }
}

/// Riverpod provider for [MotionParallaxController].
///
/// Auto-disposed when all listeners are removed (e.g. reading screen pops).
/// Callers are responsible for invoking [MotionParallaxController.start].
final motionParallaxControllerProvider =
    Provider.autoDispose<MotionParallaxController>((ref) {
  final controller = MotionParallaxController();
  ref.onDispose(controller.dispose);
  return controller;
});
