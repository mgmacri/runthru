import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/store/config.dart';

/// Placeholder purchase service for freemium paywall.
///
/// FIXME: This stub grants premium unconditionally with no receipt
/// validation. Do NOT ship to production without integrating
/// StoreKit (iOS) and Play Billing (Android) with server-side
/// receipt verification.
class PurchaseService {
  PurchaseService(this._ref);

  final Ref _ref;

  /// Triggers a premium purchase flow.
  ///
  /// Returns `true` if the purchase succeeded.
  /// FIXME: Replace with real IAP logic before production release.
  /// Currently grants premium with no payment or receipt validation.
  Future<bool> purchasePremium() async {
    await _ref.read(configProvider.notifier).setHasPremium(true);
    return true;
  }

  /// Restores previous purchases from the store.
  ///
  /// Placeholder — wire into StoreKit/Play Billing restore flow.
  Future<void> restorePurchases() async {
    // TODO: Query store for existing entitlements and call
    // setHasPremium(true) if a valid purchase is found.
  }
}

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  return PurchaseService(ref);
});
