import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/store/config.dart';

/// State of stereoscopic parallax capability on this device.
class StereoscopicState {
  const StereoscopicState({
    this.isAvailable = false,
    this.isEnabled = false,
    this.isTracking = false,
  });

  final bool isAvailable;
  final bool isEnabled;
  final bool isTracking;
}

/// Parallax is always available — driven by pointer (desktop) or
/// device motion sensors (mobile). No camera required.
final stereoscopicCapabilityProvider =
    FutureProvider<StereoscopicState>((ref) async {
  final config = ref.watch(configProvider).valueOrNull;
  final enabled = config?.stereoscopicEnabled ?? false;

  return StereoscopicState(
    isAvailable: true,
    isEnabled: enabled,
  );
});
