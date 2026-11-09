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

class _FakeStore implements StoreGateway {
  _FakeStore({this.available = true, this.product});

  final bool available;
  final ProductDetails? product;
  final controller = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <PurchaseDetails>[];
  int buyCalls = 0;
  int restoreCalls = 0;
  List<PurchaseDetails>? emitOnRestore;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;

  @override
  Future<bool> isAvailable() async => available;

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
    if (emitOnRestore != null) controller.add(emitOnRestore!);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }
}

Future<ProviderContainer> _container(_FakeStore store) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [storeGatewayProvider.overrideWithValue(store)],
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

    test('other product IDs are acknowledged but never unlock', () async {
      final store = _FakeStore(product: _product);
      final c = await _container(store);

      final other = _purchase(PurchaseStatus.purchased, productId: 'other');
      store.controller.add([other]);
      await pumpEventQueue();

      expect(c.read(hasPremiumProvider), isFalse);
      expect(store.completed, [other]);
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
