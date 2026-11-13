/// RunThru Unlock: one-time, non-consumable in-app purchase.
///
/// The app never grants the entitlement itself. It is recorded only when the
/// App Store or Google Play reports the product as `purchased` or `restored`
/// on the purchase stream. There is no server, so verification relies on the
/// platform store (StoreKit and Play Billing sign and deliver the purchase).
/// Server-side receipt validation and refund revocation are 2.1 work.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/store/config.dart';

/// Store product ID. Create a non-consumable product with this exact ID in
/// App Store Connect and a one-time in-app product in Google Play Console.
const String runThruUnlockProductId = 'runthru_unlock';

const String _tag = 'purchase';

/// Thin seam over the store plugin so the controller is testable.
abstract interface class StoreGateway {
  /// Purchase updates, including ones left over from previous sessions.
  Stream<List<PurchaseDetails>> get purchaseStream;

  /// Whether the store can be reached.
  Future<bool> isAvailable();

  /// Looks up [id]; null when the store does not know it.
  Future<ProductDetails?> queryProduct(String id);

  /// Starts the store purchase sheet for a non-consumable product.
  Future<bool> buyNonConsumable(ProductDetails product);

  /// Asks the store to re-deliver past purchases on [purchaseStream].
  Future<void> restorePurchases();

  /// Acknowledges a delivered purchase.
  Future<void> completePurchase(PurchaseDetails purchase);
}

/// [StoreGateway] backed by the official `in_app_purchase` plugin.
class InAppPurchaseGateway implements StoreGateway {
  /// Creates the gateway.
  InAppPurchaseGateway([InAppPurchase? iap])
    : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<ProductDetails?> queryProduct(String id) async {
    final response = await _iap.queryProductDetails({id});
    if (response.error != null) {
      appLog(_tag, 'query failed: ${response.error!.code}');
    }
    for (final product in response.productDetails) {
      if (product.id == id) return product;
    }
    return null;
  }

  @override
  Future<bool> buyNonConsumable(ProductDetails product) => _iap
      .buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);
}

/// Where the purchase flow currently is.
enum PurchaseFlow {
  /// Nothing in flight.
  idle,

  /// The store sheet is open or the payment is pending (e.g. Ask to Buy).
  pending,

  /// A restore request is in flight.
  restoring,

  /// The last attempt failed; see [PurchaseState.message].
  error,
}

/// Immutable purchase UI state.
class PurchaseState {
  /// Creates a state.
  const PurchaseState({
    this.loading = true,
    this.storeAvailable = false,
    this.product,
    this.flow = PurchaseFlow.idle,
    this.message,
  });

  /// True until the store and product lookup have finished.
  final bool loading;

  /// Whether the store answered.
  final bool storeAvailable;

  /// The unlock product, with the store-localised [ProductDetails.price].
  final ProductDetails? product;

  /// Current flow step.
  final PurchaseFlow flow;

  /// Plain-language message for the user, if any.
  final String? message;

  /// Whether a purchase can be started right now.
  bool get canBuy =>
      !loading &&
      storeAvailable &&
      product != null &&
      flow != PurchaseFlow.pending &&
      flow != PurchaseFlow.restoring;

  /// Copy with changes. Pass [clearMessage] to drop the message.
  PurchaseState copyWith({
    bool? loading,
    bool? storeAvailable,
    ProductDetails? product,
    PurchaseFlow? flow,
    String? message,
    bool clearMessage = false,
  }) => PurchaseState(
    loading: loading ?? this.loading,
    storeAvailable: storeAvailable ?? this.storeAvailable,
    product: product ?? this.product,
    flow: flow ?? this.flow,
    message: clearMessage ? null : (message ?? this.message),
  );
}

/// Store access; override in tests.
final storeGatewayProvider = Provider<StoreGateway>(
  (ref) => InAppPurchaseGateway(),
);

/// Drives the RunThru Unlock purchase. Kept alive and read at startup so
/// purchases finishing in the background (or left from a previous session)
/// are delivered and acknowledged.
final purchaseControllerProvider =
    NotifierProvider<PurchaseController, PurchaseState>(PurchaseController.new);

/// Whether RunThru Unlock is owned.
final hasPremiumProvider = Provider<bool>(
  (ref) => ref.watch(
    configProvider.select((c) => c.valueOrNull?.hasPremium ?? false),
  ),
);

/// See [purchaseControllerProvider].
class PurchaseController extends Notifier<PurchaseState> {
  StreamSubscription<List<PurchaseDetails>>? _sub;

  StoreGateway get _store => ref.read(storeGatewayProvider);

  @override
  PurchaseState build() {
    _sub = _store.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => appLog(_tag, 'stream error: ${e.runtimeType}'),
    );
    ref.onDispose(() => _sub?.cancel());
    unawaited(_load());
    return const PurchaseState();
  }

  Future<void> _load() async {
    try {
      final available = await _store.isAvailable();
      final product = available
          ? await _store.queryProduct(runThruUnlockProductId)
          : null;
      state = state.copyWith(
        loading: false,
        storeAvailable: available,
        product: product,
      );
      if (available && product == null) {
        appLog(_tag, 'product $runThruUnlockProductId not found in store');
      }
    } catch (e) {
      appLog(_tag, 'load failed: ${e.runtimeType}');
      state = state.copyWith(loading: false, storeAvailable: false);
    }
  }

  /// Retries the store lookup (e.g. after coming back online).
  Future<void> reload() async {
    state = state.copyWith(loading: true, clearMessage: true);
    await _load();
  }

  /// Asks the store again if the last lookup found no store or no product.
  ///
  /// The lookup runs once, at launch, and the app may have been offline
  /// then. The Unlock sheet calls this when it opens and when the app
  /// comes back to the front, so the reader is not left with "unavailable"
  /// until they restart the app.
  Future<void> reloadIfUnavailable() async {
    if (state.loading) return;
    if (state.storeAvailable && state.product != null) return;
    await reload();
  }

  /// Opens the store purchase sheet. The entitlement is granted only when
  /// the store later reports the purchase on the stream.
  Future<void> buy() async {
    final product = state.product;
    if (!state.canBuy || product == null) return;
    state = state.copyWith(flow: PurchaseFlow.pending, clearMessage: true);
    try {
      final started = await _store.buyNonConsumable(product);
      if (!started) {
        state = state.copyWith(
          flow: PurchaseFlow.error,
          message: 'The store could not start the purchase. Try again.',
        );
      }
    } catch (e) {
      appLog(_tag, 'buy failed: ${e.runtimeType}');
      state = state.copyWith(
        flow: PurchaseFlow.error,
        message: 'The store could not start the purchase. Try again.',
      );
    }
  }

  /// Asks the store to re-deliver a previous purchase.
  Future<void> restore() async {
    if (state.flow == PurchaseFlow.pending ||
        state.flow == PurchaseFlow.restoring) {
      return;
    }
    state = state.copyWith(flow: PurchaseFlow.restoring, clearMessage: true);
    try {
      await _store.restorePurchases();
      // A restored purchase arrives on the stream. If nothing arrives, the
      // flow returns to idle with a note once the store call finishes.
      if (state.flow == PurchaseFlow.restoring) {
        state = state.copyWith(
          flow: PurchaseFlow.idle,
          message: ref.read(hasPremiumProvider)
              ? null
              : 'No previous purchase was found for this account.',
        );
      }
    } catch (e) {
      appLog(_tag, 'restore failed: ${e.runtimeType}');
      state = state.copyWith(
        flow: PurchaseFlow.error,
        message: 'Restore did not finish. Check your connection and try again.',
      );
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      try {
        if (p.productID != runThruUnlockProductId) {
          if (p.pendingCompletePurchase) await _store.completePurchase(p);
          continue;
        }
        switch (p.status) {
          case PurchaseStatus.pending:
            state = state.copyWith(flow: PurchaseFlow.pending);
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            await ref.read(configProvider.notifier).setHasPremium(true);
            appLog(_tag, 'unlock delivered (${p.status.name})');
            state = state.copyWith(
              flow: PurchaseFlow.idle,
              message: 'RunThru Unlock is active. Thank you.',
            );
          case PurchaseStatus.error:
            appLog(_tag, 'purchase error: ${p.error?.code}');
            state = state.copyWith(
              flow: PurchaseFlow.error,
              message: 'The purchase did not go through. You were not charged.',
            );
          case PurchaseStatus.canceled:
            state = state.copyWith(flow: PurchaseFlow.idle, clearMessage: true);
        }
        if (p.pendingCompletePurchase) await _store.completePurchase(p);
      } catch (e) {
        appLog(_tag, 'handling purchase failed: ${e.runtimeType}');
      }
    }
  }
}
