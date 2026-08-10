import 'package:flutter/foundation.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

/// Resultado de vaciar la cola de StoreKit.
class QueueCleanupResult {
  const QueueCleanupResult({
    this.finished = 0,
    this.undeliverable = 0,
    this.blockedInProgress = 0,
  });

  /// Transacciones cerradas: el producto vuelve a poder comprarse.
  final int finished;

  /// Cerradas SIN haber podido entregar. El usuario pagó y hay que decírselo:
  /// se recupera con "Restaurar".
  final int undeliverable;

  /// En curso (`purchasing`) o esperando aprobación (`deferred`, el "Preguntar
  /// antes de comprar" de los menores). StoreKit PROHÍBE cerrarlas, así que no
  /// hay nada que hacer salvo esperar y explicarlo.
  final int blockedInProgress;

  bool get changedSomething => finished > 0;
}

/// Cierra a mano las transacciones que se quedaron colgadas en la cola de
/// StoreKit.
///
/// POR QUÉ HACE FALTA, si ya existe `completePurchase`: ese camino solo alcanza
/// a las transacciones que la tienda nos ENTREGA por `purchaseStream`. Una que
/// se quedó atrás —porque falló mientras la app estaba cerrada, porque el
/// stream ya la había emitido antes de que nadie escuchara, o porque llegó como
/// `failed` sin `pendingCompletePurchase`— no vuelve a pasar por ahí. Y
/// mientras siga en la cola, StoreKit RECHAZA cualquier compra nueva de ese
/// mismo producto con `storekit_duplicate_product_object`.
///
/// El efecto es que nadie puede suscribirse, y desde el cliente no había forma
/// de salir: la única vía era desinstalar o cambiar de Apple ID.
///
/// Es específico de iOS a propósito: Android (Google Play) no tiene este
/// problema porque las compras no consumidas se reentregan siempre en
/// `queryPurchases`, y su plugin no expone esta cola.
class StoreKitQueueCleaner {
  StoreKitQueueCleaner({SKPaymentQueueWrapper? queue, bool? isIos})
      : _queue = queue ?? SKPaymentQueueWrapper(),
        _isIos = isIos ??
            (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.iOS ||
                    defaultTargetPlatform == TargetPlatform.macOS));

  final SKPaymentQueueWrapper _queue;
  final bool _isIos;

  /// Intenta dejar la cola limpia.
  ///
  /// [deliver] recibe cada transacción COMPRADA antes de cerrarla, para tener
  /// una última oportunidad de concederla. Si devuelve false, la transacción se
  /// cierra igualmente: dejarla abierta no la entrega y además bloquea el
  /// producto, así que el usuario se quedaría sin lo pagado Y sin poder
  /// comprarlo. Cerrándola al menos puede recuperarlo con "Restaurar", porque
  /// el recibo de una suscripción persiste.
  ///
  /// [productId] acota la limpieza a un producto; sin él se limpia toda la cola.
  Future<QueueCleanupResult> cleanUp({
    String? productId,
    Future<bool> Function(SKPaymentTransactionWrapper transaction)? deliver,
  }) async {
    if (!_isIos) return const QueueCleanupResult();

    final List<SKPaymentTransactionWrapper> pending;
    try {
      pending = await _queue.transactions();
    } catch (error) {
      debugPrint('[IAP] no se pudo leer la cola de StoreKit: $error');
      return const QueueCleanupResult();
    }

    int finished = 0;
    int undeliverable = 0;
    int blocked = 0;

    for (final SKPaymentTransactionWrapper tx in pending) {
      if (productId != null && tx.payment.productIdentifier != productId) {
        continue;
      }
      switch (tx.transactionState) {
        case SKPaymentTransactionStateWrapper.unspecified:
          // Estado que el plugin no supo traducir. No se toca: cerrar una
          // transaccion que no entendemos podria dar por buena una compra que
          // no lo esta.
          blocked++;
          break;

        case SKPaymentTransactionStateWrapper.purchasing:
        case SKPaymentTransactionStateWrapper.deferred:
          // StoreKit lanza si se intenta cerrar una `purchasing`, y una
          // `deferred` espera al permiso de un adulto: cerrarla cancelaría una
          // compra que quizá se apruebe.
          blocked++;
          break;

        case SKPaymentTransactionStateWrapper.failed:
          // Una compra fallida SIGUE OCUPANDO la cola hasta que se cierra.
          // Nada que entregar aquí: no se cobró.
          if (await _finish(tx)) finished++;
          break;

        case SKPaymentTransactionStateWrapper.purchased:
        case SKPaymentTransactionStateWrapper.restored:
          bool delivered = false;
          if (deliver != null) {
            try {
              delivered = await deliver(tx);
            } catch (error) {
              debugPrint('[IAP] entrega desde la cola falló: $error');
            }
          }
          if (await _finish(tx)) {
            finished++;
            if (!delivered) undeliverable++;
          }
          break;
      }
    }

    return QueueCleanupResult(
      finished: finished,
      undeliverable: undeliverable,
      blockedInProgress: blocked,
    );
  }

  Future<bool> _finish(SKPaymentTransactionWrapper tx) async {
    try {
      await _queue.finishTransaction(tx);
      return true;
    } catch (error) {
      debugPrint('[IAP] no se pudo cerrar la transacción '
          '${tx.payment.productIdentifier}: $error');
      return false;
    }
  }
}
