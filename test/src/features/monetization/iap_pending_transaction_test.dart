import 'dart:async';

import 'package:attra/src/features/monetization/data/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// La cola de la tienda NO admite dos transacciones abiertas del mismo
/// producto. Si una compra pagada no se entrega y se deja sin completar, ese
/// producto queda BLOQUEADO: cualquier intento posterior revienta con
/// `storekit_duplicate_product_object` y la persona no puede suscribirse.
///
/// Le pasó al dueño del producto con `attra_pro_monthly`: pagó, la entrega
/// falló, y a partir de ahí el botón "Hazte Pro" solo devolvía un volcado de
/// excepción.
class _FakeStore implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> _controller =
      StreamController<List<PurchaseDetails>>.broadcast();

  final List<PurchaseDetails> completed = <PurchaseDetails>[];
  int restoreCalls = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls++;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa en el test');
}

PurchaseDetails _purchase({String id = 'tx-1'}) => PurchaseDetails(
      purchaseID: id,
      productID: 'attra_pro_monthly',
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local',
        serverVerificationData: 'server',
        source: 'app_store',
      ),
      transactionDate: '0',
      status: PurchaseStatus.purchased,
    )..pendingCompletePurchase = true;

void main() {
  late _FakeStore store;
  late IapService service;

  setUp(() {
    store = _FakeStore();
    service = IapService(iap: store);
  });

  tearDown(() => service.dispose());

  test('un fallo temporal NO cierra la transacción a la primera', () async {
    // Cerrarla sin haber concedido dejaría a alguien pagado y sin plan.
    service.deliver = (PurchaseDetails _) async =>
        const IapDeliveryResult(delivered: false, message: 'sin red');

    await service.handlePurchases(<PurchaseDetails>[_purchase()]);

    expect(store.completed, isEmpty);
  });

  test('por muchos intentos que fallen, NUNCA se cierra sin entregar',
      () async {
    // Antes, al tercer intento se cerraba igualmente ("de lo irrecuperable a lo
    // recuperable, porque el recibo persiste y Restaurar vuelve a entregarla").
    // Esa premisa era falsa para los consumibles: "Restaurar" no los devuelve
    // (Apple no los incluye en `currentEntitlements`), así que cerrar un pack
    // sin abonarlo era dinero perdido sin rastro. Y para las suscripciones ya no
    // hace falta: `recoverUnfinishedPurchases` reintenta la entrega en cada
    // arranque con el recibo, así que el bloqueo del producto dura lo que dure
    // la avería, no para siempre.
    service.deliver = (PurchaseDetails _) async =>
        const IapDeliveryResult(delivered: false, message: 'sin red');

    final PurchaseDetails p = _purchase();
    for (int i = 0; i < 5; i++) {
      await service.handlePurchases(<PurchaseDetails>[p]);
    }

    expect(store.completed, isEmpty);
  });

  test('una entrega correcta cierra la transacción y limpia el error',
      () async {
    service.deliver =
        (PurchaseDetails _) async => const IapDeliveryResult(delivered: true);

    await service.handlePurchases(<PurchaseDetails>[_purchase()]);

    expect(store.completed, hasLength(1));
    expect(service.error, isNull);
  });

  test('un fallo DEFINITIVO cierra la transacción de inmediato', () async {
    // Reintentar no arregla nada (recibo ya canjeado, producto desconocido):
    // dejarla abierta solo bloquearía el producto sin ninguna ganancia.
    service.deliver = (PurchaseDetails _) async => const IapDeliveryResult(
          delivered: false,
          permanent: true,
          message: 'recibo ya canjeado',
        );

    await service.handlePurchases(<PurchaseDetails>[_purchase()]);

    expect(store.completed, hasLength(1));
  });

  test('entregar tras un fallo temporal no vuelve a cerrar dos veces',
      () async {
    bool falla = true;
    service.deliver = (PurchaseDetails _) async => falla
        ? const IapDeliveryResult(delivered: false, message: 'sin red')
        : const IapDeliveryResult(delivered: true);

    final PurchaseDetails p = _purchase();
    await service.handlePurchases(<PurchaseDetails>[p]);
    expect(store.completed, isEmpty);

    falla = false;
    await service.handlePurchases(<PurchaseDetails>[p]);

    expect(store.completed, hasLength(1));
    expect(service.error, isNull);
  });

  test('una compra cancelada se cierra siempre', () async {
    // Si no se cierra, cancelar una vez bloquearía el producto para siempre.
    final PurchaseDetails cancelada = PurchaseDetails(
      purchaseID: 'tx-cancel',
      productID: 'attra_pro_monthly',
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local',
        serverVerificationData: 'server',
        source: 'app_store',
      ),
      transactionDate: '0',
      status: PurchaseStatus.canceled,
    )..pendingCompletePurchase = true;

    await service.handlePurchases(<PurchaseDetails>[cancelada]);

    expect(store.completed, hasLength(1));
  });
}
