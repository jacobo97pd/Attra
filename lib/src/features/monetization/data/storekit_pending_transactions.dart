import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// Una transacción que la App Store sigue teniendo SIN TERMINAR.
///
/// Lo importante es que lleva el RECIBO ([jws]). Los dos intentos anteriores de
/// arreglar esto se quedaban solo con el id de producto y tiraban el recibo, así
/// que lo único que sabían hacer era CERRAR la transacción: el usuario se
/// quedaba pagado y sin plan. Con el recibo se puede pedir al backend que
/// conceda la compra ANTES de cerrarla, que es lo que de verdad hacía falta.
@immutable
class PendingStoreKitTransaction {
  const PendingStoreKitTransaction({
    required this.transactionId,
    required this.productId,
    required this.jws,
    this.purchaseDate,
  });

  /// Id de la transacción de StoreKit 2. Es el MISMO valor que viaja como
  /// `purchaseID` en una compra normal, así que el ledger del backend
  /// (`subscriptionLedger` / `consumableLedger`, idempotentes por compra) trata
  /// el reintento como la misma compra y no concede dos veces.
  final int transactionId;

  final String productId;

  /// `jwsRepresentation` firmado por Apple. Es lo único que el backend acepta
  /// como recibo: `verifyPurchase` rechaza con `invalid-argument` cualquier
  /// llamada con `verificationData` vacío.
  final String jws;

  /// Milisegundos desde epoch, tal y como los da el plugin.
  final String? purchaseDate;
}

/// Acceso a las transacciones de StoreKit 2 que quedaron SIN TERMINAR.
///
/// POR QUÉ EXISTE: mientras una transacción siga sin terminar, el propio plugin
/// RECHAZA cualquier compra nueva de ese producto. Está en su código Swift
/// (`InAppPurchasePlugin+StoreKit2.swift`, `purchase(id:)`): antes de comprar
/// recorre `Transaction.unfinished` y, si encuentra una del mismo `productID`,
/// devuelve `storekit_duplicate_product_object` sin llegar a cobrar. Ese es el
/// error que dejó a TODOS los usuarios sin poder suscribirse.
///
/// POR QUÉ NO BASTA `purchaseStream`: la escucha nativa de StoreKit 2 solo se
/// arranca cuando alguien se suscribe al stream (`onListen` en
/// `in_app_purchase_storekit_platform.dart`), y en esta app eso ocurre después
/// del login. Lo que la tienda emitiera fuera de esa ventana no se reemite.
/// `Transaction.unfinished` es la única lista fiable de lo que sigue abierto.
///
/// SOLO StoreKit 2, a propósito. El plugin trae `_useStoreKit2 = true` y esta
/// app no llama nunca a `enableStoreKit1()`, así que el camino de StoreKit 1
/// que había aquí era código muerto con ocho tests en verde sobre una rama que
/// no se ejecuta: falsa seguridad, justo lo que ya falló dos veces. Y StoreKit 1
/// no lo necesitaría: su cola de pagos reentrega al observador las
/// transacciones sin terminar en cada arranque.
class StoreKitPendingTransactions {
  StoreKitPendingTransactions({
    bool? isIos,
    bool? storeKit2,
    Future<List<SK2Transaction>> Function()? unfinished,
    Future<void> Function(int id)? finishById,
    this.nativeTimeout = const Duration(seconds: 12),
  })  : _unfinished = unfinished ?? SK2Transaction.unfinishedTransactions,
        _finishById = finishById ?? SK2Transaction.finish,
        _forcedStoreKit2 = storeKit2,
        _isIos = isIos ??
            (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.iOS ||
                    defaultTargetPlatform == TargetPlatform.macOS));

  final Future<List<SK2Transaction>> Function() _unfinished;
  final Future<void> Function(int id) _finishById;
  final bool? _forcedStoreKit2;
  final bool _isIos;

  /// Tope para CUALQUIER llamada al canal nativo.
  ///
  /// No es prudencia genérica: el `finish(id:)` del plugin puede no responder
  /// jamás. Su Swift es `let transaction = try await fetchTransaction(by: id);
  /// if let transaction { await transaction.finish(); completion(...) }`, sin
  /// rama `else` ni `catch`. Y `fetchTransaction` busca en `Transaction.all`
  /// (el historial servido por la App Store), no en `Transaction.unfinished`
  /// (local): sin red, o con un consumible que ya no está en el historial,
  /// devuelve nil y el completion NO se llama. El Future de Dart entonces no
  /// completa nunca y se lleva por delante el bucle que lo esté esperando.
  final Duration nativeTimeout;

  /// La bandera del plugin se lee en cada llamada, no en el constructor: este
  /// objeto se crea al montar la sesión y `isStoreKit2Enabled` es estática y
  /// puede fijarse en otro punto del arranque.
  bool get _storeKit2 =>
      _forcedStoreKit2 ?? InAppPurchaseStoreKitPlatform.isStoreKit2Enabled;

  /// True si en esta plataforma hay transacciones de StoreKit 2 que consultar.
  bool get available => _isIos && _storeKit2;

  /// Lo que la App Store sigue considerando sin terminar, con su recibo.
  ///
  /// Nunca lanza: esto se llama desde el arranque de la sesión y desde el
  /// paywall, y una excepción aquí tumbaría la pantalla de pago entera.
  Future<List<PendingStoreKitTransaction>> list() async {
    if (!available) return const <PendingStoreKitTransaction>[];
    List<SK2Transaction> raw;
    try {
      raw = await _unfinished().timeout(nativeTimeout);
    } on TimeoutException {
      debugPrint('[IAP] la lista de transacciones sin terminar no respondió');
      return const <PendingStoreKitTransaction>[];
    } catch (error) {
      debugPrint('[IAP] no se pudieron leer las transacciones sin terminar: '
          '$error');
      return const <PendingStoreKitTransaction>[];
    }

    final List<PendingStoreKitTransaction> out = <PendingStoreKitTransaction>[];
    for (final SK2Transaction tx in raw) {
      final int? id = int.tryParse(tx.id);
      if (id == null) {
        // Sin id no se puede cerrar, y entregarla sin poder cerrarla la dejaría
        // reentregándose en cada arranque.
        debugPrint('[IAP] transacción con id no numérico: ${tx.id}');
        continue;
      }
      out.add(PendingStoreKitTransaction(
        transactionId: id,
        productId: tx.productId,
        jws: tx.receiptData ?? '',
        purchaseDate: tx.purchaseDate,
      ));
    }
    return out;
  }

  /// Cierra la transacción. Devuelve true SOLO si el nativo confirmó el cierre:
  /// darla por cerrada sin confirmación haría creer que el producto está libre
  /// y el siguiente intento de compra volvería a chocar sin explicación.
  Future<bool> finish(PendingStoreKitTransaction tx) async {
    if (!available) return false;
    try {
      await _finishById(tx.transactionId).timeout(nativeTimeout);
      return true;
    } on TimeoutException {
      debugPrint('[IAP] cerrar ${tx.productId} (${tx.transactionId}) no '
          'respondió a tiempo');
      return false;
    } catch (error) {
      debugPrint('[IAP] no se pudo cerrar ${tx.productId}: $error');
      return false;
    }
  }
}
