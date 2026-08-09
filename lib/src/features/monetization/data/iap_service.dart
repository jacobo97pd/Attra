import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Resultado de entregar (verificar + conceder) una compra en el backend.
class IapDeliveryResult {
  const IapDeliveryResult({
    required this.delivered,
    this.message,
    this.permanent = false,
  });

  /// true = el backend validó y concedió → se puede completar la compra.
  /// false = no se pudo conceder (no completamos: la tienda reintentará).
  final bool delivered;
  final String? message;

  /// Fallo DEFINITIVO: reintentar no va a cambiar nada (p. ej. el recibo ya lo
  /// canjeó otra cuenta, o el producto no está en el catálogo del servidor).
  ///
  /// Importa mucho: si no se finaliza la transacción, StoreKit la reencola en
  /// cada arranque, muestra el error una y otra vez y BLOQUEA las compras
  /// siguientes; en Android el consumible no se consume y no se puede
  /// recomprar. Con [permanent] se cierra la transacción y se avisa al usuario.
  final bool permanent;
}

/// Fachada de COMPRAS DENTRO DE LA APP (IAP) sobre `in_app_purchase`.
///
/// Abre la pasarela NATIVA de Google Play / App Store (obligatoria para bienes
/// digitales) y, cuando la tienda confirma una compra, delega en [deliver] para
/// que el BACKEND valide el recibo y conceda el producto. SOLO si el backend
/// confirma la entrega se llama a `completePurchase` (en consumibles, además,
/// Android lo consume para poder recomprarlo).
///
/// Regla de oro: el cliente NUNCA concede tier/saldo; solo lanza la compra y
/// reenvía el recibo. La concesión es siempre server-side.
class IapService extends ChangeNotifier {
  IapService({InAppPurchase? iap, Set<String> consumableIds = const <String>{}})
      : _iap = iap ?? InAppPurchase.instance,
        _consumableIds = consumableIds;

  final InAppPurchase _iap;
  // IDs que en Android deben CONSUMIRSE (Attras/Boosts/Swipes). El resto
  // (suscripciones) son no-consumibles.
  final Set<String> _consumableIds;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  // Ofertas por id. Una suscripción de Play con varios PLANES BÁSICOS
  // (mensual/anual) devuelve VARIOS ProductDetails con el mismo id; por eso se
  // guarda una lista, no uno solo. Los consumibles tienen una sola oferta.
  final Map<String, List<ProductDetails>> _offers =
      <String, List<ProductDetails>>{};

  /// Periodo (mensual/anual) que el usuario eligió al lanzar cada compra.
  ///
  /// Hace falta porque en Google Play los planes básicos MENSUAL y ANUAL
  /// comparten el mismo id de producto (`attra_plus`), así que el id no dice
  /// cuál se compró. Vive en el servicio, no en el paywall, porque la compra
  /// puede resolverse con esa pantalla ya cerrada y el backend necesita saber
  /// si conceder 1 mes o 12: sin este dato, quien pagaba un año recibía un mes.
  final Map<String, String> _pendingPeriods = <String, String>{};

  void notePendingPeriod(String productId, String period) {
    _pendingPeriods[productId] = period;
  }

  String? pendingPeriodFor(String productId) => _pendingPeriods[productId];

  bool _available = false;
  bool _busy = false;
  String? _error;
  bool _disposed = false;

  /// Compras que llegaron pero NO se pudieron entregar por un fallo temporal, y
  /// que por tanto se dejaron SIN completar a proposito.
  ///
  /// Hay que recordarlas porque la cola de la tienda no admite dos
  /// transacciones del mismo producto: mientras una siga abierta, cualquier
  /// intento de comprar ese producto revienta con
  /// `storekit_duplicate_product_object` y el usuario NO PUEDE SUSCRIBIRSE. Con
  /// el mapa se puede reintentar la entrega en la misma sesion, en vez de
  /// esperar a que la tienda vuelva a emitirla al reabrir la app.
  final Map<String, PurchaseDetails> _undelivered =
      <String, PurchaseDetails>{};

  /// Intentos de entrega por compra, para no reintentar en bucle.
  final Map<String, int> _deliveryAttempts = <String, int>{};

  /// A partir de aqui se cierra la transaccion aunque no se haya entregado.
  ///
  /// Es la MENOS mala de dos opciones malas. Dejarla abierta para siempre
  /// bloquea el producto y el usuario no puede ni comprar; cerrarla le deja
  /// pagado sin conceder, pero el recibo de una suscripcion PERSISTE y
  /// "Restaurar" vuelve a entregarla (los entitlements los manda el backend).
  /// De lo irrecuperable a lo recuperable.
  static const int _maxDeliveryAttempts = 3;

  /// Notifica solo si el servicio sigue vivo. Cerrar la pantalla mientras el
  /// backend verificaba lanzaba "notifyListeners after dispose".
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Limpia el último error. El paywall reemitía en bucle el snackbar de un
  /// fallo antiguo porque nadie lo borraba al reintentar.
  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  /// Backend que valida el recibo y concede el producto. Lo inyecta la capa
  /// superior (p. ej. llama a `grantConsumable` / `verifyPurchase`).
  Future<IapDeliveryResult> Function(PurchaseDetails purchase)? deliver;

  /// Se invoca tras una entrega correcta (para refrescar saldos/entitlements).
  void Function(PurchaseDetails purchase)? onDelivered;

  bool get isAvailable => _available;
  bool get isBusy => _busy;
  String? get error => _error;

  /// Primera oferta de [id] (la única en consumibles). Para suscripciones con
  /// varios planes básicos, usa [offersFor].
  ProductDetails? productById(String id) {
    final List<ProductDetails>? list = _offers[id];
    return (list != null && list.isNotEmpty) ? list.first : null;
  }

  /// Todas las ofertas de [id] (planes básicos) ordenadas por precio ascendente:
  /// la más barata suele ser la MENSUAL y la más cara la ANUAL.
  List<ProductDetails> offersFor(String id) {
    final List<ProductDetails> list =
        List<ProductDetails>.from(_offers[id] ?? const <ProductDetails>[]);
    list.sort((ProductDetails a, ProductDetails b) =>
        a.rawPrice.compareTo(b.rawPrice));
    return list;
  }

  bool get hasProducts => _offers.isNotEmpty;

  /// Inicializa: comprueba disponibilidad y se suscribe al flujo de compras.
  /// No-op en plataformas sin tienda (web/escritorio): la app sigue funcionando.
  Future<void> init({required Set<String> productIds}) async {
    try {
      _available = await _iap.isAvailable();
    } catch (_) {
      _available = false;
    }
    if (!_available) {
      _notify();
      return;
    }
    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) {
        _error = e.toString();
        _notify();
      },
    );
    await loadProducts(productIds);
  }

  /// Carga los detalles (precio localizado, título) de [ids] desde la tienda.
  Future<void> loadProducts(Set<String> ids) async {
    if (!_available || ids.isEmpty) return;
    try {
      final ProductDetailsResponse resp = await _iap.queryProductDetails(ids);
      // Reagrupa por id (una suscripción puede traer varias ofertas/planes).
      for (final String id in ids) {
        _offers.remove(id);
      }
      for (final ProductDetails p in resp.productDetails) {
        (_offers[p.id] ??= <ProductDetails>[]).add(p);
      }
      if (resp.notFoundIDs.isNotEmpty && kDebugMode) {
        debugPrint('[IAP] Productos no encontrados en la tienda: '
            '${resp.notFoundIDs.join(', ')}');
      }
    } catch (e) {
      _error = e.toString();
    }
    _notify();
  }

  /// Lanza la compra NATIVA de [productId]. Devuelve false si no se pudo iniciar
  /// (tienda no disponible o producto no dado de alta). El resultado real llega
  /// de forma asíncrona por el flujo de compras.
  Future<bool> buy(String productId) async {
    final ProductDetails? product = productById(productId);
    if (product == null) {
      _error = !_available
          ? 'Las compras no están disponibles en este dispositivo.'
          : 'Producto no disponible en la tienda ($productId).';
      _notify();
      return false;
    }
    return buyProduct(product);
  }

  /// Compra una OFERTA concreta (para suscripciones con planes básicos, pasa la
  /// oferta elegida de [offersFor]; cada ProductDetails ya lleva su plan/oferta).
  Future<bool> buyProduct(ProductDetails product) async {
    if (!_available) {
      _error = 'Las compras no están disponibles en este dispositivo.';
      _notify();
      return false;
    }
    final PurchaseParam param = PurchaseParam(productDetails: product);
    // Empezar limpio: si no, un error de un intento anterior se reemite como si
    // fuera de esta compra.
    _error = null;
    _setBusy(true);
    try {
      final bool started = _consumableIds.contains(product.id)
          // En Android consume automáticamente para poder recomprar.
          ? await _iap.buyConsumable(purchaseParam: param)
          : await _iap.buyNonConsumable(purchaseParam: param);
      // Si la tienda NO abrió el flujo no llegará nada por purchaseStream, así
      // que hay que soltar el busy aquí o la pantalla se queda congelada.
      if (!started) _setBusy(false);
      return started;
    } on PlatformException catch (e) {
      // La cola de la tienda ya tiene una transaccion ABIERTA de este mismo
      // producto y se niega a empezar otra. Le pasa a quien pago y cuya entrega
      // fallo por red: se queda sin poder suscribirse, viendo un
      // `PlatformException(storekit_duplicate_product_object, ...)` en crudo que
      // no le dice nada ni le da salida.
      //
      // No es un error del usuario ni hace falta que vuelva a pagar: hay que
      // TERMINAR la transaccion que quedo a medias.
      if (e.code == 'storekit_duplicate_product_object') {
        _setBusy(false);
        _error = 'Tenías una compra sin terminar. La estamos completando: '
            'espera unos segundos y vuelve a intentarlo. No se te cobrará dos '
            'veces.';
        _notify();
        unawaited(_recoverPending(product.id));
        return false;
      }
      _error = _readableStoreError(e);
      _setBusy(false);
      return false;
    }
  }

  /// Se invoca al terminar de restaurar, con cuántas compras se recuperaron.
  /// Sin esto el botón "Restaurar" no daba señal alguna al usuario.
  void Function(int restored)? onRestoreFinished;

  int _restoredDuringRestore = 0;
  bool _restoring = false;

  /// Restaura compras (suscripciones / no consumibles). Necesario en iOS.
  ///
  /// `restorePurchases()` devuelve void y las compras llegan por el stream, así
  /// que se cuenta lo recuperado durante una ventana corta y se informa. Antes
  /// el usuario pulsaba y no pasaba nada visible, ni siquiera cuando no había
  /// nada que restaurar.
  Future<void> restore() async {
    if (!_available || _restoring) return;
    _restoring = true;
    _restoredDuringRestore = 0;
    _error = null;
    _setBusy(true);
    try {
      await _iap.restorePurchases();
      // Las compras restauradas llegan de forma asíncrona por purchaseStream.
      await Future<void>.delayed(const Duration(seconds: 3));
    } catch (e) {
      _error = e.toString();
    } finally {
      _restoring = false;
      _setBusy(false);
      onRestoreFinished?.call(_restoredDuringRestore);
      _notify();
    }
  }

  /// Entrada del flujo de compras para los tests.
  ///
  /// Existe porque montar el stream real exigiria falsear tambien la carga de
  /// productos y la disponibilidad de la tienda, y lo que hay que fijar aqui es
  /// QUE TRANSACCIONES SE CIERRAN: dejar una abierta bloquea el producto y la
  /// persona no puede suscribirse.
  @visibleForTesting
  Future<void> handlePurchases(List<PurchaseDetails> purchases) =>
      _onPurchases(purchases);

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _setBusy(true);
          break;
        case PurchaseStatus.error:
          _error = purchase.error?.message ?? 'La compra falló.';
          _setBusy(false);
          await _safeComplete(purchase);
          break;
        case PurchaseStatus.canceled:
          _setBusy(false);
          await _safeComplete(purchase);
          break;
        case PurchaseStatus.restored:
          if (_restoring) _restoredDuringRestore += 1;
          await _handleVerified(purchase);
          break;
        case PurchaseStatus.purchased:
          await _handleVerified(purchase);
          break;
      }
    }
  }

  Future<void> _handleVerified(PurchaseDetails purchase) async {
    final Future<IapDeliveryResult> Function(PurchaseDetails)? handler =
        deliver;
    IapDeliveryResult result;
    try {
      result = handler == null
          ? const IapDeliveryResult(
              delivered: false, message: 'Entrega no configurada.')
          : await handler(purchase);
    } catch (e) {
      result = IapDeliveryResult(delivered: false, message: e.toString());
    }
    final String key = purchase.purchaseID ?? purchase.productID;
    if (result.delivered) {
      _error = null;
      _undelivered.remove(purchase.productID);
      _deliveryAttempts.remove(key);
      onDelivered?.call(purchase);
      await _safeComplete(purchase);
    } else if (result.permanent) {
      // Reintentar no arregla nada: se cierra la transacción para no dejarla
      // colgada en la cola de la tienda, y se explica al usuario qué pasó.
      _error = result.message ?? 'Esta compra no se puede entregar.';
      _undelivered.remove(purchase.productID);
      _deliveryAttempts.remove(key);
      await _safeComplete(purchase);
    } else {
      // Fallo temporal (red, backend caído): NO se completa todavía, para no
      // cerrar una compra pagada sin haberla concedido.
      final int attempts = (_deliveryAttempts[key] ?? 0) + 1;
      _deliveryAttempts[key] = attempts;
      if (attempts >= _maxDeliveryAttempts) {
        // Se agotaron los reintentos. Dejarla abierta bloquearía ESE producto
        // en la cola de la tienda para siempre: el usuario no podría ni volver
        // a intentar la compra, que es peor que quedarse pagado sin conceder,
        // porque de esto último se sale con "Restaurar".
        _undelivered.remove(purchase.productID);
        _deliveryAttempts.remove(key);
        await _safeComplete(purchase);
        _error = 'No hemos podido activar tu compra tras varios intentos. '
            'No se ha vuelto a cobrar nada: pulsa "Restaurar" cuando tengas '
            'conexión y se activará.';
      } else {
        _undelivered[purchase.productID] = purchase;
        _error = result.message ?? 'No se pudo entregar la compra.';
      }
    }
    _setBusy(false);
  }

  /// Termina la compra que quedo abierta y bloquea el producto.
  ///
  /// Primero se reintenta la entrega de la que ya tenemos en memoria. Si no la
  /// tenemos (la app se reinicio y el stream aun no la ha reemitido), se pide
  /// `restorePurchases`, que hace que la tienda la vuelva a emitir por el
  /// stream y entre por el camino normal de verificar y completar.
  Future<void> _recoverPending(String productId) async {
    final PurchaseDetails? pending = _undelivered[productId];
    if (pending != null) {
      await _handleVerified(pending);
      return;
    }
    try {
      await _iap.restorePurchases();
    } catch (_) {
      // Si ni restaurar funciona, no hay mas que hacer desde aqui: el mensaje
      // ya le ha dicho al usuario que espere y reintente.
    }
  }

  /// Traduce los codigos de la tienda a algo que una persona pueda entender y
  /// accionar. Antes se enseñaba `e.toString()` tal cual, que es un volcado con
  /// nombres de clases internas.
  String _readableStoreError(PlatformException e) {
    switch (e.code) {
      case 'storekit_duplicate_product_object':
        return 'Tenías una compra sin terminar de este mismo plan. Espera unos '
            'segundos y vuelve a intentarlo.';
      case 'storekit0':
        return 'La App Store ha rechazado la compra. Revisa tu método de pago '
            'en Ajustes.';
      default:
        return e.message ?? 'No se ha podido iniciar la compra.';
    }
  }

  Future<void> _safeComplete(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(purchase);
    } catch (_) {/* la tienda reintentará */}
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
