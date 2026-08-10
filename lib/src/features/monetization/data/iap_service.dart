import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'storekit_pending_transactions.dart';

/// Resultado de entregar (verificar + conceder) una compra en el backend.
class IapDeliveryResult {
  const IapDeliveryResult({
    required this.delivered,
    this.message,
    this.permanent = false,
  });

  /// true = el backend validó y concedió → se puede completar la compra.
  /// false = no se pudo conceder (no se completa: se reintentará).
  final bool delivered;
  final String? message;

  /// Fallo DEFINITIVO: reintentar no va a cambiar nada (p. ej. el recibo ya lo
  /// canjeó otra cuenta, o el producto no está en el catálogo del servidor).
  ///
  /// Es la ÚNICA razón por la que se cierra una transacción sin haber
  /// concedido nada: si el backend dice que ese recibo no va a valer nunca,
  /// dejarla abierta solo bloquea el producto para siempre sin ganar nada.
  final bool permanent;
}

/// Qué pasó al reintentar las compras que la tienda tenía sin terminar.
class PendingRecoveryOutcome {
  const PendingRecoveryOutcome({
    this.delivered = 0,
    this.rejected = 0,
    this.stillPending = 0,
    this.stillBlocked = 0,
  });

  /// Entregadas de verdad: el backend concedió el plan/saldo.
  final int delivered;

  /// Rechazadas de forma DEFINITIVA por el backend. Se cierran porque
  /// reintentar no cambia nada, y se avisa al usuario del motivo.
  final int rejected;

  /// No se pudieron entregar hoy (sin red, backend caído). Se dejan ABIERTAS a
  /// propósito y se reintentan en el siguiente arranque.
  final int stillPending;

  /// Entregadas pero que el nativo NO confirmó haber cerrado, así que el
  /// producto puede seguir bloqueado. Se cuenta aparte para no prometerle al
  /// usuario que ya puede comprar cuando quizá no pueda: es justo el tipo de
  /// mensaje falso que hizo perder dos rondas de arreglos.
  final int stillBlocked;

  int get found => delivered + rejected + stillPending;
}

/// Cómo acabó el intento de entrega de una compra concreta.
enum _DeliveryOutcome {
  /// Concedida por el backend y cerrada en la tienda.
  delivered,

  /// Concedida por el backend, pero el cierre en la tienda no se confirmó.
  /// El dinero está bien; el producto puede seguir bloqueado.
  deliveredNotClosed,

  /// Rechazo definitivo del backend: cerrada sin conceder, con motivo.
  rejected,

  /// No se pudo entregar ahora. Sigue ABIERTA para reintentarla.
  retryLater,

  /// Ya había otra entrega en vuelo de la misma transacción.
  skipped,
}

/// Fachada de COMPRAS DENTRO DE LA APP (IAP) sobre `in_app_purchase`.
///
/// Abre la pasarela NATIVA de Google Play / App Store (obligatoria para bienes
/// digitales) y, cuando la tienda confirma una compra, delega en [deliver] para
/// que el BACKEND valide el recibo y conceda el producto. SOLO si el backend
/// confirma la entrega se cierra la transacción (en consumibles, además,
/// Android la consume para poder recomprarla).
///
/// Regla de oro: el cliente NUNCA concede tier/saldo; solo lanza la compra y
/// reenvía el recibo. La concesión es siempre server-side.
///
/// ── LA FUGA QUE DEJÓ A TODOS SIN PODER SUSCRIBIRSE ────────────────────────
/// Una entrega que falla por algo temporal (backend caído, cold start, sin red)
/// deja la transacción SIN cerrar a propósito, para no quedarse el dinero sin
/// dar nada. Eso está bien. Lo que faltaba es lo otro: NADIE la reintentaba
/// nunca. `_undelivered` vivía solo en memoria, y en StoreKit 2 la tienda no
/// reemite por `purchaseStream` lo que ya emitió una vez, así que al cerrar la
/// app la transacción quedaba abierta para siempre. Y con una transacción
/// abierta el plugin RECHAZA toda compra posterior de ese producto con
/// `storekit_duplicate_product_object`, sin llegar a tocar el backend: por eso
/// `verifyPurchase` no registró ni una invocación durante días.
///
/// La cura es [recoverUnfinishedPurchases]: en cada arranque se lee
/// `Transaction.unfinished` —que trae el recibo JWS de cada transacción— y se
/// vuelve a intentar la ENTREGA. Lo que el backend concede se cierra; lo que no
/// se puede entregar hoy sigue abierto para el próximo arranque. Así el bloqueo
/// pasa de permanente a temporal y se cura solo en cuanto el backend responde.
class IapService extends ChangeNotifier {
  IapService({
    InAppPurchase? iap,
    Set<String> consumableIds = const <String>{},
    StoreKitPendingTransactions? pendingTransactions,
  })  : _pending = pendingTransactions ?? StoreKitPendingTransactions(),
        _iap = iap ?? InAppPurchase.instance,
        _consumableIds = consumableIds;

  final InAppPurchase _iap;

  /// Las transacciones que la App Store sigue teniendo sin terminar. Es la
  /// única forma de volver a ver (y entregar) las que la tienda ya no reemite.
  final StoreKitPendingTransactions _pending;

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
  String? _notice;
  bool _disposed = false;
  Timer? _pendingApproval;

  /// Compras que llegaron pero NO se pudieron entregar por un fallo temporal, y
  /// que por tanto se dejaron SIN cerrar a propósito. Permite reintentarlas en
  /// la misma sesión sin volver a pasar por la tienda.
  final Map<String, PurchaseDetails> _undelivered =
      <String, PurchaseDetails>{};

  /// Transacciones cuya entrega está EN VUELO ahora mismo, por clave de compra.
  ///
  /// Sin esto, el stream y la recuperación de arranque podían entregar la MISMA
  /// transacción a la vez y, peor, cerrarla dos veces: el segundo cierre se
  /// queda esperando para siempre, porque el Swift del plugin no llama al
  /// completion cuando ya no encuentra la transacción en `Transaction.all`.
  final Set<String> _inFlight = <String>{};

  /// La lista de transacciones sin terminar es GLOBAL al proceso. Si llegan a
  /// existir dos `IapService` a la vez (el de sesión y el que se crea una
  /// pantalla cuando no recibe el compartido), sus recuperaciones se serializan
  /// aquí en vez de pelearse por las mismas transacciones.
  static Future<void>? _recoveryLock;

  /// Notifica solo si el servicio sigue vivo. Cerrar la pantalla mientras el
  /// backend verificaba lanzaba "notifyListeners after dispose".
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Limpia el último error. El paywall reemitía en bucle el snackbar de un
  /// fallo antiguo porque nadie lo borraba al reintentar.
  ///
  /// NO toca [notice] a propósito: el aviso de una compra recuperada (o
  /// rechazada) se genera en el arranque, cuando ninguna pantalla escucha
  /// todavía, y el paywall llama a este método nada más abrirse. Metido en
  /// `_error`, el único mensaje que le decía al usuario qué había pasado con su
  /// dinero se borraba siempre antes de poder pintarse.
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

  /// Aviso PERSISTENTE sobre el dinero del usuario (una compra que quedó a
  /// medias y se ha activado, o un rechazo definitivo del backend). Sobrevive a
  /// [clearError] para que la primera pantalla que se abra pueda enseñarlo.
  String? get notice => _notice;

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

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

  /// Inicializa: comprueba disponibilidad, se suscribe al flujo de compras y
  /// reintenta lo que quedó sin entregar.
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

    // La recuperación se lanza ANTES de esperar al escaparate. `loadProducts`
    // consulta la App Store por red y puede tardar mucho: dejar el desbloqueo
    // detrás de ese await condenaba justo al usuario con mala conexión, que es
    // el mismo perfil que se quedó con la transacción colgada.
    final Future<PendingRecoveryOutcome> recovery = _recoverAtStartup();
    await loadProducts(productIds);
    await recovery;
  }

  Future<PendingRecoveryOutcome> _recoverAtStartup() async {
    final PendingRecoveryOutcome outcome = await recoverUnfinishedPurchases();
    if (_disposed) return outcome;
    if (outcome.delivered > 0) {
      // En `notice`, no en `_error`: esto se genera al arrancar, cuando aún no
      // hay pantallas escuchando.
      _notice = 'Había una compra sin activar de una sesión anterior y ya está '
          'lista. No se te ha cobrado otra vez.';
      _notify();
    }
    return outcome;
  }

  /// Reintenta la ENTREGA de todo lo que la App Store sigue teniendo sin
  /// terminar, usando el recibo (JWS) que la propia lista trae consigo.
  ///
  /// Esto es lo que faltaba en los dos intentos anteriores: allí se cerraba la
  /// transacción sin mandar nada al backend, así que la compra quedaba cobrada
  /// y no concedida, y el usuario solo se enteraba si adivinaba que debía pulsar
  /// "Restaurar" (que además no recupera consumibles: Apple no los devuelve en
  /// `currentEntitlements`).
  ///
  /// Lo que el backend concede se cierra. Lo que rechaza de forma DEFINITIVA se
  /// cierra también (reintentar no cambiaría nada). Lo que falla por algo
  /// temporal se deja ABIERTO y se vuelve a intentar en el próximo arranque.
  Future<PendingRecoveryOutcome> recoverUnfinishedPurchases({
    String? productId,
  }) async {
    if (_disposed) return const PendingRecoveryOutcome();
    // Sin flag de reentrada propio: [_exclusively] hace ESPERAR a la segunda
    // llamada en vez de descartarla. Descartarla haría que el usuario que pulsa
    // comprar durante la recuperación de arranque recibiera un "no hay nada
    // pendiente" que es mentira.
    return _exclusively(() => _recoverUnfinished(productId));
  }

  Future<PendingRecoveryOutcome> _recoverUnfinished(String? productId) async {
    final List<PendingStoreKitTransaction> pending = await _pending.list();
    int delivered = 0;
    int rejected = 0;
    int stillPending = 0;
    int stillBlocked = 0;
    for (final PendingStoreKitTransaction tx in pending) {
      if (_disposed) break;
      if (productId != null && tx.productId != productId) continue;
      if (tx.jws.isEmpty) {
        // Sin recibo el backend rechaza la entrega ("Falta el recibo de
        // compra"), y cerrarla sería tirar a la basura una compra pagada.
        debugPrint('[IAP] ${tx.productId} sin recibo: se deja abierta');
        stillPending++;
        continue;
      }
      final PurchaseDetails purchase = _purchaseFrom(tx);
      switch (await _handleVerified(purchase, finish: () => _pending.finish(tx))) {
        case _DeliveryOutcome.delivered:
          delivered++;
        case _DeliveryOutcome.deliveredNotClosed:
          delivered++;
          stillBlocked++;
        case _DeliveryOutcome.rejected:
          rejected++;
        case _DeliveryOutcome.retryLater:
          stillPending++;
        case _DeliveryOutcome.skipped:
          break;
      }
    }
    return PendingRecoveryOutcome(
      delivered: delivered,
      rejected: rejected,
      stillPending: stillPending,
      stillBlocked: stillBlocked,
    );
  }

  /// Reconstruye la compra a partir de la transacción sin terminar.
  ///
  /// `pendingCompletePurchase` se deja en false a propósito: esta compra se
  /// cierra por id con `finish`, no con `completePurchase`, que en iOS espera
  /// un `SK2PurchaseDetails` real del plugin y no un objeto rehecho aquí.
  PurchaseDetails _purchaseFrom(PendingStoreKitTransaction tx) => PurchaseDetails(
        purchaseID: tx.transactionId.toString(),
        productID: tx.productId,
        verificationData: PurchaseVerificationData(
          localVerificationData: tx.jws,
          serverVerificationData: tx.jws,
          source: 'app_store',
        ),
        transactionDate: tx.purchaseDate,
        status: PurchaseStatus.purchased,
      );

  /// Serializa las recuperaciones de TODOS los servicios del proceso.
  Future<T> _exclusively<T>(Future<T> Function() body) async {
    final Future<void>? previous = _recoveryLock;
    final Completer<void> mine = Completer<void>();
    final Future<void> gate = mine.future;
    _recoveryLock = gate;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {/* la anterior ya reportó lo suyo */}
    }
    try {
      return await body();
    } finally {
      mine.complete();
      if (identical(_recoveryLock, gate)) _recoveryLock = null;
    }
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
      // El plugin se niega a comprar porque ya hay una transacción ABIERTA de
      // este mismo producto. Le pasa a quien pagó y cuya entrega falló: se
      // queda sin poder suscribirse, viendo un volcado de excepción que no le
      // dice nada ni le da salida.
      //
      // No es un error del usuario ni hace falta que vuelva a pagar: lo que hay
      // que hacer es ENTREGAR la compra que quedó a medias. Se espera al
      // resultado (todas las llamadas nativas de ese camino llevan timeout)
      // para poder contarle la verdad en vez de un "espera unos segundos".
      if (e.code == 'storekit_duplicate_product_object') {
        await _recoverPending(product.id);
        _setBusy(false);
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
          _armPendingApprovalTimeout();
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

  /// Una compra `pending` (el "Preguntar antes de comprar" de los menores)
  /// puede tardar días en aprobarse, y hasta ahora dejaba `_busy` en true para
  /// el resto de la sesión: el botón de comprar no respondía y no había forma de
  /// reintentar ni de elegir otro plan sin reiniciar la app.
  void _armPendingApprovalTimeout() {
    _pendingApproval?.cancel();
    _pendingApproval = Timer(const Duration(seconds: 60), () {
      if (_disposed || !_busy) return;
      _setBusy(false);
      _error = 'Tu compra está pendiente de aprobación. En cuanto se confirme '
          'se activará sola; no hace falta que pagues otra vez.';
      _notify();
    });
  }

  /// Entrega la compra y, SOLO si el backend responde, la cierra.
  ///
  /// [finish] permite cerrar por id (recuperación desde
  /// `Transaction.unfinished`) en lugar de por `completePurchase`.
  Future<_DeliveryOutcome> _handleVerified(
    PurchaseDetails purchase, {
    Future<bool> Function()? finish,
  }) async {
    final String key = purchase.purchaseID ?? purchase.productID;
    if (!_inFlight.add(key)) return _DeliveryOutcome.skipped;
    _pendingApproval?.cancel();
    Future<bool> close() => (finish ?? () => _safeComplete(purchase))();
    // Solo se guardan para reintentar en sesión las compras que llegaron por el
    // stream, porque esas sí se cierran con `completePurchase`. Las rehechas
    // desde `Transaction.unfinished` se cierran por id con [finish]: guardarlas
    // aquí haría que un reintento posterior las entregara y NO las cerrara,
    // dejando el producto bloqueado justo después de haber concedido la compra.
    final bool remember = finish == null;
    try {
      final Future<IapDeliveryResult> Function(PurchaseDetails)? handler =
          deliver;
      if (handler == null) {
        // Sin backend configurado no hay NADA que entregar, así que tampoco hay
        // nada que cerrar. Antes esto contaba como fallo de entrega, gastaba
        // intentos y acababa cerrando una compra pagada que jamás salió del
        // dispositivo. Se deja abierta: el servicio de sesión, que sí tiene
        // entrega, la recuperará.
        debugPrint('[IAP] ${purchase.productID} llega sin entrega configurada');
        return _DeliveryOutcome.retryLater;
      }

      IapDeliveryResult result;
      try {
        result = await handler(purchase);
      } catch (e) {
        result = IapDeliveryResult(delivered: false, message: e.toString());
      }

      if (result.delivered) {
        _error = null;
        _undelivered.remove(purchase.productID);
        // Dentro del try: este handler pinta snackbars y cierra pantallas, y si
        // reventaba (contexto desmontado, sin Scaffold) la excepción salía de
        // aquí y la transacción se quedaba SIN cerrar pese a estar concedida,
        // dejando el producto bloqueado y el spinner encendido.
        try {
          onDelivered?.call(purchase);
        } catch (error) {
          debugPrint('[IAP] onDelivered falló: $error');
        }
        // El cierre puede fallar en silencio (el nativo no confirma). El dinero
        // está bien, pero el producto puede seguir bloqueado y hay que poder
        // decirlo en vez de dar por hecho que ya se puede comprar.
        return await close()
            ? _DeliveryOutcome.delivered
            : _DeliveryOutcome.deliveredNotClosed;
      }

      if (result.permanent) {
        _error = result.message ?? 'Esta compra no se puede entregar.';
        _notice = _error;
        _undelivered.remove(purchase.productID);
        await close();
        return _DeliveryOutcome.rejected;
      }

      // Fallo temporal (red, backend caído): NO se cierra. Antes, tras tres
      // intentos, se cerraba igualmente "de lo irrecuperable a lo recuperable";
      // pero eso solo era recuperable con "Restaurar", que no devuelve
      // consumibles (Apple no los incluye en `currentEntitlements`), así que un
      // pack de Attras cerrado sin conceder era dinero perdido sin rastro. Y
      // ya no hace falta ese cierre a ciegas: `recoverUnfinishedPurchases`
      // vuelve a intentarlo en cada arranque con el recibo en la mano, así que
      // el bloqueo del producto dura lo que dure la avería, no para siempre.
      if (remember) _undelivered[purchase.productID] = purchase;
      _error = result.message ?? 'No se pudo entregar la compra.';
      return _DeliveryOutcome.retryLater;
    } finally {
      _inFlight.remove(key);
      _setBusy(false);
      _notify();
    }
  }

  /// Entrega la compra que quedó abierta y bloquea el producto.
  Future<void> _recoverPending(String productId) async {
    // 1) La que ya tenemos en memoria de esta misma sesión.
    final PurchaseDetails? pending = _undelivered[productId];
    if (pending != null) {
      final _DeliveryOutcome outcome = await _handleVerified(pending);
      if (outcome == _DeliveryOutcome.delivered ||
          outcome == _DeliveryOutcome.deliveredNotClosed) {
        _error = _activatedMessage(
          stillBlocked: outcome == _DeliveryOutcome.deliveredNotClosed,
        );
        _notify();
        return;
      }
      if (outcome == _DeliveryOutcome.rejected) return; // el motivo ya está
    }

    // 2) La lista de la App Store, que trae el recibo. Es el único sitio donde
    // aparece una transacción que se quedó colgada con la app cerrada: la
    // tienda no la reemite por el stream y no hay forma de verla desde la API
    // general del plugin.
    final PendingRecoveryOutcome result =
        await recoverUnfinishedPurchases(productId: productId);
    if (result.delivered > 0) {
      _error = _activatedMessage(stillBlocked: result.stillBlocked > 0);
      _notify();
      return;
    }
    if (result.rejected > 0) return; // `_handleVerified` ya puso el motivo
    if (result.stillPending > 0) {
      _error = 'Tienes una compra anterior a medias y no hemos podido '
          'activarla ahora. Comprueba tu conexión y vuelve a intentarlo en un '
          'momento: no se te cobrará dos veces.';
      _notify();
      return;
    }

    // 3) No hay nada que ver desde aquí (o no es iOS): que la tienda reemita.
    try {
      await _iap.restorePurchases();
    } catch (error) {
      debugPrint('[IAP] restaurar tras el bloqueo falló: $error');
    }
    _error = 'Estamos comprobando tu compra anterior. Espera unos segundos y '
        'vuelve a intentarlo.';
    _notify();
  }

  /// Lo que se le cuenta a quien ya había pagado.
  ///
  /// [stillBlocked] cuando el backend concedió la compra pero la tienda no
  /// confirmó el cierre de la transacción: el plan está activo, pero ese
  /// producto puede seguir sin dejarse comprar. Decir "ya puedes" sin saberlo es
  /// exactamente el mensaje falso que ya se dio dos veces.
  String _activatedMessage({required bool stillBlocked}) {
    if (stillBlocked) {
      return 'Tu compra anterior ya está activa (no se te ha cobrado otra vez). '
          'Si la tienda sigue sin dejarte comprar, cierra la app y vuelve a '
          'abrirla.';
    }
    return 'Ya habías pagado esta compra: la acabamos de activar. No se te ha '
        'cobrado otra vez.';
  }

  /// Traduce los codigos de la tienda a algo que una persona pueda entender y
  /// accionar. Antes se enseñaba `e.toString()` tal cual, que es un volcado con
  /// nombres de clases internas.
  String _readableStoreError(PlatformException e) {
    switch (e.code) {
      case 'storekit0':
        return 'La App Store ha rechazado la compra. Revisa tu método de pago '
            'en Ajustes.';
      default:
        return e.message ?? 'No se ha podido iniciar la compra.';
    }
  }

  /// Cierra la transacción en la tienda. Devuelve true si NO queda abierta:
  /// tanto si se cerró como si no había nada que cerrar.
  Future<bool> _safeComplete(PurchaseDetails purchase) async {
    if (!_needsFinishing(purchase)) return true;
    try {
      await _iap.completePurchase(purchase).timeout(_pending.nativeTimeout);
      return true;
    } on TimeoutException {
      // El `finish` de StoreKit 2 puede no responder nunca (ver
      // StoreKitPendingTransactions.nativeTimeout). Sin este tope, el await
      // colgaba el bucle de `_onPurchases` y el spinner de compra se quedaba
      // encendido para siempre.
      debugPrint('[IAP] cerrar ${purchase.productID} no respondió a tiempo');
      return false;
    } catch (error) {
      debugPrint('[IAP] no se pudo cerrar ${purchase.productID}: $error');
      return false;
    }
  }

  bool _needsFinishing(PurchaseDetails purchase) {
    if (purchase.pendingCompletePurchase) return true;
    // En StoreKit 2 `pendingCompletePurchase` NO significa "queda algo que
    // cerrar": el plugin lo define como `status == purchased`
    // (SK2PurchaseDetails). Una compra RESTAURADA llega con `restored`, así que
    // se entregaba al backend y se salía de aquí sin cerrarla nunca: el usuario
    // pulsaba "Restaurar", recuperaba el plan, y el producto seguía bloqueado
    // con `storekit_duplicate_product_object`. Es una de las vías por las que
    // se generaban transacciones colgadas.
    if (!_pending.available) return false;
    if (purchase.status != PurchaseStatus.restored) return false;
    final String? id = purchase.purchaseID;
    return id != null && id.isNotEmpty;
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingApproval?.cancel();
    _pendingApproval = null;
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
