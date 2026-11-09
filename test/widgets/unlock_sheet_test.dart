import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:runthru/services/purchase_service.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/unlock_sheet.dart';

class _FakeConfig extends AsyncNotifier<AppConfig> implements ConfigNotifier {
  _FakeConfig(this._initial);
  final AppConfig _initial;

  @override
  Future<AppConfig> build() async => _initial;

  @override
  Future<void> setHasPremium(bool value) async {
    state = AsyncData(state.requireValue.copyWith(hasPremium: value));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeStore implements StoreGateway {
  _FakeStore({this.product});
  final ProductDetails? product;
  // Nothing is emitted in these widget tests; the stream stays empty.
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();

  int buyCalls = 0;
  int restoreCalls = 0;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetails?> queryProduct(String id) async => product;
  @override
  Future<bool> buyNonConsumable(ProductDetails product) async {
    buyCalls++;
    return true;
  }

  @override
  Future<void> restorePurchases() async => restoreCalls++;
  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}
}

final _product = ProductDetails(
  id: runThruUnlockProductId,
  title: 'RunThru Unlock',
  description: '',
  price: r'$4.99',
  rawPrice: 4.99,
  currencyCode: 'USD',
);

Widget _harness(_FakeStore store, {bool owned = false}) => ProviderScope(
  overrides: [
    storeGatewayProvider.overrideWithValue(store),
    configProvider.overrideWith(
      () => _FakeConfig(AppConfig(hasPremium: owned)),
    ),
  ],
  child: const MaterialApp(home: Scaffold(body: UnlockSheet())),
);

void main() {
  testWidgets('shows the store price, buys and restores', (tester) async {
    final store = _FakeStore(product: _product);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_harness(store));
    await tester.pumpAndSettle();

    expect(find.text(r'Unlock for $4.99'), findsOneWidget);
    for (final benefit in runThruUnlockBenefits) {
      expect(find.text(benefit), findsOneWidget);
    }

    await tester.tap(find.text(r'Unlock for $4.99'));
    await tester.pump();
    expect(store.buyCalls, 1);
    expect(find.text('Waiting for the store…'), findsOneWidget);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('restore button calls the store', (tester) async {
    final store = _FakeStore(product: _product);
    await tester.pumpWidget(_harness(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore purchase'));
    await tester.pumpAndSettle();
    expect(store.restoreCalls, 1);
  });

  testWidgets('missing product disables buying with a clear note', (
    tester,
  ) async {
    final store = _FakeStore();
    await tester.pumpWidget(_harness(store));
    await tester.pumpAndSettle();

    expect(find.text('Unlock unavailable'), findsOneWidget);
    expect(find.textContaining('not available in this store'), findsOneWidget);
    await tester.tap(find.text('Unlock unavailable'));
    expect(store.buyCalls, 0);
  });

  testWidgets('owners see it as active', (tester) async {
    final store = _FakeStore(product: _product);
    await tester.pumpWidget(_harness(store, owned: true));
    await tester.pumpAndSettle();

    expect(find.text('Unlocked'), findsOneWidget);
    expect(find.textContaining('is active'), findsOneWidget);
  });

  testWidgets('locked-feature prompt opens the unlock sheet', (tester) async {
    final store = _FakeStore(product: _product);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeGatewayProvider.overrideWithValue(store),
          configProvider.overrideWith(() => _FakeConfig(const AppConfig())),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: UnlockPrompt(title: 'Page ranges', body: 'Read less.'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('See RunThru Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('RunThru Unlock'), findsOneWidget);
    expect(find.text(r'Unlock for $4.99'), findsOneWidget);
  });
}
