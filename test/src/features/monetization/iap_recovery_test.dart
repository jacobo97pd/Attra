import 'dart:async';

import 'package:attra/src/features/monetization/data/iap_service.dart';
import 'package:attra/src/features/monetization/data/storekit_pending_transactions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// EL CIRCUITO REAL, no una réplica de la lógica.
///
/// Los dos arreglos anteriores se dieron por buenos con tests que ejercitaban
/// lambdas inyectadas mientras el cableado de producción seguía roto. Aquí se
/// monta el `IapService` de verdad, con su `StoreKitPendingTransactions`
/// inyectado, y se comprueba lo que decide el dinero: qué se entrega, qué se
/// cierra y qué NO se cierra jamás.
class _FakeStore implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> _controller =
      StreamController<List<PurchaseDetails>>.broadcast();

  final List<PurchaseDetails> completed = <PurchaseDetails>[];
  int restoreCalls = 0;

  /// Código que `buyNonConsumable`/`buyConsumable` debe lanzar, si toca.
  String? throwOnBuy;

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
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    final String? code = throwOnBuy;
    if (code != null) throw PlatformException(code: code);
    return true;
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) =>
      buyNonConsumable(purchaseParam: purchaseParam);

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls++;
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

SK2Transaction _unfinished({
  required String id,
  String product = 'attra_pro_monthly',
  String? jws = 'jws-de-apple',
}) =>
    SK2Transaction(
      id: id,
      originalId: id,
      productId: product,
      purchaseDate: '1754524800000',
      appAccountToken: null,
      receiptData: jws,
    );

void main() {
  late _FakeStore store;
  late List<int> cerradas;
  late List<PurchaseDetails> entregadas;

  setUp(() {
    store = _FakeStore();
    cerradas = <int>[];
    entregadas = <PurchaseDetails>[];
  });

  /// Servicio con la lista de transacciones colgadas que se le pase.
  IapService build({
    List<SK2Transaction> pendientes = const <SK2Transaction>[],
    Future<void> Function(int id)? finishById,
    Set<String> consumableIds = const <String>{},
    Duration nativeTimeout = const Duration(seconds: 12),
  }) =>
      IapService(
        iap: store,
        consumableIds: consumableIds,
        pendingTransactions: StoreKitPendingTransactions(
          isIos: true,
          storeKit2: true,
          nativeTimeout: nativeTimeout,
          unfinished: () async => pendientes,
          finishById: finishById ?? (int id) async => cerradas.add(id),
        ),
      );

  test('al arrancar se ENTREGA la compra colgada y solo entonces se cierra',
      () async {
    // Este es el fallo que dejó los ingresos a cero: la transacción del 7 de
    // agosto seguía sin terminar, el plugin rechazaba toda compra nueva de ese
    // producto y `verifyPurchase` no llegó a invocarse ni una vez. Ahora el
    // arranque la recupera con su recibo.
    final IapService service = build(
      pendientes: <SK2Transaction>[_unfinished(id: '1001')],
    );
    service.deliver = (PurchaseDetails p) async {
      entregadas.add(p);
      return const IapDeliveryResult(delivered: true);
    };

    await service.init(productIds: <String>{'attra_pro_monthly'});

    expect(entregadas, hasLength(1), reason: 'sin entrega no hay concesión');
    expect(
      entregadas.single.verificationData.serverVerificationData,
      'jws-de-apple',
      reason: 'el backend rechaza cualquier llamada sin recibo',
    );
    expect(
      entregadas.single.purchaseID,
      '1001',
      reason: 'mismo id que la compra original: el ledger no concede dos veces',
    );
    expect(cerradas, <int>[1001]);
    service.dispose();
  });

  test('si la entrega falla NO se cierra, y se reintenta al siguiente arranque',
      () async {
    // Cerrarla sin conceder deja a alguien pagado y sin plan. Y ya no hace
    // falta: el bloqueo dura lo que dure la avería, no para siempre.
    final List<SK2Transaction> pendientes = <SK2Transaction>[
      _unfinished(id: '2002'),
    ];
    final IapService primera = build(pendientes: pendientes);
    primera.deliver = (PurchaseDetails _) async =>
        const IapDeliveryResult(delivered: false, message: 'sin red');

    await primera.init(productIds: <String>{'attra_pro_monthly'});
    expect(cerradas, isEmpty, reason: 'no se tira una compra pagada');
    primera.dispose();

    final IapService segunda = build(pendientes: pendientes);
    segunda.deliver =
        (PurchaseDetails _) async => const IapDeliveryResult(delivered: true);

    await segunda.init(productIds: <String>{'attra_pro_monthly'});

    expect(cerradas, <int>[2002], reason: 'se cura sola en cuanto hay backend');
    expect(segunda.notice, contains('sin activar'));
    segunda.dispose();
  });

  test('un CONSUMIBLE que no se puede entregar no se cierra nunca', () async {
    // "Restaurar" no devuelve consumibles: Apple no los incluye en
    // `currentEntitlements`. Cerrar un pack sin abonarlo es dinero perdido sin
    // rastro y sin forma de recuperarlo, ni siquiera desde soporte.
    final IapService service = build(
      pendientes: <SK2Transaction>[
        _unfinished(id: '3003', product: 'attra_pack_10'),
      ],
      consumableIds: <String>{'attra_pack_10'},
    );
    service.deliver = (PurchaseDetails _) async =>
        const IapDeliveryResult(delivered: false, message: 'backend caído');

    await service.init(productIds: <String>{'attra_pack_10'});

    expect(cerradas, isEmpty);
    service.dispose();
  });

  test('sin entrega configurada no se cierra nada', () async {
    // Una pantalla puede crear su propio IapService sin backend. Antes eso
    // contaba como fallo de entrega, gastaba intentos y acababa cerrando una
    // compra pagada que nunca salió del dispositivo.
    final IapService service = build(
      pendientes: <SK2Transaction>[_unfinished(id: '4004')],
    );

    await service.init(productIds: <String>{'attra_pro_monthly'});

    expect(cerradas, isEmpty);
    service.dispose();
  });

  test('un cierre nativo que no responde no cuelga el arranque', () async {
    // `finish(id:)` del plugin no llama al completion si no encuentra la
    // transacción en `Transaction.all`: el Future no completa jamás. Sin tope,
    // `init` no volvía nunca y el usuario se quedaba con el spinner.
    final IapService service = build(
      pendientes: <SK2Transaction>[_unfinished(id: '5005')],
      finishById: (int _) => Completer<void>().future,
      nativeTimeout: const Duration(milliseconds: 30),
    );
    service.deliver =
        (PurchaseDetails _) async => const IapDeliveryResult(delivered: true);

    await service
        .init(productIds: <String>{'attra_pro_monthly'})
        .timeout(const Duration(seconds: 5));

    // Y si el usuario reintenta la compra, se le dice la verdad: el plan está
    // activo, pero el producto puede seguir bloqueado. Prometerle que ya puede
    // comprar es el mensaje falso que ya se dio dos veces.
    store.throwOnBuy = 'storekit_duplicate_product_object';
    await service
        .buyProduct(_product('attra_pro_monthly'))
        .timeout(const Duration(seconds: 5));

    expect(service.error, contains('ya está activa'));
    expect(service.error, contains('cierra la app'));
    service.dispose();
  });

  test('el error de producto duplicado acaba entregando la compra atascada',
      () async {
    // Es EL error que veía el usuario:
    // PlatformException(storekit_duplicate_product_object, ...). No hay que
    // volver a cobrar: hay que entregar lo que quedó a medias.
    bool backendOk = false;
    final IapService service = build(
      pendientes: <SK2Transaction>[_unfinished(id: '6006')],
    );
    service.deliver = (PurchaseDetails p) async {
      entregadas.add(p);
      if (!backendOk) {
        return const IapDeliveryResult(delivered: false, message: 'sin red');
      }
      return const IapDeliveryResult(delivered: true);
    };
    // En el arranque el backend aún no responde, así que la transacción sigue
    // colgada y el producto, bloqueado.
    await service.init(productIds: <String>{'attra_pro_monthly'});
    expect(cerradas, isEmpty);
    backendOk = true;
    store.throwOnBuy = 'storekit_duplicate_product_object';
    entregadas.clear();

    final bool started =
        await service.buyProduct(_product('attra_pro_monthly'));

    expect(started, isFalse);
    expect(entregadas, hasLength(1), reason: 'se entrega la atascada');
    expect(cerradas, <int>[6006], reason: 'y se cierra: producto desbloqueado');
    expect(service.error, contains('activar'));
    expect(service.isBusy, isFalse, reason: 'el botón debe volver a responder');
    service.dispose();
  });

  test('si el bloqueo persiste se dice la verdad, no "espera unos segundos"',
      () async {
    final IapService service = build(
      pendientes: <SK2Transaction>[_unfinished(id: '7007')],
    );
    service.deliver = (PurchaseDetails _) async =>
        const IapDeliveryResult(delivered: false, message: 'sin red');
    await service.init(productIds: <String>{'attra_pro_monthly'});
    store.throwOnBuy = 'storekit_duplicate_product_object';

    await service.buyProduct(_product('attra_pro_monthly'));

    expect(cerradas, isEmpty);
    expect(
      service.error,
      contains('no se te cobrará dos veces'),
      reason: 'lo que no puede pasar es que crea que va a pagar otra vez',
    );
    service.dispose();
  });

  test('un rechazo DEFINITIVO cierra la compra y deja aviso que sobrevive',
      () async {
    // El aviso no puede vivir en `error`: el paywall llama a `clearError()` al
    // abrirse, así que el único mensaje que explicaba qué pasó con el dinero se
    // borraba siempre antes de poder pintarse.
    final IapService service = build(
      pendientes: <SK2Transaction>[_unfinished(id: '8008')],
    );
    service.deliver = (PurchaseDetails _) async => const IapDeliveryResult(
          delivered: false,
          permanent: true,
          message: 'Esta compra ya está asociada a otra cuenta.',
        );

    await service.init(productIds: <String>{'attra_pro_monthly'});
    service.clearError();

    expect(cerradas, <int>[8008], reason: 'reintentar no cambiaría nada');
    expect(service.error, isNull);
    expect(service.notice, contains('otra cuenta'));
    service.dispose();
  });

  test('no se entrega dos veces la misma transacción en paralelo', () async {
    // El stream y la recuperación pueden traer la MISMA transacción a la vez. El
    // segundo cierre del mismo id se queda esperando para siempre, porque el
    // Swift del plugin no responde cuando ya no la encuentra.
    final Completer<void> enVuelo = Completer<void>();
    int llamadas = 0;
    final IapService service = build(
      pendientes: <SK2Transaction>[_unfinished(id: '9009')],
    );
    service.deliver = (PurchaseDetails _) async {
      llamadas++;
      await enVuelo.future;
      return const IapDeliveryResult(delivered: true);
    };

    final Future<void> porElStream = service.handlePurchases(<PurchaseDetails>[
      PurchaseDetails(
        purchaseID: '9009',
        productID: 'attra_pro_monthly',
        verificationData: PurchaseVerificationData(
          localVerificationData: 'jws-de-apple',
          serverVerificationData: 'jws-de-apple',
          source: 'app_store',
        ),
        transactionDate: '0',
        status: PurchaseStatus.purchased,
      )..pendingCompletePurchase = true,
    ]);
    final Future<PendingRecoveryOutcome> porLaCola =
        service.recoverUnfinishedPurchases();

    enVuelo.complete();
    await porElStream;
    await porLaCola;

    expect(llamadas, 1, reason: 'una transacción, una entrega');
    service.dispose();
  });

  test('una compra RESTAURADA se cierra, aunque el plugin diga que no toca',
      () async {
    // `SK2PurchaseDetails.pendingCompletePurchase` es `status == purchased`, así
    // que en las restauradas vale false y nunca se cerraban: el usuario pulsaba
    // "Restaurar", recuperaba el plan y el producto seguía bloqueado. Es una de
    // las vías por las que se generaban las transacciones colgadas.
    final IapService service = build();
    service.deliver =
        (PurchaseDetails _) async => const IapDeliveryResult(delivered: true);

    await service.handlePurchases(<PurchaseDetails>[
      PurchaseDetails(
        purchaseID: '4242',
        productID: 'attra_pro_monthly',
        verificationData: PurchaseVerificationData(
          localVerificationData: 'jws',
          serverVerificationData: 'jws',
          source: 'app_store',
        ),
        transactionDate: '0',
        status: PurchaseStatus.restored,
      ),
    ]);

    expect(store.completed, hasLength(1));
    service.dispose();
  });
}
