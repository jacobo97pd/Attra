import 'dart:async';

import 'package:attra/src/features/monetization/data/boost_service.dart';
import 'package:attra/src/features/monetization/data/iap_service.dart';
import 'package:attra/src/features/monetization/data/purchase_delivery_router.dart';
import 'package:attra/src/features/monetization/data/storekit_pending_transactions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// Dos cuentas de Attra en dos dispositivos con el MISMO Apple ID (las cuentas
/// demo de App Review). StoreKit reparte cada renovación automática (en
/// sandbox, una cada ~5 minutos) por `Transaction.updates` a todos los
/// dispositivos como `purchased`. En el de la segunda cuenta el backend
/// contesta `claimed_by_other_account` y eso se pintaba como error en el
/// paywall y la hoja de Boosts, sin que nadie hubiera comprado nada.
class _FakeStore implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> _controller =
      StreamController<List<PurchaseDetails>>.broadcast();

  final List<PurchaseDetails> completed = <PurchaseDetails>[];

  /// Lo que la tienda devuelve al pulsar "Restaurar compras".
  List<PurchaseDetails> owned = <PurchaseDetails>[];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: ids.map(_product).toList(),
        notFoundIDs: const <String>[],
      );

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async =>
      true;

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    final List<PurchaseDetails> snapshot = List<PurchaseDetails>.of(owned);
    scheduleMicrotask(() => _controller.add(snapshot));
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa en el test');
}

ProductDetails _product(String id) => ProductDetails(
      id: id,
      title: id,
      description: id,
      price: '9,99 €',
      rawPrice: 9.99,
      currencyCode: 'EUR',
    );

PurchaseDetails _renewal({
  String id = 'tx-renovacion',
  PurchaseStatus status = PurchaseStatus.purchased,
}) =>
    PurchaseDetails(
      purchaseID: id,
      productID: 'attra_pro_monthly',
      verificationData: PurchaseVerificationData(
        localVerificationData: 'jws',
        serverVerificationData: 'jws',
        source: 'app_store',
      ),
      transactionDate: '0',
      status: status,
    )..pendingCompletePurchase = true;

const IapDeliveryResult _claimed = IapDeliveryResult(
  delivered: false,
  permanent: true,
  reason: IapService.claimedByOtherAccount,
  message: 'Esta compra ya está asociada a otra cuenta de Attra.',
);

/// Backend falso: `verifyPurchase` contesta que la suscripción es de otra
/// cuenta, con su `reason`, como hace functions/src/subscriptions.ts.
class _ClaimedBoosts implements BoostService {
  @override
  Future<({bool ok, bool permanent, String? message, String? reason})>
      verifySubscriptionDetailed({
    required String productId,
    required String platform,
    required String verificationData,
    String? purchaseId,
    String? period,
  }) async =>
          (
            ok: false,
            permanent: true,
            message: 'Esta compra ya está asociada a otra cuenta de Attra.',
            reason: 'claimed_by_other_account',
          );

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa en el test');
}

void main() {
  late _FakeStore store;
  late List<int> cerradasPorId;

  setUp(() {
    store = _FakeStore();
    cerradasPorId = <int>[];
  });

  IapService build({
    List<SK2Transaction> pendientes = const <SK2Transaction>[],
  }) =>
      IapService(
        iap: store,
        silentRestoreSupported: false,
        pendingTransactions: StoreKitPendingTransactions(
          isIos: true,
          storeKit2: true,
          unfinished: () async => pendientes,
          finishById: (int id) async => cerradasPorId.add(id),
        ),
      );

  test(
      'renovación de la tienda que es de OTRA cuenta: se cierra en silencio, '
      'sin error ni aviso', () async {
    final IapService service = build();
    service.deliver = (PurchaseDetails _) async => _claimed;
    int avisos = 0;
    service.addListener(() {
      if (service.error != null || service.notice != null) avisos++;
    });

    await service.init(productIds: <String>{'attra_pro_monthly'});
    // Tres renovaciones aceleradas de sandbox seguidas.
    for (int i = 0; i < 3; i++) {
      await service.handlePurchases(<PurchaseDetails>[_renewal(id: 'tx-$i')]);
    }

    expect(store.completed, hasLength(3),
        reason: 'se cierra igual: dejarla abierta bloquearía el producto');
    expect(service.error, isNull);
    expect(service.notice, isNull);
    expect(avisos, 0, reason: 'ni el paywall ni la hoja de Boosts pintan nada');
    service.dispose();
  });

  test('la misma respuesta SÍ se enseña si el usuario ha pulsado comprar',
      () async {
    final IapService service = build();
    service.deliver = (PurchaseDetails _) async => _claimed;
    await service.init(productIds: <String>{'attra_pro_monthly'});

    await service.buy('attra_pro_monthly');
    await service.handlePurchases(<PurchaseDetails>[_renewal()]);

    expect(store.completed, hasLength(1));
    expect(service.error, contains('otra cuenta'));
    expect(service.notice, contains('otra cuenta'));

    // Resuelta esa compra, la siguiente renovación de la tienda vuelve a ser
    // silenciosa.
    service.clearError();
    service.clearNotice();
    await service.handlePurchases(<PurchaseDetails>[_renewal(id: 'tx-otra')]);
    expect(service.error, isNull);
    expect(service.notice, isNull);
    service.dispose();
  });

  test('y también durante "Restaurar compras"', () async {
    store.owned = <PurchaseDetails>[
      _renewal(id: 'tx-restaurada', status: PurchaseStatus.restored),
    ];
    final IapService service = build();
    service.deliver = (PurchaseDetails _) async => _claimed;
    await service.init(productIds: <String>{'attra_pro_monthly'});

    unawaited(service.restore());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.notice, contains('otra cuenta'));
    service.dispose();
  });

  test('una transacción colgada de OTRA cuenta al arrancar tampoco avisa',
      () async {
    final IapService service = build(
      pendientes: <SK2Transaction>[
        SK2Transaction(
          id: '7007',
          originalId: '7000',
          productId: 'attra_pro_monthly',
          purchaseDate: '1754524800000',
          appAccountToken: null,
          receiptData: 'jws-de-apple',
        ),
      ],
    );
    service.deliver = (PurchaseDetails _) async => _claimed;

    await service.init(productIds: <String>{'attra_pro_monthly'});

    expect(cerradasPorId, <int>[7007]);
    expect(service.notice, isNull);
    expect(service.error, isNull);
    service.dispose();
  });

  test('otros rechazos DEFINITIVOS siguen avisando aunque nadie los pida',
      () async {
    // Solo se silencia "asociada a otra cuenta": un producto que el servidor
    // no reconoce es dinero sin entregar y hay que contarlo.
    final IapService service = build();
    service.deliver = (PurchaseDetails _) async => const IapDeliveryResult(
          delivered: false,
          permanent: true,
          message: 'Producto desconocido.',
        );
    await service.init(productIds: <String>{'attra_pro_monthly'});

    await service.handlePurchases(<PurchaseDetails>[_renewal()]);

    expect(service.notice, 'Producto desconocido.');
    service.dispose();
  });

  test('el enrutador de sesión pasa el motivo del backend al servicio',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final PurchaseDeliveryRouter router = PurchaseDeliveryRouter(
        boostService: _ClaimedBoosts(),
        iapService: build(),
      );
      await router.start(subscriptionIds: <String>{'attra_pro_monthly'});

      await router.iap.handlePurchases(<PurchaseDetails>[_renewal()]);

      expect(store.completed, hasLength(1));
      expect(router.iap.error, isNull,
          reason: 'renovación de la tienda: sin error en el paywall');
      expect(router.iap.notice, isNull);
      router.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
