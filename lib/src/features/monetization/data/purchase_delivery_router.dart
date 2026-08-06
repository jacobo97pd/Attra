import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../domain/premium_product_catalog.dart';
import 'boost_service.dart';
import 'iap_service.dart';

/// Entrega de compras a nivel de SESIÓN, no de pantalla.
///
/// El problema que resuelve: `purchaseStream` es global y asíncrono, pero antes
/// la única suscripción vivía dentro del paywall (o de la hoja de Boosts) y se
/// cancelaba al cerrarlos. Consecuencias reales, todas con dinero de por medio:
///
/// - Una compra que se resolvía con la pantalla cerrada (pago diferido, "pide
///   permiso a tus padres", red lenta, la app matada a mitad) NO se entregaba ni
///   se completaba: el usuario pagaba y no recibía nada, y la transacción se
///   quedaba colgada en la cola de StoreKit bloqueando compras posteriores.
/// - Cada pantalla solo sabía entregar SUS productos: si llegaba la compra de un
///   pack de Boosts con el paywall abierto, el paywall la mandaba a
///   `verifyPurchase`, el backend la rechazaba por producto desconocido y la
///   compra se perdía igual.
///
/// Este enrutador vive mientras dura la sesión y decide el destino por el
/// PRODUCTO, no por la pantalla que esté abierta.
class PurchaseDeliveryRouter extends ChangeNotifier {
  PurchaseDeliveryRouter({
    required BoostService boostService,
    IapService? iapService,
  })  : _boosts = boostService,
        iap = iapService ??
            IapService(consumableIds: PremiumProductCatalog.consumableIds);

  final BoostService _boosts;

  /// Servicio compartido por toda la sesión. Las pantallas lo reciben inyectado
  /// en lugar de crear el suyo, para que solo exista UNA suscripción al stream.
  final IapService iap;

  /// Se llama tras entregar una suscripción (para refrescar entitlements).
  VoidCallback? onSubscriptionDelivered;

  /// Se llama tras abonar un consumible, con el nuevo saldo.
  void Function(String kind, int balance)? onConsumableDelivered;

  /// Últimos saldos confirmados POR EL BACKEND tras una entrega.
  ///
  /// Hacen falta porque la pantalla que lanzó la compra puede no ser la que
  /// recibe la respuesta: la entrega vive en la sesión. Sin esto, la hoja de
  /// Boosts pintaba el saldo que traía `AppUser` al abrirse y se quedaba
  /// congelado, así que tras comprar seguía marcando 0 aunque el abono sí se
  /// hubiera hecho en el servidor.
  int? get lastAttraBalance => _lastAttraBalance;
  int? get lastBoostBalance => _lastBoostBalance;
  int? get lastSwipeBalance => _lastSwipeBalance;
  int? _lastAttraBalance;
  int? _lastBoostBalance;
  int? _lastSwipeBalance;

  /// Anota un saldo confirmado por el backend que NO viene de una compra: al
  /// ACTIVAR un Boost, `activateBoost` descuenta y devuelve el restante.
  ///
  /// Hacía falta porque la hoja de Boosts se reconstruye desde `AppUser` cada
  /// vez que se abre, y ese documento va por detrás (la recarga es asíncrona y
  /// puede no haber llegado): activabas un Boost, cerrabas la hoja, la volvías a
  /// abrir y el saldo mostraba otra vez el valor de ANTES de gastarlo.
  ///
  /// No notifica: quien activa ya pinta su propio estado, y avisar aquí haría
  /// que la hoja interpretase el cambio como una compra recién entregada.
  void noteBoostBalance(int balance) {
    _lastBoostBalance = balance;
  }

  void noteSwipeBalance(int balance) {
    _lastSwipeBalance = balance;
  }

  bool _started = false;

  /// Todos los ids que la sesión debe vigilar: suscripciones y consumibles.
  static Set<String> productIds({
    required Set<String> subscriptionIds,
  }) {
    return <String>{...subscriptionIds, ...PremiumProductCatalog.consumableIds};
  }

  Future<void> start({required Set<String> subscriptionIds}) async {
    if (_started) return;
    _started = true;
    iap.deliver = _deliver;
    await iap.init(
      productIds: productIds(subscriptionIds: subscriptionIds),
    );
  }

  @override
  void dispose() {
    iap.dispose();
    super.dispose();
  }

  String? _platform() {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'app_store';
      case TargetPlatform.android:
        return 'play_store';
      default:
        return null;
    }
  }

  /// El periodo se deduce del ID del producto, NUNCA del selector que hubiera en
  /// pantalla: una compra restaurada o diferida puede llegar con el selector en
  /// "Anual" siendo mensual, y el backend le daría un año de plan.
  String? _periodOf(String productId) {
    if (productId.endsWith('_yearly')) return 'yearly';
    if (productId.endsWith('_monthly')) return 'monthly';
    // Planes básicos de Play: mensual y anual comparten id, así que el sufijo no
    // lo dice. Se usa el periodo que el usuario eligió al lanzar la compra,
    // anotado en el servicio de sesión (sobrevive al cierre del paywall).
    return iap.pendingPeriodFor(productId);
  }

  Future<IapDeliveryResult> _deliver(PurchaseDetails purchase) async {
    final String? platform = _platform();
    if (platform == null) {
      return const IapDeliveryResult(
        delivered: false,
        message: 'Las compras no están disponibles en esta plataforma.',
      );
    }

    final PremiumProductDefinition? def =
        PremiumProductCatalog.byId(purchase.productID);

    // Consumible (Attras / Boosts / Swipes).
    if (def?.consumableKind != null) {
      try {
        final int balance = await _boosts.purchaseConsumable(
          productId: purchase.productID,
          kind: def!.consumableKind!,
          amount: def.consumableAmount,
          purchaseId: purchase.purchaseID,
          platform: platform,
          verificationData: purchase.verificationData.serverVerificationData,
        );
        switch (def.consumableKind) {
          case 'attra':
            _lastAttraBalance = balance;
          case 'boost':
            _lastBoostBalance = balance;
          case 'swipe':
            _lastSwipeBalance = balance;
        }
        onConsumableDelivered?.call(def.consumableKind!, balance);
        notifyListeners();
        return const IapDeliveryResult(delivered: true);
      } on BoostServiceException catch (e) {
        // Un rechazo DEFINITIVO de grantConsumable (producto fuera del catálogo,
        // recibo ya canjeado por otra cuenta) se devolvía como fallo temporal: la
        // transacción se quedaba sin finalizar y la tienda la reencolaba para
        // siempre. Igual que en la ruta de suscripciones, se marca permanente
        // para cerrarla y avisar al usuario.
        return IapDeliveryResult(
          delivered: false,
          permanent: e.isPermanent,
          message: e.message,
        );
      } catch (e) {
        return IapDeliveryResult(delivered: false, message: e.toString());
      }
    }

    // Cualquier otra cosa es una suscripción.
    try {
      final ({bool ok, bool permanent, String? message}) result =
          await _boosts.verifySubscriptionDetailed(
        productId: purchase.productID,
        platform: platform,
        verificationData: purchase.verificationData.serverVerificationData,
        purchaseId: purchase.purchaseID,
        period: _periodOf(purchase.productID),
      );
      if (result.ok) onSubscriptionDelivered?.call();
      return IapDeliveryResult(
        delivered: result.ok,
        permanent: result.permanent,
        message: result.ok
            ? null
            : (result.message ?? 'No se pudo verificar la compra.'),
      );
    } on BoostServiceException catch (e) {
      return IapDeliveryResult(delivered: false, message: e.message);
    } catch (e) {
      return IapDeliveryResult(delivered: false, message: e.toString());
    }
  }
}
