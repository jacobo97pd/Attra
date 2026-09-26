import 'dart:async';

import 'package:attra/src/features/monetization/data/boost_service.dart';
import 'package:attra/src/features/monetization/data/iap_service.dart';
import 'package:attra/src/features/monetization/data/purchase_delivery_router.dart';
import 'package:attra/src/features/monetization/data/storekit_pending_transactions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Google Play NO manda las renovaciones al `purchaseStream`. Sin reentregar lo
/// que la tienda tiene a tu nombre al empezar la sesión, el backend no se
/// enteraba de la renovación y el suscriptor de Android pasaba a Free al mes
/// mientras Google le seguía cobrando.
class _FakeStore implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> _controller =
      StreamController<List<PurchaseDetails>>.broadcast();

  int restoreCalls = 0;

  /// Lo que Play "devuelve" al restaurar.
  List<PurchaseDetails> owned = <PurchaseDetails>[];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: const <ProductDetails>[],
        notFoundIDs: const <String>[],
      );

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls++;
    // Como el plugin de Android: las compras llegan por el stream DESPUÉS.
    final List<PurchaseDetails> snapshot = List<PurchaseDetails>.of(owned);
    scheduleMicrotask(() => _controller.add(snapshot));
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa en el test');
}

/// Backend de compras falso: apunta lo que llegaría a `verifyPurchase`.
class _FakeBoosts implements BoostService {
  final List<Map<String, String?>> verified = <Map<String, String?>>[];

  @override
  Future<({bool ok, bool permanent, String? message})>
      verifySubscriptionDetailed({
    required String productId,
    required String platform,
    required String verificationData,
    String? purchaseId,
    String? period,
  }) async {
    verified.add(<String, String?>{
      'productId': productId,
      'platform': platform,
      'verificationData': verificationData,
      'purchaseId': purchaseId,
    });
    return (ok: true, permanent: false, message: null);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa en el test');
}

PurchaseDetails _restored(String orderId) => PurchaseDetails(
      purchaseID: orderId,
      productID: 'attra_plus',
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: 'purchase-token',
        source: 'google_play',
      ),
      transactionDate: '1754524800000',
      status: PurchaseStatus.restored,
    );

/// Compra tal y como la construye el plugin de Android 0.5.0. Mientras está
/// PENDIENTE de pago Play no tiene orderId (el plugin lo convierte en '').
GooglePlayPurchaseDetails _play({
  required PurchaseStateWrapper state,
  String orderId = '',
  String productId = 'attra_pack_10',
}) =>
    GooglePlayPurchaseDetails.fromPurchase(
      PurchaseWrapper(
        orderId: orderId,
        packageName: 'com.jpedrero.attra',
        purchaseTime: 1754524800000,
        purchaseToken: 'token-T',
        signature: 'firma',
        products: <String>[productId],
        isAutoRenewing: false,
        originalJson: '{}',
        isAcknowledged: false,
        purchaseState: state,
      ),
    ).single;

/// Lo que hace `restorePurchases` de Android con TODO lo que devuelve Play,
/// pagado o no (in_app_purchase_android_platform.dart).
GooglePlayPurchaseDetails _restoredPlay({
  required PurchaseStateWrapper state,
  String orderId = '',
  String productId = 'attra_pack_10',
}) =>
    _play(state: state, orderId: orderId, productId: productId)
      ..status = PurchaseStatus.restored;

void main() {
  late _FakeStore store;
  late List<PurchaseDetails> entregadas;

  setUp(() {
    store = _FakeStore();
    entregadas = <PurchaseDetails>[];
  });

  IapService build({required bool android}) => IapService(
        iap: store,
        silentRestoreSupported: android,
        silentRestoreWindow: const Duration(milliseconds: 20),
        pendingTransactions: StoreKitPendingTransactions(
          isIos: !android,
          storeKit2: true,
          unfinished: () async => const [],
          finishById: (int _) async {},
        ),
      );

  test('Android: la renovación (orderId nuevo) llega al backend sin tocar nada',
      () async {
    store.owned = <PurchaseDetails>[_restored('GPA.1234-5678..1')];
    final IapService service = build(android: true);
    service.deliver = (PurchaseDetails p) async {
      entregadas.add(p);
      return const IapDeliveryResult(delivered: true);
    };
    int restauradasAvisadas = -1;
    service.onRestoreFinished = (int n) => restauradasAvisadas = n;
    int avisosDeCompra = 0;
    service.onDelivered = (PurchaseDetails _) => avisosDeCompra++;

    await service.init(productIds: <String>{'attra_plus'});
    await service.refreshSubscriptionsSilently();

    expect(store.restoreCalls, 1);
    expect(entregadas.single.purchaseID, 'GPA.1234-5678..1');
    expect(
      entregadas.single.verificationData.serverVerificationData,
      'purchase-token',
      reason: 'el backend valida el token con Google',
    );
    expect(restauradasAvisadas, -1,
        reason: 'silenciosa: no dispara el aviso del botón "Restaurar"');
    expect(avisosDeCompra, 0,
        reason: 'ni el "¡Listo!" del paywall: nadie ha comprado nada');
    expect(service.isBusy, isFalse);
    service.dispose();
  });

  test('Android: un rechazo en la reentrega silenciosa no asusta al usuario',
      () async {
    store.owned = <PurchaseDetails>[_restored('GPA.9')];
    final IapService service = build(android: true);
    service.deliver = (PurchaseDetails _) async => const IapDeliveryResult(
          delivered: false,
          permanent: true,
          message: 'Esta compra ya está asociada a otra cuenta de Attra.',
        );

    await service.init(productIds: <String>{'attra_plus'});
    await service.refreshSubscriptionsSilently();

    expect(service.notice, isNull,
        reason: 'no aparece un aviso en cada arranque por algo que no pidió');
    expect(service.error, isNull);
    service.dispose();
  });

  test('Android: un fallo temporal tampoco deja un error colgado', () async {
    store.owned = <PurchaseDetails>[_restored('GPA.10')];
    final IapService service = build(android: true);
    service.deliver = (PurchaseDetails _) async =>
        const IapDeliveryResult(delivered: false, message: 'sin red');

    await service.init(productIds: <String>{'attra_plus'});
    await service.refreshSubscriptionsSilently();

    expect(service.error, isNull);
    service.dispose();
  });

  // Pago pendiente (efectivo, métodos lentos): la reentrega de cada arranque
  // lo mandaba al backend como compra hecha, que lo abonaba sin cobrar y otra
  // vez al pagarse (sin orderId primero, con orderId después).
  test('Android: lo PENDIENTE de pago no se entrega; al pagarse, una vez',
      () async {
    store.owned = <PurchaseDetails>[
      _restoredPlay(state: PurchaseStateWrapper.pending),
      _restoredPlay(
        state: PurchaseStateWrapper.purchased,
        orderId: 'GPA.1234-5678..1',
        productId: 'attra_plus',
      ),
    ];
    final IapService service = build(android: true);
    service.deliver = (PurchaseDetails p) async {
      entregadas.add(p);
      return const IapDeliveryResult(delivered: true);
    };

    await service.init(productIds: <String>{'attra_plus', 'attra_pack_10'});
    await service.refreshSubscriptionsSilently();

    expect(
      entregadas.map((PurchaseDetails p) => p.productID),
      <String>['attra_plus'],
      reason: 'el pack sin pagar no llega al backend',
    );

    // Play la confirma pagada: llega como `purchased`, ya con orderId.
    await service.handlePurchases(<PurchaseDetails>[
      _play(
        state: PurchaseStateWrapper.purchased,
        orderId: 'GPA.1111-2222-3333-44444',
      ),
    ]);
    expect(entregadas.last.productID, 'attra_pack_10');
    expect(entregadas.last.purchaseID, 'GPA.1111-2222-3333-44444');
    expect(entregadas.length, 2, reason: 'el pack se entrega UNA vez');
    service.dispose();
  });

  test('el "Restaurar" del usuario tampoco entrega lo pendiente de pago',
      () async {
    store.owned = <PurchaseDetails>[
      _restoredPlay(
          state: PurchaseStateWrapper.pending, productId: 'attra_plus'),
    ];
    final IapService service = build(android: true);
    service.deliver = (PurchaseDetails p) async {
      entregadas.add(p);
      return const IapDeliveryResult(delivered: true);
    };

    await service.init(productIds: <String>{'attra_plus'});
    unawaited(service.restore());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(entregadas, isEmpty);
    service.dispose();
  });

  test('isUnpaidPlayPurchase: solo lo pendiente de Play', () {
    expect(
      IapService.isUnpaidPlayPurchase(
        _restoredPlay(state: PurchaseStateWrapper.pending),
      ),
      isTrue,
    );
    expect(
      IapService.isUnpaidPlayPurchase(
        _restoredPlay(state: PurchaseStateWrapper.purchased, orderId: 'GPA.1'),
      ),
      isFalse,
    );
    expect(IapService.isUnpaidPlayPurchase(_restored('GPA.2')), isFalse,
        reason: 'las de iOS / genéricas no se tocan');
  });

  test('iOS: no se restaura en silencio (puede pedir el Apple ID)', () async {
    final IapService service = build(android: false);
    service.deliver =
        (PurchaseDetails _) async => const IapDeliveryResult(delivered: true);

    await service.init(productIds: <String>{'attra_pro_monthly'});
    await service.refreshSubscriptionsSilently();

    expect(store.restoreCalls, 0);
    service.dispose();
  });

  test('el "Restaurar" del usuario sigue avisando como siempre', () async {
    store.owned = <PurchaseDetails>[_restored('GPA.11')];
    final IapService service = build(android: true);
    service.deliver = (PurchaseDetails _) async => const IapDeliveryResult(
        delivered: false, permanent: true, message: 'otra cuenta');

    await service.init(productIds: <String>{'attra_plus'});
    // `restore()` espera 3 s de ventana; se ejecuta sin bloquear el test.
    unawaited(service.restore());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.notice, 'otra cuenta');
    service.dispose();
  });

  // De punta a punta en el cliente: la sesión arranca, Play devuelve la
  // renovación y esta llega a `verifyPurchase` con su orderId NUEVO (que es lo
  // que el backend reconoce como renovación) y el token para validarla.
  test('la sesión la lanza al arrancar y la renovación llega a verifyPurchase',
      () async {
    store.owned = <PurchaseDetails>[_restored('GPA.1234-5678..2')];
    final _FakeBoosts boosts = _FakeBoosts();
    final PurchaseDeliveryRouter router = PurchaseDeliveryRouter(
      boostService: boosts,
      iapService: build(android: true),
    );
    int planesRefrescados = 0;
    router.onSubscriptionDelivered = () => planesRefrescados++;

    await router.start(subscriptionIds: <String>{'attra_plus'});
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(store.restoreCalls, 1);
    expect(boosts.verified.single['purchaseId'], 'GPA.1234-5678..2');
    expect(boosts.verified.single['platform'], 'play_store');
    expect(boosts.verified.single['verificationData'], 'purchase-token');
    expect(planesRefrescados, 1, reason: 'se recargan los entitlements');
    router.dispose();
  });
}
