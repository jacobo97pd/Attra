import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Resultado de entregar (verificar + conceder) una compra en el backend.
class IapDeliveryResult {
  const IapDeliveryResult({required this.delivered, this.message});

  /// true = el backend validó y concedió → se puede completar la compra.
  /// false = no se pudo conceder (no completamos: la tienda reintentará).
  final bool delivered;
  final String? message;
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

  bool _available = false;
  bool _busy = false;
  String? _error;

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
      notifyListeners();
      return;
    }
    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) {
        _error = e.toString();
        notifyListeners();
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
    notifyListeners();
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
      notifyListeners();
      return false;
    }
    return buyProduct(product);
  }

  /// Compra una OFERTA concreta (para suscripciones con planes básicos, pasa la
  /// oferta elegida de [offersFor]; cada ProductDetails ya lleva su plan/oferta).
  Future<bool> buyProduct(ProductDetails product) async {
    if (!_available) {
      _error = 'Las compras no están disponibles en este dispositivo.';
      notifyListeners();
      return false;
    }
    final PurchaseParam param = PurchaseParam(productDetails: product);
    _setBusy(true);
    try {
      if (_consumableIds.contains(product.id)) {
        // En Android consume automáticamente para poder recomprar.
        return await _iap.buyConsumable(purchaseParam: param);
      }
      return await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      _error = e.toString();
      _setBusy(false);
      return false;
    }
  }

  /// Restaura compras (suscripciones / no consumibles). Necesario en iOS.
  Future<void> restore() async {
    if (!_available) return;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
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
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
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
    } else {
      // No completamos: la tienda reintentará la entrega más tarde.
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
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
