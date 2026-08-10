import 'dart:async';

import 'package:attra/src/features/monetization/data/storekit_pending_transactions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// Mientras una transacción siga sin terminar, el plugin RECHAZA cualquier
/// compra de ese producto con `storekit_duplicate_product_object`
/// (InAppPurchasePlugin+StoreKit2.swift, `purchase(id:)`). Nadie podía
/// suscribirse. Estas pruebas fijan lo único que hace falta para salir de ahí:
/// poder LEER esas transacciones con su recibo, y poder cerrarlas sin que una
/// llamada nativa muda cuelgue la app.
SK2Transaction _tx({
  required String id,
  String product = 'attra_pro_monthly',
  String? jws = 'jws-firmado-por-apple',
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
  test('trae el RECIBO de cada transacción, no solo el id de producto',
      () async {
    // El recibo es lo que permite ENTREGARLA. Las dos versiones anteriores de
    // este arreglo lo descartaban y por eso solo sabían cerrar la transacción,
    // dejando al usuario pagado y sin plan.
    final StoreKitPendingTransactions pending = StoreKitPendingTransactions(
      isIos: true,
      storeKit2: true,
      unfinished: () async => <SK2Transaction>[_tx(id: '1001')],
      finishById: (int _) async {},
    );

    final List<PendingStoreKitTransaction> list = await pending.list();

    expect(list, hasLength(1));
    expect(list.single.transactionId, 1001);
    expect(list.single.productId, 'attra_pro_monthly');
    expect(list.single.jws, 'jws-firmado-por-apple');
  });

  test('cerrar devuelve true solo cuando el nativo confirma', () async {
    final StoreKitPendingTransactions pending = StoreKitPendingTransactions(
      isIos: true,
      storeKit2: true,
      unfinished: () async => <SK2Transaction>[_tx(id: '7')],
      finishById: (int _) async {},
    );

    expect(await pending.finish((await pending.list()).single), isTrue);
  });

  test('si el cierre falla NO se da por cerrada', () async {
    // Darla por cerrada haría creer que el producto está libre y el siguiente
    // intento de compra volvería a chocar, esta vez sin explicación.
    final StoreKitPendingTransactions pending = StoreKitPendingTransactions(
      isIos: true,
      storeKit2: true,
      unfinished: () async => <SK2Transaction>[_tx(id: '7')],
      finishById: (int _) async => throw StateError('canal caído'),
    );

    expect(await pending.finish((await pending.list()).single), isFalse);
  });

  test('un cierre que NO responde nunca no cuelga: vence el timeout', () async {
    // Caso real del plugin: `finish(id:)` solo llama al completion si encuentra
    // la transacción en `Transaction.all`; no hay rama `else` ni `catch`. Sin
    // red, o con un consumible que ya no está en el historial, el canal se
    // queda mudo y el Future de Dart no completa JAMÁS.
    final StoreKitPendingTransactions pending = StoreKitPendingTransactions(
      isIos: true,
      storeKit2: true,
      unfinished: () async => <SK2Transaction>[_tx(id: '7')],
      finishById: (int _) => Completer<void>().future,
      nativeTimeout: const Duration(milliseconds: 30),
    );

    expect(await pending.finish((await pending.list()).single), isFalse);
  });

  test('una lista que no responde tampoco cuelga', () async {
    final StoreKitPendingTransactions pending = StoreKitPendingTransactions(
      isIos: true,
      storeKit2: true,
      unfinished: () => Completer<List<SK2Transaction>>().future,
      finishById: (int _) async {},
      nativeTimeout: const Duration(milliseconds: 30),
    );

    expect(await pending.list(), isEmpty);
  });

  test('si no se puede leer la lista se sale sin romper', () async {
    // Esto corre en el arranque de la sesión: una excepción aquí se llevaría por
    // delante la inicialización de las compras.
    final StoreKitPendingTransactions pending = StoreKitPendingTransactions(
      isIos: true,
      storeKit2: true,
      unfinished: () async => throw StateError('canal nativo caído'),
      finishById: (int _) async {},
    );

    expect(await pending.list(), isEmpty);
  });

  test('fuera de iOS no hay nada que consultar ni que cerrar', () async {
    // Google Play reentrega lo pendiente por su propio camino y su plugin no
    // expone esta lista.
    final StoreKitPendingTransactions pending = StoreKitPendingTransactions(
      isIos: false,
      storeKit2: true,
      unfinished: () async => <SK2Transaction>[_tx(id: '1')],
      finishById: (int _) async => throw StateError('no debería llamarse'),
    );

    expect(pending.available, isFalse);
    expect(await pending.list(), isEmpty);
  });
}
