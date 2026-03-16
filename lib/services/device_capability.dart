import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device capability info for adaptive worker pool sizing.
class DeviceCapability {
  const DeviceCapability({
    required this.processorCount,
    required this.maxWorkers,
    required this.isMobile,
  });

  final int processorCount;
  final int maxWorkers;
  final bool isMobile;
}

/// Computes adaptive concurrency limits based on device capabilities.
DeviceCapability _computeCapability() {
  if (kIsWeb) {
    return const DeviceCapability(
      processorCount: 2,
      maxWorkers: 2,
      isMobile: false,
    );
  }

  final processorCount = Platform.numberOfProcessors;
  final isMobile = Platform.isIOS || Platform.isAndroid;
  final cap = isMobile ? 6 : 12;
  final raw = processorCount - 1;
  final maxWorkers = raw.clamp(2, cap);

  return DeviceCapability(
    processorCount: processorCount,
    maxWorkers: maxWorkers,
    isMobile: isMobile,
  );
}

/// Riverpod provider exposing computed concurrency limits.
final deviceCapabilityProvider = Provider<DeviceCapability>((ref) {
  return _computeCapability();
});
