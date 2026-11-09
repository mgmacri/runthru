/// Single coherent cache policy for all extracted-content storage.
///
/// Every byte of cached text lives under one total budget with one eviction
/// strategy (LRU by last-read). Storage layers (today [PdfCache]; the
/// section content store as it lands) consult this policy instead of
/// carrying private budgets that can disagree.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/services/device_capability.dart';
import 'package:runthru/services/pdf_cache.dart';

/// Budget + eviction policy for extracted-content caches.
class ContentCachePolicy {
  /// Creates a policy with a fixed total budget.
  const ContentCachePolicy({required this.totalBudgetBytes});

  /// Selects the budget from device capability: low-end mobile devices
  /// (≤4 cores) get the conservative budget, everything else the larger one.
  factory ContentCachePolicy.forDevice(DeviceCapability capability) {
    final lowEnd = capability.isMobile && capability.processorCount <= 4;
    return ContentCachePolicy(
      totalBudgetBytes: lowEnd ? lowEndBudgetBytes : highEndBudgetBytes,
    );
  }

  /// Default budget on low-end mobile (150 MB of gzip text ≈ 1–1.5 GB raw).
  static const int lowEndBudgetBytes = 150 * 1024 * 1024;

  /// Default budget elsewhere (300 MB).
  static const int highEndBudgetBytes = 300 * 1024 * 1024;

  /// Total bytes all content caches may hold together.
  final int totalBudgetBytes;
}

/// Point-in-time cache usage for the debug/settings screens.
class CacheStats {
  /// Creates cache stats.
  const CacheStats({required this.usedBytes, required this.budgetBytes});

  /// Bytes currently used by content caches.
  final int usedBytes;

  /// Total configured budget.
  final int budgetBytes;

  /// 0.0–1.0 fill ratio.
  double get percent => budgetBytes > 0 ? usedBytes / budgetBytes : 0.0;
}

/// The active cache policy. Reading this provider also configures the
/// storage layers, so anything that writes to a cache should depend on it.
final contentCachePolicyProvider = Provider<ContentCachePolicy>((ref) {
  final capability = ref.watch(deviceCapabilityProvider);
  final policy = ContentCachePolicy.forDevice(capability);
  PdfCache.configureBudget(policy.totalBudgetBytes);
  return policy;
});

/// Cache usage snapshot ("cache used: X of Y MB").
final cacheStatsProvider = FutureProvider<CacheStats>((ref) async {
  final policy = ref.watch(contentCachePolicyProvider);
  final used = await PdfCache.totalUsageBytes();
  return CacheStats(usedBytes: used, budgetBytes: policy.totalBudgetBytes);
});
