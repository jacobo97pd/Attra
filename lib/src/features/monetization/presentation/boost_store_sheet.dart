import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_buttons.dart';
import '../../auth/domain/app_user.dart';
import '../data/boost_service.dart';
import '../data/purchase_delivery_router.dart';
import '../data/iap_service.dart';
import '../domain/boost.dart';
import '../domain/monetization_feature_flags.dart';
import '../domain/premium_product_catalog.dart';
import 'monetization_plan_numbers.dart';

/// Hoja de consumibles: Boosts (visibilidad temporal) y Attra Swipes (likes
/// extra). Muestra saldos, permite ACTIVAR un Boost (consume saldo) y COMPRAR
/// más (placeholder de IAP). El Boost activo se ve en vivo con su temporizador.
Future<void> showBoostStoreSheet(
  BuildContext context, {
  required BoostService service,
  required AppUser? user,
  IapService? iapService,
  PurchaseDeliveryRouter? purchases,
  VoidCallback? onChanged,
  MonetizationFeatureFlags flags = const MonetizationFeatureFlags(),
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BoostStoreBody(
      service: service,
      user: user,
      iapService: iapService,
      purchases: purchases,
      onChanged: onChanged,
      flags: flags,
    ),
  );
}

class _BoostStoreBody extends StatefulWidget {
  const _BoostStoreBody({
    required this.service,
    required this.user,
    this.iapService,
    this.purchases,
    this.onChanged,
    this.flags = const MonetizationFeatureFlags(),
  });

  final BoostService service;
  final AppUser? user;

  /// De aquí sale el coste del Superboost. Antes la hoja no lo decía en ningún
  /// sitio: el usuario activaba un Superboost sin saber cuánto saldo le
  /// costaba, y con el precio nuevo (varios Boosts) eso es inaceptable.
  final MonetizationFeatureFlags flags;

  /// Servicio COMPARTIDO de la sesión. Se inyecta para no abrir una segunda
  /// suscripción a `purchaseStream`: con dos escuchas vivas, la compra de un
  /// pack la recibía también el paywall, que la mandaba a verifyPurchase, el
  /// backend la rechazaba por producto desconocido y el usuario se quedaba sin
  /// su saldo pese a haber pagado.
  final IapService? iapService;

  /// Enrutador de sesión. Es quien entrega las compras cuando esta hoja usa el
  /// servicio compartido, así que también es quien conoce el saldo resultante.
  final PurchaseDeliveryRouter? purchases;
  final VoidCallback? onChanged;

  @override
  State<_BoostStoreBody> createState() => _BoostStoreBodyState();
}

class _BoostStoreBodyState extends State<_BoostStoreBody> {
  bool _busy = false;
  int _attras = 0;
  int _boosts = 0;
  int _swipes = 0;

  // Compras IAP: ids consumibles del catálogo (boosts + swipes).
  static Set<String> get _consumableIds => <String>{
        for (final PremiumProductDefinition p in <PremiumProductDefinition>[
          ...PremiumProductCatalog.attraPacks,
          ...PremiumProductCatalog.boostPacks,
          ...PremiumProductCatalog.swipePacks,
        ])
          p.id,
      };
  late final IapService _iap;

  /// True si el servicio lo creó esta hoja (y por tanto le toca cerrarlo).
  bool _ownsIap = false;

  @override
  void initState() {
    super.initState();
    _attras = widget.user?.attrasBalance ?? 0;
    _boosts = widget.user?.boostBalance ?? 0;
    _swipes = widget.user?.swipeBalance ?? 0;
    // Saldos confirmados por el BACKEND durante esta sesión (compra o
    // activación). Mandan sobre los de `AppUser`, que se recarga de forma
    // asíncrona y va por detrás: al reabrir la hoja tras activar un Boost, el
    // contador volvía al valor de ANTES de gastarlo.
    widget.purchases?.addListener(_onPurchasesChanged);
    _syncBalancesFromRouter();
    final IapService? shared = widget.iapService;
    if (shared != null) {
      // El enrutador de sesión ya entrega estos productos y ya tiene sus
      // precios cargados: aquí solo se escucha para reflejar busy/errores; el
      // saldo resultante llega por el enrutador. Sin esto la compra se abonaba
      // en el servidor pero los contadores de la hoja seguían mostrando el
      // valor con el que se abrió (0), y parecía que no había servido de nada.
      _iap = shared..addListener(_onIap);
      _iap.clearError();
      _showPendingNotice();
      return;
    }
    _ownsIap = true;
    _iap = IapService(consumableIds: _consumableIds)
      ..deliver = _deliver
      ..addListener(_onIap);
    _iap.init(productIds: _consumableIds);
  }

  /// Aviso de la recuperación de compras del arranque. No puede viajar en
  /// `error` porque `clearError()` lo borra justo aquí, antes de que nadie lo
  /// pinte, y un pack de Attras recuperado (o rechazado) es dinero del usuario:
  /// tiene que enterarse.
  void _showPendingNotice() {
    final String? notice = _iap.notice;
    if (notice == null) return;
    _iap.clearNotice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _snack(notice);
    });
  }

  @override
  void dispose() {
    _iap.removeListener(_onIap);
    widget.purchases?.removeListener(_onPurchasesChanged);
    if (_ownsIap) _iap.dispose();
    super.dispose();
  }

  void _onPurchasesChanged() {
    if (!mounted) return;
    final int before = _attras + _boosts + _swipes;
    setState(_syncBalancesFromRouter);
    if (_attras + _boosts + _swipes > before) {
      _snack('Compra realizada. Boosts: $_boosts · Swipes: $_swipes');
      widget.onChanged?.call();
    }
  }

  /// Copia los saldos que el BACKEND confirmó por última vez en esta sesión
  /// (entrega de una compra o activación de un Boost).
  void _syncBalancesFromRouter() {
    final PurchaseDeliveryRouter? router = widget.purchases;
    if (router == null) return;
    final int? attras = router.lastAttraBalance;
    final int? boosts = router.lastBoostBalance;
    final int? swipes = router.lastSwipeBalance;
    if (attras != null) _attras = attras;
    if (boosts != null) _boosts = boosts;
    if (swipes != null) _swipes = swipes;
  }

  String get _uid => widget.user?.uid ?? '';

  /// Refleja el estado del flujo IAP (busy/error) en la hoja.
  void _onIap() {
    if (!mounted) return;
    setState(() => _busy = _iap.isBusy);
    final String? err = _iap.error;
    if (err != null) _snack(err);
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

  /// Entrega (server-side): valida el recibo y abona el consumible. Solo si el
  /// backend confirma, la compra se da por completada.
  Future<IapDeliveryResult> _deliver(PurchaseDetails purchase) async {
    final PremiumProductDefinition? def =
        PremiumProductCatalog.byId(purchase.productID);
    if (def == null || def.consumableKind == null) {
      return const IapDeliveryResult(
          delivered: false, message: 'Producto desconocido.');
    }
    try {
      final int balance = await widget.service.purchaseConsumable(
        productId: purchase.productID,
        kind: def.consumableKind!,
        amount: def.consumableAmount,
        purchaseId: purchase.purchaseID,
        platform: _platform(),
        verificationData: purchase.verificationData.serverVerificationData,
      );
      // El saldo confirmado se anota también en la sesión: si la hoja se cierra
      // y se vuelve a abrir, no se repinta el de `AppUser` (aún sin recargar).
      if (def.consumableKind == 'boost') {
        widget.purchases?.noteBoostBalance(balance);
      } else {
        widget.purchases?.noteSwipeBalance(balance);
      }
      if (!mounted) return const IapDeliveryResult(delivered: true);
      setState(() {
        if (def.consumableKind == 'boost') {
          _boosts = balance;
        } else {
          _swipes = balance;
        }
      });
      _snack('Compra realizada. Saldo: $balance');
      widget.onChanged?.call();
      return const IapDeliveryResult(delivered: true);
    } on BoostServiceException catch (e) {
      // Un rechazo DEFINITIVO (producto fuera del catálogo del servidor, recibo
      // ya canjeado por otra cuenta) se devolvía como temporal: la transacción
      // no se finalizaba nunca, la tienda la reencolaba en cada arranque y en
      // Android el consumible no se consumía, así que ni siquiera se podía
      // recomprar. Igual que en la ruta de suscripciones, se marca permanente.
      return IapDeliveryResult(
        delivered: false,
        permanent: e.isPermanent,
        message: e.message,
      );
    }
  }

  Future<void> _buyProduct(String productId) async {
    if (_busy) return;
    await _iap.buy(productId);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Números de la propuesta (hoy solo el coste del Superboost) desde los flags.
  MonetizationPlanNumbers get _numbers => MonetizationPlanNumbers(widget.flags);

  /// Lo que cuesta cada tipo de Boost en saldo. El Boost de 30 min siempre vale
  /// 1: es la unidad de la moneda.
  int _costOf(BoostType type) =>
      type == BoostType.superboost ? _numbers.superboostCostBoosts : 1;

  String _labelOf(BoostType type) =>
      type == BoostType.superboost ? 'Superboost' : 'Boost';

  /// "1 Boost" / "3 Boosts". El coste sale de un flag, así que el plural hay
  /// que calcularlo: no se puede dejar escrito en el texto.
  static String _boostsLabel(int amount) =>
      amount == 1 ? '1 Boost' : '$amount Boosts';

  /// Explica el saldo bajo los botones: qué cuesta el Superboost y, si no
  /// llega, cuánto falta. Sin esto, el botón deshabilitado no dice por qué.
  String _activationHint() {
    final int superCost = _costOf(BoostType.superboost);
    if (_boosts >= superCost) {
      return 'Tienes ${_boostsLabel(_boosts)}. El Boost de 30 min gasta '
          '${_boostsLabel(_costOf(BoostType.boostNormal))} y el Superboost de '
          '24 h gasta ${_boostsLabel(superCost)}: tú eliges cómo gastarlos.';
    }
    if (_boosts <= 0) {
      return 'No tienes Boosts. El de 30 min gasta '
          '${_boostsLabel(_costOf(BoostType.boostNormal))} y el Superboost de '
          '24 h, ${_boostsLabel(superCost)}. Cómpralos aquí abajo.';
    }
    return 'Tienes ${_boostsLabel(_boosts)}: te falta saldo para el '
        'Superboost de 24 h, que gasta ${_boostsLabel(superCost)}. '
        'Puedes activar el Boost de 30 min o comprar más aquí abajo.';
  }

  Future<void> _activate(BoostType type) async {
    if (_busy) return;
    final int cost = _costOf(type);
    if (_boosts < cost) {
      // Defensa de cliente: el servidor también lo rechaza, pero pedirle al
      // usuario que pulse para enterarse de que no le llega es maltratarlo.
      _snack('Te falta saldo: un ${_labelOf(type)} cuesta '
          '${_boostsLabel(cost)} y tienes ${_boostsLabel(_boosts)}.');
      return;
    }
    setState(() => _busy = true);
    try {
      final BoostActivationResult r =
          await widget.service.activateBoost(type: type);
      if (r.success) {
        setState(() => _boosts = r.remainingBoosts);
        // El saldo restante lo confirma el backend: se guarda en la sesión para
        // que al reabrir la hoja no se pinte otra vez el de `AppUser` (que aún
        // no se ha recargado y mostraría el Boost como no gastado).
        widget.purchases?.noteBoostBalance(r.remainingBoosts);
        _snack(type == BoostType.superboost
            ? '¡Superboost activado 24h!'
            : '¡Boost activado!');
        widget.onChanged?.call();
      } else if (r.status == 'no_balance') {
        _snack('Saldo insuficiente: un ${_labelOf(type)} cuesta '
            '${_boostsLabel(cost)}. Compra más abajo.');
      } else if (r.status == 'needs_story') {
        // El backend NO ha cobrado: con el muro de historias encendido,
        // Discover solo enseña a quien tiene una historia viva, y un Boost se
        // gasta por tiempo. Activarlo sin historia habría quemado el reloj
        // entero sin una sola impresión.
        _snack('Publica una historia antes de impulsarte: en Descubrir solo '
            'se ve a quien está contando algo, así que el Boost se gastaría '
            'sin que nadie te viera.');
      } else {
        _snack('No se pudo activar el Boost.');
      }
    } on BoostServiceException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.surfaceLine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Boosts y Swipes',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Más visibilidad y más likes cuando quieras.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.textSecondary)),
            const SizedBox(height: 16),

            // Boost activo (en vivo) con temporizador.
            if (_uid.isNotEmpty)
              StreamBuilder<ActiveBoost?>(
                stream: widget.service.watchActiveBoost(_uid),
                builder: (_, AsyncSnapshot<ActiveBoost?> snap) {
                  final ActiveBoost? b = snap.data;
                  if (b == null) return const SizedBox.shrink();
                  return _ActiveBoostCard(boost: b, service: widget.service);
                },
              ),

            // Saldos.
            Row(
              children: <Widget>[
                // El saldo de Attras se compra aquí, así que también se ve aquí.
                Expanded(
                    child: _BalanceTile(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Attras',
                        value: _attras)),
                const SizedBox(width: 12),
                Expanded(
                    child: _BalanceTile(
                        icon: Icons.bolt_rounded,
                        label: 'Boosts',
                        value: _boosts)),
                const SizedBox(width: 12),
                Expanded(
                    child: _BalanceTile(
                        icon: Icons.swipe_rounded,
                        label: 'Swipes',
                        value: _swipes)),
              ],
            ),
            const SizedBox(height: 18),

            // Activar. El COSTE va en la propia etiqueta: es una sola moneda
            // (Boosts) y cada producto gasta una cantidad distinta, así que sin
            // el precio delante el usuario no puede decidir.
            Text('Activar Boost',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            AttraPrimaryButton(
              label:
                  'Boost 30 min · ${_boostsLabel(_costOf(BoostType.boostNormal))}',
              icon: Icons.bolt_rounded,
              loading: _busy,
              onPressed: _boosts >= _costOf(BoostType.boostNormal) && !_busy
                  ? () => _activate(BoostType.boostNormal)
                  : null,
            ),
            const SizedBox(height: 8),
            AttraSecondaryButton(
              label:
                  'Superboost 24 h · ${_boostsLabel(_costOf(BoostType.superboost))}',
              // Antes bastaba con tener 1 Boost para activarlo, así que el
              // producto caro salía al mismo precio que el barato. Ahora se
              // desactiva si el saldo no llega, y justo debajo se explica.
              onPressed: _boosts >= _costOf(BoostType.superboost) && !_busy
                  ? () => _activate(BoostType.superboost)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              _activationHint(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _boosts >= _costOf(BoostType.superboost)
                    ? context.colors.textMuted
                    : AppColors.attraRed,
              ),
            ),
            const SizedBox(height: 20),

            // Comprar (pasarela nativa Google Play / App Store).
            Text('Comprar',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            // Packs de compra desde el catálogo (única fuente de verdad de los
            // IDs de tienda y cantidades). El precio lo pone la tienda.
            // Los packs de ATTRAS estaban definidos en el catálogo desde el
            // principio pero NO se ofrecían en ninguna pantalla: eran producto
            // muerto, imposible de comprar. Van los primeros porque el Attra es
            // la acción con más valor percibido.
            for (final PremiumProductDefinition p in <PremiumProductDefinition>[
              ...PremiumProductCatalog.attraPacks,
              ...PremiumProductCatalog.boostPacks,
              ...PremiumProductCatalog.swipePacks,
            ])
              _BuyRow(
                label: p.title,
                sub: p.description,
                badge: p.badge,
                price: _iap.productById(p.id)?.price,
                onTap: _busy ? null : () => _buyProduct(p.id),
              ),
            const SizedBox(height: 8),
            Text(
              _iap.isAvailable
                  ? 'Pago seguro a través de tu tienda (Google Play / App Store).'
                  : 'Las compras no están disponibles en este dispositivo.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: context.colors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveBoostCard extends StatefulWidget {
  const _ActiveBoostCard({required this.boost, required this.service});
  final ActiveBoost boost;
  final BoostService service;

  @override
  State<_ActiveBoostCard> createState() => _ActiveBoostCardState();
}

class _ActiveBoostCardState extends State<_ActiveBoostCard> {
  Timer? _t;

  /// Refresco de las métricas. El backend las va acumulando mientras el Boost
  /// corre, así que se vuelven a pedir cada poco (no cada segundo como el
  /// contador: sería una llamada por segundo a la Cloud Function).
  Timer? _metricsTimer;
  BoostSummary? _summary;

  static const Duration _metricsInterval = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadSummary();
    _metricsTimer = Timer.periodic(_metricsInterval, (_) => _loadSummary());
  }

  @override
  void didUpdateWidget(covariant _ActiveBoostCard old) {
    super.didUpdateWidget(old);
    // Otro Boost (se activó uno nuevo): las métricas anteriores ya no son suyas.
    if (old.boost.boostId != widget.boost.boostId) {
      _summary = null;
      _loadSummary();
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _metricsTimer?.cancel();
    super.dispose();
  }

  /// Métricas reales del Boost (getBoostSummary). Existían en backend y en el
  /// servicio, pero ninguna pantalla las pedía: el usuario pagaba por
  /// visibilidad y no llegaba a ver nunca qué le había dado.
  Future<void> _loadSummary() async {
    final String boostId = widget.boost.boostId.trim();
    if (boostId.isEmpty) return;
    try {
      final BoostSummary summary =
          await widget.service.getBoostSummary(boostId);
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      // Sin métricas la tarjeta sigue mostrando el temporizador y las
      // impresiones del propio documento del Boost: no se molesta al usuario.
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? exp = widget.boost.expiresAt;
    final Duration left =
        exp == null ? Duration.zero : exp.difference(DateTime.now());
    final int s = left.inSeconds < 0 ? 0 : left.inSeconds;
    final String mmss = left.inHours > 0
        ? '${left.inHours}h ${(left.inMinutes % 60)}m'
        : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    final BoostSummary? summary = _summary;
    final int impressions =
        summary?.deliveredImpressions ?? widget.boost.deliveredImpressions;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppColors.action),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.bolt_rounded, color: Colors.white),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Boost activo — más visibilidad',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              Text(mmss,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _BoostMetric(
                  icon: Icons.visibility_rounded,
                  label: 'Vistas',
                  value: impressions),
              _BoostMetric(
                  icon: Icons.person_search_rounded,
                  label: 'Perfil',
                  value: summary?.profileOpens ?? 0),
              _BoostMetric(
                  icon: Icons.favorite_rounded,
                  label: 'Likes',
                  value: summary?.likesReceived ?? 0),
              _BoostMetric(
                  icon: Icons.bolt_rounded,
                  label: 'Matches',
                  value: summary?.matchesGenerated ?? 0),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Resultados de este Boost, en directo.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Una métrica del Boost activo (vistas, visitas al perfil, likes, matches).
class _BoostMetric extends StatelessWidget {
  const _BoostMetric(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(height: 3),
          Text('$value',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.1)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.colors.surfaceLine),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, color: AppColors.attraRed),
          const SizedBox(height: 6),
          Text('$value',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _BuyRow extends StatelessWidget {
  const _BuyRow(
      {required this.label,
      required this.sub,
      required this.onTap,
      this.badge,
      this.price});
  final String label;
  final String sub;
  final String? badge;
  final String? price;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.colors.surfaceLine),
      ),
      child: ListTile(
        onTap: onTap,
        title: Row(
          children: <Widget>[
            Flexible(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (badge != null && badge!.isNotEmpty) ...<Widget>[
              const SizedBox(width: 8),
              _PackBadge(text: badge!),
            ],
          ],
        ),
        subtitle: Text(sub, style: theme.textTheme.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (price != null && price!.isNotEmpty) ...<Widget>[
              Text(price!,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.add_circle_outline_rounded,
                color: AppColors.attraRed),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta comercial ("Ahorro", "Más comprado"…) con degradado de marca.
class _PackBadge extends StatelessWidget {
  const _PackBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppColors.action),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}
