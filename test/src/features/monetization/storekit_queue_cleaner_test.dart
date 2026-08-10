import 'package:attra/src/features/monetization/data/storekit_queue_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

/// Mientras una transacción siga en la cola de StoreKit, ese producto NO se
/// puede volver a comprar: cualquier intento revienta con
/// `storekit_duplicate_product_object`.
///
/// Le pasó a TODOS los usuarios con `attra_pro_monthly`. Y no había salida
/// desde la app, porque `completePurchase` solo alcanza a lo que la tienda
/// reemite por `purchaseStream`, y una transacción que se quedó atrás no vuelve
/// a pasar por ahí. Estos tests fijan qué se cierra y qué no.
class _FakeQueue implements SKPaymentQueueWrapper {
  _FakeQueue(this._transactions);

  final List<SKPaymentTransactionWrapper> _transactions;
  final List<String> finished = <String>[];

  /// Productos cuyo cierre falla, para probar que no se cuenta como cerrado.
  Set<String> failFinishFor = <String>{};

  @override
  Future<List<SKPaymentTransactionWrapper>> transactions() async =>
      _transactions;

  @override
  Future<void> finishTransaction(SKPaymentTransactionWrapper t) async {
    final String id = t.payment.productIdentifier;
    if (failFinishFor.contains(id)) {
      throw StateError('no se puede cerrar');
    }
    finished.add(id);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa');
}

SKPaymentTransactionWrapper _tx({
  required SKPaymentTransactionStateWrapper state,
  String product = 'attra_pro_monthly',
}) =>
    SKPaymentTransactionWrapper(
      payment: SKPaymentWrapper(productIdentifier: product),
      transactionState: state,
      transactionIdentifier: 'tx-$product-${state.name}',
    );

void main() {
  StoreKitQueueCleaner cleaner(_FakeQueue queue) =>
      StoreKitQueueCleaner(queue: queue, isIos: true);

  test('una compra FALLIDA se cierra: seguía ocupando la cola', () async {
    // Es el caso más traicionero: no se cobró nada, no hay nada que entregar,
    // y aun así bloquea el producto hasta que alguien la cierra.
    final _FakeQueue queue = _FakeQueue(<SKPaymentTransactionWrapper>[
      _tx(state: SKPaymentTransactionStateWrapper.failed),
    ]);

    final QueueCleanupResult r = await cleaner(queue).cleanUp();

    expect(queue.finished, <String>['attra_pro_monthly']);
    expect(r.finished, 1);
    expect(r.undeliverable, 0, reason: 'una fallida no se cobró');
  });

  test('una COMPRADA se intenta entregar antes de cerrarla', () async {
    final _FakeQueue queue = _FakeQueue(<SKPaymentTransactionWrapper>[
      _tx(state: SKPaymentTransactionStateWrapper.purchased),
    ]);
    bool intentada = false;

    final QueueCleanupResult r = await cleaner(queue).cleanUp(
      deliver: (SKPaymentTransactionWrapper _) async {
        intentada = true;
        return true;
      },
    );

    expect(intentada, isTrue, reason: 'primero conceder, luego cerrar');
    expect(r.finished, 1);
    expect(r.undeliverable, 0);
  });

  test('si no se puede entregar se cierra IGUAL y se avisa', () async {
    // Dejarla abierta no la entrega y encima bloquea el producto: el usuario se
    // quedaría sin lo pagado Y sin poder comprarlo. Cerrándola al menos lo
    // recupera con "Restaurar".
    final _FakeQueue queue = _FakeQueue(<SKPaymentTransactionWrapper>[
      _tx(state: SKPaymentTransactionStateWrapper.purchased),
    ]);

    final QueueCleanupResult r = await cleaner(queue)
        .cleanUp(deliver: (SKPaymentTransactionWrapper _) async => false);

    expect(r.finished, 1);
    expect(r.undeliverable, 1, reason: 'hay que decirle que pulse Restaurar');
  });

  test('una compra EN CURSO no se toca', () async {
    // StoreKit lanza si se intenta cerrar una `purchasing`.
    final _FakeQueue queue = _FakeQueue(<SKPaymentTransactionWrapper>[
      _tx(state: SKPaymentTransactionStateWrapper.purchasing),
    ]);

    final QueueCleanupResult r = await cleaner(queue).cleanUp();

    expect(queue.finished, isEmpty);
    expect(r.blockedInProgress, 1);
    expect(r.changedSomething, isFalse);
  });

  test('una DIFERIDA no se toca: puede aprobarse luego', () async {
    // "Preguntar antes de comprar": cerrarla cancelaría una compra que un
    // adulto todavía puede aprobar.
    final _FakeQueue queue = _FakeQueue(<SKPaymentTransactionWrapper>[
      _tx(state: SKPaymentTransactionStateWrapper.deferred),
    ]);

    final QueueCleanupResult r = await cleaner(queue).cleanUp();

    expect(queue.finished, isEmpty);
    expect(r.blockedInProgress, 1);
  });

  test('acotar por producto no cierra los de otros', () async {
    final _FakeQueue queue = _FakeQueue(<SKPaymentTransactionWrapper>[
      _tx(state: SKPaymentTransactionStateWrapper.failed),
      _tx(
        state: SKPaymentTransactionStateWrapper.failed,
        product: 'attra_plus_monthly',
      ),
    ]);

    await cleaner(queue).cleanUp(productId: 'attra_pro_monthly');

    expect(queue.finished, <String>['attra_pro_monthly']);
  });

  test('si el cierre falla NO se cuenta como cerrada', () async {
    // Contarla haría creer que el producto está libre y el siguiente intento
    // volvería a chocar, esta vez sin explicación.
    final _FakeQueue queue = _FakeQueue(<SKPaymentTransactionWrapper>[
      _tx(state: SKPaymentTransactionStateWrapper.failed),
    ])
      ..failFinishFor = <String>{'attra_pro_monthly'};

    final QueueCleanupResult r = await cleaner(queue).cleanUp();

    expect(r.finished, 0);
    expect(r.changedSomething, isFalse);
  });

  test('fuera de iOS no se toca nada', () async {
    // Google Play reentrega siempre en `queryPurchases` y su plugin no expone
    // esta cola: aquí no hay nada que arreglar.
    final _FakeQueue queue = _FakeQueue(<SKPaymentTransactionWrapper>[
      _tx(state: SKPaymentTransactionStateWrapper.failed),
    ]);

    final QueueCleanupResult r =
        await StoreKitQueueCleaner(queue: queue, isIos: false).cleanUp();

    expect(queue.finished, isEmpty);
    expect(r.changedSomething, isFalse);
  });
}
