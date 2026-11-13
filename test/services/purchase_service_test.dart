import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:runthru/services/purchase_service.dart';
import 'package:runthru/store/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _product = ProductDetails(
  id: runThruUnlockProductId,
  title: 'RunThru Unlock',
  description: 'One-time unlock',
  price: r'$4.99',
  rawPrice: 4.99,
  currencyCode: 'USD',
);

PurchaseDetails _purchase(
  PurchaseStatus status, {
  String productId = runThruUnlockProductId,
  bool pendingComplete = true,
}) => PurchaseDetails(
  purchaseID: 'p1',
  productID: productId,
  verificationData: PurchaseVerificationData(
    localVerificationData: 'local',
    serverVerificationData: 'server',
    source: 'test',
  ),
  transactionDate: '0',
  status: status,
)..pendingCompletePurchase = pendingComplete;

/// Stands in for the two seconds a restore waits for its purchase.
const _settleTime = Duration(milliseconds: 60);

class _FakeStore implements StoreGateway {
  _FakeStore({this.available = true, this.product});

  bool available;
  final ProductDetails? product;
  final controller = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <PurchaseDetails>[];
  int buyCalls = 0;
  int restoreCalls = 0;
  int availabilityChecks = 0;
  List<PurchaseDetails>? emitOnRestore;

  /// When set, the restored purchase arrives this long after the store call
  /// has returned, not before it.
  Duration? emitAfter;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    return available;
  }

  @override
  Future<ProductDetails?> queryProduct(String id) async => product;

  @override
  Future<bool> buyNonConsumable(ProductDetails product) async {
    buyCalls++;
    return true;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls++;
    final purchases = emitOnRestore;
    final delay = emitAfter;
    if (purchases != null && delay == null) controller.add(purchases);
    if (purchases != null && delay != null) {
      Timer(delay, () => controller.add(purchases));
    }
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }
}

Future<ProviderContainer> _container(
  _FakeStore store, {
  Duration settle = _settleTime,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      storeGatewayProvider.overrideWithValue(store),
      restoreSettleTimeProvider.overrideWithValue(settle),
    ],
  );
  addTearDown(() {
    container.dispose();
    store.controller.close();
  });
  await container.read(configProvider.future);
  container.read(purchaseControllerProvider);
  await pumpEventQueue();
  return container;
}

void main() {
  group('PurchaseController', () {
    test('loads the store price and does not grant anything', () async {
      final store = _FakeStore(product: _product);
      final c = await _container(store);

      final state = c.read(purchaseControllerProvider);
      expect(state.loading, isFalse);
      expect(state.product?.price, r'$4.99');
      expect(state.canBuy, isTrue);
      expect(c.read(hasPremiumProvider), isFalse);
    });

    test('buy opens the store but unlocks only on a purchased event', () async {
      final store = _FakeStore(product: _product);
      final c = await _container(store);

      await c.read(purchaseControllerProvider.notifier).buy();
      expect(store.buyCalls, 1);
      expect(c.read(purchaseControllerProvider).flow, PurchaseFlow.pending);
      expect(c.read(hasPremiumProvider), isFalse);

      final p = _purchase(PurchaseStatus.purchased);
      store.controller.add([p]);
      await pumpEventQueue();

      expect(c.read(hasPremiumProvider), isTrue);
      expect(store.completed, [p]);
      expect(c.read(purchaseControllerProvider).flow, PurchaseFlow.idle);
    });

    test('error and cancel never unlock, and are still completed', () async {
      final store = _FakeStore(product: _product);
      final c = await _container(store);

      final err = _purchase(PurchaseStatus.error);
      store.controller.add([err]);
      await pumpEventQueue();
      expect(c.read(hasPremiumProvider), isFalse);
      expect(c.read(purchaseControllerProvider).flow, PurchaseFlow.error);
      expect(
        c.read(purchaseControllerProvider).message,
        contains('not charged'),
      );

      store.controller.add([_purchase(PurchaseStatus.canceled)]);
      await pumpEventQueue();
      expect(c.read(hasPremiumProvider), isFalse);
      expect(c.read(purchaseControllerProvider).flow, PurchaseFlow.idle);
      expect(store.completed, hasLength(2));
    });

    test('restore re-grants a previous purchase', () async {
      final store = _FakeStore(product: _product)
        ..emitOnRestore = [_purchase(PurchaseStatus.restored)];
      final c = await _container(store);

      await c.read(purchaseControllerProvider.notifier).restore();
      await pumpEventQueue();

      expect(store.restoreCalls, 1);
      expect(c.read(hasPremiumProvider), isTrue);
    });

    test('restore with nothing to restore says so and stays locked', () async {
      final store = _FakeStore(product: _product);
      final c = await _container(store);

      await c.read(purchaseControllerProvider.notifier).restore();

      expect(c.read(hasPremiumProvider), isFalse);
      expect(
        c.read(purchaseControllerProvider).message,
        contains('No previous purchase'),
      );
    });

    test('a purchase delivered after the store call returns is not first '
        'reported as missing', () async {
      // The restore call returns and the purchase is delivered a moment
      // later. "No previous purchase was found" used to be shown, and
      // read out by the sheet's live region, in between.
      final store = _FakeStore(product: _product)
        ..emitOnRestore = [_purchase(PurchaseStatus.restored)]
        ..emitAfter = const Duration(milliseconds: 10);
      final c = await _container(store);
      final messages = <String>[];
      c.listen(purchaseControllerProvider, (_, next) {
        final message = next.message;
        if (message != null) messages.add(message);
      });

      await c.read(purchaseControllerProvider.notifier).restore();
      await pumpEventQueue();

      expect(c.read(hasPremiumProvider), isTrue);
      expect(messages, isNotEmpty);
      expect(messages, everyElement(isNot(contains('No previous purchase'))));
      final state = c.read(purchaseControllerProvider);
      expect(state.message, contains('RunThru Unlock is active'));
      expect(state.flow, PurchaseFlow.idle);
    });

    test(
      'an empty restore is called only once the store has had time',
      () async {
        final store = _FakeStore(product: _product);
        // A wait long enough that a busy machine cannot run through it
        // while the event queue below is being pumped.
        final c = await _container(
          store,
          settle: const Duration(milliseconds: 600),
        );

        final restoring = c.read(purchaseControllerProvider.notifier).restore();
        await pumpEventQueue();

        // The store call is over; the purchase may still be on its way.
        expect(store.restoreCalls, 1);
        expect(c.read(purchaseControllerProvider).flow, PurchaseFlow.restoring);
        expect(c.read(purchaseControllerProvider).message, isNull);

        await restoring;
        expect(c.read(purchaseControllerProvider).flow, PurchaseFlow.idle);
        expect(
          c.read(purchaseControllerProvider).message,
          contains('No previous purchase'),
        );
      },
    );

    test('other product IDs are acknowledged but never unlock', () async {
      final store = _FakeStore(product: _product);
      final c = await _container(store);

      final other = _purchase(PurchaseStatus.purchased, productId: 'other');
      store.controller.add([other]);
      await pumpEventQueue();

      expect(c.read(hasPremiumProvider), isFalse);
      expect(store.completed, [other]);
    });

    test('a store that was unreachable at launch can be asked again', () async {
      final store = _FakeStore(available: false, product: _product);
      final c = await _container(store);
      final controller = c.read(purchaseControllerProvider.notifier);
      expect(c.read(purchaseControllerProvider).canBuy, isFalse);

      store.available = true;
      await controller.reloadIfUnavailable();

      expect(c.read(purchaseControllerProvider).canBuy, isTrue);
      expect(c.read(purchaseControllerProvider).product?.price, r'$4.99');

      // With the product in hand there is nothing to ask again.
      final checks = store.availabilityChecks;
      await controller.reloadIfUnavailable();
      expect(store.availabilityChecks, checks);
    });

    test('unavailable store or missing product disables buying', () async {
      final offline = await _container(_FakeStore(available: false));
      expect(offline.read(purchaseControllerProvider).canBuy, isFalse);
      expect(offline.read(purchaseControllerProvider).storeAvailable, isFalse);

      final noProduct = await _container(_FakeStore());
      expect(noProduct.read(purchaseControllerProvider).canBuy, isFalse);
      await noProduct.read(purchaseControllerProvider.notifier).buy();
      expect(noProduct.read(hasPremiumProvider), isFalse);
    });
  });
}
