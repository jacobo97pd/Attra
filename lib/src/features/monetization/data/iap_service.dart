import 'dart:async';

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
    } catch (e) {
      _error = e.toString();
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
    if (result.delivered) {
      _error = null;
      onDelivered?.call(purchase);
      await _safeComplete(purchase);
    } else if (result.permanent) {
      // Reintentar no arregla nada: se cierra la transacción para no dejarla
      // colgada en la cola de la tienda, y se explica al usuario qué pasó.
      _error = result.message ?? 'Esta compra no se puede entregar.';
      await _safeComplete(purchase);
    } else {
      // Fallo temporal (red, backend caído): NO completamos, la tienda
      // reintentará la entrega más tarde.
      _error = result.message ?? 'No se pudo entregar la compra.';
    }
    _setBusy(false);
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
